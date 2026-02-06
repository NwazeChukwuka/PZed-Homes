import 'dart:convert';
import 'dart:io';

/// Platform-specific implementation for async debug file logging.
/// Used on mobile/desktop where dart:io is available.
Future<void> writeDebugLog(Map<String, dynamic> logData) async {
  try {
    const path = r'c:\Users\user\PZed-Homes\PZed-Homes\.cursor\debug.log';
    final file = File(path);
    await file.writeAsString('${jsonEncode(logData)}\n', mode: FileMode.append);
  } catch (_) {
    // Silently ignore - logging must never affect app behavior
  }
}
