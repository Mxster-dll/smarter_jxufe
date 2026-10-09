/// 工具集：培养方案 / 毕业学分要求。
///
/// 培养方案链路 = 学籍（入学年 / 学院 / 专业）→ 学院列表 → 专业列表 →
/// 培养方案，与成绩页、分数估计模块**同一条链**。`CurriculumRepository`
/// 的 `getCurriculumIn` **命中本地缓存不发网络**，所以只要用户打开过一次
/// 培养方案页，离线也能答。
///
/// 这条链任何一步失败都返回 null —— 工具如实说「拿不到」，**不编**。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
// ⚠ 毕业学分现在只经 `graduationCreditReportProvider`（要求 + 已修进度一套算完）。
// 它内部的 `graduationRequirementsProvider` 定义在**页面文件**里（不在
// data/providers/），这是既成事实；别为了「层次好看」把要求表再复制一份过来。
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/credit_progress_provider.dart'
    show GraduationCreditReport, graduationCreditReportProvider;
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 本专业培养方案全文（拿不到就是 null）。
///
/// 与 `geCurriculumIndexProvider`（只留课程代码→学分的索引）的区别：这里要
/// **完整课程表**，才能回答「培养方案里有哪些课」「每个类别多少学分」。
final aiCurriculumProvider = FutureProvider<Curriculum?>((ref) async {
  try {
    final studentInfoRepo = await ref.watch(
      studentInfoRepositoryProvider.future,
    );
    final si = studentInfoRepo.getCachedStudentInfo().fold(
      (_) => null,
      (i) => i,
    );
    if (si == null) return null;
    final year = int.tryParse(si.enrollYear);
    if (year == null) return null;

    final collegeRepo = await ref.watch(collegeRepositoryProvider.future);
    final colleges = (await collegeRepo.getAllCollege()).fold(
      (_) => const <College>[],
      (list) => list,
    );
    College? college;
    for (final c in colleges) {
      if (c.name == si.college) {
        college = c;
        break;
      }
    }
    if (college == null) return null;

    final majorRepo = await ref.watch(majorRepositoryProvider.future);
    final majors = (await majorRepo.getAllMajorIn(
      college,
      year: year,
    )).fold((_) => const <Major>[], (list) => list);
    Major? major;
    for (final m in majors) {
      if (m.name == si.major) {
        major = m;
        break;
      }
    }
    if (major == null) return null;

    final repo = await ref.watch(curriculumRepositoryProvider.future);
    final result = await repo.getCurriculumIn(year, college, major);
    return result.fold((_) => null, (c) => c);
  } catch (_) {
    return null;
  }
});

/// 查本专业培养方案（教学计划）。
class GetCurriculumTool extends AiTool {
  const GetCurriculumTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_curriculum',
    description:
        '查本专业培养方案（教学计划）：要修哪些课、各多少学分、必修还是选修、'
        '属于哪一类课程。问「我这个专业总共要修多少学分」「培养方案里有没有 '
        'XX 课」「专业必修课有哪些」用它。'
        '注意：这是**计划**，不是已修情况；已出成绩用 get_grades、'
        '毕业学分构成要求用 get_graduation_credits。',
    parameters: aiObjectSchema({
      'course': aiStrProp('只看课程名或课程代码包含该关键词的课'),
      'requirement': aiStrProp(
        '按修读性质过滤',
        enums: ['必修课', '选修课', '限选课', '任选课', '专业方向'],
      ),
      'category': aiStrProp('按课程类别（培养方案里的「课程类别」列）包含匹配'),
      'limit': aiIntProp('最多列多少门（默认 80，避免一次灌太多）', min: 1, max: 300),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final keyword = a.optStr('course');
    final requirement = a.optStr('requirement');
    final category = a.optStr('category');
    final limit = a.intOf('limit', fallback: 80);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final Curriculum? plan;
    try {
      plan = await ctx.ref.read(aiCurriculumProvider.future);
    } catch (e) {
      return AiToolResult.fail('培养方案读取失败：$e');
    }
    if (plan == null) {
      return const AiToolResult.fail(
        '拿不到本专业的培养方案。常见原因：还没登录 / 本地没有学籍缓存 / '
        '学籍里的学院或专业名称与学院专业列表对不上。可以让用户先打开一次'
        '「我的」（拉学籍）与「培养方案」页面，之后就能离线查了。',
      );
    }

    final all = plan.courses;
    if (all.isEmpty) {
      return AiToolResult.fail('培养方案里没有课程条目（${plan.majorName}，${plan.year} 级）。');
    }

    // 先按全量算总账（筛选只影响下面的清单，不影响「总共要修多少」）。
    var totalCredit = 0.0;
    final byCategory = <String, ({int count, double credit})>{};
    for (final c in all) {
      totalCredit += c.credit;
      final key = c.mainCategory.trim().isEmpty ? '未分类' : c.mainCategory.trim();
      final prev = byCategory[key] ?? (count: 0, credit: 0.0);
      byCategory[key] = (
        count: prev.count + 1,
        credit: prev.credit + c.credit,
      );
    }

    final rows = all.where((c) {
      if (keyword != null &&
          !c.name.contains(keyword) &&
          !c.code.contains(keyword)) {
        return false;
      }
      if (requirement != null && c.requirement.displayName != requirement) {
        return false;
      }
      if (category != null && !c.mainCategory.contains(category)) return false;
      return true;
    }).toList()..sort((x, y) => y.credit.compareTo(x.credit));

    final buffer = StringBuffer()
      ..writeln(
        '【培养方案】${plan.majorName}（${plan.year} 级 · ${plan.collegeName}）',
      )
      ..writeln(
        '共 ${all.length} 门课 / ${_trim(totalCredit)} 学分。',
      );
    final cats = byCategory.keys.toList()..sort();
    for (final k in cats) {
      final v = byCategory[k]!;
      buffer.writeln('· $k：${v.count} 门 / ${_trim(v.credit)} 学分');
    }

    final filters = <String>[
      if (keyword != null) '名称或代码含「$keyword」',
      ?requirement,
      if (category != null) '类别含「$category」',
    ];
    buffer.writeln();
    if (rows.isEmpty) {
      buffer.writeln('没有符合条件的课程${filters.isEmpty ? '' : '（${filters.join('，')}）'}。');
      return AiToolResult.ok(buffer.toString());
    }
    buffer.writeln(
      '课程清单${filters.isEmpty ? '' : '（${filters.join('，')}）'}：'
      '${rows.length} 门'
      '${rows.length > limit ? '，下面只列学分最高的 $limit 门' : ''}',
    );
    for (final c in rows.take(limit)) {
      buffer.writeln(
        '· ${c.name}（${c.code}）${_trim(c.credit)} 学分'
        ' · ${c.requirement.displayName}'
        ' · ${c.mainCategory}'
        '${c.subCategory.trim().isEmpty ? '' : ' / ${c.subCategory}'}'
        ' · ${c.nature.displayName}'
        ' · ${c.importance.displayName}'
        ' · ${c.assessmentMethod.displayName}',
      );
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'curriculum',
        'count': rows.length,
        'credits': totalCredit,
      },
    );
  }
}

