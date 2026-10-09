/// 内嵌网页（Android / iOS / Windows）的**唯一实现**（2026-10-08 重写 · AGENTS.md §40）。
///
/// **为什么换实现**：本文件原先建在 `webview_flutter` 上，而它在桌面**没有平台
/// 实现**（`WebViewController()` 在 Windows 上直接抛异常），于是桌面只能降级到
/// 系统浏览器 —— 而系统浏览器**拿不到 app 的登录态**，「打开智慧江财就是登录页」。
/// 现在改用 `flutter_inappwebview`：Android 走系统 WebView、Windows 走 WebView2，
/// 两端都有 `CookieManager`，于是「把统一认证的 TGC 写进内嵌浏览器」这件事
/// 能在两个平台上用同一份代码做完（`webview_windows` 没有 Cookie API，
/// 只能靠页面脚本写 `document.cookie`，而跨域写不了 —— 排除）。
///
/// 三条口径：
/// 1. **Cookie 先写、页面后开**：`initialUrlRequest` 只在凭据写完之后才交给
///    `InAppWebView`（在此之前 `_initial` 为 null，body 显示加载态）。
///    顺序反了就是「先跳到 CAS 再说」→ CAS 看不到 TGC → 登录页，且首次导航
///    已经发生，再写 Cookie 也救不回来。
/// 2. **Windows 的环境是进程级单例**（见 [_ensureWindowsEnvironment]）：
///    WebView2 要求同一浏览器进程里的 WebView 与 `CookieManager` 用同一套
///    options，否则创建失败（`ERROR_INVALID_STATE`）。
/// 3. **失败要有出路**：本机没装 WebView2 / 用户数据目录建不出来 / 页面加载
///    失败，一律走 `AppErrorState` + 导航栏的「用系统浏览器打开」，不白屏。
/// 4. **退出本页 ≠ 网页返回**（2026-10-08 二轮 · 用户原话「我希望在这个 webview 内，
///    增加一个内部页面返回」）：导航栏**左上角箭头永远退出本页**（用户在哪儿都
///    出得来，与全仓其它服务页一致），页内历史交给**「上一页」按钮 + 系统返回键**
///    （`canGoBack()`/`goBack()`）。少了后者，点进 ehall 一个三级页面就只剩整页退出。
///    ⚠ 为了让左上角箭头**不受** `PopScope` 影响，它必须显式给 `leading`
///    并用 `Navigator.pop`（默认 `BackButton` 走 `maybePop`，会被 PopScope 拦下）。
library;

import 'dart:async' show unawaited;
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/web/browser_nav.dart';
import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';

/// 本平台能不能内嵌 WebView。
///
/// `android` / `ios` / `windows` → true。
///
/// ⚠ 2026-10-08 起 `windows` **由 false 翻成 true**：桌面终于有了实现（WebView2），
/// 于是带 `settingsSections` 的页面与「微信充值」在桌面也走内嵌。
/// 运行期兜底不变：本机没装 WebView2 运行时会落到 [AppErrorState]
/// （未装 WebView2 的 Win10 极少，且 `WebViewEnvironment.getAvailableVersion()`
/// 会在建环境前先判一次，给的是人话而不是 HRESULT）。
/// `macos` / `linux` / `web` 仍为 false —— 未发布、未验证。
bool inAppWebViewSupported(String platformName) =>
    platformName == 'android' ||
    platformName == 'ios' ||
    platformName == 'windows';

/// [inAppWebViewSupported] 的 provider 形态。
///
/// 页面读它而不是直接读 `defaultTargetPlatform`：测试里 override 一下就能分别覆盖
/// 「内嵌」与「外部浏览器」两条路径，不必去改 foundation 的全局调试变量
/// （`debugDefaultTargetPlatformOverride` 在测试体结束前必须还原，容易踩坑）。
final inAppWebViewSupportedProvider = Provider<bool>(
  (ref) => inAppWebViewSupported(defaultTargetPlatform.name),
);

