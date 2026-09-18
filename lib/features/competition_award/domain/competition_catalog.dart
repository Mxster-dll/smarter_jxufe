/// 竞赛奖励模块 —— 竞赛目录模型（《江西财经大学学科竞赛目录》）。
///
/// 目录本身是**资料库里的文档**（`assets/rules/text/r20.md` = 2024-2025 学年、
/// `r21.md` = 2025-2026 年），运行时由 `competition_catalog_parser.dart` 解析，
/// 这里只放「解析后长什么样」。
///
/// 用户原话（2026-09-17）：「新功能：竞赛奖励 / 参考《学科竞赛管理办法》 /
/// 自动资料库里获取竞赛信息，然后时间范围不是按学年，而是手动选择时间范围」
/// —— 「时间范围」指**获奖记录**的筛选区间，不是目录版本；目录版本只是
/// 名称与类别的出处（见 `award_record.dart` / `award_calc.dart`）。
library;

/// 学科竞赛类别（《学科竞赛管理办法（2024年修订）》第七条）。
enum CompetitionClass {
  i('Ⅰ类'),
  ii('Ⅱ类'),
  iii('Ⅲ类'),
  iv('Ⅳ类');

  const CompetitionClass(this.label);

  final String label;

  /// 办法第九条：Ⅳ类学科竞赛只奖励指导教师（组），**不奖励学生**。
  bool get rewardsStudents => this != CompetitionClass.iv;

  String get description => switch (this) {
    CompetitionClass.i => '教育部、共青团中央主办的全国性综合竞赛',
    CompetitionClass.ii => '中国高等教育学会《高校学科竞赛排行榜》目录内竞赛',
    CompetitionClass.iii => '国家部委 / 教指委 / 国家级学会等举办的单项竞赛',
    CompetitionClass.iv => '其他竞赛（重点支持江西省教育厅主办项目）',
  };

  /// 从「Ⅰ类 / I类 / 1类 / 一类」这类文本解析。
  static CompetitionClass? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains('Ⅳ') || s.contains('IV') || s.contains('ⅳ')) {
      return CompetitionClass.iv;
    }
    if (s.contains('Ⅲ') || s.contains('III') || s.contains('ⅲ')) {
      return CompetitionClass.iii;
    }
    if (s.contains('Ⅱ') || s.contains('II') || s.contains('ⅱ')) {
      return CompetitionClass.ii;
    }
    if (s.contains('Ⅰ') || s.contains('I') || s.contains('ⅰ')) {
      return CompetitionClass.i;
    }
    if (s.contains('四')) return CompetitionClass.iv;
    if (s.contains('三')) return CompetitionClass.iii;
    if (s.contains('二')) return CompetitionClass.ii;
    if (s.contains('一')) return CompetitionClass.i;
    return null;
  }
}

/// 目录里的一条竞赛。Ⅲ/Ⅳ类目录列了「申报专业 / 子项目」，Ⅳ类还靠 rowspan
/// 把同一主赛事的多个子项目并在一起 → [subProject] 与 [name] 分开存，
/// [displayName] 给出「主赛事 · 子项目」的完整称呼。
class CompetitionEntry {
  final int serial;
  final String name;
  final CompetitionClass klass;
  final String? subProject;
  final String? organizer;
  final String? major;
  final String? note;

  /// 目录版本标签（如 `2025-2026 年`）——获奖记录登记时一并保存，便于回溯出处。
  final String edition;

  const CompetitionEntry({
    required this.serial,
    required this.name,
    required this.klass,
    required this.edition,
    this.subProject,
    this.organizer,
    this.major,
    this.note,
  });

  String get displayName {
    final sub = (subProject ?? '').trim();
    return sub.isEmpty ? name : '$name · $sub';
  }

  /// 搜索命中的关键词集合（名称 / 子项目 / 组织单位 / 备注 / 类别）。
  bool matches(String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final lower = q.toLowerCase();
    for (final field in [
      name,
      subProject ?? '',
      organizer ?? '',
      major ?? '',
      note ?? '',
      klass.label,
    ]) {
      if (field.toLowerCase().contains(lower)) return true;
    }
    return false;
  }
}

/// 一个版本的目录（一份文档）。
class CompetitionCatalogEdition {
  final String label; // '2025-2026 年'
  final String title; // 文档标题原文
  final String? sourceDocId; // 资料库文档 id（RuleDoc.id）
  final List<CompetitionEntry> entries;

  const CompetitionCatalogEdition({
    required this.label,
    required this.title,
    required this.entries,
    this.sourceDocId,
  });

  List<CompetitionEntry> of(CompetitionClass klass) =>
      [for (final e in entries) if (e.klass == klass) e];

  int countOf(CompetitionClass klass) => of(klass).length;

  /// 年份排序键（'2025-2026 年' → 2025）。版本新旧只按它比。
  int get sortYear {
    final m = RegExp(r'(\d{4})').firstMatch(label);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }
}

/// 全部版本（新 → 旧）。名称查类别时优先用最新版目录。
class CompetitionCatalog {
  /// 新版本在前。
  final List<CompetitionCatalogEdition> editions;

  const CompetitionCatalog(this.editions);

  static const CompetitionCatalog empty = CompetitionCatalog([]);

  bool get isEmpty => editions.isEmpty;

  CompetitionCatalogEdition? get latest => editions.isEmpty ? null : editions.first;

  List<CompetitionEntry> get allEntries => [
    for (final e in editions) ...e.entries,
  ];

  List<CompetitionEntry> of(CompetitionClass klass) => [
    for (final e in editions) ...e.of(klass),
  ];

  /// 按名称（或「主赛事 · 子项目」）精确/包含匹配，返回**最新版本**里的条目。
  CompetitionEntry? find(String name) {
    final target = name.trim();
    if (target.isEmpty) return null;
    for (final edition in editions) {
      for (final e in edition.entries) {
        if (e.displayName == target || e.name == target) return e;
      }
    }
    for (final edition in editions) {
      for (final e in edition.entries) {
        if (e.name.contains(target) || target.contains(e.name)) return e;
      }
    }
    return null;
  }

  /// 全库搜索（跨版本去重：同名同类别只留最新版本的那条）。
  List<CompetitionEntry> search(String query) {
    final out = <CompetitionEntry>[];
    final seen = <String>{};
    for (final edition in editions) {
      for (final e in edition.entries) {
        if (!e.matches(query)) continue;
        final key = '${e.klass.name}|${e.displayName}';
        if (!seen.add(key)) continue;
        out.add(e);
      }
    }
    return out;
  }
}

/// 由多个版本构建目录（按 [CompetitionCatalogEdition.sortYear] 降序）。
CompetitionCatalog competitionCatalogOf(
  Iterable<CompetitionCatalogEdition> editions,
) {
  final list = editions.where((e) => e.entries.isNotEmpty).toList()
    ..sort((a, b) => b.sortYear.compareTo(a.sortYear));
  return CompetitionCatalog(list);
}
