/// 把学校统一认证（CAS）的登录态交给**浏览器 / 内嵌 WebView** 的唯一口径
/// （2026-10-08 立 · AGENTS.md §40）。
///
/// **原理**：CAS 的 SSO 凭据是一枚 `ssl.jxufe.edu.cn` 下的 host-only Cookie
/// `TGC`（app 早就握着它，存在 `auth` box 的 `TGC|<账号>` 键，由
/// `AuthRepository` 按账号读写）。只要**浏览器**也带上这枚 Cookie，CAS 就会
/// 直接发票据（302），不再弹登录页 —— 这就是「内嵌页免登录」的全部原理，
/// 不需要密码，也不需要 WebView 里再登一次。
///
/// **实测（2026-10-08 · 真实账号 · 真服务端）** —— 用真实 TGC 走了一遍
/// WebView 会走的那条跳转链：
///
/// ```
/// [0] 302  http://ehall.jxufe.edu.cn/amp-auth-adapter/login?service=…
/// [1] 302  https://ssl.jxufe.edu.cn/cas/login?service=…        ← 带 TGC 才是 302
/// [2] 302  http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess?…&ticket=ST-…
///          Set-Cookie: CASTGC=…          ← **ehall 自己的会话票据**
/// [3] 301  http://ehall.jxufe.edu.cn/
/// [4] 200  http://ehall.jxufe.edu.cn/new/index.html             ← 已登录门户
/// ```
/// 终到页正文含「网上办事大厅」「个人中心」，登录表单（`name="execution"`）为零。
/// 对照：TGC 过期时 [1] 会变成 **200 + 登录页**
/// （`<title>登录 - 江西财经大学统一身份认证</title>`，CAS 同时用
/// `Max-Age=0` 把 TGC 删掉）—— 所以「内嵌页显示登录页」= TGC 死了，
/// 应当先让 App 静默重登再注入。
///
/// ⚠ 这条实测同时**推翻了 §30 的一句旧结论**（「ehall（`ehall.jxufe.edu.cn`）
/// 登录后一个会话 cookie 都不下发」）：ehall **会**下发 `CASTGC`。旧结论来自
/// 「只用 dio 打 API、不跟浏览器跳转」的探针 —— 它看到的是一次未完成 SSO 的
/// 响应。别再拿那句话当「ehall 做不了」的依据。
library;

import 'package:smarter_jxufe/core/web/web_session.dart';

/// CAS 主机 —— TGC 的归属域（host-only，不带前导点）。
const String kCasHost = 'ssl.jxufe.edu.cn';

/// 统一认证的 SSO 票据 Cookie 名。
const String kTgcCookieName = 'TGC';

/// 把一枚 TGC 包装成「要写进内嵌浏览器 Cookie 罐」的凭据。
///
/// ⚠ 入参是**凭据本体**：调用方不许把它写进日志（`WebSessionCookie.toString()`
/// 已经只报名字与域，打 `cookie` 本身是安全的）。
WebSessionCookie casTgcCookie(String tgc) =>
    WebSessionCookie(name: kTgcCookieName, value: tgc, domain: kCasHost);