/// 由一次「内嵌网页请求」造一个页面。
///
/// provider 化的原因：widget 测试里不能真的构造 WebView（需要平台实现），
/// 测试 override 成假 widget 即可断言「点了按钮会内嵌打开哪个 URL、先写了哪些
/// Cookie」。
///
/// ⚠ 2026-10-08 起入参由 `(title, url)` 换成整个 [EmbeddedWebRequest]：
/// 「带登录态的内嵌页」（智慧江财）要连同 Cookie 一起断言，两个位置参数装不下。
/// 全仓只有一个实现、一个调用点，收口后仍是一个缝。
typedef WebViewScreenBuilder = Widget Function(EmbeddedWebRequest request);

final webViewScreenBuilderProvider = Provider<WebViewScreenBuilder>(
  (ref) => (request) => InAppWebScreen(request: request),
);

/// 本机没装 WebView2 运行时 —— Windows 内嵌浏览器唯一的硬前置。
///
/// 与「页面打不开」区分开：这一条要用户去装运行时，重试多少次都没用。
class WebViewRuntimeMissingException extends AppException {
  const WebViewRuntimeMissingException()
    : super('本机没有安装 WebView2 运行时，装好之后就能在内嵌窗口里打开这个页面');
}

/// Windows（WebView2）的**进程级**环境 —— 只建一次，所有内嵌页共用。
WebViewEnvironment? _windowsEnvironment;
Future<WebViewEnvironment>? _windowsEnvironmentPending;

Future<WebViewEnvironment> _ensureWindowsEnvironment() {
  final existing = _windowsEnvironment;
  if (existing != null) return Future<WebViewEnvironment>.value(existing);
  final pending = _windowsEnvironmentPending;
  if (pending != null) return pending;
  // ⚠ 失败时**必须清掉在途 future**：建环境失败（没装运行时 / 用户数据目录建不出来）
  // 会走页面的错误态，而错误态上有「重试」。若把失败 future 一直缓存着，
  // 重试只会拿到同一个失败结果、永远好不了 —— 装完运行时也得重启 App 才行。
  final created = _createWindowsEnvironment().whenComplete(() {
    if (_windowsEnvironment == null) _windowsEnvironmentPending = null;
  });
  _windowsEnvironmentPending = created;
  return created;
}

Future<WebViewEnvironment> _createWindowsEnvironment() async {
  // 先问运行时在不在：不在就给人话，别把 HRESULT 甩到屏幕上。
  final version = await WebViewEnvironment.getAvailableVersion();
  if (version == null || version.isEmpty) {
    throw const WebViewRuntimeMissingException();
  }
  final env = await WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(userDataFolder: await _userDataFolder()),
  );
  _windowsEnvironment = env;
  return env;
}

/// WebView2 的用户数据目录。
///
/// ⚠ **不能用默认值**：非 UWP 应用默认把 `smarter_jxufe.exe.WebView2` 建在
/// **exe 旁边**（`dist/` 或 `build/.../Debug/`），而本机实测「应用进程建目录
/// 一律被拒」（AGENTS §1.3）→ WebView2 会创建失败。这里显式指到应用自己的
/// 数据目录（`<应用支持目录>/webview2`，由 path_provider 给）。
/// 建不出来就返回 null（交回 WebView2 默认值）—— 那样大概率仍会失败，
/// 但失败会走页面的错误态 + 「用系统浏览器打开」，不会白屏。
Future<String?> _userDataFolder() async {
  try {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'webview2'));
    await dir.create(recursive: true);
    return dir.path;
  } catch (e) {
    debugPrint('[InAppWeb] WebView2 用户数据目录建不出来，交回默认值：$e');
    return null;
  }
}

