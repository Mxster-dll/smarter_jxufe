/// 通识课程库 —— 「这门通识选修课属于哪个模块」的唯一口径。
///
/// 数据来源 = 学校下发的《2026年通识课程库（含外校网课）》xlsx，由
/// `tool/make_ge_catalog.py` 转成 `assets/general_education/ge_catalog.json`
/// 后入库（源 xlsx 不入库；重新生成见工具的 docstring）。
///
/// **为什么需要它**：培养方案里通识选修那一段只有 4 个「占位课」
/// （`1002302502 哲学、思维与语言模块` 之类，各 2 学分），学生实际修的是
/// 课程库里的任意一门通识课 —— 想算「美育还差几分」就只能靠这张库把
/// 课程代码映射回模块。
///
/// 三张 sheet 按入学年级适用：2021-2023 / 2024-2025 / 外校网课（各年级）。
library;

/// 通识课程模块（课程库「模块」列的取值）。
///
/// 前四个**逐一对应教务「毕业学分要求」表里的要求项**（美育 / 科学、技术与方法 /
/// 历史、政治与社会 / 哲学、思维与语言）；[developmentGuidance] 只出现在
/// 2021-2023 那张表里，教务要求项中没有它。
enum GeneralEducationModule {
  historyPoliticsSociety('历史、政治与社会（经典阅读）', '历史政治与社会'),
  philosophyThinkingLanguage('哲学、思维与语言', '哲学思维与语言'),
  scienceTechnologyMethod('科学、技术与方法', '科学技术与方法'),
  aesthetic('美育', '美育'),
  developmentGuidance('发展指导课', '发展指导课');

  const GeneralEducationModule(this.label, this.canonicalKey);

  /// 展示名（取课程库里的写法）。
  final String label;

  /// 归一化后的比对键，见 [canonicalCategoryKey]。
  final String canonicalKey;
}

/// 归一化「课程类别 / 要求项名 / 模块名」成可比对的核心词。
///
/// 三类噪音一律剥掉：**年级前缀**（数字与拉丁字母）、**标点与空白**、
/// **修饰词**（经典阅读 / 模块 / 选修 / 学分 / 课程）。于是下面这些两两对齐：
///
/// ```text
/// 2024公共外语选修课            → 公共外语课     ┐ 同一个键
/// 公共外语课                    → 公共外语课     ┘
/// 2024科学、技术与方法选修2学分  → 科学技术与方法 ┐ 同一个键
/// 科学、技术与方法模块          → 科学技术与方法 ┘
/// 历史、政治与社会（经典阅读）    → 历史政治与社会
/// ```
///
/// ⚠ **「课 / 必修 / 限选 / 任选」不在噪音表里**（2026-10-08 实测踩过）：
/// 早先版本把「课」也当噪音剥，`专业必修课 → 专业必修 → 专业`、
/// `专业限选课 → 专业限选 → 专业` 会一路塌成同一个键，把「专业必修」和
/// 「专业限选」混成一类。真正需要抹平的只有**要求项名里的「选修 / 学分」**
/// （教务写「公共外语选修课」，培养方案写「公共外语课」）。
///
/// 实测口径见 `test/general_education_catalog_test.dart` 的台账。
String canonicalCategoryKey(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'[0-9A-Za-z]'), '');
  s = s.replaceAll(RegExp(r'[、，,·・.。\s（）()\[\]【】]'), '');
  for (final word in _categoryNoiseWords) {
    s = s.replaceAll(word, '');
  }
  return s;
}

/// 修饰词，**按长度从长到短**依次剥（先「经典阅读」再「模块」）。
const List<String> _categoryNoiseWords = [
  '经典阅读',
  '模块',
  '选修',
  '学分',
  '课程',
];

/// 把任意写法归一成模块；认不出返回 null（**不猜**）。
GeneralEducationModule? generalEducationModuleOf(String raw) {
  final key = canonicalCategoryKey(raw);
  if (key.isEmpty) return null;
  for (final m in GeneralEducationModule.values) {
    if (m.canonicalKey == key) return m;
  }
  // 前缀兜底：「历史政治与社会」这类截断写法（要求项与模块名长度不一致时）。
  // 阈值 3 个字，避免「美」把「美育」蒙对。
  if (key.length >= 3) {
    for (final m in GeneralEducationModule.values) {
      if (key.startsWith(m.canonicalKey) || m.canonicalKey.startsWith(key)) {
        return m;
      }
    }
  }
  return null;
}

/// 课程库里的一门通识课。
class GeneralEducationCourse {
  /// 课程编码（主码）。
  final String code;

  /// 同一行里并列写着的其它编码（如「军事与艺术 I~IV」一格里 4 个码）。
  final List<String> extraCodes;

  /// 课程名称。
  final String name;

  /// 学分；区间学分（「0.5-1」）解析不了时为 null，原文见 [creditText]。
  final double? credit;

  /// 学分原文（仅区间学分时非空）。
  final String? creditText;

  /// 所属模块；2021-2023 那张表开头 89 门课在源表里**没有模块标签**，此处为 null。
  final GeneralEducationModule? module;

  /// 课程归属单位。
  final String dept;

  /// 备注里写着的旧课程代码（老生成绩只认旧码）。
  final List<String> oldCodes;

  /// 备注原文。
  final String? note;

  /// 来自哪张 sheet（用于界面标注口径）。
  final String sheetTitle;

