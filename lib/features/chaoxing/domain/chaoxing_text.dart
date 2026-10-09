/// 学习通展示层文案口径（纯函数，时钟可注入 —— 测试推得动）。
///
/// 全部集中在这里，页面里不许再各拼一套 `'还剩 $n 天'`：倒计时这类文案一旦分散，
/// 「今天截止」与「已过期 3 小时」两处口径迟早不一致。
library;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

/// 「今天 / 3 天内」的阈值（与截止日期管理同口径）。
const Duration chaoxingSoonWindow = Duration(days: 3);

/// 作业倒计时文案。
///
/// - 无截止时间 → `无截止时间`
/// - 已过期 → `已过期 3 小时` / `已过期 2 天`
/// - 当天 → `今天 23:59 截止`
/// - 次日 → `明天 23:59 截止`
/// - 3 天内 → `还剩 2 天 3 小时`
/// - 更远 → `9月20日 23:59 截止`
String chaoxingCountdownText(DateTime? dueAt, DateTime now) {
  if (dueAt == null) return '无截止时间';
  final diff = dueAt.difference(now);
  if (diff.isNegative) return '已过期 ${_span(-diff)}';
  if (_sameDay(dueAt, now)) return '今天 ${_hm(dueAt)} 截止';
  if (_sameDay(dueAt, now.add(const Duration(days: 1)))) {
    return '明天 ${_hm(dueAt)} 截止';
  }
  if (diff <= chaoxingSoonWindow) return '还剩 ${_span(diff)}';
  return '${dueAt.month}月${dueAt.day}日 ${_hm(dueAt)} 截止';
}

/// `2026-09-20 23:59` 形态（列表右侧的绝对时刻）。
String chaoxingDueText(DateTime? dueAt) =>
    dueAt == null ? '—' : '${dueAt.month}月${dueAt.day}日 ${_hm(dueAt)}';

/// 详情弹窗用的**完整绝对时刻**（`2026-09-20 23:59`）。
///
/// 与 [chaoxingTimeText] 分工：那个是列表里的相对口语（「今天 08:05」），
/// 详情里要的是不会被误读的绝对时间（开始时间可能是几个月前）。
String chaoxingMomentText(DateTime? at) {
  if (at == null) return '—';
  final m = at.month.toString().padLeft(2, '0');
  final d = at.day.toString().padLeft(2, '0');
  return '${at.year}-$m-$d ${_hm(at)}';
}

/// 通知时间：今天只给时刻，今年只给月日，跨年带年份。
String chaoxingTimeText(DateTime? at, DateTime now) {
  if (at == null) return '—';
  if (_sameDay(at, now)) return '今天 ${_hm(at)}';
  if (_sameDay(at, now.subtract(const Duration(days: 1)))) {
    return '昨天 ${_hm(at)}';
  }
  if (at.year == now.year) return '${at.month}月${at.day}日 ${_hm(at)}';
  return '${at.year}年${at.month}月${at.day}日';
}

/// 作业状态胶囊文案（已完成带分数）。
String chaoxingWorkStatusText(ChaoxingWork work) {
  if (work.status == ChaoxingWorkStatus.done && work.score != null) {
    return '已完成 ${_trimNum(work.score!)} 分';
  }
  if (work.status == ChaoxingWorkStatus.unknown) return '状态未知';
  return work.status.label;
}

/// 距截止还差多久（中文短文案，用于分组标题行）。
String chaoxingSpanText(Duration d) => _span(d);

/// 签到时间行：同一天给 `10-09 09:51 ~ 09:52`，跨天给 `09-30 23:00 ~ 10-01 00:20`。
///
/// 给不出时刻时返回 `—`（别拿空串拼出「  · 」这种残缺行）。
String chaoxingSignTimeText(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '—';
  if (start == null) return '截止 ${_mdhm(end!)}';
  final sameDay = end != null &&
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (end == null) return _mdhm(start);
  return '${_mdhm(start)} ~ ${sameDay ? _hm(end) : _mdhm(end)}';
}

/// 签到状态文案（`已签` / `未签` / `状态未知` …）。
///
/// ⚠ `statusLoaded == false` 时说「状态未知」而**不是**「未签」——清单接口不给我
/// 自己的状态（见 `chaoxing_sign.dart`），把「没查」说成「没签」就是骗人。
String chaoxingSignStatusText(ChaoxingSign sign) =>
    sign.statusLoaded ? sign.status.label : '状态未知';

