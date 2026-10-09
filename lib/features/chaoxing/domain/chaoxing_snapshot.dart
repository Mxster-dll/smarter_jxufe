/// 学习通一次取数的快照（课程 + 作业 + 通知）—— 缓存与界面共用的唯一模型。
///
/// **刻意扁平**：作业是「34 门课 × 各若干条」的扁平列表（带 `courseId`/`courseName`），
/// 不套「课 → 作业」两层。因为界面主要按**截止时间**排（待做在前），
/// 按课分组只是另一种视图，两种都能从扁平表派生；反过来嵌套了再拍平就丢信息。
library;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

/// 一次取数的结果。
class ChaoxingSnapshot {
  const ChaoxingSnapshot({
    this.courses = const [],
    this.works = const [],
    this.signs = const [],
    this.notices = const [],
    this.fetchedAt,
    this.failedCourseKeys = const [],
    this.failedSignCourseKeys = const [],
    this.pendingCourseKeys = const [],
    this.skippedCourseKeys = const [],
    this.throttled = false,
    this.noticesAvailable = true,
  });

  /// 全部课程（顺序 = 「学生端」页面顺序）。
  final List<ChaoxingCourse> courses;

  /// 全部作业（**扁平**，跨课程）。
  final List<ChaoxingWork> works;

  /// 全部签到活动（**扁平**，跨课程；只含 `activeType == 2` 的签到）。
  ///
  /// ⚠ `status` 默认是「未查」而不是「未签」：清单接口不给我自己的状态
  /// （见 `chaoxing_sign.dart`），只有 `statusLoaded == true` 的那几条才有结论。
  final List<ChaoxingSign> signs;

  /// 最近通知（实测一次 20 条，最新在前）。
  final List<ChaoxingNotice> notices;

  /// 取数完成时刻（界面显示「更新于 HH:mm:ss」）。
  final DateTime? fetchedAt;

  /// 扫描失败的课程键（`<courseId>/<classId>`）—— 如实展示，不要静默当成「没作业」。
  final List<String> failedCourseKeys;

  /// **签到清单**扫描失败的课程键（与 [failedCourseKeys] 分开记）。
  ///
  /// 签到与作业是同一批课程上的两个请求，可能一个成一个败（实测存在），
  /// 合成一句话说会把「作业拿到了但签到没拿到」说成整门课失败。
  final List<String> failedSignCourseKeys;

  /// **本轮没扫到**的课程键（分批轮转：下一轮从这里接着扫）。
  ///
  /// ⚠ 与 [failedCourseKeys] 分开：这个是「还没轮到、数据用的是上一次的」，
  /// 那个是「扫了但失败」。界面都要如实说，否则用户分不清「没作业」与「没扫」。
  final List<String> pendingCourseKeys;

  /// **本轮压根不扫**的课程键（非当下学期 —— 见 `chaoxing_scan.dart`）。
  ///
  /// ⚠ 与 [pendingCourseKeys] 分开：那个是「排上了但这一轮没跑到（下次会扫）」，
  /// 这个是「**不在扫描范围内**（下次也不会扫）」。合成一句话说会骗人。
  final List<String> skippedCourseKeys;

  /// 本轮是否**撞上学习通限流**（验证码页）—— 撞了就用上次数据兜底。
  final bool throttled;

  /// 通知是否取到（收件箱 token 缺失 / 接口异常时为 false）。
  final bool noticesAvailable;

  /// 空快照（尚未取过数）。
  static const ChaoxingSnapshot empty = ChaoxingSnapshot();

  /// 还没交的作业（待做），按截止时间升序；无截止时间的排在最后。
  List<ChaoxingWork> get openWorks {
    final list = [for (final w in works) if (w.status.isOpen) w];
    list.sort(_byDueAsc);
    return list;
  }

  /// 已批阅完成的作业，按截止时间倒序（最近的在前）。
  List<ChaoxingWork> get finishedWorks {
    final list = [for (final w in works) if (w.status == ChaoxingWorkStatus.done) w];
    list.sort((a, b) => _byDueAsc(b, a));
    return list;
  }

  /// 待做作业条数。
  int get todoCount => openWorks.length;

