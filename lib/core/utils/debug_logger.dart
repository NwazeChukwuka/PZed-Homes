import 'package:flutter/foundation.dart';

import 'debug_logger_stub.dart' if (dart.library.io) 'debug_logger_io.dart' as impl;

/// Async debug logger - schedules file writes off the UI thread.
/// Never blocks; failures are silently ignored.
/// Only runs when kDebugMode is true.
void debugLog(Map<String, dynamic> logData) {
  if (kDebugMode) {
    Future.microtask(() => impl.writeDebugLog(logData));
  }
}
