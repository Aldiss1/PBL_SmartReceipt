import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import '../widgets/receipt_photo_preview.dart';
import '../models/models.dart';
import '../ocr/ocr_abbreviations.dart';
import '../ocr/ocr_service.dart';
import '../ocr/receipt_classifier.dart';
import '../ocr/receipt_parser.dart';
import '../ocr/tfidf_classifier.dart';
import '../services/ml_classifier_service.dart';
import '../services/receipt_image_store.dart';
import 'review_transaction.dart';
import '../theme/theme_controller.dart';


/// Screen 5 - Category Classification.
///
/// Runs the on-device TF-IDF + Naive Bayes classifier over the item names that
/// were extracted by OCR, then forwards the classified items to the review
/// screen.
///
/// Classification is performed by the exported model
/// (`assets/model_kategori_produk.json`) executed by [TfidfNaiveBayesEngine]
/// through [MLClassifierService]. Items the model is unsure about are flagged
/// for manual confirmation instead of guessing.
class CategoryClassificationScreen extends StatefulWidget {
  const CategoryClassificationScreen({super.key, required this.scan});

  final OcrScanResult scan;

  @override
  State<CategoryClassificationScreen> createState() =>
      _CategoryClassificationScreenState();
}

class _CategoryClassificationScreenState
    extends State<CategoryClassificationScreen> {
  final ReceiptClassifier _fallbackClassifier = ReceiptClassifier();
  final MLClassifierService _ml = MLClassifierService();

  late final List<String> _names;
  List<ItemPrediction> _predictions = const <ItemPrediction>[];
  int _reviewCount = 0;
  bool _modelReady = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _names = widget.scan.parsed.items
        .map((ParsedItem i) => i.name)
        .toList();
    _loadAndClassify();
  }

  @override
  void dispose() {
    _ml.dispose();
    super.dispose();
  }

  /// Loads the exported TF-IDF + Naive Bayes model, then classifies every item.
  ///
  /// Without the model we fall back to the built-in lexicon classifier so the
  /// scan flow never dead-ends on a classification error.
  Future<void> _loadAndClassify() async {
    final bool ready = await _ml.loadModel();
    if (!mounted) {
      return;
    }
    final List<ItemPrediction> predictions = ready
        ? _names.map<ItemPrediction>(_classifyOne).toList()
        : _fallbackClassifier.classifyAll(_names);
    setState(() {
      _modelReady = ready;
      _predictions = predictions;
      _reviewCount =
          predictions.where((ItemPrediction p) => p.needsReview).length;
      _loading = false;
    });
  }

  /// Expands minimarket abbreviations before classification.
  final OcrAbbreviationExpander _expander = OcrAbbreviationExpander();

  ItemPrediction _classifyOne(String name) {
    // Classify the raw OCR text first: the exported model was trained on raw
    // item names with a char n-gram analyzer, so brand tokens like "lifebuoy"
    // that survived OCR intact should not be rewritten.
    final TfidfPrediction rawPrediction = _ml.predict(name);

    // Also classify the abbreviation-expanded text. Minimarket receipts
    // truncate aggressively ("GRG" = goreng, "BTL" = botol, "RDSO" = rinso),
    // and the model has never seen these abbreviations. Expanding first gives
    // the char n-grams something to match against.
    final String expanded = _expander.expand(name);
    final TfidfPrediction expandedPrediction =
        expanded != name ? _ml.predict(expanded) : rawPrediction;

    // Pick whichever prediction the model is more confident about (higher
    // margin = more separation between the top two classes).
    final TfidfPrediction best =
        expandedPrediction.margin > rawPrediction.margin
            ? expandedPrediction
            : rawPrediction;

    return ItemPrediction(
      name: name,
      category: kCategoryNameForId(best.categoryId),
      confidence: best.confidence,
      needsReview: best.needsReview,
    );
  }


  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    final List<ItemPrediction> predictions = _predictions;

    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Klasifikasi Kategori',
              subtitle: 'TF-IDF + Naive Bayes',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _StoreSummary(scan: widget.scan),
                    const SizedBox(height: 16),
                    _ReceiptPhotoSection(scan: widget.scan),
                    _ModelCard(
                      classCount: _modelReady ? _ml.classCount : 9,
                      fromExportedModel: _modelReady,
                    ),
                    if (_reviewCount > 0) ...<Widget>[
                      const SizedBox(height: 12),
                      _ReviewNotice(count: _reviewCount),
                    ],
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Hasil Klasifikasi',
                      trailing: Text(
                        '${predictions.length} item',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const _ClassifyingCard()
                    else if (predictions.isEmpty)
                      const _NoItemsCard()
                    else
                      for (final ItemPrediction p in predictions)
                        _PredictionCard(p: p),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: PrimaryButton(
                label: 'Lanjut ke Review',
                icon: Icons.arrow_forward,
                onPressed: _loading
                    ? null
                    : () => Navigator.push(
                          context,
                          appRoute(
                            ReviewTransactionScreen(
                              scan: widget.scan,
                              predictions: predictions,
                            ),
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the model loads and items are classified.
class _ClassifyingCard extends StatelessWidget {
  const _ClassifyingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.navy),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Menjalankan model TF-IDF + Naive Bayes…',
              style: TextStyle(fontSize: 12.5, color: AppColors.textLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warns that some items were flagged for manual confirmation.
class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.rule_folder_outlined, size: 20, color: AppColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count item perlu dikonfirmasi karena dua kategori teratas '
              'terlalu berdekatan. Perbaiki kategorinya di langkah review — '
              'koreksi Anda ikut menyempurnakan model.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows store/date/total recovered by OCR above the classifier card.
class _StoreSummary extends StatelessWidget {
  const _StoreSummary({required this.scan});

  final OcrScanResult scan;

  @override
  Widget build(BuildContext context) {
    final DateTime? date = scan.parsed.date;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          const IconBox(icon: Icons.storefront_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  scan.parsed.store,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date != null
                      ? '${formatDateTime(date)} • ${scan.parsed.paymentMethod}'
                      : 'Hasil OCR • ${scan.parsed.paymentMethod}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Receipt photo, so the user can sanity-check the categories against the
/// actual print without leaving the screen.
///
/// Compact by default (this screen is about the classification result, not about
/// reading the receipt) but tappable to open the full-screen zoomable viewer.
/// Renders nothing at all when the capture is unavailable, so the layout does
/// not gain a gap for scans that have no image.
class _ReceiptPhotoSection extends StatelessWidget {
  const _ReceiptPhotoSection({required this.scan});

  final OcrScanResult scan;

  @override
  Widget build(BuildContext context) {
    final String path = scan.sourcePath;
    if (path.isEmpty || !ReceiptImageStore.exists(path)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'Foto Struk',
            trailing: Text(
              'Ketuk untuk memperbesar',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ReceiptPhotoPreview(
            imagePath: path,
            heroTag: 'classification-receipt-photo',
            height: 180,
          ),
        ],
      ),
    );
  }
}

class _NoItemsCard extends StatelessWidget {
  const _NoItemsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: AppColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'OCR tidak menemukan baris item yang bisa diklasifikasi. '
              'Anda masih bisa menambah item secara manual di langkah review.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.classCount,
    required this.fromExportedModel,
  });

  /// Number of classes the active model knows about.
  final int classCount;

  /// Whether the exported TF-IDF + Naive Bayes model is driving predictions or
  /// the built-in lexicon fallback is in use.
  final bool fromExportedModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.hub_outlined, size: 21, color: AppColors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      fromExportedModel
                          ? 'Model TF-IDF + Naive Bayes'
                          : 'Klasifikasi Cadangan (Lexicon)',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fromExportedModel
                          ? 'Ekstraksi fitur TF-IDF • $classCount kelas • '
                              'on-device'
                          : 'Model ML tidak dapat dimuat • memakai aturan '
                              'kata kunci',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ModelStatus(
            fromExportedModel: fromExportedModel,
            classCount: classCount,
          ),
        ],
      ),
    );
  }
}

/// Replaces the old hard-coded accuracy/precision/recall/F1 numbers.
///
/// Real evaluation metrics now come from
/// `assets/eval_dataset_dummy.json` and are computed by
/// `ModelEvaluator` — the metrics card on the Analysis screen reports them, so
/// this card only states which model is active.
class _ModelStatus extends StatelessWidget {
  const _ModelStatus({
    required this.fromExportedModel,
    required this.classCount,
  });

  final bool fromExportedModel;
  final int classCount;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        fromExportedModel ? AppColors.green : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.iconBox,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            fromExportedModel ? Icons.verified_outlined : Icons.info_outline,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fromExportedModel
                  ? 'Model aktif: $classCount kelas, dijalankan on-device.'
                  : 'Model belum tersedia; hasil di bawah bersifat perkiraan.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.p});

  final ItemPrediction p;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(p.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBox(icon: c.icon, size: 38, iconSize: 19, background: c.color.withValues(alpha: 0.14), color: c.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              CategoryChip(category: p.category, dense: true),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Text(
                p.needsReview ? 'Confidence (perlu review)' : 'Confidence',
                style: TextStyle(
                  fontSize: 11,
                  color: p.needsReview ? AppColors.amber : AppColors.textMuted,
                  fontWeight:
                      p.needsReview ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.confidence,
                    minHeight: 7,
                    backgroundColor: AppColors.track,
                    valueColor: AlwaysStoppedAnimation<Color>(c.color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(p.confidence * 100).round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
