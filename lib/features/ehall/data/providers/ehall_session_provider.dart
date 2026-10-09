/// 「智慧江财」内嵌页的登录态解析（2026-10-08 立 · AGENTS.md §40）。
///
/// 一件事：**把 App 的统一认证 TGC 交给内嵌浏览器**。
///
/// 为什么必须由 App 先做一步：内嵌浏览器的 Cookie 罐与 app 的 `dio` 是两套东西，
/// 浏览器自己不认得这个账号。而 CAS 的 SSO 只看 `ssl.jxufe.edu.cn` 上的 `TGC`
/// Cookie —— 于是「把 TGC 写进浏览器」就等于「已登录」（原理与实测链见
/// `core/network/cas_browser_session.dart`）。
///
/// 第二步（换票）刻意**交给浏览器自己走**，而不在 Dart 里换好票再把回调地址塞给
/// WebView：`service` 上那个 `sessionToken` 是 ehall **每次现生成**的，只有浏览器
/// 从头走那条 302 链才拿得到；Dart 侧硬拼一个 `loginSuccess?ticket=…` 没有 token，
/// 属于没验证过的路径。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cas_browser_session.dart';
import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_for_account_provider.dart';
import 'package:smarter_jxufe/features/ehall/data/ehall_endpoints.dart';

/// 拿不到可用的统一认证登录态（TGC 死了且静默重登没成功）。
class EhallSessionException extends AppException {
  const EhallSessionException(super.message);
}

/// 「智慧江财」的内嵌请求：**先写 TGC，再开登录入口**。
///
/// [AuthRepository.ensureTgcFor] 内部复用 `getServiceRedirectUrl` —— 它会拿 TGC 去
/// CAS 换一次票，**TGC 过期就用缓存凭据静默重登一次再重试**，因此返回 Right 时手里
/// 那枚 TGC 一定是 CAS 当下认的。这一步不能省：实测（2026-10-08）杀掉 App 之后
/// `auth` box 里的旧 TGC 会被 CAS 用 `Max-Age=0` 直接删掉，此时若把死票写进浏览器，
/// 用户看到的是**统一认证登录页**而不是门户。
final ehallWebSessionProvider = FutureProvider<EmbeddedWebRequest>((ref) async {
  final account = ref.watch(currentAccountProvider);
  final auth = await ref.watch(
    authRepositoryForAccountProvider(account).future,
  );
  final result = await auth.ensureTgcFor(ehallCasLoginUrl);
  // 失败在 provider 边界转成异常（与 `ims_session_provider.dart` 同一套路）：
  // 页面侧只认 `AsyncValue.error`，`AppErrorState` 直接吃异常对象。
  final tgc = result.fold(
    (failure) => throw EhallSessionException('统一认证登录态不可用：${failure.message}'),
    (tgc) => tgc,
  );

  return EmbeddedWebRequest(
    title: '智慧江财',
    url: ehallLoginEntryUrl,
    cookies: <WebSessionCookie>[casTgcCookie(tgc)],
  );
});
