import 'package:flutter/foundation.dart';

import 'debug_logger_stub.dart' if (dart.library.io) 'debug_logger_io.dart' as impl;

void debugLog(Map<String, dynamic> logData) {
  if (kDebugMode) {
    Future.microtask(() => impl.writeDebugLog(logData));
  }
}

