/// 左侧导航栏视图（仅电脑端宽窗口；判定见 `domain/home_layout.dart`）。
///
/// 用户 2026-09-15 裁定：
/// - 第 1 条：侧栏按分组列出全部服务；
/// - 第 2 条（同日二轮，**推翻了本文件旧注释里「点它直接 push 功能页」的写法**）：
///   「点击左侧导航栏后，不是跳转页面，而是直接在右侧显示原跳转页面，并取消原
///   页面的返回按钮」→ 侧栏只负责**选中**（[onSelect]/[selectedTitle]），页面由
///   `HomeScreen` 装进右侧的 `HomeDetailPane`（面板自带 Navigator，见该文件）。
///   返回按钮的取消是自动的：内嵌页在面板路由栈里是首页 → `canPop == false`
///   → 各页 AppBar 不再画返回键（`ims_tab_container.dart` / `data_center_screen.dart`
///   两处硬编码返回键已改为按 `canPop` 判定）。
///
/// 顶部固定一行「数据一览」= 未选中任何服务时的右侧概览（[onOverview] 为 null
/// 时不渲染，测试与旧调用点因此不受影响），**紧跟其后**是
/// [HomeServiceEntry.sidebarPinned] 的条目（2026-09-19 起只有「AI 助手」一条，
/// 用户要求它「和"数据一览"下方紧贴」）。这两行同样不画分割线、不插分组标题。
///
/// ⚠ 「数据一览」与它下面第一个分组（`HomeServiceGroup.values[0]` = 「教务系统」）
/// 之间**不画分割线**（用户 2026-09-17：「桌面端主页的侧边导航栏里，顶部"数据
/// 一览"和教务系统之间不要显示分割线」）—— 靠分组标题自身的上内边距（14）留白
/// 即可。分组之间本来就没有分割线，别再加回来（列表里唯一的另一条线在底部
/// 固定区上方，那条不动）。
///
/// **底部固定区**（用户 2026-09-16 裁定：「桌面端把标题栏里的头像和设置都应该改到
/// 侧边导航栏，设置在下，头像在上，并且这两个是固定在底部不浮动的」）：由调用方通过
/// [footer] 传入（用 [HomeSidebarFooterRow] 拼行），渲染在滚动区**之外** ——
/// 服务列表再长也压不到它。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 概览行文案（也是它在侧栏里的 Key 后缀）。
const String homeSidebarOverviewTitle = '数据一览';

/// 底部固定区：头像行（进「我的」）的 Key。
const Key homeSidebarProfileKey = Key('homeSidebarProfile');

/// 底部固定区：设置行的 Key。
const Key homeSidebarSettingsKey = Key('homeSidebarSettings');

/// 侧栏底部固定区的一行：左内边距 / 行高与上方服务行同口径（图标或头像 + 标签）。
class HomeSidebarFooterRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  const HomeSidebarFooterRow({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: HomeSidebar.footerRowHeight,
        padding: const EdgeInsets.only(
          left: 18 - HomeSidebar.indicatorWidth,
          right: 18,
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左侧导航栏。
class HomeSidebar extends StatelessWidget {
  final List<HomeServiceEntry> entries;

  /// 栏宽（默认 [homeSidebarWidth]）。
  final double width;

  /// 当前选中的服务标题；`null` = 顶部「数据一览」概览。
  final String? selectedTitle;

  /// 点击服务条目。为 null 时回落到条目自带的 [HomeServiceEntry.onTap]。
  final ValueChanged<HomeServiceEntry>? onSelect;

  /// 点击顶部「数据一览」；为 null 时不渲染该行。
  final VoidCallback? onOverview;

  /// 底部固定区（不随列表滚动）；为 null 时整块不画。
  final Widget? footer;

  const HomeSidebar({
    super.key,
    required this.entries,
    this.width = homeSidebarWidth,
    this.selectedTitle,
    this.onSelect,
    this.onOverview,
    this.footer,
  });

  /// 单个条目行高。
  static const double rowHeight = 38;

  /// 底部固定区单行行高（比服务行略高：头像外径 30）。
  static const double footerRowHeight = 46;

  /// 选中态的左侧指示条宽（占位恒定，避免选中/未选中行文字左右跳动）。
  static const double indicatorWidth = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('homeSidebar'),
      width: width,
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 服务列表：**只有它滚动**。
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              children: [
                if (onOverview != null) _overviewRow(context, scheme),
                // 顶部固定项：紧贴「数据一览」下方**不分节**（用户 2026-09-19：
                // 「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴」）——
                // 中间不插分组标题、不加分割线，两行同高（rowHeight）直接相接。
                for (final item in homePinnedSidebarEntries(entries))
                  _row(context, item),
                for (final group in HomeServiceGroup.values)
                  ..._group(context, scheme, group),
              ],
            ),
          ),
          // 底部固定区：不随列表滚动（超长服务列表也压不到它）。
          if (footer != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              // ⚠ 别写回 `scheme.outlineVariant.withValues(alpha: 0.6)`：深色下
              // `outlineVariant` 本身就是 10% 白（带 alpha），而 `withValues` 是
              // **替换** alpha 不是相乘 → 会变成 60% 白，叠在侧栏 `#1A1A1A` 上混成
              // `#A3A3A3`（实测），用户 2026-09-17 报「底部固定项最顶部的分割线太亮」。
              // `hairline` 浅色逐像素不变、深色落到 10% 白基准。
              color: AppColors.hairline(context),
            ),
            footer!,
          ],
        ],
      ),
    );
  }

  /// 顶部「数据一览」：右侧面板的默认内容，也是唯一的「返回概览」入口。
  Widget _overviewRow(BuildContext context, ColorScheme scheme) {
    final selected = selectedTitle == null;
    final accent = scheme.primary;
    return InkWell(
      key: const Key('homeSidebarOverview'),
      onTap: onOverview,
      hoverColor: accent.withValues(alpha: 0.06),
      child: _rowShell(
        context,
        selected: selected,
        accent: accent,
        child: Row(
          children: [
            Icon(Icons.dashboard_outlined, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                homeSidebarOverviewTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _group(
    BuildContext context,
    ColorScheme scheme,
    HomeServiceGroup group,
  ) {
    // 固定项已经在「数据一览」下方单独渲染过 → 从分组里摘掉，别出现两次。
    final items = [
      for (final e in homeServiceEntriesInGroup(entries, group))
        if (!e.sidebarPinned) e,
    ];
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text(
          group.title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      for (final item in items) _row(context, item),
    ];
  }

  Widget _row(BuildContext context, HomeServiceEntry item) {
    final scheme = Theme.of(context).colorScheme;
    final selected = item.title == selectedTitle;
    return InkWell(
      key: Key('homeSidebarItem-${item.title}'),
      onTap: () {
        final select = onSelect;
        if (select != null) {
          select(item);
        } else {
          item.onTap();
        }
      },
      hoverColor: item.accent.withValues(alpha: 0.06),
      child: _rowShell(
        context,
        selected: selected,
        accent: item.accent,
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: item.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 行外壳：恒定的定高 + 左侧指示条占位（选中才着色）+ 选中底色。
  Widget _rowShell(
    BuildContext context, {
    required bool selected,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        color: selected ? AppColors.tint(context, accent, 0.10) : null,
        border: Border(
          left: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: indicatorWidth,
          ),
        ),
      ),
      padding: const EdgeInsets.only(
        left: 18 - indicatorWidth,
        right: 18,
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
