import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../theme/theme_controller.dart';

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
    ThemeScope.watch(context);
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.8, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutBack,
                      builder:
                          (BuildContext context, double value, Widget? child) {
                            return Opacity(
                              opacity: value.clamp(0, 1),
                              child: child,
                            );
                          },
                      child: const _LogoMark(),
                    ),
                    const SizedBox(height: 26),
                    const _LogoWordmark(),
                    const SizedBox(height: 14),
                    Text(
                      'Analisis & klasifikasi pengeluaran\nlangsung dari foto struk',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.orange,
                        backgroundColor: AppColors.track,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Politeknik Negeri Malang • 2026',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
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

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    final Color? solid = AppColors.brandSolid;
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: solid,
        gradient: solid == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.brandGradient,
              )
            : null,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (solid ?? AppColors.navy).withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Center(
            child: Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: AppColors.brandIcon,
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.brandIcon,
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
              TextSpan(
                text: 'Smart',
                style: TextStyle(color: AppColors.textDark),
              ),
              TextSpan(
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
        Text(
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
