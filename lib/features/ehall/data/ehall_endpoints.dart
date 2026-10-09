/// 智慧江财（ehall 综合服务门户）的**地址唯一出处**（2026-10-08 立 · AGENTS.md §40）。
///
/// ⚠ 学校这套门户是 `http://`（没上 https），协议**照实写**，不要「顺手统一成 https」
/// —— 与 §32.3 对 `xk.jxufe.cn` 那批站点的口径一致。
library;

/// 门户首页（登录后的落点是 `/new/index.html`）。
const String ehallPortalUrl = 'http://ehall.jxufe.edu.cn/';

/// 门户的 CAS 登录入口：服务端 302 到统一认证（并带上回跳用的 `sessionToken`）。
///
/// 这是**浏览器语义下正确的入口** —— 把自己交给它，剩下的跳转它自己会走完：
/// ```
/// 本地址 → 302 ssl.jxufe.edu.cn/cas/login?service=…
///        → 302 …/amp-auth-adapter/loginSuccess?…&ticket=ST-…
///          （ehall 在这一跳下发自己的 CASTGC）
///        → 301 / → 200 /new/index.html
/// ```
/// app 自己的登录链用的也是同一个入口（`auth_remote_datasource.dart` 的
/// `_ehallLoginEntry`，逐字相同）。两处刻意**各留一份常量**：那边是「拿 CAS 登录页
/// 来提 execution」，这边是「让浏览器去登录」，谁都不该反过来 import 对方。
const String ehallLoginEntryUrl =
    'http://ehall.jxufe.edu.cn/amp-auth-adapter/login'
    '?service=http%3A%2F%2Fehall.jxufe.edu.cn%2F';

/// 换票时交给 CAS 的 service（与 [ehallLoginEntryUrl] 里那个 `service` 参数同值）。
///
/// **只用来让 CAS 认一次 TGC**（顺便在 TGC 过期时触发 App 的静默重登），
/// 换回来的回调地址本身不用 —— 见 `AuthRepository.ensureTgcFor`。
/// ⚠ 这里**没有** `sessionToken`：该 token 由 ehall 每次现生成，只有浏览器那条路才有。
const String ehallCasLoginUrl =
    'https://ssl.jxufe.edu.cn/cas/login'
    '?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess';
