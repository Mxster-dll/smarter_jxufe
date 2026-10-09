<!-- 本册 = AGENTS.md §40 的正文（节号与标题原样保留，勿重编号）。根文件：../AGENTS.md -->

## 40. 智慧江财（ehall）内嵌网页 · 复用统一认证登录态（2026-10-08 立）

用户原话：「我希望内置一个 webview，用于加载原生网页：http://ehall.jxufe.edu.cn/，但是支持直接复用当前项目里的登录 cookie」；
二轮拍板：「Android 内嵌 + Windows 也内嵌（加 webview_windows / WebView2 依赖）」+「通用地基件 + 智慧江财一个入口」。

> **页内跳转已接入顶部全局路由历史**（2026-10-10 二十八轮 · 用户：「我希望内嵌的智慧江财的
> 内部页面也要接入路由」）：门户里点进去的每一层都会记一笔（键 = `web:<URL>`，标题取网页
> 自己的），顶部前进/后退因此对网页内部也有效。口径与守卫见 **§45.2 第 3 条**。

### 40.1 原理：把 TGC 交给浏览器，剩下交给浏览器自己跳

内嵌浏览器（Android WebView / Windows WebView2）与 App 自己的 `dio` **不共享 Cookie 罐** —— App 握着统一认证的 TGC，内嵌页打开时仍是未登录的。唯一的路是**在导航之前**把凭据写进 WebView 的 Cookie 罐：

```
App 的 auth box（TGC|<账号>）→ 注入 ssl.jxufe.edu.cn 的 TGC Cookie
      ↓
GET http://ehall.jxufe.edu.cn/amp-auth-adapter/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2F
  → 302 https://ssl.jxufe.edu.cn/cas/login?service=…      ← CAS 看到 TGC，直接发票据
  → 302 …/amp-auth-adapter/loginSuccess?…&ticket=ST-…      ← ehall 在这一跳下发自己的会话票
  → 301 / → 200 /new/index.html                            ← 已登录门户
```

**实测（2026-10-08 · 真实账号 · 真服务端）**：上面 5 跳逐跳验过 —— `[1]` 是 **302（不是登录页）**、`[2]` 的 `Set-Cookie` 里有 **`CASTGC`**、`[4]` 终到页正文含「网上办事大厅」「个人中心」且**没有**登录表单（`name="execution"` 命中 0）。
对照：TGC 过期时 `[1]` 变成 **200 + 登录页**（`<title>登录 - 江西财经大学统一身份认证</title>`），CAS 同时用 `Max-Age=0; Expires=1970` 把 TGC 删掉。

⚠ **这条实测推翻了 §30 的一句旧结论**（「ehall 登录后一个会话 cookie 都不下发」）：ehall **会**下发 `CASTGC`。旧结论来自「只用 dio 打 API、不跟浏览器跳转」的探针，它看到的是一次**没走完 SSO** 的响应。§30 那句话已就地更正。

⚠ **TGC 必须先换成「当下可用」的那一枚**：杀掉 App 之后 `auth` box 里的旧票会被 CAS 删掉（实测两个账号的旧票全部 200 登录页）。所以入口不是「读磁盘上的 TGC」，而是 `AuthRepository.ensureTgcFor(casLoginUrl)` —— 它复用 `getServiceRedirectUrl`（**过期 → 用缓存凭据静默重登一次 → 重试**），返回 Right 时手里那枚一定是 CAS 认的。

⚠ **第二步（换票）刻意交给浏览器自己走**：`service` 上那个 `sessionToken` 是 ehall **每次现生成**的，只有浏览器从头走那条 302 链才拿得到。Dart 侧硬拼 `loginSuccess?ticket=…` 是**没验证过的路径**，别改成那样。

### 40.2 分层：地基件在 core，站点口径在 feature

