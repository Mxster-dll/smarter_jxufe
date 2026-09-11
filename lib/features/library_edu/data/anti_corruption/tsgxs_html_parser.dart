/// 入馆教育(tsgxs.jxufe.cn)HTML 解析器。
///
/// 该平台为 ASP.NET MVC 服务端渲染,页面结构稳定(实测 fixture 见
/// `test/fixtures/tsgxs_*.html`),故用正则解析,不引入额外依赖。
library;

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

final _titleRe = RegExp(r'<title>(.*?)</title>', dotAll: true);
const _titleSuffix = '-江西财经大学图书馆-入馆教育系统';
final _chapterLinkRe = RegExp(
  r"/Web/Chapter/Index/([0-9a-f\-]{36})\?tid=([0-9a-f\-]{36})",
  caseSensitive: false,
);

String _pageTitle(String html) {
  final raw = _titleRe.firstMatch(html)?.group(1)?.trim() ?? '';
  return raw.endsWith(_titleSuffix)
      ? raw.substring(0, raw.length - _titleSuffix.length).trim()
      : raw;
}

/// 解析首页(`/Web/User`):章节 id 列表 + 皮肤 id。
///
/// 首页虽标题仍为“登录”(登录后复用同一模板),但含章节入口与个人中心。
({List<String> chapterIds, String? themeId}) parseTsgxsHome(String html) {
  final ids = <String>[];
  String? themeId;
  for (final m in _chapterLinkRe.allMatches(html)) {
    final id = m.group(1)!;
    themeId ??= m.group(2);
    if (!ids.contains(id)) ids.add(id);
  }
  return (chapterIds: ids, themeId: themeId);
}

/// 解析章节地图页:标题、线索(节点)、是否已看完、考试状态码。
TsgxsChapter parseTsgxsChapter(String html, String chapterId) {
  final nodes = <TsgxsNode>[];
  final nodeRe = RegExp(
    r"""<a id="([0-9a-f\-]{36})"[^>]*?href='[^']*'[^>]*?>\s*<img([^>]*?)>""",
    caseSensitive: false,
  );
  for (final m in nodeRe.allMatches(html)) {
    final id = m.group(1)!;
    final attrs = m.group(2)!;
    final src = RegExp(r'''src=["']([^"']+)["']''').firstMatch(attrs)?.group(1);
    if (src == null) continue;
    final intro = RegExp(
      r'''data-intro=["']([^"']*)["']''',
    ).firstMatch(attrs)?.group(1);
    var name = intro?.trim();
    if (name != null) {
      // “请点击学习 - 图书馆概况 ” → 图书馆概况
      name = name.replaceFirst(RegExp(r'^请点击学习\s*-\s*'), '').trim();
      if (name.isEmpty) name = null;
    }
    if (nodes.any((n) => n.id == id)) continue;
    nodes.add(TsgxsNode(id: id, imageUrl: src.trim(), name: name));
  }

  var isVisitAll = false;
  var examinations = 0;
  final examRe = RegExp(r"""exam\(\s*'(\w+)'\s*,\s*'[^']*'\s*,\s*(\d+)\s*\)""");
  final em = examRe.firstMatch(html);
  if (em != null) {
    isVisitAll = em.group(1)!.toLowerCase() == 'true';
    examinations = int.tryParse(em.group(2)!) ?? 0;
  }

  return TsgxsChapter(
    id: chapterId,
    title: _pageTitle(html),
    isVisitAll: isVisitAll,
    examinations: examinations,
    nodes: nodes,
  );
}

