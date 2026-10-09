/// 「带登录态的内嵌网页」的**唯一数据口径**（2026-10-08 立 · AGENTS.md §40）。
///
/// **为什么需要它**：内嵌浏览器（Android WebView / Windows WebView2）与 app 自己的
/// `dio` **不共享 Cookie 罐** —— app 在 `auth` box 里握着统一认证的 TGC，可内嵌页
/// 打开时仍是**未登录**的。想让内嵌页也是登录态，只有一条路：在导航之前把凭据
/// 显式写进 WebView 的 Cookie 罐（`CookieManager.setCookie`）。
///
/// 本文件只描述「写什么」，**怎么写**在 `in_app_web_screen.dart`
/// （页面负责按平台建环境、写 Cookie、再导航）。
///
/// ⚠ 这里装的是**凭据**：任何日志、异常文案、`toString()` 都不许带值出来 ——
/// 本文件两个类的 `toString` 都只报名字 / 域 / 条数（与 `cookie_jar.dart` 的
/// `namesOf` 同一口径）。
library;

/// 要预写进内嵌浏览器 Cookie 罐的一段会话凭据。
///
/// 语义对齐**浏览器**（而不是 `SessionCookieJar`）：这里没有「域感知」这回事，
/// `CookieManager.setCookie` 收的就是一条 `name=value + domain + path`。
class WebSessionCookie {
  const WebSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.isSecure = true,
    this.isHttpOnly = true,
  });

  /// Cookie 名（如统一认证的 `TGC`）。
  final String name;

  /// **凭据本体**。绝不进日志。
  final String value;

  /// 归属域，**不带前导点**（如 `ssl.jxufe.edu.cn`）。
  ///
  /// ⚠ 必须是 host-only 的那台主机：写 `jxufe.edu.cn` 会把凭据发给所有子域。
  final String domain;

  /// 发送范围。默认 `/`。
  ///
  /// ⚠ CAS 实测下发的是 `Path=/cas/`，这里**刻意写 `/`**：Cookie 的 path 只决定
  /// 「浏览器把它发给哪些路径」，`/` 完整覆盖 `/cas/`，所以 CAS 一定收得到；
  /// 反过来照抄 `/cas/` 就会漏掉 `ssl.jxufe.edu.cn` 上的其它入口
  /// （如 `/cas/login` 之外的 `/cas/qr/qrcode`）。
  final String path;

  /// 只在 https 上发送（CAS 的 TGC 实测就是 `Secure`）。
  final bool isSecure;

  /// 禁止页面脚本读取（CAS 实测就是 `HttpOnly`）。
  ///
  /// ⚠ 这一位**只有服务端下发时才是真约束**：我们是从 Dart 侧写进罐子的，
  /// 写 `true` 只是让罐里的这条与浏览器里那条**看起来一致**，不构成安全边界。
  final bool isHttpOnly;

  /// 写 Cookie 时用的地址（`CookieManager.setCookie` 靠它判归属）。
  String get seedUrl => '${isSecure ? 'https' : 'http'}://$domain$path';

  /// 诊断用 —— **只报名字与域，永不报值**。
  @override
  String toString() => 'WebSessionCookie($name@$domain$path)';
}

/// 一次「带登录态的内嵌网页」请求：**要开哪个页面 + 先写哪些 Cookie**。
class EmbeddedWebRequest {
  const EmbeddedWebRequest({
    required this.title,
    required this.url,
    this.cookies = const <WebSessionCookie>[],
    this.pageScript,
  });

  /// 页面标题（导航栏 / 内嵌模式下的按钮行不带标题，仅用于整页模式）。
  final String title;

  /// 要导航到的地址。
  ///
  /// ⚠ 存 `String` 而不是 `Uri`：这里放的是**服务端给的原文**（含
  /// `%3A%2F%2F` 这类已编码的 `service=` 参数），多一次 parse→还原只会引入失真。
  final String url;

  /// 导航前要写进 WebView Cookie 罐的凭据（为空 = 普通内嵌页）。
  final List<WebSessionCookie> cookies;

  /// **页面每次加载完成后**注入执行的脚本；`null` / 空串 = 不注入（默认）。
  ///
  /// 用途只有一个：**替服务端页面补它自己的漏**（页面上的 bug 只能从页面里修）。
  /// 首个采用点 = 校园网充值 —— 校方 `recharge.js` 的 `initAmount` 分支写反了
  /// （`if (flag && …) {…} else { $("#moneybut1").click(); }`），于是 **URL 预填的
  /// 档位金额会被打回 10 元**，只有注入一次 `changeMoney(<档位 id>)` 才纠正得回来
  /// （详见 `features/net_fee/domain/net_fee_recharge.dart` 文件头）。
  ///
  /// 三条纪律：
  /// 1. **必须幂等且无害**：它会在**每一次**导航结束时执行（含页内跳转、结果页），
  ///    所以脚本第一句就该是「找不到目标函数就 `return`」；
  /// 2. **不许把凭据拼进去**：脚本会留在 WebView 的 JS 上下文里，只放常量与数字；
  /// 3. 是**补救**不是依赖：页面结构一变脚本会静默失效，所以调用方仍要在 UI 上
  ///    让用户核对（`net_fee_recharge_sheet.dart` 的「支付页上会显示金额」那句）。
  final String? pageScript;

  /// 诊断用（**不含任何 Cookie 值**，也不回显脚本正文）。
  @override
  String toString() =>
      'EmbeddedWebRequest($title, $url, ${cookies.length} cookies'
      '${pageScript == null ? '' : ', +pageScript'})';
}