/// 内嵌网页页（整页模式带标题栏，内嵌服务主页的按钮下沉到内容顶部）。
///
/// 与 app 自己的 `dio` **不共享 Cookie 罐**：要让页面处于登录态，调用方必须把
/// 凭据放进 [EmbeddedWebRequest.cookies]（见 `core/network/cas_browser_session.dart`）。
///
/// **页内前进 / 后退融合进顶部**（用户 2026-10-10 二十九轮：「我不希望你手动记录，
/// 我只希望把浏览器原生的前进回退融合进来」）：这一页可见时把自己登记给
/// [browserNavService]（WebView 自己的 `canGoBack`/`goBack`/`canGoForward`/`goForward`），
/// 顶部那两枚按钮**先回网页、回到底才回应用的位置**。
/// ⚠ **刻意不把网页内部跳转记进 `route_history`**：那棵树的深度会把"访问过的位置"冲垮，
/// 而浏览器本来就自己存着（见 `browser_nav.dart` 文件头）。
class InAppWebScreen extends ConsumerStatefulWidget {
  const InAppWebScreen({super.key, required this.request});

  final EmbeddedWebRequest request;

  @override
  ConsumerState<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends ConsumerState<InAppWebScreen> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;

  /// 非 null 才会建 WebView —— 只有凭据写完才赋值（见文件头第 1 条口径）。
  URLRequest? _initial;

  Object? _bootError;
  Object? _pageError;
  int _progress = 0;

  /// 网页**内部**还有没有上一页（决定「上一页」按钮灰不灰、以及系统返回键
  /// 是回网页还是退页面）。真值只能问 WebView，所以每次导航后同步一次。
  bool _canGoBack = false;

  /// 网页**内部**还有没有下一页（顶部「前进」按钮用）。
  bool _canGoForward = false;

