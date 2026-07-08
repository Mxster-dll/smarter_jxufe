import 'package:flutter/material.dart';

/// 全局 Navigator Key，用于在任意位置（如自动重登回调中）获取当前活跃的 BuildContext，
/// 避免因原 widget 已销毁导致 context 失效。
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
