/// 分数估计 · 学习通作业成绩的来源（只读）。
///
/// 数据来源：**学习通页写下的 Hive 快照缓存**（box `chaoxing_<账号>` 的单 key
/// `snapshot`，见 `features/chaoxing/data/chaoxing_store.dart` 与 §30）。
///
/// ⚠ **本文件一个网络请求都不发**：超星有累计请求预算（≈60 个/窗口，超了就回
/// 「请输入图片中的验证码」的 202 页），作业数据只能沿用「学习通」页最近一次取数的
/// 结果 —— 所以界面上必须显示快照的取数时刻（[GeChaoxingHomework.fetchedAt]），
/// 不能假装它是最新的。
///
/// 口径：
/// - 只有「**已完成**」且有分数的作业参与平均（待做 / 待批阅 / 认不出的状态一律不算，
///   否则会把「还没批」当成 0 分）；
/// - 均分 = 已批作业分数的算术平均（学习通作业分是百分制，越界值 clamp 到 0~100）；
/// - 课程名匹配：教务课程名 ↔ 学习通课程名（已去掉学期前缀），先全等、再包含，
///   多门命中时取「已评分作业最多」的那门，并合并**同学期**的多教学班。
library;

import 'package:flutter/foundation.dart';

import '../../chaoxing/data/chaoxing_store.dart';
import '../../chaoxing/domain/chaoxing_course.dart';
import '../../chaoxing/domain/chaoxing_snapshot.dart';
import '../../chaoxing/domain/chaoxing_work.dart';

/// 一门课在学习通里的作业成绩。
class GeChaoxingHomework {
  const GeChaoxingHomework({
    required this.courseId,
    required this.courseIds,
    required this.courseName,
    required this.average,
    required this.works,
    this.fetchedAt,
  });

  /// 主课程 id（展示用；多教学班合并时取第一条）。
  final String courseId;

  /// 参与的课程 id（同课多教学班时会多于一条）。
  final List<String> courseIds;

  /// 学习通里的课程名（已去学期前缀）。
  final String courseName;

  /// 作业均分（百分制）。
  final double average;

  /// 参与平均的作业（已完成且有分数），按截止时间升序。
  final List<ChaoxingWork> works;

  /// 快照取数时刻（null = 缓存里没记）。
  final DateTime? fetchedAt;

  /// 参与平均的作业条数。
  int get count => works.length;

  @override
  String toString() =>
      'GeChaoxingHomework($courseName, ${works.length} 条, 均分 $average)';
}

/// 课程名归一（匹配用）：小写 + 全角括号/连字符 → 半角 + 去空白 + 去学期/年份前缀。
///
/// 例：`261学期 计算机组成原理` → `计算机组成原理`；`253程序设计实训` → `程序设计实训`；
/// `大学英语（读写）` → `大学英语(读写)`。
String geNormalizeCourseName(String raw) {
  var s = raw.trim().toLowerCase();
  s = s
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('【', '[')
      .replaceAll('】', ']')
      .replaceAll('：', ':')
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('·', '');
  s = s.replaceAll(RegExp(r'\s+'), '');
  // 学习通课程名常带学期前缀：`261学期…`（`displayName` 已去，这里再兜一层），
  // 也有只带三位学期码的写法（`253程序设计实训`）。
  s = s.replaceAll(RegExp(r'^\d{3}学期'), '');
  s = s.replaceAll(RegExp(r'^\d{3}(?=[^\d]|$)'), '');
  return s;
}

/// 按课程分组「已批阅且有分数」的作业；空快照 → 空表。
///
/// ⚠ 只认 [ChaoxingWorkStatus.done]：把「待批阅」当成 0 分会把均分算低。
Map<String, List<ChaoxingWork>> geScoredWorksByCourse(
  ChaoxingSnapshot? snapshot,
) {
  final out = <String, List<ChaoxingWork>>{};
  if (snapshot == null) return out;
  for (final w in snapshot.works) {
    if (w.status != ChaoxingWorkStatus.done) continue;
    final s = w.score;
    if (s == null || !s.isFinite) continue;
    if (w.courseId.isEmpty) continue;
    (out[w.courseId] ??= <ChaoxingWork>[]).add(w);
  }
  return out;
}

