import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';

/// Screen 1 - SmartReceipt logo / launch screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        navigateTab(context, 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: <Widget>[
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.8, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (BuildContext context, double value, Widget? child) {
                  return Opacity(opacity: value.clamp(0, 1), child: child);
                },
                child: const _LogoMark(),
              ),
              const SizedBox(height: 26),
              const _LogoWordmark(),
              const SizedBox(height: 14),
              const Text(
                'Analisis & klasifikasi pengeluaran\nlangsung dari foto struk',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.orange,
                  backgroundColor: AppColors.track,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Politeknik Negeri Malang • 2026',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF141A34), Color(0xFF232A46)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          const Center(
            child: Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: AppColors.orange,
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoWordmark extends StatelessWidget {
  const _LogoWordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <TextSpan>[
              const TextSpan(
                text: 'Smart',
                style: TextStyle(color: AppColors.textDark),
              ),
              const TextSpan(
                text: 'Receipt',
                style: TextStyle(color: AppColors.orange),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ANALYZER',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 6,
            fontWeight: FontWeight.w600,
            color: AppColors.textLabel,
          ),
        ),
      ],
    );
  }
}
