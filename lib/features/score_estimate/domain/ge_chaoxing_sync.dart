/// 分数估计 · 学习通作业成绩 → 平时分项 的接入口径（纯函数，无 IO / 无 UI）。
///
/// ## 为什么这么定（用户口径，2026-09-22）
/// 用户原话：「我们希望把学习通中的各课程作业成绩接入『分数估计』，但**前提是该课程
/// 给出了作业的占比**」→ 本模块把「占比」定义为 **该课「作业」分项的分值上限在平时分
/// 里的份额**（`cap ÷ Σcap`）——因为在估算引擎里，作业对总评的唯一权重来源就是这个
/// `cap`（口径见 `ge_engine.dart`：总评 = 平时均分 × 平时占比 + 期末 × 期末占比，
/// 平时均分 = Σ(得分率 × cap) ÷ Σcap）。因此：
///
/// 1. **没有「作业」分项 = 占比未知 → 一律不接入**（[geApplyChaoxingHomework] 返回
///    null），界面必须把这件事说清楚，不许悄悄塞一个分项进来；
/// 2. 接入后的形态 = **「直接分数」**：满分 `target = 100`（学习通作业分是百分制）、
///    得分 `score` = 作业均分、`source = [gePartSourceChaoxing]`（此后由自动同步接管）；
/// 3. **分值上限（= 占比）、名称、编号、备注一律不动** —— 同步只改得分，不改结构；
/// 4. **计数型分项（正计数 / 负计数）不静默改写**：把「已完成 12/20」变成「92.5 分」
///    是结构性变更，必须由用户明确同意（界面上点「接入」→ `force: true`，或在分项
///    弹窗里打开「学习通自动同步」开关）；
/// 5. **幂等**：值没变就返回 null，绝不因为「进了页面」而反复写库。
library;

import 'ge_models.dart';

/// 分项来源标记：由「学习通作业成绩」自动同步。
const String gePartSourceChaoxing = 'chaoxing';

/// 分项来源标记：**明确手填** —— 用户在分项弹窗里关掉了「学习通自动同步」。
///
/// 有了这一档，关掉开关才是真的关掉：否则一个「直接分数」型的「作业」分项下次进
/// 课程详情又会被静默接管（`source` 为空 = 未表态，才允许自动接管）。
const String gePartSourceManual = 'manual';

/// 「作业」分项名匹配词（小写去空白后按**包含**判断）。
///
/// ⚠ 刻意不含 `hw` 这种两字母缩写：`shw`、`show` 之类会被误命中。
const List<String> geHomeworkPartKeywords = ['作业', 'homework', 'assignment'];

/// 分项名是否像「作业」。
bool gePartNameLooksLikeHomework(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (n.isEmpty) return false;
  for (final k in geHomeworkPartKeywords) {
    if (n.contains(k)) return true;
  }
  return false;
}

/// 该课要接管的学习通作业分项；null = 这门课没给出作业的占比（不接入）。
///
/// 先找**已接入**的分项（[GePart.source] 标记优先，用户改了名也照样认），
/// 再找第一个「名字像作业且分值上限 > 0」的分项；被用户标成
/// [gePartSourceManual] 的分项**永不接管**。
GePart? geHomeworkPartOf(GeCourse course) {
  for (final p in course.parts) {
    if (p.source == gePartSourceChaoxing) return p;
  }
  for (final p in course.parts) {
    if (p.source == gePartSourceManual) continue;
    if (p.cap > 0 && gePartNameLooksLikeHomework(p.name)) return p;
  }
  return null;
}

/// 分项在**平时分**里的占比（%）：`cap ÷ Σcap × 100`（无有效分值时 0）。
double gePartDailyShare(GeCourse course, GePart part) {
  var total = 0.0;
  for (final p in course.parts) {
    if (p.cap.isFinite && p.cap > 0) total += p.cap;
  }
  if (total <= 0 || !part.cap.isFinite || part.cap <= 0) return 0;
  return part.cap / total * 100;
}