/// 教务课程名 → 学习通课程（可能多条：同课多教学班）。
///
/// 匹配顺序：① 归一后全等；② 归一后互相包含（`线性代数` ↔ `线性代数(工)`）；
/// 都没命中 → 空表（**宁可不要，也不要猜错课**）。多门命中时先按「已评分作业条数」
/// 排序，再取与它**同学期**的全部课程（合并重复教学班，避免跨学期混算）。
List<ChaoxingCourse> geMatchChaoxingCourses(
  List<ChaoxingCourse> courses,
  String courseName, {
  Map<String, List<ChaoxingWork>> scored = const {},
}) {
  final target = geNormalizeCourseName(courseName);
  if (target.isEmpty || courses.isEmpty) return const [];
  final exact = <ChaoxingCourse>[];
  final loose = <ChaoxingCourse>[];
  for (final c in courses) {
    final n = geNormalizeCourseName(c.displayName);
    if (n.isEmpty) continue;
    if (n == target) {
      exact.add(c);
    } else if (n.contains(target) || target.contains(n)) {
      loose.add(c);
    }
  }
  final pool = exact.isNotEmpty ? exact : loose;
  if (pool.isEmpty) return const [];
  if (pool.length == 1) return pool;

  final sorted = [...pool]..sort((a, b) {
    final d =
        (scored[b.courseId]?.length ?? 0) - (scored[a.courseId]?.length ?? 0);
    if (d != 0) return d;
    return a.courseId.compareTo(b.courseId);
  });
  final best = sorted.first;
  final sameTerm = [
    for (final c in pool)
      if (c.termCode == best.termCode) c,
  ]..sort((a, b) => a.courseId.compareTo(b.courseId));
  return sameTerm.isEmpty ? [best] : sameTerm;
}

/// 从快照里取这门课的作业成绩；null = 没缓存 / 名字对不上 / 没有已评分作业。
GeChaoxingHomework? geChaoxingHomeworkFor(
  ChaoxingSnapshot? snapshot,
  String courseName,
) {
  if (snapshot == null) return null;
  final scored = geScoredWorksByCourse(snapshot);
  final matched = geMatchChaoxingCourses(
    snapshot.courses,
    courseName,
    scored: scored,
  );
  if (matched.isEmpty) return null;

  final works = <ChaoxingWork>[];
  final seen = <String>{};
  for (final c in matched) {
    for (final w in scored[c.courseId] ?? const <ChaoxingWork>[]) {
      // 同课多教学班时同一份作业会出现多次（workId 相同）→ 只算一次。
      if (w.workId.isEmpty || seen.add(w.workId)) works.add(w);
    }
  }
  if (works.isEmpty) return null;
  works.sort((a, b) {
    final da = a.dueAt;
    final db = b.dueAt;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });

  var sum = 0.0;
  for (final w in works) {
    sum += w.score!.clamp(0.0, 100.0);
  }
  return GeChaoxingHomework(
    courseId: matched.first.courseId,
    courseIds: [for (final c in matched) c.courseId],
    courseName: matched.first.displayName,
    average: sum / works.length,
    works: works,
    fetchedAt: snapshot.fetchedAt,
  );
}

/// 读学习通快照缓存（离线；任何异常 → null，不抛）。
Future<ChaoxingSnapshot?> loadGeChaoxingSnapshot({String? account}) async {
  try {
    final store = await ChaoxingStore.open(account);
    return await store.load();
  } catch (e) {
    debugPrint('[score_estimate] 读学习通作业缓存失败：$e');
    return null;
  }
}
