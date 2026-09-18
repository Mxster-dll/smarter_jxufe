import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_menu_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_tab_container.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';

/// IMS 功能入口闸门（培养方案 / 课表 / 成绩 / 毕业学分 / 我的 都经这里）。
///
/// **不再强制重新登录**（2026-09-11 改）：以前这里无条件调
/// `refreshJsessionId()`，等于每次进任一功能都重走一遍完整 CAS 换票，慢且在
/// CAS 侧失败时直接抛异常——而旧代码没有 try/catch，页面会永远停在「加载中…」。
///
/// 现在：
/// - 全局会话本地已有 → `ensureReady()` **一个请求都不发**，直接进页面；
/// - 会话真失效 → 业务请求触发拦截器自动用 TGC 静默换票并重试，用户无感；
/// - 本地压根没有会话且换票失败 → 明确报错，可「重试」，也可以「先看缓存」。
///
/// **不再 pushReplacement，改成就地渲染目标页**（2026-09-16 改，用户反馈
/// 「点开这四个部分时会显示一个由中心向外的扩张动画」）：
/// - 旧实现是 `Navigator.pushReplacement(context, MaterialPageRoute(target))`，
///   于是「点一下」会连做两次路由转场（本页转场 → 目标页转场），中间还闪一帧转圈；
///   再叠上 Flutter 默认的 zoom 转场，观感就是「从中心扩出来」。
/// - 现在本页**自己就是**目标页的宿主：会话就绪即渲染 `ImsTabContainer` /
///   `ImsMenuScreen`，整个打开动作只有**一次**转场
///   （横向共享轴，见 `lib/design/app_page_transitions.dart`）。
/// - 副作用（都是想要的）：不再有 `setState during build` 风险（压根不动 Navigator）；
///   首页侧栏的右侧内嵌面板里，本页仍作为面板栈的首页存在 → `canPop() == false`
///   → 内嵌页照旧不显示返回按钮（用户 2026-09-15 裁定第 2 条）。
class ImsSplashScreen extends ConsumerStatefulWidget {
  final ImsTab? initialTab;

  const ImsSplashScreen({super.key, this.initialTab});

  @override
  ConsumerState<ImsSplashScreen> createState() => _ImsSplashScreenState();
}

class _ImsSplashScreenState extends ConsumerState<ImsSplashScreen> {
  /// 会话准备中的进度提示（false 且未就绪 = 无需等待）。
  bool _preparing = false;

  /// 换票失败时的错误文案（非 null = 显示失败面板）。
  String? _error;

  /// 会话就绪 → 直接渲染目标页。
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  Future<void> _enter() async {
    final session = ref.read(imsSessionProvider);

    // 本地已有会话时这里不发任何请求（ensureReady 只读持久化）。
    // 且这是同步分支：首帧 build 之前就把 _ready 置好 → 不闪转圈、不换路由。
    if (session.hasSession) {
      _ready = true;
      return;
    }

    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      await session.ensureReady(); // 本地没有才换票（CAS TGC → JSESSIONID）
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = '$e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _ready = true;
    });
  }

  /// 目标页：本页即宿主（**不要再换成 push / pushReplacement**）。
  Widget _target() {
    final initialTab = widget.initialTab;
    if (initialTab == null) return const ImsMenuScreen();
    return ImsTabContainer(initialTab: initialTab);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return _buildFailure(context, error);
    if (_ready) return _target();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_preparing ? '正在恢复教务会话…' : '加载中…'),
          ],
        ),
      ),
    );
  }

  /// 换票失败：给出可操作出路，**不再**把用户困在转圈页。
  Widget _buildFailure(BuildContext context, String error) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: paneAppBar(context, title: const Text('教务会话')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '教务会话暂时没能准备好',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '可能是网络不通，或统一登录（CAS）已过期需要重新登录。\n'
              '本地缓存的数据仍可查看。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _enter,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _error = null;
                _ready = true;
              }),
              child: const Text('先看本地缓存'),
            ),
            const SizedBox(height: 20),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
