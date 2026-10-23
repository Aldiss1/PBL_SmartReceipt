import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps the captured receipt image alongside the saved transaction.
///
/// `image_picker` hands back a file in the app's temporary directory, which iOS
/// is free to purge at any time (and does, especially under storage pressure).
/// Storing that path in SQLite would therefore give a working thumbnail today
/// and a broken one next week. Copying the file into the documents directory
/// makes the preview durable for the lifetime of the receipt.
class ReceiptImageStore {
  ReceiptImageStore({Directory? directory}) : _override = directory;

  /// Injected in tests so nothing touches the real documents directory.
  final Directory? _override;

  static const String _folder = 'receipt_images';

  Future<Directory> _targetDirectory() async {
    final Directory base = _override ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/$_folder');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Copies [sourcePath] into permanent storage and returns the new path.
  ///
  /// Returns [sourcePath] unchanged when the source is already inside the
  /// managed folder (so re-saving does not duplicate files), and `null` when the
  /// source is missing or the copy fails — callers store that as "no image"
  /// rather than pointing at a file that will vanish.
  Future<String?> persist(String? sourcePath) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      return null;
    }

    final Directory dir = await _targetDirectory();
    if (source.parent.absolute.path == dir.absolute.path) {
      return source.path;
    }

    final String extension = _extensionOf(sourcePath);
    final String name =
        'receipt_${DateTime.now().millisecondsSinceEpoch}$extension';
    final File target = File('${dir.path}/$name');
    try {
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the stored image for a receipt, if it is one we manage.
  Future<void> remove(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) {
      return;
    }
    final Directory dir = await _targetDirectory();
    final File file = File(imagePath);
    if (file.parent.absolute.path != dir.absolute.path) {
      return;
    }
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {
        // A leftover file is harmless; never fail a delete over it.
      }
    }
  }

  /// Whether [imagePath] still points at a readable file.
  static bool exists(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return false;
    }
    return File(imagePath).existsSync();
  }

  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return '.jpg';
    }
    final String ext = path.substring(dot).toLowerCase();
    const Set<String> allowed = <String>{'.jpg', '.jpeg', '.png', '.heic'};
    return allowed.contains(ext) ? ext : '.jpg';
  }
}
