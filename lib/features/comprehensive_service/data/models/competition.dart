/// 第二课堂「学科竞赛」申请 / 公示的领域模型。
///
/// 数据源 = 综合管理服务平台（ssp.jxufe.edu.cn）团委模块
/// `/admin/tzz/dektSubjectGame/*`，全部是登录后页面（需 JSESSIONID）：
/// - 我的申请列表 `apply_list.html`、新增 `toAdd.html` → `add.do`、删除 `delete.do`、
///   详情 `detail.html`；
/// - 竞赛公示 `gs_list.html`、公示详情 `xd_detail.html`；
/// - 比赛目录 `find_game.do`（208 页）、比赛奖项 `getCredit.do`（JSON）、
///   学生检索 `find_student.do`（团队申请选成员用）；
/// - 证书图片上传 `/admin/accessory/upload.do?system_dir_path=base/indexdownload`。
library;

import 'dart:typed_data';

/// 申请类型（官网表单 `type`：`0` = 个人、`1` = 团队）。
enum CompetitionType {
  individual('个人'),
  team('团队');

  const CompetitionType(this.label);

  /// 界面文案，与官网「类型」列的取值一致。
  final String label;

  /// 官网表单值（`0` 个人 / `1` 团队）。
  String get formValue => this == CompetitionType.team ? '1' : '0';

  /// 由官网「类型」列文本反推；无法识别时按个人处理。
  static CompetitionType fromLabel(String label) =>
      label.contains('团队') ? CompetitionType.team : CompetitionType.individual;
}

/// 我的一条学科竞赛申请（`apply_list.html` 的一行）。
class CompetitionApply {
  final int id;

  /// 比赛年份（列表里的「比赛年份」列）。
  final String year;

  final String studentId;
  final String studentName;

  /// 比赛名称（官网目录里的全名，含赛别后缀，如「…【国赛】」）。
  final String gameName;

  final CompetitionType type;

  /// 申请时间（`yyyy-MM-dd`，官网原文）。
  final String applyTime;

  /// 审批状态原文（`未审批` / `通过` / `未通过` …）。
  final String status;

  const CompetitionApply({
    required this.id,
    required this.year,
    required this.studentId,
    required this.studentName,
    required this.gameName,
    required this.type,
    required this.applyTime,
    required this.status,
  });

  /// 是否还没审批（官网 `未审批`；宽容匹配「未 / 待」）。
  bool get pending => status.contains('未') || status.contains('待');

  /// 是否已通过（已审批且不含「未通过」）。
  bool get approved => !pending && !status.contains('不通过');
}

/// 竞赛公示的一条记录（`gs_list.html` 的一行，全校可见）。
class CompetitionPublicity {
  final int id;
  final String studentId;
  final String studentName;

  /// 学院 / 行政班级（公示列表特有）。
  final String college;
  final String className;

  final String gameName;
  final CompetitionType type;

  /// 公示时间（`yyyy-MM-dd`，官网原文）。
  final String time;

  const CompetitionPublicity({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.college,
    required this.className,
    required this.gameName,
    required this.type,
    required this.time,
  });
}

/// 竞赛获奖等级（`【省赛】二等奖` 拆成级别 + 奖项）。
///
/// **公示列表没有等级列**（`gs_list.html` 只有学号 / 姓名 / 学院 / 班级 / 比赛名称 /
/// 类型 / 时间），等级只能从该行详情页取（见 `competitionAwardLevelOf`）：
/// - `level` = 赛别，来自「学生提交的奖项」的 `【…】` 前缀（校赛 / 省赛 / 国赛 …）；
/// - `award` = 奖项名（一等奖 / 二等奖 / 参与未获奖 …），已去掉官网附带的 `(2)分` 分值。
class CompetitionAwardLevel {
  final String level;
  final String award;

  const CompetitionAwardLevel({this.level = '', this.award = ''});

  static const CompetitionAwardLevel empty = CompetitionAwardLevel();

  bool get isEmpty => level.isEmpty && award.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 展示文案：`省赛 · 二等奖`；只有一段时只显示那一段。
  String get label => [level, award].where((s) => s.isNotEmpty).join(' · ');

  /// 解析官网原文：`【省赛】二等奖` / `【校赛】参与未获奖` / `特等奖(2)分` / `无`。
  factory CompetitionAwardLevel.parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return empty;
    var level = '';
    final bracket = RegExp(r'^[【\[]([^】\]]*)[】\]]').firstMatch(text);
    if (bracket != null) {
      level = (bracket.group(1) ?? '').trim();
      text = text.substring(bracket.end).trim();
    }
    // 官网在奖项后附带分值：`一等奖(2)分` / `参与未获奖(0.5)分`。
    text = text.replaceAll(RegExp(r'[（(]\s*[\d.]+\s*[)）]\s*分?$'), '').trim();
    if (level == '无' || level == '无奖项') level = '';
    if (text == '无' || text == '无奖项' || text == '暂无') text = '';
    if (level.isEmpty && text.isEmpty) return empty;
    return CompetitionAwardLevel(level: level, award: text);
  }

  @override
  bool operator ==(Object other) =>
      other is CompetitionAwardLevel &&
      other.level == level &&
      other.award == award;

  @override
  int get hashCode => Object.hash(level, award);

  @override
  String toString() => 'CompetitionAwardLevel($label)';
}

