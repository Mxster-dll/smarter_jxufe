/// 网站导航 · 领域模型与查询纯函数。
///
/// 用户 2026-09-19 立项：「我希望添加一个网站导航的功能」（先给了 8 条，并要求
/// 「各学院你去找，然后非学院官网的应该也还要很多其他网站」）。
/// 目录数据在 [site_directory.dart]，本文件只放模型与「筛选 / 分节」这两件纯逻辑，
/// 页面（`presentation/site_nav_screen.dart`）因此可以很薄、也便于单测。
library;

/// 站点分类（枚举顺序 = 页面里的分节顺序）。
enum CampusSiteCategory {
  college('学院与学部'),
  department('职能部门'),
  service('服务系统'),
  research('科研机构'),
  other('其他站点');

  const CampusSiteCategory(this.title);

  /// 分节标题。
  final String title;
}

/// 一条站点。
class CampusSite {
  const CampusSite(
    this.name,
    this.url,
    this.category, {
    this.hot = false,
    this.note,
  });

  /// 站点名（如 `教务处`、`软件与物联网工程学院`）。
  final String name;

  /// 完整 URL（**协议按站点实况写死**：多个站点只有单向可用，见 [note]）。
  final String url;

  /// 分类（决定它落在哪一节）。
  final CampusSiteCategory category;

  /// 常用（每天都可能点的那几个）：行内出「常用」小标，并可用「常用」筛选。
  final bool hot;

  /// 备注：改名提示 / 协议限制 / 仅校园网可达 / 需登录 等；`null` = 无。
  final String? note;

  /// 展示用的主机名（`https://jwc.jxufe.edu.cn/` → `jwc.jxufe.edu.cn`）。
  String get host => campusSiteHost(url);

  /// 收藏的稳定键 —— **用 URL 而不是名称**：站点改名后收藏不会丢。
  String get key => url;
}

/// 从 URL 里取主机名；解析不出时原样返回（空串、奇怪输入都不抛）。
String campusSiteHost(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  return host.isEmpty ? url : host;
}

/// 搜索匹配：名称 / URL（含主机名）/ 备注，**忽略大小写与首尾空白**。
bool campusSiteMatches(CampusSite site, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (site.name.toLowerCase().contains(q)) return true;
  if (site.url.toLowerCase().contains(q)) return true;
  return (site.note ?? '').toLowerCase().contains(q);
}

/// 筛选：搜索词 + 分类 + 只看常用 + 只看收藏，**四个条件是「与」**。
///
/// [favorites] 是收藏键集合（`Set<CampusSite.key>`，来自
/// `siteFavoritesProvider`）；[favoritesOnly] 为 true 时只保留收藏项。
List<CampusSite> filterCampusSites(
  Iterable<CampusSite> all, {
  String query = '',
  CampusSiteCategory? category,
  bool hotOnly = false,
  bool favoritesOnly = false,
  Set<String> favorites = const <String>{},
}) => [
  for (final s in all)
    if ((category == null || s.category == category) &&
        (!hotOnly || s.hot) &&
        (!favoritesOnly || favorites.contains(s.key)) &&
        campusSiteMatches(s, query))
      s,
];

/// 页面里的一节。
class CampusSiteSection {
  const CampusSiteSection({
    required this.title,
    required this.key,
    required this.sites,
    this.favorites = false,
  });

  /// 节标题（分类名，或「我的收藏」）。
  final String title;

  /// 稳定 key：`'fav'` 或 `CampusSiteCategory.name`（渲染与测试都用它定位）。
  final String key;

  /// 本节条目（保持目录原始顺序）。
  final List<CampusSite> sites;

  /// 是否「我的收藏」节（图标与强调色不同）。
  final bool favorites;
}

/// 分节：**收藏段恒在最前**（无收藏时不出现），其后按 [CampusSiteCategory] 枚举顺序。
///
/// 空节不占位。四个筛选条件对**收藏段同样生效** —— 否则按分类筛过之后，
/// 收藏段里会冒出一条被筛掉的站点（同一站点在两处出现、且与筛选矛盾）。
///
/// 两条刻意保留的语义：
/// - 未开 [favoritesOnly] 时，**收藏过的站点在两处都出现**（收藏段 + 它自己的分类段）
///   —— 收藏段是「置顶快捷区」，分类段是「完整目录」，这正是用户要的「置顶分组」；
/// - 开了 [favoritesOnly] 则**只出收藏段**，否则分类段会把同一批站点再列一遍。
List<CampusSiteSection> campusSiteSections({
  required Iterable<CampusSite> all,
  Set<String> favorites = const <String>{},
  String query = '',
  CampusSiteCategory? category,
  bool hotOnly = false,
  bool favoritesOnly = false,
}) {
  final visible = filterCampusSites(
    all,
    query: query,
    category: category,
    hotOnly: hotOnly,
    favoritesOnly: favoritesOnly,
    favorites: favorites,
  );
  final faves = [
    for (final s in visible)
      if (favorites.contains(s.key)) s,
  ];
  final favSection = faves.isEmpty
      ? const <CampusSiteSection>[]
      : [
          CampusSiteSection(
            title: '我的收藏',
            key: 'fav',
            sites: faves,
            favorites: true,
          ),
        ];
  if (favoritesOnly) return favSection;
  return [
    ...favSection,
    for (final c in CampusSiteCategory.values)
      ...() {
        final sites = [
          for (final s in visible)
            if (s.category == c) s,
        ];
        return sites.isEmpty
            ? const <CampusSiteSection>[]
            : [
                CampusSiteSection(
                  title: c.title,
                  key: c.name,
                  sites: sites,
                ),
              ];
      }(),
  ];
}
