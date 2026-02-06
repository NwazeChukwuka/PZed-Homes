/// Stub implementation for platforms where dart:io is unavailable (e.g. web).
/// No-op - does not perform any file I/O.
Future<void> writeDebugLog(Map<String, dynamic> logData) async {
  // No-op on web - File API not available
}
