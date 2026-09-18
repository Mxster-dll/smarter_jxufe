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
      // 底部**不**留 SafeArea 内边距：Android 已铺满整屏（edge-to-edge），
      // 若在这里避开导航栏，导航栏那一条只会露出 Scaffold 的白底（用户
      // 2026-09-16：「主页宫格底部只显示白色而不是内容」）。不避开后磁贴
      // 会一直画到屏幕底边；列表底部 48 的内边距保证最后一行仍在导航栏之上。
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 强调色随亮度解析（宫格磁贴与侧栏共用这一份目录）：
            // 深色下 `FeatureColors.forBrightness` 会把每条 accent 提到可读档。
            final entries = homeServiceEntries(
              brightness: Theme.of(context).brightness,
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
                // 侧栏视图下顶栏不再放设置/头像（它们在侧栏底部固定区）。
                _buildTopBar(
                  context,
                  scheme,
                  showAccountActions: !useSidebar,
                ),
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

  /// 宫格视图：仪表盘（左：指标卡；右：今日课程 12 格）+ 服务宫格。
  ///
  /// 两个小标题（原「数据一览」「全部服务」）已按用户 2026-09-18 裁定撤掉。
  Widget _buildGridBody(BuildContext context, List<HomeServiceEntry> entries) {
    return ListView(
      // 底部内边距只留 12：Android 已铺满整屏（edge-to-edge），导航栏那一栏
      // 归 App 绘制；留 48 会让列表末尾空出一条通屏宽白带（用户 2026-09-16
      // 两次追问「主页宫格底部为什么只显示白色」，并裁定「铺到最底」）。
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        // 桌面小组件同步触发点（首帧推送 + 回前台重推 + 冷启动路由）
        const HomeWidgetSyncScope(child: DashboardPanel()),
        const SizedBox(height: 26),
        HomeServiceGrid(entries: entries),
      ],
    );
  }

  /// 左侧导航栏视图：侧栏（全部服务，按分组）+ 右侧「概览 / 内嵌功能页」。
  Widget _buildSidebarBody(
    BuildContext context,
    List<HomeServiceEntry> entries,
  ) {
    final selected = _selectedEntry(entries);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSidebar(
          entries: entries,
          selectedTitle: selected?.title,
          onOverview: () => _select(null),
          onSelect: (entry) => _select(entry.title),
          // 底部固定区：头像在上、设置在下（用户 2026-09-16 裁定 —— 桌面端这两个
          // 入口从顶栏搬到这里，恒贴侧栏底部、不随服务列表滚动）。
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeSidebarFooterRow(
                key: homeSidebarProfileKey,
                leading: const AccountAvatar(radius: 15),
                label: '我的',
                onTap: () => _pushPage(context, const StudentInfoScreen()),
              ),
              HomeSidebarFooterRow(
                key: homeSidebarSettingsKey,
                leading: Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                label: '设置',
                onTap: () => _pushPage(context, const SettingsScreen()),
              ),
            ],
          ),
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

  /// push 一个整页（顶栏品牌区与侧栏底部共用同一种转场）。
  void _pushPage(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  // ---------- 顶部：品牌（+ 宫格视图下的设置 / 头像） ----------
  //
  // 顶栏不再显示账号名/卡号，也不再有「切换账号」按钮：
  // 姓名与卡号在「我的」页里看，账号管理（添加/切换/删除账户）走
  // 「我的」页右上角的退出图标 → AccountScreen。
  //
  // **侧栏视图下设置与头像不在这里**（用户 2026-09-16 裁定）：它们搬到左侧导航栏
  // 底部的固定区（头像在上、设置在下，见 `home_sidebar.dart`），顶栏只留品牌。
  Widget _buildTopBar(
    BuildContext context,
    ColorScheme scheme, {
    required bool showAccountActions,
  }) {
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
          if (showAccountActions) ...[
            // 全局设置入口（紧凑排布，避免窄屏顶栏溢出）。
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              visualDensity: VisualDensity.compact,
              onPressed: () => _pushPage(context, const SettingsScreen()),
            ),
            const SizedBox(width: 4),
            // 个人入口：本地头像（未设置则姓名首字，再退通用图标）。
            AccountAvatar(
              radius: 18,
              tooltip: '我的',
              onTap: () => _pushPage(context, const StudentInfoScreen()),
            ),
          ],
        ],
      ),
    );
  }
}
