import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_route.dart';
import 'app_widgets.dart';
import 'ocr_processing.dart';
import 'receipt_mock.dart';
import 'theme_controller.dart';

/// Screen 2 - Scan Receipt.
class ScanReceiptScreen extends StatelessWidget {
  const ScanReceiptScreen({super.key});

  void _proceed(BuildContext context) {
    Navigator.pushReplacement(
      context,
      appRoute(const OcrProcessingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Scan Struk',
              subtitle: 'Ambil foto struk belanja',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _Viewfinder(),
                    const SizedBox(height: 18),
                    const _TipCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
              child: Column(
                children: <Widget>[
                  PrimaryButton(
                    label: 'Ambil Foto',
                    icon: Icons.photo_camera_outlined,
                    onPressed: () => _proceed(context),
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Pilih dari Galeri',
                    icon: Icons.image_outlined,
                    onPressed: () => _proceed(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.84,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.viewfinderGradient,
          ),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Opacity(
                opacity: 0.9,
                child: Transform.rotate(
                  angle: -0.02,
                  child: const ReceiptMock(width: 156),
                ),
              ),
            ),
            Positioned(top: 16, left: 16, child: _corner(top: true, left: true)),
            Positioned(top: 16, right: 16, child: _corner(top: true, right: true)),
            Positioned(bottom: 16, left: 16, child: _corner(bottom: true, left: true)),
            Positioned(bottom: 16, right: 16, child: _corner(bottom: true, right: true)),
            const Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Row(
                children: <Widget>[
                  _Pill(label: 'AUTO', icon: Icons.auto_awesome),
                  Spacer(),
                  _RoundIcon(icon: Icons.flash_on),
                  SizedBox(width: 10),
                  _RoundIcon(icon: Icons.grid_on),
                ],
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: Text(
                'Posisikan struk di dalam bingkai',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC7CBD6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corner({bool top = false, bool left = false, bool bottom = false, bool right = false}) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: AppColors.orange, width: 3) : BorderSide.none,
          bottom: bottom ? BorderSide(color: AppColors.orange, width: 3) : BorderSide.none,
          left: left ? BorderSide(color: AppColors.orange, width: 3) : BorderSide.none,
          right: right ? BorderSide(color: AppColors.orange, width: 3) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: top && left ? const Radius.circular(10) : Radius.zero,
          topRight: top && right ? const Radius.circular(10) : Radius.zero,
          bottomLeft: bottom && left ? const Radius.circular(10) : Radius.zero,
          bottomRight: bottom && right ? const Radius.circular(10) : Radius.zero,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: const Color(0xFF3A2A00)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFF3A2A00),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.promoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lightbulb_outline, size: 18, color: AppColors.amber),
              SizedBox(width: 8),
              Text(
                'Tips hasil OCR terbaik',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _Tip(text: 'Pastikan seluruh struk berada di dalam bingkai'),
          const _Tip(text: 'Gunakan pencahayaan yang cukup, hindari bayangan'),
          const _Tip(text: 'Tahan kamera stabil agar teks tidak buram'),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
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
