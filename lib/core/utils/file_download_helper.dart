import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart' as impl;

/// Triggers a CSV download. On web: downloads a file; elsewhere: copies to clipboard.
Future<void> triggerCsvDownload(String content, String filename) async {
  await impl.triggerCsvDownload(content, filename);
}
