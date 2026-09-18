/// 打开外部链接的唯一入口（provider 化 → 测试可替换，不打真实浏览器）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开一个外部 URL，返回是否成功交给系统。
typedef ExternalUrlOpener = Future<bool> Function(Uri uri);

/// 默认实现 = 交给系统默认浏览器 / 邮件客户端（与
/// `competition_detail_screen.dart` 的 `LaunchMode.externalApplication` 同款）。
///
/// 页面一律通过本 provider 取用，测试里 override 成假的即可断言「点了按钮要打开的
/// 是哪个 URL」，不必真的调起浏览器。
final externalUrlOpenerProvider = Provider<ExternalUrlOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