/// 签到状态的补充说明（签上了给时刻：`10-09 09:51:58`）。
String chaoxingSignSignedAtText(ChaoxingSign sign) =>
    sign.signedAt == null ? '' : chaoxingMomentText(sign.signedAt);

/// 这次签到现在还在进行中吗（列表右侧的即时提示）。
String chaoxingSignOpenText(ChaoxingSign sign, DateTime now) =>
    sign.isOpenAt(now) ? '进行中' : '已结束';

/// 一门课的签到小结：`6 次签到 · 已签 5 · 未签 1`（只数**已确认**的状态）。
String chaoxingSignCourseSummary(List<ChaoxingSign> signs) {
  final signed = signs.where((s) => s.statusLoaded && s.status.isSigned).length;
  final absent = signs.where((s) => s.statusLoaded && s.status.isAbsent).length;
  final unknown = signs.where((s) => !s.statusLoaded).length;
  final parts = <String>[
    '${signs.length} 次签到',
    if (signed > 0) '已签 $signed',
    if (absent > 0) '未签 $absent',
    if (unknown > 0) '$unknown 条状态未查',
  ];
  return parts.join(' · ');
}

/// 全部签到的一句话小结（主页区块标题右侧用）。
String chaoxingSignSummary(ChaoxingSnapshot snapshot, DateTime now) {
  final open = snapshot.openSignsAt(now).length;
  final parts = <String>[
    if (open > 0) '进行中 $open',
    '共 ${snapshot.signs.length} 次',
    if (snapshot.signedSignCount > 0) '已签 ${snapshot.signedSignCount}',
    if (snapshot.absentSignCount > 0) '未签 ${snapshot.absentSignCount}',
  ];
  return parts.join(' · ');
}

/// 时间戳 → `10-09 09:51`（签到列表用的紧凑形态）。
String _mdhm(DateTime t) =>
    '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${_hm(t)}';

/// 按课程聚合作业：`课程键 → 该课作业`；顺序 = 课程顺序，无作业的课也保留空列表。
///
/// 认不出归属的作业（课程已从学习通侧消失）**直接丢掉** —— 页面按课展示，
/// 挂不上去的条目会变成幽灵行。
Map<String, List<ChaoxingWork>> chaoxingWorksByCourse(ChaoxingSnapshot snapshot) {
  final keyOfCourseId = <String, String>{
    for (final c in snapshot.courses) c.courseId: c.key,
  };
  final out = <String, List<ChaoxingWork>>{
    for (final c in snapshot.courses) c.key: <ChaoxingWork>[],
  };
  for (final w in snapshot.works) {
    final key = keyOfCourseId[w.courseId];
    if (key == null) continue;
    out[key]!.add(w);
  }
  for (final list in out.values) {
    list.sort(_byDue);
  }
  return out;
}

/// 从快照里按课程 id 取课程名；找不到返回空串。
///
/// 通知只带 `courseId`（`tag` 形如 `courseId266659194`），课程名得在这里查 ——
/// 查不到就**返回空串让调用方整行不画**，别回显裸 id（那是内部编号，用户看不懂）。
String chaoxingCourseNameOf(ChaoxingSnapshot? snapshot, String courseId) {
  if (snapshot == null || courseId.isEmpty) return '';
  for (final c in snapshot.courses) {
    if (c.courseId == courseId) return c.name;
  }
  return '';
}

/// 这门课**本轮取数状态**的一句话说明；正常扫过（无论有没有作业）返回空串。
///
/// ⚠ 「**没扫到**」与「**没有作业**」必须分开说（用户 2026-09-20 报的正是这个）：
/// 学习通有请求配额，一轮只扫一部分课，其余课沿用上一次的数据。把「本轮未扫到」
/// 显示成「无作业记录」就是骗人 —— 用户看到的「我明明有作业，为什么提示没有作业」
/// 有一半来自这里（另一半是那轮刷新把旧作业丢了，见 `ChaoxingController` 的单飞）。
String chaoxingCourseScanNote(ChaoxingSnapshot snapshot, String courseKey) {
  if (snapshot.isCourseFailed(courseKey)) {
    return '本轮扫描失败，显示的是上次数据';
  }
  if (snapshot.isCoursePending(courseKey)) {
    return '本轮未扫到（学习通有请求配额，下次进入补扫）';
  }
  // ⚠ 与上面两档**不是一回事**：非当下学期的课**下一轮也不会扫**，说「下次进入补扫」
  // 是撒谎（用户 2026-09-20 选定「只扫当下学期」，这些课有意不扫）。
  if (snapshot.isCourseSkipped(courseKey)) {
    return '非当下学期，未扫描（只扫当下学期）';
  }
  return '';
}

