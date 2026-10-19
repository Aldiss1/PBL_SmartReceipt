import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_receipt/models/receipt_model.dart';
import 'package:smart_receipt/ocr/receipt_classifier.dart';
import 'package:smart_receipt/services/correction_training_service.dart';

/// In-memory [CorrectionStore] so the training loop is testable without the
/// Flutter asset bundle or a device.
class _MemoryCorrectionStore implements CorrectionStore {
  final List<CategoryCorrection> rows = <CategoryCorrection>[];
  int _nextId = 1;

  @override
  Future<int> insertCategoryCorrection(CategoryCorrection correction) async {
    final int id = _nextId++;
    rows.add(
      CategoryCorrection(
        id: id,
        itemName: correction.itemName,
        originalName: correction.originalName,
        predictedLabel: correction.predictedLabel,
        predictedCategoryId: correction.predictedCategoryId,
        correctedCategoryId: correction.correctedCategoryId,
        correctedCategoryName: correction.correctedCategoryName,
        confidence: correction.confidence,
        source: correction.source,
        usedInTraining: correction.usedInTraining,
        createdAt: correction.createdAt,
      ),
    );
    return id;
  }

  @override
  Future<List<CategoryCorrection>> getCategoryCorrections({
    bool onlyUnused = false,
  }) async {
    final List<CategoryCorrection> out = rows
        .where((CategoryCorrection c) => !onlyUnused || !c.usedInTraining)
        .toList()
      ..sort((CategoryCorrection a, CategoryCorrection b) =>
          b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<int> countCategoryCorrections({bool onlyUnused = false}) async =>
      (await getCategoryCorrections(onlyUnused: onlyUnused)).length;

  @override
  Future<Map<String, int>> getCorrectionCountsByCategory() async {
    final Map<String, int> counts = <String, int>{};
    for (final CategoryCorrection c in rows) {
      counts[c.correctedCategoryName] =
          (counts[c.correctedCategoryName] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<int> markCorrectionsUsed(Iterable<int> ids) async {
    int touched = 0;
    for (int i = 0; i < rows.length; i++) {
      if (ids.contains(rows[i].id)) {
        final CategoryCorrection c = rows[i];
        rows[i] = CategoryCorrection(
          id: c.id,
          itemName: c.itemName,
          originalName: c.originalName,
          predictedLabel: c.predictedLabel,
          predictedCategoryId: c.predictedCategoryId,
          correctedCategoryId: c.correctedCategoryId,
          correctedCategoryName: c.correctedCategoryName,
          confidence: c.confidence,
          source: c.source,
          usedInTraining: true,
          createdAt: c.createdAt,
        );
        touched += 1;
      }
    }
    return touched;
  }
}

void main() {
  group('CorrectionTrainingService (in-memory store)', () {
    late _MemoryCorrectionStore store;
    late CorrectionTrainingService service;
    late Directory tmp;

    setUp(() {
      store = _MemoryCorrectionStore();
      service = CorrectionTrainingService(store: store);
      tmp = Directory.systemTemp.createTempSync('corrections_');
      service.outputDirectory = tmp;
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    test('records a correction using raw classifier input', () async {
      final int id = await service.recordCorrection(
        itemName: 'INDOMIE GORENG Rp 3.500',
        correctedCategoryName: 'Makanan',
        correctedCategoryId: 1,
        prediction: const ItemPrediction(
          name: 'INDOMIE GORENG',
          category: 'Rumah Tangga',
          confidence: 0.62,
        ),
      );

      expect(id, greaterThan(0));
      final CategoryCorrection saved = store.rows.single;
      // Stored verbatim (whitespace collapsed) so the training corpus matches
      // what the classifier actually vectorizes.
      expect(saved.itemName, 'INDOMIE GORENG Rp 3.500');
      expect(saved.originalName, 'INDOMIE GORENG Rp 3.500');
      expect(saved.correctedCategoryName, 'Makanan');
      expect(saved.correctedCategoryId, 1);
      // The overridden prediction is retained for auditability.
      expect(saved.predictedLabel, 'Rumah Tangga');
      expect(saved.confidence, closeTo(0.62, 1e-9));
    });

    test('ignores blank input', () async {
      final int id = await service.recordCorrection(
        itemName: '   ',
        correctedCategoryName: 'Makanan',
        correctedCategoryId: 1,
      );
      expect(id, -1);
      expect(store.rows, isEmpty);
    });

    test('counts and groups corrections by corrected category', () async {
      await service.recordCorrection(
        itemName: 'AYAM GEPREK',
        correctedCategoryName: 'Makanan',
        correctedCategoryId: 1,
      );
      await service.recordCorrection(
        itemName: 'TISU PASEO',
        correctedCategoryName: 'Rumah Tangga',
        correctedCategoryId: 3,
      );
      await service.recordCorrection(
        itemName: 'AQUA',
        correctedCategoryName: 'Minuman',
        correctedCategoryId: 2,
      );

      expect(await service.correctionCount(), 3);
      final Map<String, int> grouped = await service.correctionsByCategory();
      expect(grouped['Makanan'], 1);
      expect(grouped['Rumah Tangga'], 1);
      expect(grouped['Minuman'], 1);
    });

    test('training dataset dedupes by item name, keeping the latest', () async {
      await service.recordCorrection(
        itemName: 'KOPI ABC',
        correctedCategoryName: 'Minuman',
        correctedCategoryId: 1,
      );
      // Same item, user changes their mind.
      await service.recordCorrection(
        itemName: 'KOPI ABC',
        correctedCategoryName: 'Makanan',
        correctedCategoryId: 1,
      );

      final List<Map<String, String>> dataset =
          await service.buildTrainingDataset();
      expect(dataset.length, 1);
      expect(dataset.single['label'], 'Makanan');
    });

    test('exports a dataset file in the evaluator-compatible shape', () async {
      await service.recordCorrection(
        itemName: 'PERTALITE',
        correctedCategoryName: 'Transportasi',
        correctedCategoryId: 2,
      );

      final File file = await service.exportTrainingDataset();
      expect(file.existsSync(), isTrue);
      expect(file.path, endsWith('.json'));

      final Map<String, dynamic> json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['source'], 'user_corrections');
      final List<dynamic> samples = json['samples'] as List<dynamic>;
      expect(samples.length, 1);
      expect((samples.single as Map)['text'], 'PERTALITE');
      expect((samples.single as Map)['label'], 'Transportasi');
    });

    test('markUsed excludes rows from the next unused export', () async {
      await service.recordCorrection(
        itemName: 'AQUA',
        correctedCategoryName: 'Minuman',
        correctedCategoryId: 2,
      );
      expect(await service.correctionCount(onlyUnused: true), 1);

      await service.exportTrainingDataset(onlyUnused: true, markUsed: true);
      expect(await service.correctionCount(onlyUnused: true), 0);
      expect(await service.correctionCount(), 1);
    });
  });

  group('DatabaseHelper correction storage (in-memory SQLite)', () {
    setUpAll(() {
      sqfliteFfiInit();
      // Points sqflite at the FFI factory so tests run on desktop.
      databaseFactory = databaseFactoryFfi;
    });

    test('creates the corrections table and round-trips rows', () async {
      // A physical temp DB keeps the test isolated from the app database.
      final Directory dir = Directory.systemTemp.createTempSync('corr_db_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final Database db = await databaseFactory.openDatabase(
        '${dir.path}/test.db',
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (Database d, int v) async {
            await d.execute('''
              CREATE TABLE category_corrections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                item_name TEXT NOT NULL,
                original_name TEXT,
                predicted_label TEXT,
                predicted_category_id INTEGER,
                corrected_category_id INTEGER NOT NULL,
                corrected_category_name TEXT NOT NULL,
                confidence REAL,
                source TEXT NOT NULL DEFAULT 'review',
                used_in_training INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      addTearDown(() => db.close());

      final int id = await db.insert('category_corrections', <String, Object?>{
        'item_name': 'mie instan goreng',
        'original_name': 'INDOMIE GORENG',
        'predicted_label': 'Rumah Tangga',
        'corrected_category_id': 1,
        'corrected_category_name': 'Makanan',
        'confidence': 0.61,
        'source': 'review',
        'used_in_training': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(id, greaterThan(0));

      final List<Map<String, Object?>> rows =
          await db.query('category_corrections');
      final CategoryCorrection parsed = CategoryCorrection.fromMap(rows.single);
      expect(parsed.itemName, 'mie instan goreng');
      expect(parsed.correctedCategoryName, 'Makanan');
      expect(parsed.predictedLabel, 'Rumah Tangga');
      expect(parsed.usedInTraining, isFalse);
      expect(parsed.toTrainingSample(),
          <String, String>{'text': 'mie instan goreng', 'label': 'Makanan'});

      // The used_in_training flag can be flipped, closing the feedback loop.
      await db.update(
        'category_corrections',
        <String, Object?>{'used_in_training': 1},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      final List<Map<String, Object?>> after =
          await db.query('category_corrections', where: 'used_in_training = 1');
      expect(after.length, 1);
    });
  });
}
