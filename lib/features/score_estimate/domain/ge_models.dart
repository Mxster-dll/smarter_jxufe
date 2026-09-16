/// 分数估计 · 领域模型。
///
/// 模型约定（与教师口径一致）：
/// - 一门课：平时分占比 + 期末占比（两档合计 100%）；总评按
///   平时均分（百分制）× 平时占比 + 期末分 × 期末占比 折算。
/// - 平时分由若干「分项」组成，每个分项设「分值上限」（分值相加即
///   平时满分，如平时 30 分 = 考勤 5 + 作业 15 + 表现 10）。
/// - 每个分项按「计数」或「直接分数」折算得分（得分率封顶 100%）：
///   得分 = 得分率 × 分值上限。计分方式三种：
///     [GePartMode.up]    正计数：从 0 起累计已完成事件（如打卡 12/20）；
///     [GePartMode.down]  负计数：以目标总事件数为满分向下计数（如全学期
///                        共 16 次课，每缺勤一次 −1，剩 13 次 → 13/16）；
///     [GePartMode.score] 直接分数：老师直接给分，填「该项满分 + 实际得分」
///                        （如 期中 85/100 → 得分率 85%），
///                        满分填成与分值上限相同即为「直接填得分」。
library;

import 'ge_deadline.dart';
import 'ge_memo.dart';

/// 分项计分方式。
enum GePartMode { up, down, score }

/// 计分方式中文标签。
String gePartModeLabel(GePartMode mode) => switch (mode) {
  GePartMode.up => '正计数',
  GePartMode.down => '负计数',
  GePartMode.score => '直接分数',
};

/// 计分方式一句话说明（编辑弹窗与提示卡复用）。
String gePartModeHint(GePartMode mode) => switch (mode) {
  GePartMode.up => '从 0 向上累计已完成次数，如打卡 12/20 → 12/20。',
  GePartMode.down => '以总次数为满分向下计数，每次扣减（如缺勤）−1，如全学期 16 次课已缺 3 次 → 剩 13/16。',
  GePartMode.score =>
    '老师直接给分：填「该项满分」与「实际得分」（如 85 / 100），得分率 = 得分 ÷ 满分；满分与分值上限填成一样时，就是直接填得分。',
};

/// 平时分的一个计分分项。
class GePart {
  final String id;

  /// 名称，如「考勤」「作业提交」。
  final String name;

  /// 计分方式：正计数（从 0 累计）/ 负计数（从目标总数向下扣）/ 直接分数（老师给分）。
  final GePartMode mode;

  /// 目标值，须 ≥ 1：
  /// 正计数 = 应完成次数；负计数 = 总事件数（如总课次）；
  /// 直接分数 = **该项满分**（如 100 分制填 100；与分值上限相同即「直接填得分」）。
  final int target;

  /// 当前计数：
  /// 正计数 = 已完成次数（允许超过目标，得分仍封顶）；
  /// 负计数 = 剩余次数（满分为 [target]；engine 按剩余/target 计得分，下限 0）；
  /// 直接分数 = 不使用。
  final int current;

  /// 直接分数模式下的**实际得分**（其余模式为 0）；
  /// 得分率 = clamp(得分 / [target], 0, 1)，可填小数（如 85.5）。
  final double score;

  /// 该分项在平时分内的分值上限（平时满分 = 各分项分值之和）。
  final double cap;

  /// 备注（可选），如「每周四上课」。
  final String note;

