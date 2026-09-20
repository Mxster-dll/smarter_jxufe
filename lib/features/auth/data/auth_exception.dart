/// 统一认证（CAS / MFA / 扫码）链路的**业务异常**。
///
/// 与 `TgcExpiredException`（会话失效族，见 `data/datasources/auth_remote_datasource.dart`）
/// 分工：那个 = 票据过期要重登；本类 = 流程本身没走通（拿不到重定向 / 用户取消 MFA /
/// 页面上下文缺失 / 重定向次数过多）。
///
/// 「用户取消 MFA 验证」也在本类里：它**不是错误**，但确实是从 `authorize()` 抛出来的
/// 控制流信号，调用方按文案提示即可（`friendlyErrorText`）。契约见
/// `lib/core/errors/app_exception.dart`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class AuthException extends AppException {
  const AuthException(super.message);
}
