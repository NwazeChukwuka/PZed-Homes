import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart' as impl;

Future<void> triggerCsvDownload(String content, String filename) async {
  await impl.triggerCsvDownload(content, filename);
}

