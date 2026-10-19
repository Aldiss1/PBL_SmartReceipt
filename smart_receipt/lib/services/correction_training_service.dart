import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../helpers/database_helper.dart';
import '../models/receipt_model.dart';
import '../ocr/receipt_classifier.dart';

/// Persistence surface the training service depends on.
///
/// Extracted so the service can be exercised against an in-memory SQLite
/// database in tests; [DatabaseHelper] is the production implementation.
abstract class CorrectionStore {
  Future<int> insertCategoryCorrection(CategoryCorrection correction);
  Future<List<CategoryCorrection>> getCategoryCorrections({bool onlyUnused});
  Future<int> countCategoryCorrections({bool onlyUnused});
  Future<Map<String, int>> getCorrectionCountsByCategory();
  Future<int> markCorrectionsUsed(Iterable<int> ids);
}

/// Records user category corrections and turns them into training data.
///
/// This is the feedback loop that lets the classifier improve without shipping
/// a new model: every time a user fixes a predicted category we store
/// (item name → corrected category) and can later export those rows as a
/// labelled dataset for the next training run.
class CorrectionTrainingService {
  CorrectionTrainingService({CorrectionStore? store})
      : _store = store ?? DatabaseHelper();

  final CorrectionStore _store;

  /// Directory used by [exportTrainingDataset]; overridable for tests.
  Directory? _outputDirectory;
  set outputDirectory(Directory dir) => _outputDirectory = dir;

  /// Records that the user changed an item's category.
  ///
  /// [itemName] may be raw OCR text; only whitespace is collapsed. It is stored
  /// as-is because the classifier vectorizes raw text — normalizing here would
  /// make the exported training corpus disagree with inference input.
  /// [prediction] is the model output that was overridden (nullable if the item
  /// was added manually). Returns the row id, or -1 on failure — a logging
  /// problem must never block saving the receipt.
  Future<int> recordCorrection({
    required String itemName,
    required String correctedCategoryName,
    required int correctedCategoryId,
    ItemPrediction? prediction,
    String? predictedLabel,
    String source = 'review',
  }) async {
    final String trainingName =
        itemName.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trainingName.isEmpty) {
      return -1;
    }
    try {
      return await _store.insertCategoryCorrection(
        CategoryCorrection(
          itemName: trainingName,
          originalName: itemName,
          predictedLabel: predictedLabel ?? prediction?.category,
          predictedCategoryId: null,
          correctedCategoryId: correctedCategoryId,
          correctedCategoryName: correctedCategoryName,
          confidence: prediction?.confidence,
          source: source,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      return -1;
    }
  }

  Future<int> correctionCount({bool onlyUnused = false}) =>
      _store.countCategoryCorrections(onlyUnused: onlyUnused);

  Future<Map<String, int>> correctionsByCategory() =>
      _store.getCorrectionCountsByCategory();

  Future<List<CategoryCorrection>> allCorrections({bool onlyUnused = false}) =>
      _store.getCategoryCorrections(onlyUnused: onlyUnused);

  /// Builds a labelled dataset (text → corrected category) from stored
  /// corrections, ready to be merged into the training corpus.
  ///
  /// Duplicate item names keep only the most recent correction, so a user who
  /// changes their mind twice does not add contradicting labels.
  Future<List<Map<String, String>>> buildTrainingDataset({
    bool onlyUnused = false,
  }) async {
    final List<CategoryCorrection> rows =
        await _store.getCategoryCorrections(onlyUnused: onlyUnused);
    return _dedupeLatest(rows).values.toList();
  }

  /// Keeps only the most recent correction per item name.
  ///
  /// Sorting ascending by timestamp (with id as a tiebreaker for same-millisecond
  /// writes) guarantees the last write wins, regardless of the store's ordering.
  Map<String, Map<String, String>> _dedupeLatest(
    Iterable<CategoryCorrection> rows,
  ) {
    final List<CategoryCorrection> sorted = rows.toList()
      ..sort((CategoryCorrection a, CategoryCorrection b) {
        final int byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) {
          return byTime;
        }
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });
    final Map<String, Map<String, String>> deduped =
        <String, Map<String, String>>{};
    for (final CategoryCorrection c in sorted) {
      deduped[c.itemName] = c.toTrainingSample();
    }
    return deduped;
  }

  /// Writes the training dataset to a JSON file and returns its path.
  ///
  /// Shape matches `assets/eval_dataset_dummy.json`
  /// (`{ "samples": [ { "text": ..., "label": ... } ] }`) so the exported file
  /// can be fed straight back into the training pipeline or the evaluator.
  Future<File> exportTrainingDataset({
    bool onlyUnused = true,
    bool markUsed = false,
  }) async {
    final List<CategoryCorrection> rows =
        await _store.getCategoryCorrections(onlyUnused: onlyUnused);
    final Map<String, Map<String, String>> deduped = _dedupeLatest(rows);

    final Map<String, dynamic> payload = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
      'source': 'user_corrections',
      'samples': deduped.values.toList(),
    };

    final Directory dir =
        _outputDirectory ?? await getApplicationDocumentsDirectory();
    final File file = File(
      '${dir.path}/training_corrections_'
      '${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

    if (markUsed && rows.isNotEmpty) {
      await _store.markCorrectionsUsed(
        rows.map((CategoryCorrection c) => c.id!).whereType<int>(),
      );
    }
    return file;
  }
}