  /// 本页是不是**当前可见的那一层路由**（被别的页面盖住时要主动让出顶部按钮）。
  bool _isCurrentRoute = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 可见性会随"有没有被别的路由盖住"变化，所以每次依赖变化都重算一次。
    _syncBrowserRegistration();
  }

  @override
  void dispose() {
    browserNavService.detach();
    _controller?.dispose();
    super.dispose();
  }

  /// 把自己（或撤销自己）登记成"管顶部前进/后退的那个网页"。
  ///
  /// ⚠ **只在当前可见时登记**：被设置页 / 二级页盖住的那层如果继续占着顶部按钮，
  /// 用户点"后退"会莫名其妙地动底下那个网页。
  void _syncBrowserRegistration() {
    final route = ModalRoute.of(context);
    final current = route?.isCurrent ?? true;
    if (current == _isCurrentRoute && current == browserNavService.isActive) return;
    _isCurrentRoute = current;
    if (!current) {
      browserNavService.detach();
      return;
    }
    browserNavService.attach(
      onBack: () => unawaited(_goBack()),
      onForward: () => unawaited(_goForward()),
      state: BrowserNavState(
        canGoBack: _canGoBack,
        canGoForward: _canGoForward,
      ),
    );
  }

  /// 建环境 → 写凭据 → 放行导航。
  Future<void> _boot() async {
    setState(() {
      _bootError = null;
      _pageError = null;
      _initial = null;
      _progress = 0;
      _canGoBack = false;
    });
    try {
      final env = defaultTargetPlatform == TargetPlatform.windows
          ? await _ensureWindowsEnvironment()
          : null;
      if (!mounted) return;

      final cookies = widget.request.cookies;
      if (cookies.isNotEmpty) {
        // Windows 上必须带上同一个环境，否则写进去的是**另一个 profile** 的罐子。
        final manager = CookieManager.instance(webViewEnvironment: env);
        for (final c in cookies) {
          await manager.setCookie(
            url: WebUri(c.seedUrl),
            name: c.name,
            value: c.value,
            domain: c.domain,
            path: c.path,
            isSecure: c.isSecure,
            isHttpOnly: c.isHttpOnly,
            sameSite: HTTPCookieSameSitePolicy.LAX,
          );
        }
        if (!mounted) return;
        // 只打名字 —— 值永不进日志（§34）。
        debugPrint('[InAppWeb] 已写入 ${cookies.length} 条会话 Cookie：$cookies');
      }

      setState(() {
        _environment = env;
        _initial = URLRequest(url: WebUri(widget.request.url));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _bootError = e);
    }
  }

  void _goHome() {
    _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.request.url)),
    );
  }

  /// 问一次 WebView「还有没有上一页 / 下一页」，变了才重建。
  ///
  /// 三个调用点：`onUpdateVisitedHistory`（每次历史变化，最准）、
  /// `onLoadStop`（兜底，某些平台不抛 visited-history）、以及回 / 进之后。
  ///
  /// ⚠ 同步完要**顺手更新 [browserNavService]** —— 顶部那两枚按钮的灰/亮靠它。
  Future<void> _syncHistory() async {
    final controller = _controller;
    if (controller == null) return;
    bool canBack;
    bool canForward;
    try {
      canBack = await controller.canGoBack();
      canForward = await controller.canGoForward();
    } catch (e) {
      // 控制器已销毁 / 平台不支持 —— 当作「没有上一页」，不阻断页面。
      debugPrint('[InAppWeb] canGoBack/canGoForward 查询失败：$e');
      return;
    }
    if (!mounted) return;
    if (canBack != _canGoBack || canForward != _canGoForward) {
      setState(() {
        _canGoBack = canBack;
        _canGoForward = canForward;
      });
    }
    // 顶部按钮的能力跟着一起更新（**不记历史**，只是把能力报上去）。
    if (_isCurrentRoute) {
      browserNavService.update(
        BrowserNavState(canGoBack: canBack, canGoForward: canForward),
      );
    }
  }

  /// 网页内部返回上一页（不是退出本页 —— 退出走导航栏左上角那个箭头）。
  ///
  /// ⚠ 顶部那枚「后退」按钮也走这里（见 [browserNavService]），
  /// 所以它**不许**顺手记一笔路由历史 —— 用户要的就是"浏览器原生"。
  Future<void> _goBack() async {
    await _controller?.goBack();
    await _syncHistory();
  }

  /// 网页内部前进一页（顶部「前进」按钮用）。
  Future<void> _goForward() async {
    await _controller?.goForward();
    await _syncHistory();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.request.url);
    if (uri == null) return;
    await ref.read(externalUrlOpenerProvider)(uri);
  }

  /// 执行调用方给的「页面加载后脚本」。
  ///
  /// 失败**只记日志**：这段脚本是补救（见 `EmbeddedWebRequest.pageScript`），
  /// 它跑不起来也不该把页面判死 —— 用户仍然可以在页面上自己改。
  Future<void> _runPageScript(
    InAppWebViewController controller,
    String script,
  ) async {
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[InAppWeb] 页面脚本执行失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = inAppWebNavActions(
      canGoBack: _canGoBack,
      onBack: _goBack,
      onRefresh: _controller == null ? null : () => _controller!.reload(),
      onHome: _controller == null ? null : _goHome,
      onOpenExternal: _openExternal,
    );
    // ⚠ 系统返回键 / 侧滑手势：**网页还有上一页就先回网页**（与手机浏览器一致），
    // 回到底了才退出本页。`canPop: !_canGoBack` 是关键 —— 反过来写会让用户
    // 在三级页面里一按返回就整页退出。
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_goBack());
      },
      child: Scaffold(
        appBar: paneAppBar(
          context,
          title: Text(widget.request.title),
          centerTitle: false,
          backgroundColor: Theme.of(context).cardTheme.color,
          surfaceTintColor: Colors.transparent,
          // ⚠ 左上角箭头**永远退出本页**，与全仓其它服务页一致。
          // 这里必须显式给 leading：默认的 `BackButton` 走的是 `Navigator.maybePop`，
          // 而 `maybePop` 会被下面那个 `PopScope` 拦下来 → 变成「页内返回」，
          // 用户在三级页面里就会连按好几次才出得去。`pop` 直通、不受 PopScope 管。
          leading: Navigator.of(context).canPop()
              ? BackButton(onPressed: () => Navigator.of(context).pop())
              : null,
          actions: actions,
        ),
        body: PaneBody(actions: actions, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bootError = _bootError;
    if (bootError != null) {
      return AppErrorState(
        error: bootError,
        title: '内嵌浏览器用不了',
        onRetry: _boot,
        retryKey: const Key('inAppWebBootRetry'),
      );
    }

    final initial = _initial;
    if (initial == null) {
      return const AppLoadingState(message: '正在把登录态交给内嵌浏览器…');
    }

    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: _environment,
          initialUrlRequest: initial,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            supportZoom: true,
            // ehall 门户是 `http://`（学校没上 https）：Android 侧靠
            // AndroidManifest 的 `usesCleartextTraffic="true"` 放行整站明文；
            // 这里再放宽混合内容，免得 https 的 CAS 页里引的 http 资源被拦。
            mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
          ),
          onWebViewCreated: (controller) => _controller = controller,
          onProgressChanged: (controller, progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onLoadStop: (controller, url) {
            if (!mounted) return;
            setState(() => _progress = 100);
            // 兜底同步一次：有的平台不抛 visited-history。
            unawaited(_syncHistory());

            // 「页面加载后再修一次」的注入点（可选，语义与纪律见
            // `EmbeddedWebRequest.pageScript`）。
            final script = widget.request.pageScript;
            if (script != null && script.isNotEmpty) {
              unawaited(_runPageScript(controller, script));
            }
          },
          onUpdateVisitedHistory: (controller, url, isReload) {
            // 历史一变就更新「能不能上一页」——「上一页」按钮的灰/亮靠它。
            unawaited(_syncHistory());

          },
          onReceivedError: (controller, request, error) {
            if (!mounted) return;
            // 子资源失败不该把整页判死（一张图挂了不等于页面打不开）。
            if (request.isForMainFrame != true) return;
            // ⚠ 只留 `description`，**不带 URL**：失败的那一跳可能是
            // `…loginSuccess?…&ticket=ST-…`，把 URL 印上屏等于把票据印上屏。
            setState(() => _pageError = error.description);
          },
        ),
        if (_progress < 100)
          LinearProgressIndicator(value: _progress <= 0 ? null : _progress / 100),
        if (_pageError != null)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: AppErrorState(
              error: _pageError!,
              title: '网页没打开',
              onRetry: () {
                setState(() => _pageError = null);
                _controller?.reload();
              },
              retryKey: const Key('inAppWebReloadRetry'),
            ),
          ),
      ],
    );
  }
}

