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
/// 时不渲染，测试与旧调用点因此不受影响）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 概览行文案（也是它在侧栏里的 Key 后缀）。
const String homeSidebarOverviewTitle = '数据一览';

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

  const HomeSidebar({
    super.key,
    required this.entries,
    this.width = homeSidebarWidth,
    this.selectedTitle,
    this.onSelect,
    this.onOverview,
  });

  /// 单个条目行高。
  static const double rowHeight = 38;

  /// 选中态的左侧指示条宽（占位恒定，避免选中/未选中行文字左右跳动）。
  static const double indicatorWidth = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('homeSidebar'),
      width: width,
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 24),
        children: [
          if (onOverview != null) ...[
            _overviewRow(context, scheme),
            Divider(
              height: 17,
              thickness: 1,
              indent: 12,
              endIndent: 12,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ],
          for (final group in HomeServiceGroup.values)
            ..._group(context, scheme, group),
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
    final items = homeServiceEntriesInGroup(entries, group);
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
  Widget _rowShell({
    required bool selected,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.10) : null,
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
