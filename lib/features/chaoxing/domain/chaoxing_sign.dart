/// 学习通「签到」记录模型（只读）。
///
/// 口径来源（2026-10-09 真机实测，见 `reverse_engineering/学习通接口.md` §10）：
/// - **清单** = `POST mobilelearn.chaoxing.com/widget/pcpick/stu/activeList`
///   （form `courseId` / `classId` / `puid`）→ `data.startList`（进行中）+
///   `data.endList`（已结束），**1 个请求 / 门课**；
/// - **我的状态**只能逐活动再取一次详情页
///   （`GET …/widget/sign/pcStuSignController/preSign?activeId=…`，1 个请求 / 活动），
///   所以状态是**按需补全**的（[statusLoaded] 区分「查过了」与「还没查」）。
///
/// ⚠ 清单接口的 `userStatus` **恒为 null**（实测：加 `stuid` / `uid` / `studentId` /
/// `showUserStatus` 都不变；`/v2/apis/sign/*` 与 `/pptSign/*` 全部 500）——
/// 别再指望「一个请求带全部状态」。
library;

/// 一次签到活动的「我的状态」。
///
/// 码值字典出自站方 `util2.js`（`activeType == 2` 分支）：
/// `0 未签 / 1 已签 / 2 代签 / 4 请假 / 5 缺勤 / 7 病假 / 8 事假 / 9 迟到 / 10 早退 /
/// 11 签到已过期`。清单接口不给这个字段，只有详情页给**文案**，故两套解析都在这里。
enum ChaoxingSignStatus {
  unsigned('未签'),
  signed('已签'),
  proxy('代签'),
  leave('请假'),
  absent('缺勤'),
  sickLeave('病假'),
  personalLeave('事假'),
  late('迟到'),
  earlyLeave('早退'),
  expired('签到已过期'),

  /// 还没查过 / 查了但认不出（界面要说「状态未知」，别说成「未签」）。
  unknown('');

  const ChaoxingSignStatus(this.label);

  final String label;

  /// 计入「已签」的档（代签也算签到了）。
  bool get isSigned => this == signed || this == proxy;

  /// 计入「没签上」的档（未签 / 缺勤 / 已过期）。
  bool get isAbsent => this == unsigned || this == absent || this == expired;

  /// 状态是否已确认（[unknown] = 还没查或认不出）。
  bool get isKnown => this != unknown;

  /// 码值 → 状态（[code] 为 null / 认不出时给 [unknown]）。
  static ChaoxingSignStatus fromCode(Object? code) {
    final n = code is num ? code.toInt() : int.tryParse('${code ?? ''}');
    return switch (n) {
      0 => unsigned,
      1 => signed,
      2 => proxy,
      4 => leave,
      5 => absent,
      7 => sickLeave,
      8 => personalLeave,
      9 => late,
      10 => earlyLeave,
      11 => expired,
      _ => unknown,
    };
  }

  /// 详情页文案 → 状态（「签到成功」是实测真值；其余按同族措辞兜）。
  static ChaoxingSignStatus fromText(String text) {
    final t = text.trim();
    if (t.isEmpty) return unknown;
    // ⚠ 顺序要紧：「未签到」含子串「签到」，「签到已过期」含「签到」。
    for (final pair in const [
      ('未签', unsigned),
      ('缺勤', absent),
      ('签到已过期', expired),
      ('已过期', expired),
      ('迟到', late),
      ('早退', earlyLeave),
      ('病假', sickLeave),
      ('事假', personalLeave),
      ('请假', leave),
      ('代签', proxy),
      ('签到成功', signed),
      ('已签到', signed),
      ('已签', signed),
      ('签到', signed),
    ]) {
      if (t.contains(pair.$1)) return pair.$2;
    }
    return unknown;
  }
}

/// 签到活动的 `activeType`（站方常量：`2` = 签到；选人 / 抢答 / 投票等是别的值）。
const int chaoxingSignActiveType = 2;

