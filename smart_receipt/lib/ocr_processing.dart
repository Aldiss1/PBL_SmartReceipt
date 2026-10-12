import 'dart:async';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
import 'category_classification.dart';
import 'receipt_mock.dart';

/// Screen 3 - OCR Processing.
class OcrProcessingScreen extends StatefulWidget {
  const OcrProcessingScreen({super.key});

  @override
  State<OcrProcessingScreen> createState() => _OcrProcessingScreenState();
}

class _OcrProcessingScreenState extends State<OcrProcessingScreen> {
  static const List<_OcrStep> _steps = <_OcrStep>[
    _OcrStep(label: 'Mendeteksi tepi struk', icon: Icons.crop_free),
    _OcrStep(label: 'Meningkatkan kualitas gambar', icon: Icons.auto_fix_high),
    _OcrStep(label: 'Membaca teks (OCR)', icon: Icons.text_fields),
    _OcrStep(label: 'Menstrukturkan data transaksi', icon: Icons.table_rows_outlined),
  ];

  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (Timer t) {
      if (!mounted) {
        return;
      }
      if (_current >= _steps.length - 1) {
        t.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const CategoryClassificationScreen(),
          ),
        );
        return;
      }
      setState(() => _current++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (_current + 1) / _steps.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Memproses OCR',
              subtitle: 'Mohon tunggu sebentar',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _Preview(),
                    const SizedBox(height: 22),
                    Row(
                      children: <Widget>[
                        const Text(
                          'Progres',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOut,
                        builder: (BuildContext context, double value, Widget? child) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 9,
                            backgroundColor: AppColors.track,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < _steps.length; i++)
                            _StepRow(
                              step: _steps[i],
                              done: i < _current,
                              active: i == _current,
                              last: i == _steps.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrStep {
  const _OcrStep({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 190,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF141A34), Color(0xFF232A46)],
          ),
        ),
        child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Opacity(
                  opacity: 0.55,
                  child: Transform.rotate(
                    angle: -0.02,
                    child: const SizedBox(
                      width: 112,
                      height: 148,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: ReceiptMock(width: 132),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 104,
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 26),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.orange.withValues(alpha: 0.7),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              top: 14,
              left: 14,
              child: _Tag(icon: Icons.document_scanner_outlined, label: 'Scan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.orange),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.done,
    required this.active,
    required this.last,
  });

  final _OcrStep step;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final bool complete = done || active;
    return Padding(
      padding: EdgeInsets.only(top: 14, bottom: last ? 14 : 0),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: complete ? AppColors.navy : AppColors.iconBox,
              borderRadius: BorderRadius.circular(11),
            ),
            child: done
                ? const Icon(Icons.check, size: 17, color: AppColors.orange)
                : Icon(
                    step.icon,
                    size: 17,
                    color: active ? AppColors.orange : const Color(0xFF8A93A8),
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.textDark : AppColors.textLabel,
              ),
            ),
          ),
          if (active)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.orange,
                backgroundColor: AppColors.track,
              ),
            )
          else if (done)
            const Text(
              'Selesai',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.green,
              ),
            ),
        ],
      ),
    );
  }
}