  /// 进行中的签到（按开始时间倒序）—— 用户最关心的「现在要不要签」。
  List<ChaoxingSign> openSignsAt(DateTime now) {
    final list = [for (final s in signs) if (s.isOpenAt(now)) s];
    list.sort((a, b) {
      final da = a.startAt, db = b.startAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  /// 某一门课的签到（开始时间倒序）。
  List<ChaoxingSign> signsOfCourse(String courseId) =>
      [for (final s in signs) if (s.courseId == courseId) s];

  /// 按课程分组的签到（保持 [signs] 的顺序：课程内已是时间倒序）。
  Map<String, List<ChaoxingSign>> signsByCourse() {
    final out = <String, List<ChaoxingSign>>{};
    for (final s in signs) {
      out.putIfAbsent(s.courseId, () => <ChaoxingSign>[]).add(s);
    }
    return out;
  }

  /// **已确认**「签上了」的次数（未查状态的不算 —— 别把「没查」说成「签了」）。
  int get signedSignCount =>
      signs.where((s) => s.statusLoaded && s.status.isSigned).length;

  /// **已确认**「没签上」的次数（未签 / 缺勤 / 已过期）。
  int get absentSignCount =>
      signs.where((s) => s.statusLoaded && s.status.isAbsent).length;

  /// 状态还没查过的条数（界面据此提示「可补全状态」）。
  int get unknownSignStatusCount =>
      signs.where((s) => !s.statusLoaded).length;

  /// 这门课的签到清单本轮没取到（数据用的是上一次的）。
  bool isSignCourseFailed(String courseKey) =>
      failedSignCourseKeys.contains(courseKey);

  /// 未读通知条数。
  int get unreadNoticeCount =>
      notices.where((n) => !n.read).length;

  /// 有没有任何数据（用于「首次进入且还没取过数」的判断）。
  bool get isEmpty =>
      courses.isEmpty && works.isEmpty && notices.isEmpty && fetchedAt == null;

  /// 快照里的课程键集合（界面按课筛作业时用）。
  Set<String> get courseKeys => {for (final c in courses) c.key};

  /// 这门课**本轮没扫到**（分批轮转的窗口外，或撞风控后收手）—— 数据是上一次的。
  bool isCoursePending(String courseKey) => pendingCourseKeys.contains(courseKey);

  /// 这门课**本轮扫描失败** —— 数据是上一次的。
  bool isCourseFailed(String courseKey) => failedCourseKeys.contains(courseKey);

  /// 这门课**不在扫描范围内**（非当下学期，只扫当下学期）。
  bool isCourseSkipped(String courseKey) => skippedCourseKeys.contains(courseKey);

  /// 本轮**没能确认作业清单**的课程键（未扫到 + 失败，去重）。
  ///
  /// 界面用它说「可能有遗漏」：这类课的作业数**可能是 0 但并不代表没有作业**。
  Set<String> get unscannedCourseKeys => {
    ...pendingCourseKeys,
    ...failedCourseKeys,
  };

  /// 本轮没能确认的课程门数。
  int get unscannedCourseCount => unscannedCourseKeys.length;

  Map<String, dynamic> toJson() => {
    'courses': [for (final c in courses) c.toJson()],
    'works': [for (final w in works) w.toJson()],
    'signs': [for (final s in signs) s.toJson()],
    'notices': [for (final n in notices) n.toJson()],
    'fetchedAt': fetchedAt?.toIso8601String(),
    'failedCourseKeys': failedCourseKeys,
    'failedSignCourseKeys': failedSignCourseKeys,
    'pendingCourseKeys': pendingCourseKeys,
    'skippedCourseKeys': skippedCourseKeys,
    'throttled': throttled,
    'noticesAvailable': noticesAvailable,
  };

  /// 容错解析：任何一层脏数据都只丢那一条，不整表失败。
  factory ChaoxingSnapshot.fromJson(Map<String, dynamic> json) => ChaoxingSnapshot(
    courses: _list(json['courses'], (m) => ChaoxingCourse.fromJson(m)),
    works: _list(json['works'], (m) => ChaoxingWork.fromJson(m)),
    signs: _list(json['signs'], (m) => ChaoxingSign.fromJson(m)),
    notices: _list(json['notices'], (m) => ChaoxingNotice.fromJson(m)),
    fetchedAt: _date(json['fetchedAt']),
    failedCourseKeys: _keys(json['failedCourseKeys']),
    failedSignCourseKeys: _keys(json['failedSignCourseKeys']),
    pendingCourseKeys: _keys(json['pendingCourseKeys']),
    skippedCourseKeys: _keys(json['skippedCourseKeys']),
    throttled: json['throttled'] == true,
    noticesAvailable: json['noticesAvailable'] != false,
  );

  static List<String> _keys(Object? raw) => [
    for (final v in (raw as List<dynamic>? ?? const [])) v.toString(),
  ];

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) build) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        out.add(build(item.map((k, v) => MapEntry(k.toString(), v))));
      } catch (_) {
        // 单条坏数据丢掉即可，别让整个缓存读不回来。
      }
    }
    return out;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// 复制一份并替换部分字段（刷新时保留旧字段用）。
  ChaoxingSnapshot copyWith({
    List<ChaoxingCourse>? courses,
    List<ChaoxingWork>? works,
    List<ChaoxingSign>? signs,
    List<ChaoxingNotice>? notices,
    DateTime? fetchedAt,
    List<String>? failedCourseKeys,
    List<String>? failedSignCourseKeys,
    List<String>? pendingCourseKeys,
    List<String>? skippedCourseKeys,
    bool? throttled,
    bool? noticesAvailable,
  }) => ChaoxingSnapshot(
    courses: courses ?? this.courses,
    works: works ?? this.works,
    signs: signs ?? this.signs,
    notices: notices ?? this.notices,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    failedCourseKeys: failedCourseKeys ?? this.failedCourseKeys,
    failedSignCourseKeys: failedSignCourseKeys ?? this.failedSignCourseKeys,
    pendingCourseKeys: pendingCourseKeys ?? this.pendingCourseKeys,
    skippedCourseKeys: skippedCourseKeys ?? this.skippedCourseKeys,
    throttled: throttled ?? this.throttled,
    noticesAvailable: noticesAvailable ?? this.noticesAvailable,
  );
}

/// 截止时间升序；`null` 视为「很晚」（排在最后）。[flip] 为真时倒序。
int _byDueAsc(ChaoxingWork a, ChaoxingWork b, [bool flip = false]) {
  final da = a.dueAt;
  final db = b.dueAt;
  int r;
  if (da == null && db == null) {
    r = a.title.compareTo(b.title);
  } else if (da == null) {
    r = 1;
  } else if (db == null) {
    r = -1;
  } else {
    r = da.compareTo(db);
  }
  return flip ? -r : r;
}
