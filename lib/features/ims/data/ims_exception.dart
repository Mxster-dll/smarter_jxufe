/// 教务（IMS）族的**业务异常** —— 页面结构变了 / 请求失败 / 解析失败。
///
/// 与 `JwSessionExpiredException`（`lib/core/network/jw_page_decoding.dart`，会话失效）
/// 分工：那个管「要重新换票」，本类管「拿到了响应但这次没成」。
///
/// 本文件的另一个意义：教务此前**没有自己的共享数据层目录**，27 处裸 `throw Exception`
/// 散在 9 个子模块（auth / curriculum / grades / graduation_requirements / schedule /
/// student_info）里，各写各的文案。契约见 `lib/core/errors/app_exception.dart`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class ImsApiException extends AppException {
  const ImsApiException(super.message);
}
