import 'dart:io';

/// Removes a throwaway directory after a test.
///
/// Windows keeps a handle on a SQLite file for a moment after `close()`, so a
/// plain `deleteSync` occasionally throws `PathAccessException (errno = 32)` and
/// fails a test that already passed. That only shows up when the whole suite runs
/// in parallel, which makes it look like flakiness in whatever ran alongside it.
///
/// The retries are bounded: a folder still locked after a second is a real leak
/// and the failure should surface.
Future<void> deleteTempDir(Directory dir) async {
  for (int attempt = 0; attempt < 20; attempt++) {
    if (!dir.existsSync()) {
      return;
    }
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  dir.deleteSync(recursive: true);
}
