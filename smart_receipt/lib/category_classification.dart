import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_route.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'ocr/ocr_service.dart';
import 'ocr/receipt_classifier.dart';
import 'ocr/receipt_parser.dart';
import 'review_transaction.dart';
import 'theme_controller.dart';

/// Screen 5 - Category Classification.
///
/// Runs the on-device TF-IDF + Naive Bayes classifier over the item names that
/// were extracted by OCR, then forwards the classified items to the review
/// screen.
class CategoryClassificationScreen extends StatefulWidget {
  const CategoryClassificationScreen({super.key, required this.scan});

  final OcrScanResult scan;

  @override
  State<CategoryClassificationScreen> createState() =>
      _CategoryClassificationScreenState();
}

class _CategoryClassificationScreenState
    extends State<CategoryClassificationScreen> {
  final ReceiptClassifier _classifier = ReceiptClassifier();

  late final List<ItemPrediction> _predictions;

  @override
  void initState() {
    super.initState();
    final List<String> names = widget.scan.parsed.items
        .map((ParsedItem i) => i.name)
        .toList();
    _predictions = _classifier.classifyAll(names);
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
                    const _ModelCard(),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Hasil Klasifikasi',
                      trailing: Text(
                        '${predictions.length} item',
                        style:  TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (predictions.isEmpty)
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
                onPressed: () => Navigator.push(
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
                  style:  TextStyle(
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
                  style:  TextStyle(
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
      child:  Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: AppColors.amber),
          SizedBox(width: 12),
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
  const _ModelCard();

  static const List<List<String>> _metrics = <List<String>>[
    <String>['Akurasi', '92.4%'],
    <String>['Precision', '90.1%'],
    <String>['Recall', '89.6%'],
    <String>['F1-Score', '89.8%'],
  ];

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
                      'Model Naive Bayes',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ekstraksi fitur TF-IDF • 9 kategori',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              for (int i = 0; i < _metrics.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: AppColors.iconBox,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          _metrics[i][1],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _metrics[i][0],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
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
                'Confidence',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