/// 查毕业学分要求**与进度**（教务「毕业学分」页）。
class GetGraduationCreditsTool extends AiTool {
  const GetGraduationCreditsTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_graduation_credits',
    description:
        '查毕业学分要求**与已修进度**：必修课还差多少学分（按本专业培养方案）、'
        '选修课各分项还差多少（教务「毕业学分」页那张构成表 + 已修成绩推算）。'
        '问「毕业还要修多少学分」「XX 类还差几分」「我离毕业还差多少」用它。'
        '需要教务会话（在线）；培养方案只读本地缓存，没打开过培养方案页时'
        '必修进度会缺，此时会如实说明。',
    parameters: aiObjectSchema({
      'item': aiStrProp('只看分项名包含该关键词的行（如「通识」「专业」「美育」）'),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final item = a.optStr('item');
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final GraduationCreditReport report;
    try {
      report = await ctx.ref.read(graduationCreditReportProvider.future);
    } catch (e) {
      return AiToolResult.fail(
        '毕业学分读取失败：$e（这一项要教务会话，可以先打开一次「毕业学分」页面）。',
      );
    }
    final progress = report.progress;

    if (!progress.hasElectives && !progress.compulsory.available) {
      return AiToolResult.fail(
        report.requirementsError == null
            ? '教务没有返回毕业学分构成表。'
            : '毕业学分要求读取失败：${report.requirementsError}'
                  '（这一项要教务会话，可以先打开一次「毕业学分」页面）。',
      );
    }

    final buffer = StringBuffer()..writeln('毕业学分进度：');

    final c = progress.compulsory;
    if (c.available) {
      buffer.writeln(
        '· 必修课：已修 ${_trim(c.earned)} / 要求 ${_trim(c.required)} 学分，'
        '${c.satisfied ? '已修完' : '还差 ${_trim(c.remaining)} 学分'}'
        '（${c.doneCount}/${c.totalCount} 门）',
      );
    } else {
      buffer.writeln('· 必修课：拿不到本专业培养方案，无法统计。');
    }

    if (progress.hasElectives) {
      buffer.writeln(
        '· 选修课：已修 ${_trim(progress.electiveCounted)} / '
        '要求 ${_trim(progress.electiveRequired)} 学分，'
        '${progress.electiveRemaining <= 0 ? '已全部满足' : '还差 ${_trim(progress.electiveRemaining)} 学分'}',
      );
    }

    final wanted = item == null
        ? progress.electives
        : [
            for (final e in progress.electives)
              if (e.title.contains(item)) e,
          ];
    if (item != null && wanted.isEmpty) {
      buffer.writeln('没有分项名含「$item」的学分要求行。');
    } else {
      for (final e in wanted) {
        buffer.writeln(
          '· ${e.title}：要求 ${_trim(e.required)} 学分，'
          '已修 ${_trim(e.earned)} 学分，'
          '${e.satisfied ? '已满足' : '还差 ${_trim(e.remaining)} 学分'}'
          '｜口径：${e.rule}',
        );
      }
    }

    if (progress.electives.isEmpty && report.requirementsError != null) {
      buffer.writeln(
        '（选修要求表没取到：${report.requirementsError}；'
        '这一项要教务会话，可以先打开一次「毕业学分」页面）',
      );
    }

    if (progress.unmatched.isNotEmpty) {
      buffer.writeln(
        '未归类课程 ${progress.unmatched.length} 门 / '
        '${_trim(progress.unmatchedCredits)} 学分（没被算进上面任何一项）：',
      );
      for (final u in progress.unmatched.take(10)) {
        buffer.writeln('· ${u.course.name}：${_reasonShort(u.reason)}');
      }
      if (progress.unmatched.length > 10) {
        buffer.writeln('（其余 ${progress.unmatched.length - 10} 门从略）');
      }
    }

    buffer.writeln('已修学分合计 ${_trim(progress.earnedTotal)} 学分（含未归类课程）。');

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'graduationCredits',
        'count': wanted.length,
        'electiveRemaining': progress.electiveRemaining,
        'compulsoryRemaining': c.remaining,
      },
    );
  }
}

/// 把未归类原因压成一句短的（给模型看，不占太多 token）。
String _reasonShort(String reason) {
  if (reason.length <= 28) return reason;
  return '${reason.substring(0, 27)}…';
}

String _trim(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
