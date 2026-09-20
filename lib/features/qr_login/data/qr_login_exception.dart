/// 扫码 / MFA 登录链路的异常（2026-09-20 · ③ 错误体系收敛）。
///
/// 收敛前这一族（`data/datasources/` 的 3 个数据源 + `data/repositories/` +
/// `presentation/` 共 28 处）全是裸 `throw Exception('文案')` —— `toString()` 出来是
/// `'Exception: 文案'`，界面层写 `'登录失败：$e'` 就会把英文类名一起打给用户。
///
/// 契约见 `lib/core/errors/app_exception.dart`：`message` = **能直接上屏的一句话**，
/// `toString()` 恒等于 `message`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class QrLoginException extends AppException {
  const QrLoginException(super.message);
}