/// 一次签到活动。
class ChaoxingSign {
  const ChaoxingSign({
    required this.activeId,
    required this.courseId,
    this.classId = '',
    this.courseName = '',
    this.typeName = '',
    this.startAt,
    this.endAt,
    this.attendCount = 0,
    this.status = ChaoxingSignStatus.unknown,
    this.signedAt,
    this.statusLoaded = false,
  });

  /// 活动 id（`activeId`，13 位数字）。
  final String activeId;

  final String courseId;

  /// 班级 id（清单里的 `clazzid`）—— 取详情（我的状态）时要原样带上。
  final String classId;

  final String courseName;

  /// 站方给的类型名（`二维码签到` / `手势签到` / `位置签到` / `拍照签到` …）。
  final String typeName;

  /// 活动开始 / 结束时刻（清单里的 `starttimeStr` / `endtimeStr`）。
  final DateTime? startAt;
  final DateTime? endAt;

  /// 参与人数（清单里的 `attendNum`，是**全班**的签到人数，不是我的）。
  final int attendCount;

  /// 我的状态（清单接口不给 → 默认 [ChaoxingSignStatus.unknown]）。
  final ChaoxingSignStatus status;

  /// 我的签到时刻（详情页 `#st`；只有签上了才有）。
  final DateTime? signedAt;

  /// 是否已经查过详情（[status] 可信；false 时状态未知 ≠ 未签）。
  final bool statusLoaded;

  /// 唯一键（跨课不会撞：`activeId` 本身全局唯一，带上 `courseId` 便于按课过滤）。
  String get key => '$courseId/$activeId';

  /// 这门课里这一次签到现在还在进行中。
  bool isOpenAt(DateTime now) {
    final end = endAt;
    if (end != null) return !now.isAfter(end);
    final start = startAt;
    return start != null && !now.isBefore(start);
  }

  /// 时长文案（`45 秒` / `8 分钟` / `1 小时 20 分`）。
  String? get durationText {
    final s = startAt, e = endAt;
    if (s == null || e == null) return null;
    final d = e.difference(s);
    if (d.inMinutes < 1) return '${d.inSeconds} 秒';
    if (d.inHours < 1) return '${d.inMinutes} 分钟';
    final rest = d.inMinutes % 60;
    return rest == 0 ? '${d.inHours} 小时' : '${d.inHours} 小时 $rest 分';
  }

  ChaoxingSign copyWith({
    String? courseName,
    String? typeName,
    DateTime? startAt,
    DateTime? endAt,
    int? attendCount,
    ChaoxingSignStatus? status,
    DateTime? signedAt,
    bool? statusLoaded,
  }) => ChaoxingSign(
    activeId: activeId,
    courseId: courseId,
    classId: classId,
    courseName: courseName ?? this.courseName,
    typeName: typeName ?? this.typeName,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    attendCount: attendCount ?? this.attendCount,
    status: status ?? this.status,
    signedAt: signedAt ?? this.signedAt,
    statusLoaded: statusLoaded ?? this.statusLoaded,
  );

  Map<String, dynamic> toJson() => {
    'activeId': activeId,
    'courseId': courseId,
    'classId': classId,
    'courseName': courseName,
    'typeName': typeName,
    'startAt': startAt?.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'attendCount': attendCount,
    'status': status.name,
    'signedAt': signedAt?.toIso8601String(),
    'statusLoaded': statusLoaded,
  };

  /// 容错解析（旧缓存没有的字段一律走默认值）。
  factory ChaoxingSign.fromJson(Map<String, dynamic> json) {
    final statusName = _str(json['status']);
    return ChaoxingSign(
      activeId: _str(json['activeId']),
      courseId: _str(json['courseId']),
      classId: _str(json['classId']),
      courseName: _str(json['courseName']),
      typeName: _str(json['typeName']),
      startAt: _date(json['startAt']),
      endAt: _date(json['endAt']),
      attendCount: _int(json['attendCount']),
      status: ChaoxingSignStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => ChaoxingSignStatus.unknown,
      ),
      signedAt: _date(json['signedAt']),
      statusLoaded: json['statusLoaded'] == true,
    );
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  static int _int(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }
}