  const GeneralEducationCourse({
    required this.code,
    required this.name,
    required this.sheetTitle,
    this.extraCodes = const [],
    this.credit,
    this.creditText,
    this.module,
    this.dept = '',
    this.oldCodes = const [],
    this.note,
  });

  /// 本行认领的全部编码（主码 + 并列码 + 旧码）。
  List<String> get allCodes => [code, ...extraCodes, ...oldCodes];
}

/// 课程库里的一张 sheet。
class GeneralEducationSheet {
  final String title;

  /// 适用入学年级区间（含端点）；[allCohorts] 为 true 时两者皆 null。
  final int? cohortFrom;
  final int? cohortTo;

  /// 「适用各年级」。
  final bool allCohorts;

  final List<GeneralEducationCourse> courses;

  const GeneralEducationSheet({
    required this.title,
    required this.courses,
    this.cohortFrom,
    this.cohortTo,
    this.allCohorts = false,
  });

  bool covers(int year) {
    if (allCohorts) return true;
    if (cohortFrom == null || cohortTo == null) return false;
    return year >= cohortFrom! && year <= cohortTo!;
  }
}

/// 「这次按哪几张表查」的结果 —— 连同**为什么**，好让界面照实说明。
class GeneralEducationScope {
  final List<GeneralEducationSheet> sheets;

  /// 查表用的入学年级。
  final int? cohort;

  /// 是否有 sheet 的适用区间真的盖住了 [cohort]。
  ///
  /// false 有两种情形：学籍年份未知，或学校还没下发该年级的表（此时退到
  /// 最新的那张）。两种都必须在界面上讲明白，不能让用户以为查的是本年级的表。
  final bool exactCohortMatch;

  const GeneralEducationScope({
    required this.sheets,
    required this.cohort,
    required this.exactCohortMatch,
  });

  List<String> get sheetTitles => [for (final s in sheets) s.title];

  bool get isEmpty => sheets.isEmpty;
}

/// 通识课程库全文 + 按入学年级建索引。
class GeneralEducationCatalog {
  /// 修订日期（源文件名里的日期）。
  final String revision;

  /// 来源名。
  final String sourceName;

  final List<GeneralEducationSheet> sheets;

  const GeneralEducationCatalog({
    required this.revision,
    required this.sourceName,
    required this.sheets,
  });

  static const GeneralEducationCatalog empty = GeneralEducationCatalog(
    revision: '',
    sourceName: '',
    sheets: [],
  );

  /// 该入学年级适用的表：命中的年级区间表 + 「适用各年级」表。
  ///
  /// 一个区间都没命中时退到 cohortTo 最大的那张（学校还没下发新表），并把
  /// [GeneralEducationScope.exactCohortMatch] 置 false。
  GeneralEducationScope scopeFor(int? cohort) {
    final all = [for (final s in sheets) if (s.allCohorts) s];
    if (cohort != null) {
      // ⚠ 只拿**年级区间表**判命中：「适用各年级」那张对任何 cohort 都 covers，
      // 混进来会让「没有本年级的表」永远判成命中（2026 级实测踩过）。
      final exact = [
        for (final s in sheets)
          if (!s.allCohorts && s.covers(cohort)) s,
      ];
      if (exact.isNotEmpty) {
        return GeneralEducationScope(
          sheets: [...exact, ...all],
          cohort: cohort,
          exactCohortMatch: true,
        );
      }
    }
    final ranged =
        [for (final s in sheets) if (!s.allCohorts && s.cohortTo != null) s]
          ..sort((a, b) => b.cohortTo!.compareTo(a.cohortTo!));
    return GeneralEducationScope(
      sheets: [...ranged.isEmpty ? const <GeneralEducationSheet>[] : [ranged.first], ...all],
      cohort: cohort,
      exactCohortMatch: false,
    );
  }

  /// 按 [scope] 建查询索引。
  GeneralEducationIndex indexFor(int? cohort) =>
      GeneralEducationIndex(scopeFor(cohort));
}

/// 一个适用范围下的课程索引（主码 / 并列码 / 旧码 / 课程名 四路）。
class GeneralEducationIndex {
  final GeneralEducationScope scope;

  GeneralEducationIndex(this.scope);

  late final Map<String, GeneralEducationCourse> _byCode = () {
    final map = <String, GeneralEducationCourse>{};
    for (final sheet in scope.sheets) {
      for (final course in sheet.courses) {
        for (final code in course.allCodes) {
          if (code.isEmpty) continue;
          // 先到先得：同码在多张表里出现时以先命中的表为准（顺序 = 年级表 → 各年级表）
          map.putIfAbsent(code, () => course);
        }
        if (course.name.isNotEmpty) {
          map.putIfAbsent('name:${course.name}', () => course);
        }
      }
    }
    return map;
  }();

  /// 按课程代码查（含并列码与旧码）。
  GeneralEducationCourse? byCode(String code) {
    final key = code.trim();
    if (key.isEmpty) return null;
    return _byCode[key];
  }

  /// 按课程名查（成绩里偶尔没有代码，兜底用）。
  GeneralEducationCourse? byName(String name) {
    final key = name.trim();
    if (key.isEmpty) return null;
    return _byCode['name:$key'];
  }

  /// 代码优先、名字兜底。
  GeneralEducationCourse? lookup({String code = '', String name = ''}) =>
      byCode(code) ?? byName(name);

  /// 该课程在这个适用范围里属于哪个模块。
  GeneralEducationModule? moduleOf({String code = '', String name = ''}) =>
      lookup(code: code, name: name)?.module;
}
