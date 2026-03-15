// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

/// Web: triggers a file download with the given content and filename.
Future<void> triggerCsvDownload(String content, String filename) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
