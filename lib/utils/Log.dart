import 'dart:developer' as developer;

void logInfo(String msg) {
  developer.log('\x1B[34m$msg\x1B[0m');
}

void logSuccess(String msg) {
  developer.log('\x1B[32m$msg\x1B[0m');
}

void logWarning(String msg) {
  developer.log('\x1B[33m$msg\x1B[0m');
}

void logError(String msg) {
  developer.log('\x1B[31m$msg\x1B[0m');
}
