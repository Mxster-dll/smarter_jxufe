/// 培养方案页的**行级零件**：数字格式、修读性质徽标、字段对、课程行、实践环节行。
///
/// 取色一律走 `fluent(context)`（§13「Fluent 基础层」），**不许出现裸色值**。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

/// 学分文本：`2.0 → 2`、`1.25 → 1.25`（与毕业学分页 `creditText` 同一口径）。
///
/// 刻意**没有**跨 feature 去 import 那边 presentation 里的那个函数
/// （跨模块 import 别家 widget 文件不值当），规则就一行，两边都别改口径。
String crCreditText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// 修读性质徽标（必修 / 选修 / 限选 …）。
///
/// 配色只区分三档语义：必修 = accent（主题红）、限选 = caution（琥珀）、
/// 其余（选修 / 任选 / 未知） = 中性灰。**没有第四种颜色** —— 主干课程走行首的
/// 星标图标，不再占一个颜色（见 [CurriculumCourseRow]）。
class CurriculumRequirementBadge extends StatelessWidget {
  const CurriculumRequirementBadge({super.key, required this.requirement});

  final CourseRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final (Color fill, Color ink) = switch (requirement) {
      CourseRequirement.compulsory => (p.accentSubtle, p.accent),
      CourseRequirement.restricted => (p.cautionBg, p.cautionDeep),
      _ => (p.neutralBg, p.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: FluentRadius.controlAll,
      ),
      child: Text(
        curriculumRequirementShort(requirement),
        style: FluentType.caption.copyWith(color: ink),
      ),
    );
  }
}

/// 「标签 + 值」字段对（展开详情里横排铺开）。
class CurriculumFieldPair extends StatelessWidget {
  const CurriculumFieldPair({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: FluentType.caption.copyWith(color: p.textTertiary)),
        const SizedBox(height: 2),
        Text(value, style: FluentType.body.copyWith(color: p.textPrimary)),
      ],
    );
  }
}

/// 一门课的行（可展开学时明细）。
///
/// 触摸可用：整行手势挂在 [FluentListRow] 的 `GestureDetector` 上（不许做成
/// hover 才响应，§3 硬约定）；展开的是**行下方**的详情块，不是弹窗。
class CurriculumCourseRow extends StatelessWidget {
  const CurriculumCourseRow({
    super.key,
    required this.item,
    required this.expanded,
    required this.onToggle,
    this.showCategory = true,
  });

  final CurriculumCourseItem item;
  final bool expanded;
  final VoidCallback onToggle;

  /// 行内要不要写二级分类 —— 「按分类」聚合时组头已经写了，不必重复。
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final course = item.course;
    final description = [
      if (course.code.isNotEmpty) '[${course.code}]',
      if (showCategory && course.subCategory.trim().isNotEmpty)
        course.subCategory,
      course.assessmentMethod.displayName,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentListRow(
          leading: _CourseIndexLabel(index: item.index),
          title: course.name,
          description: description,
          onTap: onToggle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (course.importance == CourseImportance.core) ...[
                Tooltip(
                  message: '主干课程',
                  child: Icon(Icons.star_rate_rounded, size: 16, color: p.cautionDeep),
                ),
                const SizedBox(width: FluentSpacing.sm),
              ],
              CurriculumRequirementBadge(requirement: course.requirement),
              const SizedBox(width: FluentSpacing.md),
              Text(
                '${crCreditText(course.credit)} 学分',
                style: FluentType.bodyStrong.copyWith(color: p.textPrimary),
              ),
              const SizedBox(width: FluentSpacing.xs),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: p.textTertiary,
              ),
            ],
          ),
        ),
        if (expanded) _CourseDetail(item: item),
      ],
    );
  }
}