  const GePart({
    required this.id,
    required this.name,
    this.mode = GePartMode.up,
    this.target = 1,
    this.current = 0,
    this.score = 0,
    this.cap = 0,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'target': target,
    'current': current,
    'score': score,
    'cap': cap,
    'note': note,
  };

  factory GePart.fromJson(Map<String, dynamic> json) {
    final target = (json['target'] as num?)?.toInt() ?? 1;
    return GePart(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mode: GePartMode.values.asNameMap()[json['mode']] ?? GePartMode.up,
      target: target < 1 ? 1 : target,
      current: ((json['current'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      // 旧数据无 score 字段 → 0（不影响计数型分项）。
      score: ((json['score'] as num?)?.toDouble() ?? 0).clamp(0.0, 1e6),
      cap: ((json['cap'] as num?)?.toDouble() ?? 0).clamp(0.0, 1e6),
      note: json['note'] as String? ?? '',
    );
  }

  GePart copyWith({
    String? id,
    String? name,
    GePartMode? mode,
    int? target,
    int? current,
    double? score,
    double? cap,
    String? note,
  }) => GePart(
    id: id ?? this.id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    target: target ?? this.target,
    current: current ?? this.current,
    score: score ?? this.score,
    cap: cap ?? this.cap,
    note: note ?? this.note,
  );
}

/// 一门可独立估算的课程。
class GeCourse {
  final String id;

  /// 课程名，如「高等数学（上）」。
  final String name;

  /// 课程代码（教务课程号，如 1004704393）；课表导入自动带入，手工添加可留空。
  /// 培养方案学分回填优先按课程代码匹配，其次按课程名。
  final String courseCode;

  /// 平时分占比（%），0~100；期末占比 = 100 − 平时占比。默认 30%。
  final double dailyPercent;

  /// 学分（学分加权平均用）：课表导入自动带入，手工添加默认 1。
  final double credits;

  /// 平时分分项（顺序即展示顺序）。
  final List<GePart> parts;

  /// 期末成绩（百分制预估/实得，null = 未出分/未填）。
  final double? finalScore;

  /// 备注（可选），如授课教师。
  final String note;

  /// 课程备忘录（自由文字 + 图片文件名列表），见 [GeMemo]。
  ///
  /// 图片本体在应用私有目录（`ge_memos/<账号>/<课程 id>/`），这里只存文件名。
  final GeMemo memo;

  /// 课程截止日期（网课 / 作业 / 考试），见 [GeDeadline]。
  ///
  /// 只属于本课程；提醒排期走 `data/ge_deadline_reminders.dart`。
  final List<GeDeadline> deadlines;

  /// 创建时间（epoch ms），列表排序用。
  final int createdAt;

  const GeCourse({
    required this.id,
    required this.name,
    this.courseCode = '',
    this.dailyPercent = 30,
    this.credits = 1,
    this.parts = const [],
    this.finalScore,
    this.note = '',
    this.memo = GeMemo.empty,
    this.deadlines = const [],
    this.createdAt = 0,
  });

  /// 期末占比（%）。
  double get finalPercent => 100 - dailyPercent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'courseCode': courseCode,
    'dailyPercent': dailyPercent,
    'credits': credits,
    'parts': [for (final p in parts) p.toJson()],
    'finalScore': finalScore,
    'note': note,
    'memo': memo.toJson(),
    'deadlines': [for (final d in deadlines) d.toJson()],
    'createdAt': createdAt,
  };

  factory GeCourse.fromJson(Map<String, dynamic> json) {
    final dp = (json['dailyPercent'] as num?)?.toDouble();
    final cr = (json['credits'] as num?)?.toDouble();
    return GeCourse(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      dailyPercent: (dp == null ? 30 : dp.clamp(0.0, 100.0)),
      // 旧数据无 credits 字段 → 默认 1 学分。
      credits: (cr == null ? 1 : cr.clamp(0.0, 100.0)),
      parts: [
        for (final p in (json['parts'] as List?) ?? const [])
          if (p is Map<String, dynamic>) GePart.fromJson(p),
      ],
      finalScore: (json['finalScore'] as num?)?.toDouble(),
      note: json['note'] as String? ?? '',
      // 旧数据没有 memo 字段 → 空备忘录（容错在 GeMemo.fromJson 里）。
      memo: GeMemo.fromJson(json['memo']),
      // 旧数据没有 deadlines 字段 → 空列表（脏项在 geDeadlinesFromJson 里被跳过）。
      deadlines: geDeadlinesFromJson(json['deadlines']),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  GeCourse copyWith({
    String? id,
    String? name,
    String? courseCode,
    double? dailyPercent,
    double? credits,
    List<GePart>? parts,
    double? finalScore,
    String? note,
    GeMemo? memo,
    List<GeDeadline>? deadlines,
    int? createdAt,
    bool clearFinalScore = false,
  }) => GeCourse(
    id: id ?? this.id,
    name: name ?? this.name,
    courseCode: courseCode ?? this.courseCode,
    dailyPercent: dailyPercent ?? this.dailyPercent,
    credits: credits ?? this.credits,
    parts: parts ?? this.parts,
    finalScore: clearFinalScore ? null : (finalScore ?? this.finalScore),
    note: note ?? this.note,
    memo: memo ?? this.memo,
    deadlines: deadlines ?? this.deadlines,
    createdAt: createdAt ?? this.createdAt,
  );
}
