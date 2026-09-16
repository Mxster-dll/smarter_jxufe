import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_page_transitions.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_grid.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_sync_scope.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/shared/widgets/account_avatar.dart';

/// 单页功能主页 —— 登录后的统一落地页。
///
/// 两种布局（用户 2026-09-15 裁定第 1 条，**切换入口只在设置页**、选择记住）：
/// - **宫格视图**（默认，手机端唯一形态）：图标磁贴铺满页面，点磁贴 push 整页；
/// - **左侧导航栏视图**（仅电脑端且宽度 ≥ [homeSidebarMinWidth]）：左侧按分组
///   列出全部服务，点击**把功能页内嵌在右侧面板**（`HomeDetailPane`，用户同日
///   第 2 条），右侧默认内容是「数据一览」概览。
///
/// 服务条目表在 `home_service_catalog.dart`（宫格与侧栏共用一份，强调色随条目走）。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 侧栏当前选中的服务标题；`null` = 右侧显示「数据一览」概览。
  ///
  /// 只活在页面 State 里（不进 Hive）：切走再回来仍是概览，符合「主页 = 概览」
  /// 的直觉；窄窗口 / 宫格视图下这个字段被忽略。
  String? _selectedService;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = ref.watch(homeLayoutStoreProvider).layout;
    final desktop = homeDesktopPlatform(Theme.of(context).platform.name);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final entries = homeServiceEntries(
              push: (screen) => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => screen)),
            );
            final useSidebar = homeUsesSidebarLayout(
              layout: layout,
              desktop: desktop,
              width: constraints.maxWidth,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(context, scheme),
                const Divider(height: 1),
                Expanded(
                  child: useSidebar
                      ? _buildSidebarBody(context, entries)
                      : _buildGridBody(context, entries),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 宫格视图：数据一览 + 全部服务宫格。
  Widget _buildGridBody(BuildContext context, List<HomeServiceEntry> entries) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
      children: [
        // 桌面小组件同步触发点（首帧推送 + 回前台重推 + 冷启动路由）
        const HomeWidgetSyncScope(child: DashboardPanel()),
        const SizedBox(height: 26),
        _buildSectionHeader(context, '全部服务'),
        const SizedBox(height: 14),
        HomeServiceGrid(entries: entries),
      ],
    );
  }

  /// 左侧导航栏视图：侧栏（全部服务，按分组）+ 右侧「概览 / 内嵌功能页」。
  Widget _buildSidebarBody(BuildContext context, List<HomeServiceEntry> entries) {
    final selected = _selectedEntry(entries);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSidebar(
          entries: entries,
          selectedTitle: selected?.title,
          onOverview: () => _select(null),
          onSelect: (entry) => _select(entry.title),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          // 换服务 → 右栏内容横向滑入 + 淡入（与页面转场同一语言，见
          // lib/design/app_page_transitions.dart）。原来是从概览/上一个服务**硬切**。
          //
          // ⚠ 必须自备 layoutBuilder：AnimatedSwitcher 默认那个用
          // `Stack(alignment: center)` 且不撑满 → 右栏内容（ListView / 内嵌 Navigator）
          // 会缩成内容大小、贴着中间，看起来像「页面变小了」。
          child: AnimatedSwitcher(
            duration: appPaneSwitchDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: <Widget>[...previous, ?current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(appPaneSwitchOffsetX, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<String>(
                selected?.title ?? homeSidebarOverviewTitle,
              ),
              child: selected == null
                  ? _buildOverviewPane()
                  : HomeDetailPane(entry: selected),
            ),
          ),
        ),
      ],
    );
  }

  /// 右侧默认内容：数据一览概览。
  Widget _buildOverviewPane() {
    return ListView(
      key: const Key('homeOverviewPane'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
      children: const [HomeWidgetSyncScope(child: DashboardPanel())],
    );
  }

  /// 按标题找回当前条目；目录里已不存在该标题（改版残留）→ 回落概览。
  HomeServiceEntry? _selectedEntry(List<HomeServiceEntry> entries) {
    final title = _selectedService;
    if (title == null) return null;
    for (final entry in entries) {
      if (entry.title == title) return entry;
    }
    return null;
  }

  void _select(String? title) {
    if (_selectedService == title) return;
    setState(() => _selectedService = title);
  }

  Widget _buildSectionHeader(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ---------- 顶部：品牌 + 设置 + 头像（点头像进「我的」） ----------
  //
  // 顶栏不再显示账号名/卡号，也不再有「切换账号」按钮：
  // 姓名与卡号在「我的」页里看，账号管理（添加/切换/删除账户）走
  // 「我的」页右上角的退出图标 → AccountScreen。
  Widget _buildTopBar(BuildContext context, ColorScheme scheme) {
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '智',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '智慧er江财',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          // 全局设置入口（紧凑排布，避免窄屏顶栏溢出）。
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          const SizedBox(width: 4),
          // 个人入口：本地头像（未设置则姓名首字，再退通用图标）。
          AccountAvatar(
            radius: 18,
            tooltip: '我的',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudentInfoScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
