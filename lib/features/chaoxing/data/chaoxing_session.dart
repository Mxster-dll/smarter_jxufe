/// 学习通会话 —— Cookie 罐 + 收件箱 token。
///
/// 两者同生共死：token 就藏在**登录链最后一跳**（`https://i.chaoxing.com/base`）
/// 的页面里，所以建立会话时顺手抠出来，省掉一次请求；会话换新时 token 也会换，
/// 因此它们必须一起更新，不能各自缓存。
library;

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_cookie_jar.dart';

/// 一次学习通会话。
class ChaoxingSession {
  ChaoxingSession({required this.jar, this.noticeToken});

  /// 按域匹配的 Cookie 罐。
  final SessionCookieJar jar;

  /// 收件箱签名 token（`…/pc/notice/myNotice?s=<token>`）；认不出时为 null。
  String? noticeToken;

  /// 会话是否已就位（学习通 passport Cookie 是否落在能覆盖 `i.chaoxing.com` 的域上）。
  bool get isAlive => jar.hasPassport;

  /// 能否取通知（有会话 + 有 token）。
  bool get canFetchNotices => isAlive && (noticeToken ?? '').isNotEmpty;

  @override
  String toString() =>
      'ChaoxingSession(passport=$isAlive, noticeToken=${noticeToken == null ? '无' : '有'}, $jar)';
}

/// 学习通会话建立/使用失败。
class ChaoxingSessionException extends AppException {
  ChaoxingSessionException(super.message);
}

/// 会话过期（目标域把请求踢回登录页）—— 适配器据此**只重换一次**再重试。
class ChaoxingSessionExpiredException extends ChaoxingSessionException implements SessionExpiredException {
  ChaoxingSessionExpiredException(super.message);
}

/// **被学习通风控拦截**（`202` + 4527 B 的「【9010】操作异常，请输入图片中的验证码」页）。
///
/// 与 [ChaoxingSessionExpiredException] **必须分开**：这不是会话失效 —— 换票没用，
/// 而且风控窗口按实测**至少 60 秒**（突发 24 并发触发后，每 1 秒探测一次、60 次全中）。
/// 因此上层口径是「**本次取数作废、保留上次数据、冷却一段时间**」，
/// 既不要重试、也不要把空结果当成「这门课没有作业」。
class ChaoxingChallengedException extends ChaoxingSessionException {
  ChaoxingChallengedException(super.message);
}

/// **页面拿到了但不是业务页**（结构变了 / 空的业务页）。
///
/// 用途：把「真没数据」与「没拿到可信页面」分开 —— 前者是正常空态（如作业页写着
/// 「暂无内容」），后者**必须算失败**，否则一门课的作业会静默消失。
class ChaoxingPageException extends ChaoxingSessionException {
  ChaoxingPageException(super.message);
}