/// 比赛目录里的一条比赛（`find_game.do` 的一行）。
class CompetitionGame {
  final int id;

  final String year;
  final String name;

  /// 赛别（`国赛` / `省赛` / `校赛` …，来自行内 `data-level`）。
  final String level;

  /// 校内对接单位。
  final String college;

  /// 比赛时间（官网原文，可能只有年份）。
  final String time;

  /// 比赛网址（可能为空）。
  final String url;

  const CompetitionGame({
    required this.id,
    required this.year,
    required this.name,
    required this.level,
    required this.college,
    required this.time,
    required this.url,
  });

  /// 提交申请时用的奖项前缀，如 `【国赛】`。官网把赛别拼在奖项名前面。
  String get awardPrefix => level.isEmpty ? '' : '【$level】';
}

/// 某个比赛可选的奖项（`getCredit.do?gameId=` 的 JSON 一行）。
class CompetitionAward {
  final int gameId;
  final String name;

  /// 该项分值（官网 `score`，用于给用户一个参考）。
  final double score;

  const CompetitionAward({
    required this.gameId,
    required this.name,
    required this.score,
  });

  /// 提交给官网的 `remark` 值：`【赛别】奖项名`（与官网 JS 拼法一致）。
  String remarkFor(CompetitionGame game) => '${game.awardPrefix}$name';
}

/// 团队申请可选的成员（`find_student.do` 的一行）。
///
/// ⚠ **两个 id 不是一回事**（官网实测）：
/// - [rowId] = 行内 radio 的 `value`，官网 `setGame()` 就是把它当 `student_id`
///   传出去、再 `join(';')` 成 `team` 字段 —— **提交必须用这个**；
/// - [studentId] = 「学号」列（`0000000` 这种），只用于展示与搜索。
class CompetitionStudent {
  /// 官网内部成员 id（radio value），进 `team` 字段。
  final int rowId;

  /// 学号（列表第 2 列）。
  final String studentId;

  final String name;
  final String college;
  final String className;

  const CompetitionStudent({
    required this.rowId,
    required this.studentId,
    required this.name,
    required this.college,
    required this.className,
  });

  /// 提交 `team` 时用的值（官网内部 id）。
  String get teamValue => '$rowId';
}

/// 详情页（申请 `detail.html` / 公示 `xd_detail.html`）的一个只读字段。
class CompetitionDetailField {
  final String label;
  final String value;

  const CompetitionDetailField({required this.label, required this.value});
}

/// 详情页内容：只读字段表 + 证书附件地址。
class CompetitionDetail {
  final List<CompetitionDetailField> fields;

  /// 证书图片地址（官网附件按钮的 `openImg_lx('<url>')`）。
  final List<String> attachments;

  const CompetitionDetail({required this.fields, this.attachments = const []});

  static const CompetitionDetail empty = CompetitionDetail(fields: []);

  bool get isEmpty => fields.isEmpty && attachments.isEmpty;

  /// 按标题取字段值；不存在返回空串。
  String valueOf(String label) {
    for (final f in fields) {
      if (f.label == label) return f.value;
    }
    return '';
  }
}

/// 一页服务端列表（官网分页是服务端渲染的 `pageNumber`）。
class CompetitionPage<T> {
  final List<T> items;

  /// 当前页（从 1 开始）。
  final int page;

  /// 总页数（官网分页条里最大的 `$.pageSkip(N)`；解析不到按 1 页）。
  final int totalPages;

  const CompetitionPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  /// 空页（无数据 / 未登录时不至于崩）。
  static CompetitionPage<T> empty<T>() =>
      CompetitionPage<T>(items: const [], page: 1, totalPages: 1);

  bool get hasPrevious => page > 1;
  bool get hasNext => page < totalPages;
}

/// 官方「最终获得奖项」下拉里的一档 = **该赛别的分值标准**。
///
/// 官网把分值写在选项文案里（`三等奖(2)分`、旧版还带赛别前缀 `【国赛】三等奖(5)分`），
/// 这就是第二课堂加分口径。[label] 已归一（去掉 `【赛别】` 前缀与 `(N)分` 后缀）。
///
/// ⚠ 首项是「尚未评定」的占位（现行版 `无`、旧版 `请设置奖项`）→ [selectable] 为 false，
/// 列表展示时必须滤掉（见 `CompetitionApplyAward.tiers`）。
class CompetitionAwardOption {
  /// 归一后的奖项名（`三等奖` / `参与未获奖` / `无`）。
  final String label;

  /// 该档分值（占位项为 0）。
  final double score;

  /// 官网已选定它（= 这条记录已评定为该奖项）。
  final bool selected;

  const CompetitionAwardOption({
    required this.label,
    required this.score,
    this.selected = false,
  });

  /// 是否是一档真奖项（占位项 `无` / `请设置奖项`、以及 0 分项都不是）。
  bool get selectable =>
      score > 0 && label.isNotEmpty && label != '无' && label != '请设置奖项';

