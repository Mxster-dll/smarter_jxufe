/// 移动端内嵌网页（Android / iOS）与「不支持内嵌」时的降级口径。
///
/// 桌面端（Windows）**没有** webview_flutter 的平台实现 —— `WebViewController()`
/// 在桌面上会直接抛异常，所以由 [inAppWebViewSupported] 先判定，不支持时调用方改走
/// [externalUrlOpenerProvider]（系统浏览器）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

/// 本平台能不能内嵌 WebView。桌面 / Web → false。
bool inAppWebViewSupported(String platformName) =>
    platformName == 'android' || platformName == 'ios';

/// [inAppWebViewSupported] 的 provider 形态。
///
/// 页面读它而不是直接读 `defaultTargetPlatform`：测试里 override 一下就能分别覆盖
/// 「内嵌」与「外部浏览器」两条路径，不必去改 foundation 的全局调试变量
/// （`debugDefaultTargetPlatformOverride` 在测试体结束前必须还原，容易踩坑）。
final inAppWebViewSupportedProvider = Provider<bool>(
  (ref) => inAppWebViewSupported(defaultTargetPlatform.name),
);

/// 由 (title, url) 造一个内嵌网页页面。
///
/// provider 化的原因：widget 测试里不能真的构造 `WebViewController`（需要平台实现），
/// 测试 override 成假 widget 即可断言「点了按钮会内嵌打开哪个 URL」。
typedef WebViewScreenBuilder = Widget Function(String title, String url);

final webViewScreenBuilderProvider = Provider<WebViewScreenBuilder>(
  (ref) => (title, url) => InAppWebScreen(title: title, url: url),
);

/// 内嵌网页页（带标题栏与刷新按钮）。
class InAppWebScreen extends StatefulWidget {
  const InAppWebScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends State<InAppWebScreen> {
  // 底色取卡片色（浅色 = 纯白、深色 = #1A1A1A）：WebView 未加载完成时露出的
  // 就是这块底，写死 `Colors.white` 会在深色下闪一片白。
  // `late final` 首次读取发生在 `build`（body: WebViewWidget），此时 `context` 已可用。
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(AppColors.card(context))
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