/// 内嵌页导航栏的按钮组 —— 整页模式塞进 `AppBar.actions`，
/// 侧栏内嵌模式由 `PaneBody` 下沉成一行（两处传的是同一批 widget 实例）。
///
/// **为什么是顶层函数而不是内联在 `build` 里**：真 WebView 在 widget 测试里
/// 建不出来（`InAppWebViewPlatform.instance` 没被设置过），内联就没法验
/// 「上一页该灰的时候灰、该亮的时候亮」。抽成「只吃普通入参」的函数之后，
/// 测试直接 pump 一排按钮就能推 `canGoBack` 这一位。
///
/// ⚠ `onBack` 与另外三个语义不同：它是**网页内部**返回上一页，
/// 而导航栏左上角那个箭头是**退出本页**。两个都留着是刻意的 ——
/// 少了前者，用户点进 ehall 的三级页面就只剩「整页退出」一条路。
List<Widget> inAppWebNavActions({
  required bool canGoBack,
  required VoidCallback? onBack,
  required VoidCallback? onRefresh,
  required VoidCallback? onHome,
  required VoidCallback onOpenExternal,
}) => <Widget>[
  IconButton(
    key: const Key('inAppWebBack'),
    tooltip: '上一页',
    // 没有上一页就**禁用**（灰）：与浏览器一致，也免得用户以为是坏的。
    onPressed: canGoBack ? onBack : null,
    icon: const Icon(Icons.chevron_left),
  ),
  IconButton(
    key: const Key('inAppWebRefresh'),
    tooltip: '刷新',
    onPressed: onRefresh,
    icon: const Icon(Icons.refresh),
  ),
  IconButton(
    key: const Key('inAppWebHome'),
    tooltip: '回到首页',
    onPressed: onHome,
    icon: const Icon(Icons.home_outlined),
  ),
  IconButton(
    key: const Key('inAppWebExternal'),
    tooltip: '用系统浏览器打开',
    onPressed: onOpenExternal,
    icon: const Icon(Icons.open_in_new),
  ),
];