/// 解析学习内容页:标题、正文图片、上一节/下一节、返回地图的章节 id。
TsgxsContent parseTsgxsContent(String html, String nodeId) {
  // 正文图片:优先取 .wenzi 区块(正文容器)内的图片。
  final images = <String>[];
  final wenzi = RegExp(
    r'<div[^>]*class="[^"]*wenzi[^"]*"[^>]*>(.*?)</div>',
    dotAll: true,
  ).firstMatch(html)?.group(1);
  final scope = wenzi ?? html;
  final imgRe = RegExp(
    r'''(?:lay-src|src)=["'](/upload/image/[^"']+)["']''',
    caseSensitive: false,
  );
  for (final m in imgRe.allMatches(scope)) {
    final url = m.group(1)!.trim();
    if (!images.contains(url)) images.add(url);
  }

  String? prev;
  String? next;
  final prevRe = RegExp(
    r"""href=['"](/Web/Chapter/Content/([0-9a-f\-]{36})\?tid=[^'"]*)['"]\s*>\s*<img[^>]*btn_left""",
    caseSensitive: false,
  );
  final nextRe = RegExp(
    r"""href=['"](/Web/Chapter/Content/([0-9a-f\-]{36})\?tid=[^'"]*)['"]\s*>\s*<img[^>]*btn_right""",
    caseSensitive: false,
  );
  prev = prevRe.firstMatch(html)?.group(2);
  next = nextRe.firstMatch(html)?.group(2);

  final chapterId = RegExp(
    r"""href=["']/Web/Chapter/Index/([0-9a-f\-]{36})\?tid=""",
    caseSensitive: false,
  ).firstMatch(html)?.group(1);

  return TsgxsContent(
    nodeId: nodeId,
    title: _pageTitle(html),
    imageUrls: images,
    prevNodeId: prev,
    nextNodeId: next,
    chapterId: chapterId,
  );
}

/// 解析「我的成绩」页的两张表(本次成绩 / 考试记录)。
List<TsgxsGrade> parseTsgxsGrades(String html) {
  final out = <TsgxsGrade>[];
  for (final row in _tableRows(html)) {
    if (row.length < 3) continue;
    // 跳过表头
    if (row[0].contains('考试时间') || row[1].contains('闯关用时')) continue;
    final grade = TsgxsGrade(
      examTime: row[0],
      elapsed: row[1],
      score: row[2].replaceAll('分', '').trim(),
    );
    if (!out.contains(grade)) out.add(grade);
  }
  return out;
}

/// 解析排行榜页:榜单行 + 注释。
TsgxsRanking parseTsgxsRanking(String html) {
  final rows = <TsgxsRankRow>[];
  for (final row in _tableRows(html)) {
    if (row.length < 4) continue;
    if (row[0].contains('名次') || row[1].contains('姓名')) continue;
    final rank = int.tryParse(row[0].replaceAll(RegExp(r'\D'), ''));
    if (rank == null) continue;
    final out = TsgxsRankRow(
      rank: rank,
      name: row[1],
      score: row[2].replaceAll('分', '').trim(),
      elapsed: row[3],
    );
    if (rows.any((r) => r.rank == rank && r.name == out.name)) continue;
    rows.add(out);
  }
  rows.sort((a, b) => a.rank.compareTo(b.rank));
  final note =
      RegExp(
        r'<div class="zhushi">(.*?)</div>',
        dotAll: true,
      ).firstMatch(html)?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ??
      '';
  return TsgxsRanking(rows: rows, note: note);
}

/// 解析个人资料页(账号 / 姓名 / 学院)。
TsgxsProfile parseTsgxsProfile(String html) {
  final text = html
      .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '\n');
  String grab(String label) {
    final m = RegExp('$label[：:]\\s*([^\\n\\s][^\\n]*)').firstMatch(text);
    return m?.group(1)?.trim() ?? '';
  }

  return TsgxsProfile(
    account: grab('账号'),
    name: grab('姓名'),
    college: grab('学院'),
  );
}

/// 提取表格行的单元格文本(已去标签、压缩空白)。
List<List<String>> _tableRows(String html) {
  final out = <List<String>>[];
  for (final table in RegExp(
    r'<table.*?</table>',
    dotAll: true,
  ).allMatches(html)) {
    for (final row in RegExp(
      r'<tr.*?</tr>',
      dotAll: true,
    ).allMatches(table.group(0)!)) {
      final cells = <String>[];
      for (final cell in RegExp(
        r'<t[dh][^>]*>(.*?)</t[dh]>',
        dotAll: true,
      ).allMatches(row.group(0)!)) {
        cells.add(
          cell
              .group(1)!
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        );
      }
      if (cells.isNotEmpty) out.add(cells);
    }
  }
  return out;
}
