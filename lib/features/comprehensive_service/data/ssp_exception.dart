/// 综合服务族（竞赛 / 志愿时长 / 第二课堂 / 蛟湖阅读）的**业务异常**。
///
/// 与 `SspSessionExpiredException`（会话失效，见 `data/datasource/ssp_auth_remote_datasource.dart`）
/// 分工：本类 = 「会话没问题，但这次操作失败了」（请求失败 / 页面结构异常 / 未登录的前置校验）。
/// 2026-09-20 前这一族是 31 处裸 `throw Exception('文案')` —— `toString()` 会带上
/// `Exception: ` 英文前缀进用户视野，且没有任何公共类型。契约见
/// `lib/core/errors/app_exception.dart`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class SspApiException extends AppException {
  const SspApiException(super.message);
}
