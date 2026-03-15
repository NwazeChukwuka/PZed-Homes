import 'package:flutter/services.dart';

/// Stub: copies text to clipboard. Used on non-web platforms where blob download is not available.
Future<void> triggerCsvDownload(String content, String filename) async {
  await Clipboard.setData(ClipboardData(text: content));
  // Caller should show a snackbar e.g. "CSV copied to clipboard (save from your editor)"
}
