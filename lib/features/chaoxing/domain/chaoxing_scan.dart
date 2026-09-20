/// 本轮作业扫描的**课程范围**口径（用户 2026-09-20 裁定：「只扫当下学期」）。
///
/// ## 为什么要有这一层
/// 作业是学习通里**唯一没有统一接口**的数据（见 `reverse_engineering/学习通接口.md`
/// §9.1）：通知 1 个请求、课程 1 个请求就能拿全，作业却必须**逐课**取
/// （`stucoursemiddle` 拿签名 query + `getAllWork`），一门课 2 个请求。
/// 35 门课 = 70 个请求 > 学习通的风控预算（≈60 个/窗口），于是首版不得不
/// 「每轮只扫 20 门 + 游标轮转 + 冷却」，代价是**一次刷新拿不全**：用户会看到
/// 「我明明有作业，它说没有」。
///
/// 只扫当下学期（实测该账号：当下学期 10 门 + 学期认不出的 2 门 = 12 门 = **24 个请求**）
/// 就整个脱离了预算区：**一轮扫完、不再轮转**，用户点一次刷新就是全的。
/// 非当下学期的课（往期课程）沿用缓存里的旧数据，界面如实标注。
library;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';

/// 这门课是否属于本轮扫描范围。
///
/// [currentTermCode] 为空（拿不到当下学期，如校历与月份规则都失效）→ **不筛**，
/// 全部课程都扫（宁可多花请求，也不要因为判不出学期就什么都不扫）。
///
/// 学期前缀**认不出**的课（`253程序设计实训`、`大学生国家安全教育`）一律**照扫**：
/// 实测 35 门里有 2 门没有前缀，多为实训/通识课，可能就是本学期的课 ——
/// 为省 4 个请求而漏掉一门真在上的课不划算。
bool chaoxingCourseScannable(
  ChaoxingCourse course, {
  required String currentTermCode,
}) {
  if (currentTermCode.isEmpty) return true;
  final code = course.termCode;
  return code.isEmpty || code == currentTermCode;
}

/// 本轮要扫的课（**保持课程页原顺序** —— 顺序稳定，分批窗口才不会跳）。
List<ChaoxingCourse> chaoxingScanTargets(
  List<ChaoxingCourse> courses, {
  required String currentTermCode,
}) => [
  for (final c in courses)
    if (chaoxingCourseScannable(c, currentTermCode: currentTermCode)) c,
];

/// 本轮**不扫**的课（非当下学期）——界面要如实说明，别让它看起来像「没有作业」。
List<ChaoxingCourse> chaoxingSkippedCourses(
  List<ChaoxingCourse> courses, {
  required String currentTermCode,
}) => [
  for (final c in courses)
    if (!chaoxingCourseScannable(c, currentTermCode: currentTermCode)) c,
];

/// 本轮扫描计划（**仓库唯一入口**：要不要筛也在这一层决定，别在仓库里再判一次）。
///
/// 两条「不筛」的退路，都是为了**别把功能变成扫不到东西**：
/// 1. [currentTermCode] 为空 —— 学期判不出来（校历与月份规则都失效）；
/// 2. **一门课都不匹配当下学期码** —— 新学期课程还没建、或学期码口径对不上。
///    实测该账号 261 学期有 10 门，所以正常不会走到这里；但若照 252 的门数变化
///    （如暑假里新学期课还没导入），筛下去会把整个学期的课全判成「非当下学期」，
///    界面直接变成「一条作业都没有」——比多花请求糟得多。
///
/// 命中退路时 `skipped` 一律为空（没有课被有意跳过）。
({List<ChaoxingCourse> targets, List<ChaoxingCourse> skipped}) chaoxingScanPlan(
  List<ChaoxingCourse> courses, {
  required String currentTermCode,
}) {
  if (currentTermCode.isEmpty) {
    return (targets: courses, skipped: const <ChaoxingCourse>[]);
  }
  final hasCurrentTerm = courses.any((c) => c.termCode == currentTermCode);
  if (!hasCurrentTerm) {
    return (targets: courses, skipped: const <ChaoxingCourse>[]);
  }
  return (
    targets: chaoxingScanTargets(courses, currentTermCode: currentTermCode),
    skipped: chaoxingSkippedCourses(courses, currentTermCode: currentTermCode),
  );
}
