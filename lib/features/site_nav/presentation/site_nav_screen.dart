/// 网站导航入口页：江西财经大学**全量站点目录**（搜索 + 分类筛选 + 收藏置顶）。
///
/// 用户 2026-09-19 立项，三条拍板口径：
/// 1. **一律用系统浏览器打开**（明确否掉「手机内嵌 WebView」）→ 走
///    `externalUrlOpenerProvider`（`LaunchMode.externalApplication`），
///    **刻意不用** `lib/core/web/in_app_web_screen.dart`；
/// 2. **全量收录**（学院 + 职能部门 + 服务系统 + 科研机构 + 其他），目录在
///    `domain/site_directory.dart`（137 条，双层核实）；
/// 3. **星标收藏 + 置顶分组**（`data/site_favorites.dart`，Hive 持久化）——
///    收藏段恒排最前，另一个入口是行尾那颗星。
///
/// 页面本身很薄：筛选与分节全是 `domain/campus_site.dart` 的纯函数，这里只负责画。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';

import '../data/site_favorites.dart';
import '../domain/campus_site.dart';
import '../domain/site_directory.dart';

/// 分类图标（分节标题与行图标共用）。
IconData campusSiteIcon(CampusSiteCategory category) => switch (category) {
  CampusSiteCategory.college => Icons.school_outlined,
  CampusSiteCategory.department => Icons.account_balance_outlined,
  CampusSiteCategory.service => Icons.apps_outlined,
  CampusSiteCategory.research => Icons.science_outlined,
  CampusSiteCategory.other => Icons.public_outlined,
};

class SiteNavScreen extends ConsumerStatefulWidget {
  const SiteNavScreen({super.key});

  @override
  ConsumerState<SiteNavScreen> createState() => _SiteNavScreenState();
}

class _SiteNavScreenState extends ConsumerState<SiteNavScreen> {
  final _qCtrl = TextEditingController();
  String _q = '';

  /// 当前分类（`null` = 全部）。
  CampusSiteCategory? _category;

  /// 只看常用（16 条高频入口）。
  bool _hotOnly = false;

  /// 只看收藏（行尾星标的集合）。
  bool _favOnly = false;

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  bool get _filtering => _q.isNotEmpty || _category != null || _hotOnly || _favOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favorites = ref.watch(siteFavoritesProvider);
    final sections = campusSiteSections(
      all: campusSites,
      favorites: favorites.keys,
      query: _q,
      category: _category,
      hotOnly: _hotOnly,
      favoritesOnly: _favOnly,
    );
    final hit = sections.fold<int>(0, (sum, s) => sum + s.sites.length);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text(
          '网站导航',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: TextField(
              controller: _qCtrl,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索：站点名称 / 域名（如 教务、jwc、lib）',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '清空',
                        onPressed: () {
                          _qCtrl.clear();
                          setState(() => _q = '');
                        },
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _filterBar(favorites),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 22, 6),
            child: Row(
              children: [
                Text(
                  _filtering
                      ? '共 ${campusSites.length} 个站点 · 命中 $hit 个'
                      : '共 ${campusSites.length} 个站点 · 已收藏 ${favorites.length} 个',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_filtering)
                  Text(
                    '点「全部」还原',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: hit == 0
                ? Center(
                    child: Text(
                      _favOnly && favorites.isEmpty
                          ? '还没有收藏 · 点行尾的星标即可收藏'
                          : '未找到匹配的站点',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                    children: [
                      for (final section in sections) ...[
                        _sectionHeader(context, section),
                        for (final site in section.sites)
                          _siteTile(
                            site,
                            favorite: favorites.contains(site.key),
                          ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 筛选条：全部 / 常用 / 五个分类（单行横向滚动，带条数）。
  Widget _filterBar(SiteFavoritesStore favorites) {
    final all = _category == null && !_hotOnly;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(
            '全部',
            campusSites.length,
            all,
            () => setState(() {
              _category = null;
              _hotOnly = false;
              _favOnly = false;
            }),
          ),
          _chip(
            '常用',
            campusSites.where((s) => s.hot).length,
            _hotOnly,
            () => setState(() => _hotOnly = !_hotOnly),
          ),
          _chip(
            '我的收藏',
            favorites.length,
            _favOnly,
            () => setState(() => _favOnly = !_favOnly),
            star: true,
          ),
          for (final c in CampusSiteCategory.values)
            _chip(
              c.title,
              campusSites.where((s) => s.category == c).length,
              _category == c,
              () => setState(() => _category = _category == c ? null : c),
            ),
        ],
      ),
    );
  }

  /// 一枚筛选胶囊。[star] 为 true 时前面带一颗星（「我的收藏」）。
  Widget _chip(
    String label,
    int count,
    bool selected,
    VoidCallback? onTap, {
    bool star = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? AppColors.tint(context, scheme.primary, 0.12)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected ? AppColors.tint(context, scheme.primary, 0.5)
                : scheme.outline,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                if (star) ...[
                  Icon(Icons.star_rounded, size: 13, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 分组标题（3px 竖条 + 标题 + 条数），收藏段多一颗星。
  ///
  /// Key = `siteSection-<section.key>`（`fav` / 分类名）—— 测试靠它认段，
  /// 免得与筛选条上同名的胶囊文字混淆。
  Widget _sectionHeader(BuildContext context, CampusSiteSection section) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('siteSection-${section.key}'),
      padding: const EdgeInsets.only(top: 6, bottom: 8, left: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          if (section.favorites) ...[
            Icon(Icons.star_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          Text(
            section.title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            '${section.sites.length} 个',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 一行站点：整行 = 用系统浏览器打开；行尾 = 收藏 / 复制链接。
  Widget _siteTile(CampusSite site, {required bool favorite}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(site),
          hoverColor: scheme.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, scheme.primary, 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    campusSiteIcon(site.category),
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              site.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (site.hot) ...[
                            const SizedBox(width: 6),
                            _tag(context, '常用'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        site.note == null
                            ? site.host
                            : '${site.host} · ${site.note}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _iconAction(
                  icon: favorite ? Icons.star_rounded : Icons.star_border,
                  tooltip: favorite ? '取消收藏' : '收藏',
                  color: favorite ? scheme.primary : scheme.onSurfaceVariant,
                  onPressed: () => ref
                      .read(siteFavoritesProvider)
                      .toggle(site.key),
                ),
                _iconAction(
                  icon: Icons.link,
                  tooltip: '复制链接',
                  color: scheme.onSurfaceVariant,
                  onPressed: () => _copy(site),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「常用」小标。
  Widget _tag(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.tint(context, scheme.primary, 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }

  /// 行尾紧凑图标按钮（30×30 点击区，与标题栏口径一致）。
  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) => IconButton(
    icon: Icon(icon, size: 18),
    tooltip: tooltip,
    color: color,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
  );

  /// 打开站点：**一律交给系统浏览器**（用户 2026-09-19 拍板）。
  Future<void> _open(CampusSite site) async {
    final uri = Uri.tryParse(site.url);
    if (uri == null) {
      _toast('链接无效：${site.url}');
      return;
    }
    final ok = await ref.read(externalUrlOpenerProvider)(uri);
    if (!mounted || ok) return;
    _toast('无法打开 ${site.host}（可能需要校园网）');
  }

  /// 复制链接到剪贴板（站内打不开时的手动兜底）。
  Future<void> _copy(CampusSite site) async {
    await Clipboard.setData(ClipboardData(text: site.url));
    if (!mounted) return;
    _toast('已复制链接：${site.url}');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