/// 这条通知是不是**平台自动发的作业通知**。
///
/// 实测标题形态（`notice.chaoxing.com` 收件箱，2026-09-20）：
/// `作业:《261学期 线性代数（工）》9月20日24:00前提交作业` —— 老师发布作业时
/// 平台自动发一条，**标题里就带课程名与作业标题**。还有一种是「作业结束提醒」
/// （已结束，不是待做），故只认 `作业:` / `作业：` 开头这一种形态。
bool chaoxingNoticeIsWorkPost(ChaoxingNotice notice) {
  final t = chaoxingCleanText(notice.title);
  return t.startsWith('作业:') || t.startsWith('作业：');
}

/// 从作业通知标题里剥出**作业标题本身**（去掉 `作业:` 前缀与《课程名》）。
String chaoxingNoticeWorkTitle(ChaoxingNotice notice) {
  var t = chaoxingCleanText(notice.title);
  t = t.replaceFirst(RegExp(r'^作业\s*[:：]\s*'), '');
  t = t.replaceFirst(RegExp(r'^《[^》]*》\s*'), '');
  return t.trim();
}

/// **通知里的作业提醒**：平台发的作业通知里，「作业列表还没扫到对应记录」的那些。
///
/// ## 为什么要有这一层（用户 2026-09-20 选定的 B 方案）
/// 作业是学习通里**唯一没有统一接口**的数据（通知 1 个请求、课程 1 个请求就能拿全，
/// 作业得逐课 2 个请求，见 `reverse_engineering/学习通接口.md` §9.1）。所以作业清单
/// 天然可能不全：只扫当下学期时往期课不扫、撞风控时当轮收手。
/// 通知是**统一接口**（一次 20 条），其中就含老师发布作业时的自动通知 ——
/// 拿它当兜底信号，把「没扫到但确实发布了」的作业至少显示出来（点开是通知详情）。
///
/// ⚠ **去重口径** = 该课已有作业的标题**是否出现在通知标题里**（实测：作业列表里那条
/// `9月20日24:00前提交作业` 正是通知标题 `作业:《261学期 线性代数（工）》9月20日24:00前提交作业`
/// 的后半段）→ 已扫到的不再重复显示。认不出课程的（`courseId` 为空）直接跳过：
/// 挂不上课程的通知在作业语境里没法用。
List<ChaoxingNotice> chaoxingNoticeWorkHints(ChaoxingSnapshot snapshot) => [
  for (final n in snapshot.notices)
    if (n.courseId.isNotEmpty && chaoxingNoticeIsWorkPost(n) && !_noticeCoveredByWorks(snapshot, n)) n,
];

/// 通知提到的作业是否**已经在作业列表里**（标题包含判定）。
bool _noticeCoveredByWorks(ChaoxingSnapshot snapshot, ChaoxingNotice notice) {
  final title = chaoxingCleanText(notice.title);
  for (final w in snapshot.works) {
    if (w.courseId != notice.courseId) continue;
    final workTitle = chaoxingCleanText(w.title);
    if (workTitle.isNotEmpty && title.contains(workTitle)) return true;
  }
  return false;
}

/// 通知正文的单行摘要（收拢空白 + 截断）。
String chaoxingNoticeSnippet(String content, {int max = 80}) {
  final t = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max)}…';
}

/// 收拢空白（正文里大量 `\r`）。
String chaoxingCleanText(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

int _byDue(ChaoxingWork a, ChaoxingWork b) {
  final da = a.dueAt;
  final db = b.dueAt;
  if (da == null && db == null) return a.title.compareTo(b.title);
  if (da == null) return 1;
  if (db == null) return -1;
  return da.compareTo(db);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `3 天 4 小时` / `45 分钟` / `不到 1 分钟`。
String _span(Duration d) {
  if (d.inMinutes < 1) return '不到 1 分钟';
  if (d.inHours < 1) return '${d.inMinutes} 分钟';
  if (d.inDays < 1) {
    final m = d.inMinutes - d.inHours * 60;
    return m == 0 ? '${d.inHours} 小时' : '${d.inHours} 小时 $m 分钟';
  }
  final h = d.inHours - d.inDays * 24;
  return h == 0 ? '${d.inDays} 天' : '${d.inDays} 天 $h 小时';
}

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
