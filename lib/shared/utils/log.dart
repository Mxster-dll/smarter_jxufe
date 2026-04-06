import 'dart:developer' as developer;

/// 记录信息 蓝色
void logInfo(String msg) {
  developer.log('\x1B[34m$msg\x1B[0m');
}

/// 记录成功 绿色
void logSuccess(String msg) {
  developer.log('\x1B[32m$msg\x1B[0m');
}

/// 记录警告 黄色
void logWarning(String msg) {
  developer.log('\x1B[33m$msg\x1B[0m');
}

/// 记录错误 红色
void logError(String msg) {
  developer.log('\x1B[31m$msg\x1B[0m');
}
