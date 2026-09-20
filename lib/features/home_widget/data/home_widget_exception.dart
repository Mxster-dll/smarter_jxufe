/// 桌面小组件后台刷新（`home_widget_background.dart`）的异常。
///
/// 这个入口跑在**没有 UI 的后台 isolate**里，文案最终会进小组件或日志，
/// 所以更要保证 `toString()` 是干净的一句话（别带 `Exception: ` 前缀）。
/// 契约见 `lib/core/errors/app_exception.dart`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class HomeWidgetException extends AppException {
  const HomeWidgetException(super.message);
}