/// 行首行号（教务表序号）。
///
/// 刻意**不用** `FluentIndexBadge`：那是固定 24×24 的实心徽标，真实方案有 180+ 门课，
/// 三位数会在这个宽度里折行。这里给固定宽度的右对齐小字，位数变了也不会崩。
class _CourseIndexLabel extends StatelessWidget {
  const _CourseIndexLabel({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return SizedBox(
      width: 28,
      child: Text(
        '$index',
        textAlign: TextAlign.right,
        maxLines: 1,
        style: FluentType.caption.copyWith(color: p.textTertiary),
      ),
    );
  }
}

/// 展开后的学时 / 口径明细。
class _CourseDetail extends StatelessWidget {
  const _CourseDetail({required this.item});

  final CurriculumCourseItem item;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final course = item.course;
    final hours = course.creditHour;

    return Container(
      margin: const EdgeInsets.only(
        left: FluentSpacing.lg,
        right: FluentSpacing.sm,
        bottom: FluentSpacing.sm,
      ),
      padding: const EdgeInsets.all(FluentSpacing.md),
      decoration: BoxDecoration(
        color: p.subtleSecondary,
        borderRadius: FluentRadius.controlAll,
      ),
      child: Wrap(
        spacing: FluentSpacing.xl,
        runSpacing: FluentSpacing.md,
        children: [
          CurriculumFieldPair(label: '总学时', value: '${hours.total}'),
          CurriculumFieldPair(label: '讲授', value: '${hours.lecture}'),
          // 实验 / 实践 / 其它多为 0，只在真有学时的时候才占位，免得刷屏。
          if (hours.lab > 0)
            CurriculumFieldPair(label: '实验', value: '${hours.lab}'),
          if (hours.practice > 0)
            CurriculumFieldPair(label: '实践', value: '${hours.practice}'),
          if (hours.other > 0)
            CurriculumFieldPair(label: '其它', value: '${hours.other}'),
          CurriculumFieldPair(
            label: '周学时',
            value: crCreditText(hours.weekly),
          ),
          CurriculumFieldPair(
            label: '课程地位',
            value: course.importance.displayName,
          ),
          CurriculumFieldPair(label: '课程大类', value: course.mainCategory),
          CurriculumFieldPair(
            label: '开课学期',
            value: item.termLabel,
          ),
          if (course.tertiaryCategory != null &&
              course.tertiaryCategory!.trim().isNotEmpty)
            CurriculumFieldPair(
              label: '三级分类',
              value: course.tertiaryCategory!,
            ),
          if (course.identification.trim().isNotEmpty)
            CurriculumFieldPair(label: '标识', value: course.identification),
        ],
      ),
    );
  }
}

/// 实践环节类别 → 图标（Material Icons，不用 emoji）。
IconData curriculumPracticeIcon(String category) {
  final text = category.trim();
  if (text.contains('军训')) return Icons.military_tech_outlined;
  if (text.contains('实习') || text.contains('实训')) {
    return Icons.engineering_outlined;
  }
  if (text.contains('论文') || text.contains('设计')) {
    return Icons.description_outlined;
  }
  if (text.contains('科研') || text.contains('创新')) {
    return Icons.science_outlined;
  }
  return Icons.checklist_rtl_outlined;
}

/// 一条实践环节的行。
class PracticeStageRow extends StatelessWidget {
  const PracticeStageRow({super.key, required this.stage});

  final PracticeStage stage;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final description = [
      if (stage.code.isNotEmpty) '[${stage.code}]',
      if (stage.category.trim().isNotEmpty) stage.category,
      curriculumTermLabel(stage.semester),
      if (stage.weeks > 0) '${crCreditText(stage.weeks)} 周',
      if (stage.assessment.trim().isNotEmpty) stage.assessment,
    ].join(' · ');

    return FluentListRow(
      leading: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.accentSubtle,
          borderRadius: FluentRadius.controlAll,
        ),
        child: Icon(
          curriculumPracticeIcon(stage.category),
          size: 18,
          color: p.accent,
        ),
      ),
      title: stage.name,
      description: description,
      minHeight: 56,
      trailing: Text(
        '${crCreditText(stage.credit)} 学分',
        style: FluentType.bodyStrong.copyWith(color: p.textPrimary),
      ),
    );
  }
}
