/// 学习通（超星）作业 —— 课程「作业」页里的一条。
///
/// 来源：`GET https://mooc1.chaoxing.com/mooc-ans/work/getAllWork?<每课签名>`
/// （**HTML**，不是 JSON），条目 DOM 实测（2026-09-19）：
///
/// ```html
/// <li style="padding:30px 0">
///   <div class="titTxt" data="0">
///     <p class="clearfix">
///       <a class="inspectTask" data="55739815" data2="0" data3="0"
///          title="9月20日24:00前提交作业">9月20日24:00前提交作…</a>
///       <i id="reddot55739815" …></i>
///     </p>
///     <span class="pt5"><span class="fl">开始时间：</span>2026-09-17 14:28</span>
///     <span class="pt5"><span class="fl">截止时间：</span>2026-09-20 23:59</span>
///     <span class="pt5"><span class="fl">作业状态：</span><strong> 待做 </strong></span>
///   </div>
///   <div class="titOper"><span …>90分</span>…</div>
/// </li>
/// ```
library;

/// 作业状态（页面上的 `作业状态：` 后面那个 `<strong>`）。
enum ChaoxingWorkStatus {
  /// 未提交、可做。
  todo('待做'),

  /// 已提交、等老师批阅。
  pendingReview('待批阅'),

  /// 已批阅完成（此时带分数）。
  done('已完成'),

  /// 认不出的新状态（页面改版时兜底，**不要**当成待做）。
  unknown('');

  const ChaoxingWorkStatus(this.label);

  /// 页面上的原文。
  final String label;

  /// 是否「还没交」（列表里要标红/排前）。
  bool get isOpen => this == ChaoxingWorkStatus.todo;

  /// 原文 → 枚举；认不出返回 [unknown]。
  static ChaoxingWorkStatus fromLabel(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), '');
    for (final s in ChaoxingWorkStatus.values) {
      if (s != unknown && s.label == t) return s;
    }
    return unknown;
  }
}

/// 一条作业。
class ChaoxingWork {
  const ChaoxingWork({
    required this.workId,
    required this.title,
    required this.courseId,
    required this.courseName,
    this.startAt,
    this.dueAt,
    this.status = ChaoxingWorkStatus.unknown,
    this.score,
  });

  /// 作业 id（条目里 `<a class="inspectTask" data="…">`）。
  final String workId;

  /// 作业标题（`<a>` 的 `title`，兜底用它的文本）。
  final String title;

  /// 所属课程（解析时由调用方回填）。
  final String courseId;
  final String courseName;

  /// 开始时间 / 截止时间（页面给的是 `yyyy-MM-dd HH:mm`，本地时区）。
  final DateTime? startAt;
  final DateTime? dueAt;

  final ChaoxingWorkStatus status;

  /// 分数（仅 [ChaoxingWorkStatus.done] 时页面上有，形如 `90分`）。
  final double? score;

  /// 稳定键：同课内 `workId` 唯一。
  String get key => '$courseId/$workId';

  /// 在给定时刻是否已过期（只有「待做」才谈得上过期）。
  bool isOverdueAt(DateTime now) =>
      status == ChaoxingWorkStatus.todo && dueAt != null && now.isAfter(dueAt!);

  /// 距截止还有多久；无截止时间返回 null（负数 = 已过期）。
  Duration? remainingAt(DateTime now) => dueAt?.difference(now);

  Map<String, dynamic> toJson() => {
    'workId': workId,
    'title': title,
    'courseId': courseId,
    'courseName': courseName,
    'startAt': startAt?.toIso8601String(),
    'dueAt': dueAt?.toIso8601String(),
    'status': status.name,
    'score': score,
  };

  /// 容错解析：脏字段一律回落（状态认不出 → [ChaoxingWorkStatus.unknown]）。
  factory ChaoxingWork.fromJson(Map<String, dynamic> json) => ChaoxingWork(
    workId: _str(json['workId']),
    title: _str(json['title']),
    courseId: _str(json['courseId']),
    courseName: _str(json['courseName']),
    startAt: _date(json['startAt']),
    dueAt: _date(json['dueAt']),
    status: _status(json['status']),
    score: _num(json['score']),
  );

  static String _str(Object? value) => value == null ? '' : value.toString().trim();

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static ChaoxingWorkStatus _status(Object? value) {
    final name = value?.toString() ?? '';
    for (final s in ChaoxingWorkStatus.values) {
      if (s.name == name) return s;
    }
    return ChaoxingWorkStatus.unknown;
  }

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    final t = value?.toString().trim() ?? '';
    return t.isEmpty ? null : double.tryParse(t);
  }

  @override
  String toString() =>
      'ChaoxingWork($key, $title, ${status.name}, due=$dueAt, score=$score)';
}