  /// 文案是否就是这一档（`二等奖` ↔ `二等奖`；允许一边含另一边，防官网措辞微调）。
  bool matches(String award) {
    final a = competitionAwardKey(award);
    final l = competitionAwardKey(label);
    if (a.isEmpty || l.isEmpty) return false;
    return a == l || a.contains(l) || l.contains(a);
  }

  @override
  bool operator ==(Object other) =>
      other is CompetitionAwardOption &&
      other.label == label &&
      other.score == score &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(label, score, selected);

  @override
  String toString() => 'CompetitionAwardOption($label=$score${selected ? '* ' : ''})';
}

/// 奖项文案归一：去 `【赛别】` 前缀、去 `(N)分` 后缀、去全部空白。
///
/// ⚠ `(N)分` 与 `【…】` 都要去掉才能让「学生提交的奖项」与分值表的档位名对上：
/// 提交值形如 `【国赛】三等奖`，而分值表在不同版本里写作 `三等奖(5)分` 或
/// `【国赛】三等奖(5)分`（实测 2026-09-18）。
String competitionAwardKey(String text) => text
    .replaceAll(RegExp(r'^[【\[][^】\]]*[】\]]'), '')
    .replaceAll(RegExp(r'[（(]\s*[\d.]+\s*[)）]\s*分?'), '')
    .replaceAll(RegExp(r'\s+'), '')
    .trim();

/// 一条学科竞赛记录的加分信息（`xd_detail.html`）。
///
/// 用户 2026-09-18 原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」。
///
/// ⚠ 官网「我的申请」列表（`apply_list.html`）**没有奖项列、也没有分值列**（10 列 = 序号 /
/// 比赛年份 / 学号 / 姓名 / 比赛名称 / 类型 / 申请时间 / 附件 / 审批状态 / 操作），
/// 申请详情端点 `detail.html` 自 2026-09-18 起对全部记录返回「出错了」页 —— 能拿到加分
/// 的只有 `xd_detail.html`（**同一个 id** 即可，见
/// `CompetitionRemoteDataSource.fetchApplyAward`）：
/// - `学生提交的奖项`（`input[readonly]`）= `【赛别】奖项名`，**每条都有**；
/// - `最终获得奖项`（`select[disabled]`）= 该赛别的**完整分值表**，评定后写下 `selected`；
/// - `个人得分`（`input[readonly]`）= 评定后的实得分（未评定为 `0分`；**团队记录没有这一项**）。
class CompetitionApplyAward {
  /// 你申报的奖项（带赛别，如 `国赛 · 三等奖`）。
  final CompetitionAwardLevel submitted;

  /// 最终获得奖项（评定后才有；赛别沿用 [submitted] 的前缀）。
  final CompetitionAwardLevel granted;

  /// 按该赛别分值表算出的**申报奖项**分值（认不出 → null）。
  final double? submittedScore;

  /// 最终获得奖项的分值（评定后才有）。
  final double? grantedScore;

  /// 官网「个人得分」（未评定为 0；团队记录为 null）。
  final double? personalScore;

  /// 该赛别的分值表（含占位项，展示时用 [tiers]）。
  final List<CompetitionAwardOption> options;

  const CompetitionApplyAward({
    this.submitted = CompetitionAwardLevel.empty,
    this.granted = CompetitionAwardLevel.empty,
    this.submittedScore,
    this.grantedScore,
    this.personalScore,
    this.options = const [],
  });

  /// 什么都没解析到（详情拉失败 / 结构变化）→ 页面不显示胶囊。
  static const CompetitionApplyAward empty = CompetitionApplyAward();

  bool get hasData =>
      submitted.isNotEmpty || granted.isNotEmpty || options.isNotEmpty;

  /// 是否已评定（个人得分 > 0，或官网已选定最终奖项）。
  bool get scored => (personalScore ?? 0) > 0 || grantedScore != null;

  /// **这一项的加分**：个人得分（> 0）→ 最终获得奖项分值 → 申报奖项按标准的分值。
  double? get score {
    final personal = personalScore;
    if (personal != null && personal > 0) return personal;
    return grantedScore ?? submittedScore;
  }

  /// 分值表里的真档位（滤掉「无」/「请设置奖项」，保持官网顺序）。
  List<CompetitionAwardOption> get tiers =>
      options.where((o) => o.selectable).toList(growable: false);

  /// 展示用的奖项（已评定看最终奖项，否则看你申报的）。
  CompetitionAwardLevel get displayAward =>
      granted.isNotEmpty ? granted : submitted;

  @override
  String toString() =>
      'CompetitionApplyAward(${displayAward.label} score=$score '
      'tiers=${tiers.length}${scored ? ' 已评定' : ''})';
}

/// 待上传的证书图片（取自相册 / 文件选择器）。
class CompetitionAttachment {
  final String fileName;
  final Uint8List bytes;

  /// MIME 类型（`image/jpeg` 等），随文件名一起送给官网。
  final String? mimeType;

  const CompetitionAttachment({
    required this.fileName,
    required this.bytes,
    this.mimeType,
  });

  int get sizeInBytes => bytes.length;
}
