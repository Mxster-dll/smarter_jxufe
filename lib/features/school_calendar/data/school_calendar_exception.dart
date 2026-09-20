/// 校历（`jwxt.jxufe.edu.cn/SchoolCalendar.jsp`）链路的业务异常。
///
/// 会话失效另走 `JwSessionExpiredException`（`lib/core/network/jw_page_decoding.dart`）；
/// 本类管「拿到了响应但解析不了 / 服务端没给会话标识」这类。
/// 契约见 `lib/core/errors/app_exception.dart`。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';

class SchoolCalendarException extends AppException {
  const SchoolCalendarException(super.message);
}
