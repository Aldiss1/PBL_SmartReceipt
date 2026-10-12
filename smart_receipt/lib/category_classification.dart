import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'review_transaction.dart';

/// Screen 5 - Category Classification (TF-IDF + Naive Bayes results).
class CategoryClassificationScreen extends StatelessWidget {
  const CategoryClassificationScreen({super.key});

  static const List<_Prediction> _predictions = <_Prediction>[
    _Prediction(name: 'Indomie Goreng', category: 'Makanan', confidence: 0.97),
    _Prediction(name: 'Aqua 600ml', category: 'Minuman', confidence: 0.95),
    _Prediction(name: 'Sabun Lifebuoy', category: 'Perawatan Diri', confidence: 0.91),
    _Prediction(name: 'Tissue Paseo', category: 'Rumah Tangga', confidence: 0.88),
    _Prediction(name: 'Teh Botol Sosro', category: 'Minuman', confidence: 0.93),
    _Prediction(name: 'Roti Tawar', category: 'Makanan', confidence: 0.9),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    const _ModelCard(),
                    const SizedBox(height: 18),
                    const SectionHeader(
                      title: 'Hasil Klasifikasi',
                      trailing: Text(
                        '6 item',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final _Prediction p in _predictions) _PredictionCard(p: p),
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
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const ReviewTransactionScreen(),
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

class _Prediction {
  const _Prediction({
    required this.name,
    required this.category,
    required this.confidence,
  });

  final String name;
  final String category;
  final double confidence;
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
        color: Colors.white,
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
                child: const Icon(Icons.hub_outlined, size: 21, color: AppColors.orange),
              ),
              const SizedBox(width: 12),
              const Expanded(
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
                    SizedBox(height: 2),
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
                          style: const TextStyle(
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
                          style: const TextStyle(
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

  final _Prediction p;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(p.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(
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
              const Text(
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
                style: const TextStyle(
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
