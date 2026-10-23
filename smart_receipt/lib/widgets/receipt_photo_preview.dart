import 'dart:io';

import 'package:flutter/material.dart';

import '../services/receipt_image_store.dart';
import '../theme/app_colors.dart';

/// Thumbnail of a receipt photo that opens a full-screen, zoomable viewer.
///
/// Shared by the review screen (where the user corrects OCR output and needs to
/// compare against the original print) and the transaction detail screen (where
/// the saved total is verified against the photo). Keeping one implementation
/// means the zoom behaviour, the missing-file fallback and the Hero transition
/// stay identical in both places.
class ReceiptPhotoPreview extends StatelessWidget {
  const ReceiptPhotoPreview({
    super.key,
    required this.imagePath,
    required this.heroTag,
    this.height = 210,
    this.borderRadius = 18,
  });

  /// Absolute path to the stored capture. Null or missing renders nothing.
  final String? imagePath;

  /// Unique Hero tag; two previews of the same receipt must not share one.
  final String heroTag;

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final String? path = imagePath;
    if (path == null || path.isEmpty || !ReceiptImageStore.exists(path)) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => ReceiptPhotoViewer(path: path, heroTag: heroTag),
        ),
      ),
      child: Hero(
        tag: heroTag,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.iconBox,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // `contain` rather than `cover`: cropping the edges of a receipt
              // would hide exactly the totals the user is checking.
              Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 28,
                            color: AppColors.textMuted,
                          ),
                        ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.zoom_out_map, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Perbesar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen receipt viewer with pinch-zoom and pan.
class ReceiptPhotoViewer extends StatelessWidget {
  const ReceiptPhotoViewer({
    super.key,
    required this.path,
    required this.heroTag,
  });

  final String path;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stack,
                          ) => const Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                            color: Colors.white54,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Tutup',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