| 层 | 文件 | 管什么 |
|---|---|---|
| core · 模型 | `lib/core/web/web_session.dart` | `WebSessionCookie`（name/value/domain/path/secure/httpOnly + `seedUrl`）· `EmbeddedWebRequest`（title/url/cookies/**pageScript**，后者见 §40.8） |
| core · CAS 口径 | `lib/core/network/cas_browser_session.dart` | `kCasHost` / `kTgcCookieName` / `casTgcCookie(tgc)` + 上面那条实测链的台账 |
| core · 页面 | `lib/core/web/in_app_web_screen.dart` | **全平台唯一的内嵌网页实现**：建环境 → 写 Cookie → 才放行导航；三态 + 刷新 / 回首页 / 用系统浏览器打开 |
| feature | `lib/features/ehall/data/ehall_endpoints.dart` | 门户地址 / 登录入口 / CAS service 三个常量 |
| feature | `lib/features/ehall/data/providers/ehall_session_provider.dart` | `ehallWebSessionProvider`：`ensureTgcFor` → `EmbeddedWebRequest` |
| feature | `lib/features/ehall/presentation/ehall_screen.dart` | 三态薄壳：加载 / 错误（重试 + 浏览器出路）/ 数据 → 交给内嵌页 |
| auth | `AuthRepository.ensureTgcFor` | 「保证 TGC 当下可用」的唯一入口（复用既有静默重登链） |

**唯一的跳转缝** = `webViewScreenBuilderProvider`（`WebViewScreenBuilder = Widget Function(EmbeddedWebRequest)`）。
2026-10-08 由 `(String title, String url)` 换成整个请求 —— 「带登录态的内嵌页」要**连同 Cookie 一起断言**，两个位置参数装不下。全仓一个实现、两个调用点（微信充值 / 智慧江财），仍是一个缝；widget 测试 override 它就能断言「开哪个 URL、先写了哪些 Cookie」，不必去建真的 WebView。

### 40.3 ⚠ Windows 侧的三条硬前置（踩过才知道）

1. **`nuget` 必须在 PATH 里**：`flutter_inappwebview_windows` 的 `windows/CMakeLists.txt` 要 `nuget install` 三个包（`Microsoft.Windows.ImplementationLibrary` / `Microsoft.Web.WebView2` / `nlohmann.json`），`find_program(NUGET nuget)` 找不到就只能报 NOTICE 然后构建失败。本机装法：`https://dist.nuget.org/win-x86-commandline/latest/nuget.exe` → 放 `%USERPROFILE%\nuget\` 并加进 PATH。包会下到 `build\windows\x64\packages\`，之后增量构建很快。**发布脚本 / 新机器都要先有它。**
2. **WebView2 运行时**：本机已装（`HKLM\SOFTWARE\WOW6432Node\EdgeUpdate\Clients\{F3017226-…}` = 154.x）。页面在建环境前先问 `WebViewEnvironment.getAvailableVersion()`，没有就抛 `WebViewRuntimeMissingException`（人话：「本机没有安装 WebView2 运行时…」），不是把 HRESULT 甩给用户。
3. **用户数据目录必须显式指定**：WebView2 对非 UWP 应用的默认目录是 **exe 旁边**的 `smarter_jxufe.exe.WebView2` —— 发布版装到 `C:\Program Files\…` 时普通用户建不了目录，WebView2 会创建失败。现指到 `<getApplicationSupportDirectory()>/webview2`，建不出来就交回默认值（不阻断）。

**实测台账（2026-10-08 · 造了个只跑探针的入口 `-t lib/tmp_probe_main.dart`，直接跑 exe 读 stdout）**：
```
[probe] WebView2 运行时版本 = 154.0.4258.62
[probe] appSupport = %APPDATA%\com.example\智慧er江财
[probe] 用户数据目录建不出来（会交回 WebView2 默认值）:
        PathAccessException: Creation failed, path = '…\webview2' (OS Error: 拒绝访问。, errno = 5)
[probe] 环境创建成功 id=2122…
[probe] 写 TGC Cookie = true
[probe] CAS 路径能读到的 Cookie = TGC
[probe] 其它主机读到的 Cookie =            ← host-only 生效（jwxt 拿不到）
[probe] PROBE OK
```
三条结论：
- 本机 §1.3 那条「应用进程建目录一律被拒」**仍然存在**（`errno 5`），连 `%APPDATA%\…` 也一样；
- **但 WebView2 照样建成了环境**：它回落到默认目录 `build\windows\x64\runner\Debug\smarter_jxufe.exe.WebView2\EBWebView` —— 那是 **WebView2 原生装载器**（浏览器进程）建的，不走 Dart 的 `Directory.create`，所以不受这条限制。**开发目录可写 → 本机没问题**；发布版装进 `Program Files` 才会有问题，所以第 3 条那个显式目录不能省；
- Cookie 注入链**在真机进程里通**：`setCookie` 返回 true、CAS 路径读得到、别的主机读不到（host-only 语义正确）。

另外两条实现约束：
- **WebView2 环境是进程级单例**（`_windowsEnvironment` 静态缓存）：同一个浏览器进程里的所有 WebView 与 `CookieManager` 必须用**同一套 options**，否则创建报 `HRESULT_FROM_WIN32(ERROR_INVALID_STATE)`。`CookieManager.instance(webViewEnvironment: env)` 也必须带上同一个 env，否则写进去的是**另一个 profile** 的罐子。
- **Cookie 先写、页面后开**：`initialUrlRequest` 只在凭据写完才交给 `InAppWebView`（在此之前 `_initial` 为 null，body 是加载态）。顺序反了就是「先跳 CAS 再说」→ 登录页，且首次导航已经发生，再写 Cookie 也救不回来。

### 40.4 依赖变更：`webview_flutter` → `flutter_inappwebview`

- **为什么换**：`webview_flutter` **在桌面没有平台实现**（`WebViewController()` 在 Windows 直接抛异常），桌面只能降级到系统浏览器 —— 而系统浏览器拿不到 App 的登录态，正是这个功能要解决的问题。`flutter_inappwebview` 的 Windows 端是 **WebView2**，且**两端都有 `CookieManager`**。
- **为什么不选 `webview_windows`**：它**没有 Cookie API**，只能靠页面脚本写 `document.cookie` —— 而跨域写不了（ehall 的脚本写不了 `ssl.jxufe.edu.cn` 的 Cookie）。
- **连带影响**：`inAppWebViewSupported` 的 `windows` **由 false 翻成 true**（桌面终于有真实现），于是「微信充值」在桌面也走内嵌。守卫 `test/network_service_ui_test.dart` 的真值表已同步。
- **`webview_flutter` 已从 `pubspec.yaml` 删除**（改完实测：全仓 `package:webview_flutter/` 的 import **命中为 0**）—— 留着会让 `repo_hygiene_test` 的「依赖都被真的 import」变红，那条守卫的口径就是「只留真被 import 的包」。要回退就把两行一起加回来（`webview_flutter: ^4.4.2` + 把 `in_app_web_screen.dart` 换回旧实现，旧实现见 git 历史）。

### 40.5 守卫

`test/ehall_session_test.dart` —— **17 例**，五组：

1. **凭据口径**：`casTgcCookie` 的域必须是 **host-only** 的 `ssl.jxufe.edu.cn`（写 `jxufe.edu.cn` 会把凭据发给所有子域）、path 取 `/`（CAS 下发的是 `/cas/`，但 path 只决定发送范围，`/` 完整覆盖它）、非 secure 用 http seedUrl；**★ `toString` 只报名字与域，绝不带值**（`WebSessionCookie` 与 `EmbeddedWebRequest` 都验，§34 隐私纪律）。
2. **门户地址**：门户与登录入口都是 `http://`（学校没上 https，**照实写**，别顺手统一成 https —— 与 §32.3 同口径）；登录入口的 `service` 百分号编码后指向门户根；CAS 入口的 `service` 与它同 host。
3. **`ensureTgcFor`**：有效 → 直接返回且只探一次；过期 → 静默重登一次并返回**新**票（不是旧票）+ 新票落盘；无票 → Left 且**零请求**；一直过期 → Left **不抛异常**；返回值是 TGC 本身而不是换回来的回调地址。
4. **页面三态**：加载态文案 / 错误态（人话 + `Key('ehallSessionRetry')` + 「用系统浏览器打开」真的走 `externalUrlOpenerProvider` 且 URL = 门户）/ 数据态（交给内嵌页的 URL = 登录入口、恰好一条 `TGC@ssl.jxufe.edu.cn`、**不跳系统浏览器**）。
5. **源码守卫**：智慧江财页必须含 `webViewScreenBuilderProvider` 且**不得出现 `launchUrl(`**（跳浏览器就没有登录态了，那正是本功能要解决的）；`ehall_session_provider.dart` 不得有 `debugPrint` / `print(`；内嵌页不得出现 `$c.value` 这类把凭据打出来的写法。

配套：`test/home_tile_alignment_test.dart` 条目数 **31 → 32**，并新增一例钉住「智慧江财」紧跟在「毕业学分要求」之后、分组 = `campus`、页面 = `EhallScreen`；`test/network_service_ui_test.dart` 的内嵌支持真值表加 `windows`。

### 40.6 入口与配色

- 首页宫格：`Icons.apps_outlined` + 「智慧江财」+ 副标题「综合服务门户 · 复用统一认证登录态直接进」，分组 `HomeServiceGroup.campus`，**排在四枚教务磁贴之后**（它是教务 / 学工 / 后勤 / 图书馆的总入口，「门户」挨着「教务」最符合找东西的顺序）。
- 强调色 = `FeaturePalette.ehall = #004D40`（Teal 900）：语义 = 「门户」；青绿族已有五档，取其中**最深**的一档，且不与任何一个既有值相等。
- 页面用 `paneAppBar` + `PaneBody`（走 chrome 口径，整页模式带标题栏、内嵌侧栏模式按钮下沉）；二级页形态、**不带设置齿轮**之外的特殊声明（`settingsSections` 留空 = 完整设置页）。

### 40.7 页内返回：退出本页 ≠ 网页返回（2026-10-08 二轮）

用户原话：「我希望在这个 webview 内，增加一个内部页面返回」—— 起因是点进 ehall 的子页面之后**只剩整页退出**一条路。

**两条语义刻意分开，别合并**：

| 控件 | 做什么 | 实现 |
|---|---|---|
| 导航栏**左上角箭头** | **退出本页**（放掉整条路由） | 显式 `leading: BackButton(onPressed: () => Navigator.pop(context))` |
| 导航栏**「上一页」按钮**（`Key('inAppWebBack')`） | **网页内部**回上一页 | `canGoBack()` 为真才可点，否则**禁用（灰）** |
| Android **系统返回键 / 侧滑** | 网页有历史就回网页，回到底才退页面 | `PopScope(canPop: !_canGoBack, onPopInvokedWithResult: …)` |

⚠ **最大的坑 = 左上角箭头会被 `PopScope` 顺手接管**：Flutter 默认的 `BackButton` 走的是 `Navigator.maybePop`，而 `maybePop` 正是 `PopScope` 拦截的那个入口 → 不显式给 `leading` 的话，左上角箭头会变成「页内返回」，用户在三级页面里得连按好几次才出得去。
`Navigator.pop` **不经** `maybePop`，所以显式 `leading` + `pop` 才是「永远退得出去」的保证。
守卫 `test/in_app_web_nav_test.dart` 钉住了这一点（断言 `leading:` / `Navigator.of(context).pop()` / `BackButton(onPressed:` 三处都在）。

「上一页」的灰/亮由 `_canGoBack` 驱动，只在**导航事件**后同步（`onUpdateVisitedHistory` 最准 + `onLoadStop` 兜底 + `goBack()` 之后各一次），建页时重置为假 —— 不要在 `build` 里直接 `await canGoBack()`（会每帧一次平台调用、还可能与当前帧状态打架）。

为什么按钮组抽成**顶层函数** `inAppWebNavActions({canGoBack, onBack, onRefresh, onHome, onOpenExternal})`：真 WebView 在 widget 测试里建不出来（`InAppWebViewPlatform.instance` 没被设置过 → 一 build 就断言失败），内联在 `build` 里就没法验「该灰的时候灰、该亮的时候亮」。抽成「只吃普通入参」之后，测试直接 pump 那一排按钮即可。

守卫 = `test/in_app_web_nav_test.dart` **11 例**（禁用/可点/无回调仍禁用/刷新与回首页随回调置灰/浏览器出路恒可点/按钮顺序 + 四条源码接线守卫：`PopScope` 与 `canPop: !_canGoBack` 不许写反、`leading` 与 `pop` 必须在、`canGoBack()` 与两个同步点必须在、建页重置）。

### 40.8 页面加载后脚本（`EmbeddedWebRequest.pageScript` · 2026-10-09 加）

内嵌件新增的**唯一**一个可选能力：`pageScript`（`String?`，默认 `null` = 行为完全不变）。

- **挂点** = `onLoadStop` 之后 `controller.evaluateJavascript(source: script)`；失败**只记日志**
  （`_runPageScript`），绝不把页面判死 —— 它会跑不起来也不该影响用户自己操作。
- **用途**：把校方那一页收拾成 App 想要的样子。两类用法，目前只有**一个**采用点
  （校园网充值）：
  1. **补服务端页面的漏** —— 页面上的 bug 只能从页面里修：校方 `recharge.js` 把
     `initAmount` 的 `flag` 写反，**URL 预填的档位金额会被打回 10 元**，
     只有注入一次 `changeMoney(<档位 id>)` 才纠正得回来；
  2. **替用户点掉多余的一步** —— 同一段脚本接着点掉表单上的「立即支付」，
     于是「选完金额 → 3 秒后就是二维码页」（`POST submitRecharge` → `wxPaySaoma`）。
  口径与两轮真机实测对照表见 **§21.7**。

  ⚠ **2026-10-09 三轮起，校园网充值的主路径已经不是内嵌网页**：用户要求「把二维码封装到
  我们的 UI 里」，于是改成 **App 原生收银台**（`dio` 复刻校方四步链路、二维码取回来
  `Image.memory` 自己画，见 §21.7）。`pageScript` 现在只服务**下单失败时的兜底路径**，
  以及第二段「微信充值」那个老入口 —— 能力本身没变，别以为它过时了。
- **三条纪律**（写在 `web_session.dart` 的字段注释里，别绕过）：
  1. **必须幂等且无害** —— 每次导航结束都会执行（含页内跳转、结果页、刷新），
     脚本第一句就该是「目标函数不存在就 `return`」、找不到目标元素就什么都不做；
  2. **不许把凭据拼进去** —— 脚本会留在 WebView 的 JS 上下文里，只放常量与数字；
  3. **是补救不是依赖** —— 页面结构一变就静默失效，所以调用方仍要在 UI 上让用户核对
     （充值面板那句「打开后请核对一眼再付款」）。
- **走系统浏览器那条兜底路时注入不了**（那是浏览器的事）：所以需要 `pageScript` 的场景
  必须自带一句「请核对」的用户提示，不能假设脚本一定生效。
- `EmbeddedWebRequest.toString()` 只报「有没有脚本」（`+pageScript`），**不回显脚本正文**。
