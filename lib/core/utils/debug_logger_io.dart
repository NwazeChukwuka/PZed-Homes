import 'dart:convert';
import 'dart:io';

Future<void> writeDebugLog(Map<String, dynamic> logData) async {
  try {
    const path = r'c:\Users\user\PZed-Homes\PZed-Homes\.cursor\debug.log';
    final file = File(path);
    await file.writeAsString('${jsonEncode(logData)}\n', mode: FileMode.append);
  } catch (_) {
  }
}


