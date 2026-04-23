import 'package:flutter/services.dart';

Future<void> triggerCsvDownload(String content, String filename) async {
  await Clipboard.setData(ClipboardData(text: content));
}