/// 分项在**总评**里的占比（%）：平时占比 × 分项在平时里的占比。
double gePartTotalShare(GeCourse course, GePart part) =>
    gePartDailyShare(course, part) *
    course.dailyPercent.clamp(0.0, 100.0) /
    100;

/// 一次同步的结果（[geApplyChaoxingHomework] 的返回）。
class GeChaoxingSyncResult {
  /// 更新后的课程（调用方写库用这一个）。
  final GeCourse course;

  /// 更新后的作业分项。
  final GePart part;

  /// 写进去的作业均分（百分制，已 clamp 到 0~100）。
  final double average;

  /// 参与平均的作业条数（已批阅且有分数的）。
  final int workCount;

  /// 本次是否**首次接管**（此前不是学习通来源）。
  final bool adopted;

  /// 学习通快照的取数时刻（界面显示数据新鲜度）。
  final DateTime? fetchedAt;

  const GeChaoxingSyncResult({
    required this.course,
    required this.part,
    required this.average,
    required this.workCount,
    required this.adopted,
    this.fetchedAt,
  });

  /// 作业分项在平时分里的占比（%）。
  double get dailyShare => gePartDailyShare(course, part);

  /// 作业分项在总评里的占比（%）。
  double get totalShare => gePartTotalShare(course, part);
}

/// 把学习通作业均分写进该课的「作业」分项。
///
/// 返回 null = **无事可做**（调用方不要写库）：
/// - [average] 为空/非法，或 [workCount] ≤ 0（没有已批阅的作业成绩）；
/// - 该课没有「作业」分项 → 占比未知，按用户口径不接入；
/// - 候选分项是计数型且尚未接入，而 [force] 为 false（不静默改写计数）；
/// - 值已经是最新的（幂等）。
///
/// [force] = true 表示**用户明确同意**接管（界面上的「接入」按钮 / 分项弹窗里的
/// 自动同步开关）：此时允许把计数型分项改写成「直接分数」。
GeChaoxingSyncResult? geApplyChaoxingHomework(
  GeCourse course, {
  required double? average,
  required int workCount,
  DateTime? fetchedAt,
  bool force = false,
}) {
  if (average == null || !average.isFinite || workCount <= 0) return null;
  final part = geHomeworkPartOf(course);
  if (part == null) return null;
  final bound = part.source == gePartSourceChaoxing;
  if (!bound && !force && part.mode != GePartMode.score) return null;

  final value = average.clamp(0.0, 100.0);
  // ⚠ 只改「得分 + 计分方式 + 来源」：cap（占比）、name、note、id 原样保留；
  //   `current` 也不动 —— 万一用户把分项改回计数型，原来的计数还在。
  final next = part.copyWith(
    mode: GePartMode.score,
    target: 100,
    score: value,
    source: gePartSourceChaoxing,
  );
  if (_samePart(next, part)) return null;

  return GeChaoxingSyncResult(
    course: course.copyWith(
      parts: [
        for (final p in course.parts)
          if (p.id == part.id) next else p,
      ],
    ),
    part: next,
    average: value,
    workCount: workCount,
    adopted: !bound,
    fetchedAt: fetchedAt,
  );
}

/// 解除接管（分项弹窗里关掉开关时用）：把来源标成 [gePartSourceManual]，
/// **得分与分值一律不动**，此后自动同步不再碰这个分项。
GeCourse geUnbindChaoxingHomework(GeCourse course, String partId) =>
    course.copyWith(
      parts: [
        for (final p in course.parts)
          if (p.id == partId) p.copyWith(source: gePartSourceManual) else p,
      ],
    );

bool _samePart(GePart a, GePart b) =>
    a.id == b.id &&
    a.name == b.name &&
    a.mode == b.mode &&
    a.target == b.target &&
    a.current == b.current &&
    a.cap == b.cap &&
    a.note == b.note &&
    a.source == b.source &&
    (a.score - b.score).abs() < 1e-9;
