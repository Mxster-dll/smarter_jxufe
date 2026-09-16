/// 畅想之星书架域模型（分类树 / 分类书单 / 检索）。
///
/// 数据来源（2026-09-14 实测，全部在 `/api` 前缀下）：
/// - `GET /api/system/categories?pinst=<pinst>` → 分类字典（`clc` 中图法 /
///   `subject` 学科 / `college` 院系三套体系，**不是 data 列表**）；
/// - `GET /api/categories/{categoryId}/books?page&size&pinst&sortField=
///   orderno&sortType=DESC&keyword=&Publishers=&Authors=&Pubdates=&Types=
///   &Aggs=true` → 书单（`data[]` + `total` + 分面聚合），`keyword` 即检索词；
/// - `GET /api/system/hotSearch?pinst=<pinst>` → 热门检索词。
library;

/// 宽松取整（服务端同类字段在 string / int 之间摇摆）。
int cxstarNum(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

/// 去掉检索结果里的高亮标签与实体（服务端会把命中词包成 `<em>…</em>`）。
String cxstarPlainText(String raw) {
  if (raw.isEmpty) return '';
  final noTags = raw.replaceAll(RegExp(r'<[^>]*>'), '');
  return noTags
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}

/// 分类节点（可嵌套；`children` 为空表示叶子）。
class CxstarCategoryNode {
  final String id;
  final String name;
  final int total;
  final List<CxstarCategoryNode> children;

  const CxstarCategoryNode({
    required this.id,
    required this.name,
    this.total = 0,
    this.children = const [],
  });

  bool get hasChildren => children.isNotEmpty;

  factory CxstarCategoryNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = (json['children'] as List?) ?? const [];
    return CxstarCategoryNode(
      id: '${json['id'] ?? ''}',
      name: cxstarPlainText('${json['name'] ?? ''}'),
      total: cxstarNum(json['total']),
      children: [
        for (final c in rawChildren)
          if (c is Map) CxstarCategoryNode.fromJson(c.cast<String, dynamic>()),
      ],
    );
  }
}

/// 分类体系名（服务端键 → 中文）。
const Map<String, String> cxstarCategoryGroupLabels = {
  'clc': '中图法',
  'subject': '学科',
  'college': '院系',
};

/// 一套分类体系（如「中图法」的 22 个根节点）。
class CxstarCategoryGroup {
  final String key;
  final String label;
  final List<CxstarCategoryNode> roots;

  const CxstarCategoryGroup({
    required this.key,
    required this.label,
    required this.roots,
  });

  bool get isEmpty => roots.isEmpty;

  factory CxstarCategoryGroup.fromJson(String key, List<dynamic> raw) {
    return CxstarCategoryGroup(
      key: key,
      label: cxstarCategoryGroupLabels[key] ?? key,
      roots: [
        for (final n in raw)
          if (n is Map) CxstarCategoryNode.fromJson(n.cast<String, dynamic>()),
      ],
    );
  }
}

/// 分类字典（三套体系 + 本机构藏书量）。
class CxstarShelfCategories {
  final List<CxstarCategoryGroup> groups;

  /// 本机构（`pinst`）可读总册数。
  final int total;

  /// 服务端给的机构别名（本机构 = `蛟湖经典阅读`）。
  final String venueName;

  const CxstarShelfCategories({
    required this.groups,
    this.total = 0,
    this.venueName = '',
  });

  CxstarCategoryGroup? groupOf(String key) {
    for (final g in groups) {
      if (g.key == key) return g;
    }
    return null;
  }

  factory CxstarShelfCategories.fromJson(Map<String, dynamic> json) {
    return CxstarShelfCategories(
      groups: [
        for (final key in cxstarCategoryGroupLabels.keys)
          if ((json[key] as List?)?.isNotEmpty ?? false)
            CxstarCategoryGroup.fromJson(key, json[key] as List),
      ],
      total: cxstarNum(json['total']),
      venueName: cxstarPlainText('${json['collegeName'] ?? ''}'),
    );
  }
}

/// 书单中的一本书（字段与服务端 `data[]` 一致，未用字段不建模）。
class CxstarBook {
  final String id;
  final String title;
  final String author;
  final String cover;
  final String publisher;
  final String publishDate;
  final String intro;
  final String isbn;

  /// 平台侧阅读人次（`readNum`，用于「热门」排序展示）。
  final int readNum;

  const CxstarBook({
    required this.id,
    required this.title,
    this.author = '',
    this.cover = '',
    this.publisher = '',
    this.publishDate = '',
    this.intro = '',
    this.isbn = '',
    this.readNum = 0,
  });

  bool get hasCover => cover.isNotEmpty;

  /// 副标题行：「作者 · 出版年 · 出版社」中可用部分。
  String get subtitle {
    final parts = [
      if (author.isNotEmpty) author,
      if (publishDate.isNotEmpty) publishDate,
      if (publisher.isNotEmpty) publisher,
    ];
    return parts.join(' · ');
  }

  factory CxstarBook.fromJson(Map<String, dynamic> json) => CxstarBook(
    id: '${json['id'] ?? ''}',
    title: cxstarPlainText('${json['title'] ?? ''}'),
    author: cxstarPlainText('${json['author'] ?? ''}'),
    cover: '${json['cover'] ?? ''}',
    publisher: cxstarPlainText('${json['publisher'] ?? ''}'),
    publishDate: cxstarPlainText('${json['publishDate'] ?? ''}'),
    intro: cxstarPlainText('${json['intro'] ?? ''}'),
    isbn: cxstarPlainText('${json['isbn'] ?? ''}'),
    readNum: cxstarNum(json['readNum']),
  );
}

/// 一页书单。
class CxstarBookPage {
  final List<CxstarBook> books;
  final int total;
  final int page;
  final int size;

  const CxstarBookPage({
    required this.books,
    required this.total,
    required this.page,
    required this.size,
  });

  /// 是否还有下一页（按「已请求条数 < 总数」判定）。
  bool get hasMore => page * size < total;

  static const CxstarBookPage empty = CxstarBookPage(
    books: [],
    total: 0,
    page: 0,
    size: 0,
  );
}
