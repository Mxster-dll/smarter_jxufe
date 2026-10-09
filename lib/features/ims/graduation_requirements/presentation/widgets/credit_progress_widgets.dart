/// 毕业学分页的进度视图件（必修 / 选修 / 未归类）。
///
/// 口径全部来自 `domain/credit_progress.dart`，本文件**只做渲染**，
/// 页面里不再重算任何数字，免得界面与算法两边漂移。
///
/// 视觉沿用 §13 的 Fluent 口径：`FluentCard` / `FluentSectionHeader` /
/// `FluentProgressBar` / `FluentListRow`，颜色只从 `fluent(context)` 取，
/// **不写裸 `Color(0x…)`**（§3「色彩」）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';

/// 学分文本：整数不留小数位，非整数保留必要位数（2.00 → 「2」，1.25 → 「1.25」）。
///
/// 实现已上收到 `domain/credit_progress.dart` 的 [creditTextOf]（挂科分值也要用
/// 同一套取整规则），这里只留一个名字给页面用。
String creditText(double value) => creditTextOf(value);

/// 挂科警示条：有挂科记录时顶在最上面。
///
/// 2026-10-08 加（用户原话：「不及格的话即使已修也算未获得学分，并且我希望有 UI
/// 提示」）。⚠ 挂在**页面最上方**而不是塞进脚注 —— 挂科会直接改变「还差多少」的
/// 含义，用户必须先看到。
class FailedWarningBar extends StatelessWidget {
  const FailedWarningBar({super.key, required this.courses});

  final List<CreditProgressCourse> courses;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final credits = courses.fold<double>(0, (s, c) => s + c.credit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentInfoBar(
          severity: FluentInfoSeverity.error,
          title: '有 ${courses.length} 门挂科，未获得学分',
          message:
              '挂科课程即使已经上过也不算「已修」，必须重修通过才计入毕业学分 —— '
              '所以它们仍然留在「还差」里。合计 ${creditText(credits)} 学分。',
        ),
        const SizedBox(height: FluentSpacing.md),
        FluentCard(
          padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < courses.length; i++) ...[
                if (i > 0) const FluentDivider(),
                FluentListRow(
                  leading: Icon(
                    Icons.cancel_outlined,
                    size: 18,
                    color: p.critical,
                  ),
                  title: courses[i].name,
                  description: courses[i].code.isEmpty
                      ? null
                      : courses[i].code,
                  trailing: _CreditPair(
                    top: '${creditText(courses[i].credit)} 学分',
                    bottom: courses[i].score == null
                        ? '未获得学分'
                        : '${courses[i].scoreText} 分',
                    bottomColor: p.critical,
                  ),
                  minHeight: 44,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部两张指标卡：必修进度 + 选修进度。
class CreditOverviewCards extends StatelessWidget {
  const CreditOverviewCards({
    super.key,
    required this.progress,
    required this.refreshing,
    required this.onRefresh,
  });

  final GraduationCreditProgress progress;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = progress.compulsory;
    final compulsory = FluentMetricCard(
      label: '必修课',
      value: creditText(c.earned),
      unit: '学分',
      description: c.available
          ? '要求 ${creditText(c.required)} 学分 · ${c.doneCount}/${c.totalCount} 门已修'
          : '培养方案拿不到，暂无法统计',
      trailing: FluentIconButton(
        icon: Icons.refresh,
        tooltip: '刷新',
        onPressed: refreshing ? null : onRefresh,
      ),
      footer: _ProgressFooter(
        ratio: c.ratio,
        inProgressRatio: c.inProgressRatio,
        inProgressText: c.inProgress > 0
            ? '另有 ${creditText(c.inProgress)} 学分已选未考'
            : null,
        tone: c.satisfied ? fluent(context).success : null,
        text: c.available
            ? (c.satisfied
                  ? '必修课已全部修完'
                  : '还差 ${creditText(c.remaining)} 学分')
            : '需要先取到本专业培养方案',
      ),
    );

    final elective = FluentMetricCard(
      label: '选修课',
      value: creditText(progress.electiveCounted),
      unit: '学分',
      description: progress.hasElectives
          ? '要求 ${creditText(progress.electiveRequired)} 学分 · '
                '${progress.electives.length} 项 · '
                '${progress.satisfiedElectives.length} 项已满足'
          : '教务未返回选修学分要求',
      footer: _ProgressFooter(
        ratio: progress.electiveRequired <= 0
            ? 0
            : progress.electiveCounted / progress.electiveRequired,
        inProgressRatio: progress.electiveRequired <= 0
            ? 0
            : progress.electives.fold<double>(
                    0,
                    (s, e) => s + e.inProgressCounted,
                  ) /
                  progress.electiveRequired,
        inProgressText:
            progress.electives.any((e) => e.inProgress > 0)
            ? '另有 ${creditText(progress.electives.fold<double>(0, (s, e) => s + e.inProgress))} 学分已选未考'
            : null,
        tone: progress.hasElectives && progress.electiveRemaining <= 0
            ? fluent(context).success
            : null,
        text: progress.hasElectives
            ? (progress.electiveRemaining <= 0
                  ? '选修要求已全部满足'
                  : '还差 ${creditText(progress.electiveRemaining)} 学分')
            : '需要教务会话',
      ),
    );

    final pr = progress.practice;
    final practice = FluentMetricCard(
      label: '实践环节',
      value: creditText(pr.earned),
      unit: '学分',
      description: pr.available
          ? '要求 ${creditText(pr.required)} 学分 · ${pr.doneCount}/${pr.totalCount} 项已修'
          : '实践环节表拿不到，暂无法统计',
      footer: _ProgressFooter(
        ratio: pr.ratio,
        inProgressRatio: pr.inProgressRatio,
        inProgressText: pr.inProgress > 0
            ? '另有 ${creditText(pr.inProgress)} 学分已选未考'
            : null,
        tone: pr.satisfied ? fluent(context).success : null,
        text: pr.available
            ? (pr.satisfied
                  ? '实践环节已全部修完'
                  : '还差 ${creditText(pr.remaining)} 学分')
            : '军训 / 毕业实习这类环节需要实践环节表',
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // ⚠ **只有两档**（2026-10-08 实测定案）：本页内容被
        // `FluentPageBackground.maxContentWidth = 880` 夹住 → 这里拿到的最宽就是
        // **832**，`Breakpoints.extraWide`(1000) 永远到不了。原先写的「三张并排」
        // 分支是**死代码**（写完才发现，探针打印 `overview=Size(832.0, 230.0)`），
        // 已删掉 —— 留一段跑不到、也测不到的布局分支比少一档更糟。
        if (constraints.maxWidth >= Breakpoints.wide) {
          return Column(
            children: [
              _EqualHeightRow(children: [compulsory, elective]),
              const SizedBox(height: FluentSpacing.md),
              practice,
            ],
          );
        }
        return Column(
          children: [
            compulsory,
            const SizedBox(height: FluentSpacing.md),
            elective,
            const SizedBox(height: FluentSpacing.md),
            practice,
          ],
        );
      },
    );
  }
}

/// 一排**等高**的卡片。
///
/// 2026-10-08 加（用户原话：「我希望顶部的必修课和选修课总览卡片等高」）——
/// 从前是裸 `Row(crossAxisAlignment: start)`，两张卡的说明行数不同就参差不齐
/// （实测「必修 + 选修」这一排 230 / 230，修之前是 230 / 210）。
///
/// ⚠ `CrossAxisAlignment.stretch` **必须**裹在 [IntrinsicHeight] 里：本排位于
/// `ListView` 内、纵向无界，直接 stretch 会断言「BoxConstraints forces an
/// infinite height」。`IntrinsicHeight` 先量出最高那张，再把高度定死传给各个
/// `Expanded`，于是同排的下沿对齐。
///
/// 代价 = 一次额外 intrinsic 布局（卡片子树都很浅，实测无感）；
/// **别**把它套到带 `ListView` / `GridView` 的子树外面 —— viewport 不支持
/// intrinsic 尺寸（同 §3.1 那条坑，`RenderViewport does not support returning
/// intrinsic dimensions`）。
class _EqualHeightRow extends StatelessWidget {
  const _EqualHeightRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: FluentSpacing.lg),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// 指标卡页脚：进度条（含「在修」浅色段）+ 一句话状态。
class _ProgressFooter extends StatelessWidget {
  const _ProgressFooter({
    required this.ratio,
    required this.text,
    this.inProgressRatio = 0,
    this.inProgressText,
    this.tone,
  });

  final double ratio;

  /// 「已选未考」那一段（画成更浅的红）。
  final double inProgressRatio;

  final String text;

  /// 「另有 N 学分在修」那句；为 null 时不画。
  final String? inProgressText;

  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentProgressBar(
          value: ratio,
          secondary: inProgressRatio,
          tone: tone,
        ),
        const SizedBox(height: FluentSpacing.sm),
        Text(text, style: FluentType.caption.copyWith(color: p.textSecondary)),
        if (inProgressText != null) ...[
          const SizedBox(height: FluentSpacing.xs),
          _InProgressLine(text: inProgressText!, tone: tone ?? p.accent),
        ],
      ],
    );
  }
}

/// 「另有 N 学分在修」那一行 —— **用更浅的那档红**，与进度条上的浅色段同源。
class _InProgressLine extends StatelessWidget {
  const _InProgressLine({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: FluentSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: FluentType.caption.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}

/// 必修课进度卡：总进度 + 可展开的「还差哪些课」。
class CompulsoryProgressCard extends StatefulWidget {
  const CompulsoryProgressCard({super.key, required this.progress});

  final CompulsoryCreditProgress progress;

  @override
  State<CompulsoryProgressCard> createState() => _CompulsoryProgressCardState();
}

class _CompulsoryProgressCardState extends State<CompulsoryProgressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final c = widget.progress;

    if (!c.available) {
      return const FluentCard(
        padding: EdgeInsets.all(FluentSpacing.lg),
        child: FluentInfoBar(
          message: '拿不到本专业培养方案（需要学籍的入学年 / 学院 / 专业，且至少打开过一次培养方案页）。'
              '必修进度暂无法统计。',
        ),
      );
    }

    final pending = c.pendingCourses;
    return FluentCard(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.lg,
              vertical: FluentSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ⚠ 这里**不能**用 `Row` + `Spacer`：窄屏下「已修 56 / 113 学分。
                // 与「还差 57 学分」两段加起来会超出可用宽度（实测 360 宽溢出 50px。
                // 280 宽溢出 130px）。`Wrap` 负责左右分列 / 窄屏折行，左段再用
                // **单个 `Text.rich`**（而不是内嵌 `Row`）—— `Row` 永远不会自己换行，
                // 而 `Text` 会在放不下时软换行，极端窄屏也不会溢出。
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: FluentSpacing.md,
                  runSpacing: FluentSpacing.xs,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '已修 ${creditText(c.earned)}',
                            style: FluentType.subtitle.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${creditText(c.required)} 学分',
                            style: FluentType.body.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      c.satisfied
                          ? '已修完'
                          : '还差 ${creditText(c.remaining)} 学分',
                      style: FluentType.bodyStrong.copyWith(
                        color: c.satisfied ? p.success : p.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.sm),
                FluentProgressBar(
                  value: c.ratio,
                  secondary: c.inProgressRatio,
                  tone: c.satisfied ? p.success : null,
                  semanticLabel: '必修课完成度',
                ),
                if (c.inProgress > 0) ...[
                  const SizedBox(height: FluentSpacing.sm),
                  _InProgressLine(
                    text: '另有 ${creditText(c.inProgress)} 学分已选未考（还没出成绩）',
                    tone: p.accent,
                  ),
                ],
                const SizedBox(height: FluentSpacing.sm),
                Text(
                  '培养方案共 ${c.totalCount} 门必修课，已修 ${c.doneCount} 门',
                  style: FluentType.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          if (pending.isNotEmpty) ...[
            const FluentDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FluentSpacing.md,
                FluentSpacing.sm,
                FluentSpacing.lg,
                0,
              ),
              // 同上一处：`Row` + `Spacer` 在极窄屏放不下「按钮 + 还差 N 学分」，
              // 用 `Wrap` 让右侧那句自己折到下一行。
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: FluentSpacing.md,
                runSpacing: FluentSpacing.xs,
                children: [
                  FluentButton(
                    label: _expanded ? '收起' : '查看还差 ${pending.length} 门',
                    icon: _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    dense: true,
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  Text(
                    '还差 ${creditText(
                      pending.fold<double>(0, (s, e) => s + e.credit),
                    )} 学分',
                    style: FluentType.caption.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
            if (_expanded)
              for (final course in pending)
                FluentListRow(
                  title: course.name,
                  description: course.category,
                  trailing: _CreditPair(
                    top: '${creditText(course.credit)} 学分',
                    bottom: course.failed
                        ? (course.score == null
                              ? '挂科'
                              : '挂科 ${course.scoreText}')
                        : course.inProgress
                        ? '在修'
                        : '未修',
                    bottomColor: course.failed
                        ? p.critical
                        : course.inProgress
                        ? p.accent.withValues(alpha: 0.70)
                        : p.textTertiary,
                  ),
                  minHeight: 44,
                ),
          ],
        ],
      ),
    );
  }
}

/// 一门选修要求项：标题 + 口径 + 已修/要求 + 进度条 + 计入的课程。
class ElectiveProgressRow extends StatelessWidget {
  const ElectiveProgressRow({super.key, required this.index, required this.item});

  final int index;
  final CreditProgressItem item;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final tone = item.satisfied ? p.success : p.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.md,
        vertical: FluentSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FluentIndexBadge(index: index),
              const SizedBox(width: FluentSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: FluentType.body.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Text(
                      _descriptionOf(item),
                      style: FluentType.caption.copyWith(
                        color: p.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluentSpacing.md),
              _CreditPair(
                top: '${creditText(item.counted)} / ${creditText(item.required)}',
                bottom: item.satisfied
                    ? '已满足'
                    : '还差 ${creditText(item.remaining)}',
                bottomColor: tone,
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.md),
          FluentProgressBar(
            value: item.ratio,
            secondary: item.inProgressRatio,
            tone: item.satisfied ? p.success : null,
            semanticLabel: '${item.title}完成度',
          ),
          if (item.inProgress > 0) ...[
            const SizedBox(height: FluentSpacing.sm),
            _InProgressLine(
              text:
                  '在修 ${creditText(item.inProgress)} 学分（${item.inProgressCourses.map((c) => c.name).join('、')}）',
              tone: p.accent,
            ),
          ],
          if (item.courses.isNotEmpty) ...[
            const SizedBox(height: FluentSpacing.sm),
            Text(
              '计入：${item.courses.map(_courseLabel).join(' · ')}',
              style: FluentType.caption.copyWith(color: p.textSecondary),
            ),
          ],
          if (item.overflow > 0) ...[
            const SizedBox(height: FluentSpacing.xs),
            Text(
              '已超出 ${creditText(item.overflow)} 学分（不抵扣其它项）',
              style: FluentType.caption.copyWith(color: p.cautionDeep),
            ),
          ],
        ],
      ),
    );
  }

  String _descriptionOf(CreditProgressItem item) {
    final parts = <String>[item.rule];
    if (item.poolCount > 0) {
      parts.add('可选 ${item.poolCount} 门 · 共 ${creditText(item.poolCredits)} 学分');
    }
    return parts.join(' · ');
  }

  String _courseLabel(CreditProgressCourse c) =>
      '${c.name} ${creditText(c.earned)}';
}

/// 实践环节进度卡：军训 / 实习实训 / 论文设计 / 科研创新实践。
///
/// 与必修卡的区别：项数很少（本专业 4 项），所以**直接全列**，不做展开收起。
class PracticeProgressCard extends StatelessWidget {
  const PracticeProgressCard({super.key, required this.progress});

  final PracticeCreditProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final pr = progress;

    if (!pr.available) {
      return const FluentCard(
        padding: EdgeInsets.all(FluentSpacing.lg),
        child: FluentInfoBar(
          message: '拿不到本专业的实践环节表（教务「培养方案 → 实践环节」那一页）。'
              '军事训练、毕业实习这类环节统计不了。',
        ),
      );
    }

    return FluentCard(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.lg,
              vertical: FluentSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: FluentSpacing.md,
                  runSpacing: FluentSpacing.xs,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '已修 ${creditText(pr.earned)}',
                            style: FluentType.subtitle.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${creditText(pr.required)} 学分',
                            style: FluentType.body.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      pr.satisfied
                          ? '已修完'
                          : '还差 ${creditText(pr.remaining)} 学分',
                      style: FluentType.bodyStrong.copyWith(
                        color: pr.satisfied ? p.success : p.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.sm),
                FluentProgressBar(
                  value: pr.ratio,
                  secondary: pr.inProgressRatio,
                  tone: pr.satisfied ? p.success : null,
                  semanticLabel: '实践环节完成度',
                ),
                if (pr.inProgress > 0) ...[
                  const SizedBox(height: FluentSpacing.sm),
                  _InProgressLine(
                    text: '另有 ${creditText(pr.inProgress)} 学分已选未考（还没出成绩）',
                    tone: p.accent,
                  ),
                ],
                const SizedBox(height: FluentSpacing.sm),
                Text(
                  '共 ${pr.totalCount} 个环节，已修 ${pr.doneCount} 个',
                  style: FluentType.caption.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          const FluentDivider(),
          for (var i = 0; i < pr.stages.length; i++) ...[
            if (i > 0) const FluentDivider(),
            FluentListRow(
              leading: Icon(
                pr.stages[i].done
                    ? Icons.check_circle_outline
                    : pr.stages[i].failed
                    ? Icons.cancel_outlined
                    : pr.stages[i].inProgress
                    ? Icons.timelapse
                    : Icons.radio_button_unchecked,
                size: 18,
                color: pr.stages[i].done
                    ? p.success
                    : pr.stages[i].failed
                    ? p.critical
                    : pr.stages[i].inProgress
                    ? p.accent.withValues(alpha: 0.70)
                    : p.textTertiary,
              ),
              title: pr.stages[i].name,
              description: _stageDescription(pr.stages[i]),
              trailing: _CreditPair(
                top: '${creditText(pr.stages[i].credit)} 学分',
                bottom: pr.stages[i].done
                    ? '已修'
                    : pr.stages[i].failed
                    ? '挂科'
                    : pr.stages[i].inProgress
                    ? '在修'
                    : '未修',
                bottomColor: pr.stages[i].done
                    ? p.success
                    : pr.stages[i].failed
                    ? p.critical
                    : pr.stages[i].inProgress
                    ? p.accent.withValues(alpha: 0.70)
                    : p.textTertiary,
              ),
              minHeight: 44,
            ),
          ],
        ],
      ),
    );
  }

  String _stageDescription(PracticeStageState s) {
    final parts = <String>[
      if (s.category.isNotEmpty) s.category,
      if (s.semester.isNotEmpty) s.semester,
      if (s.code.isNotEmpty) s.code,
    ];
    return parts.join(' · ');
  }
}

/// 「不计入总学分」卡：学校文件明说这些课不算毕业学分（如大学生安全教育）。
///
/// 与 [UnmatchedCoursesCard] 分开：那边是「我们归不了类」，这边是「规定了不算」。
class NotCountedCoursesCard extends StatelessWidget {
  const NotCountedCoursesCard({super.key, required this.courses});

  final List<CreditProgressCourse> courses;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return FluentCard(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) const FluentDivider(),
            FluentListRow(
              title: courses[i].name,
              description: '学校文件规定不计入总学分，只作毕业资格审核依据',
              leading: Icon(
                Icons.info_outline,
                size: 18,
                color: p.textTertiary,
              ),
              trailing: _CreditPair(
                top: '${creditText(courses[i].earned)} 学分',
                bottom: courses[i].code.isEmpty ? '无课程代码' : courses[i].code,
                bottomColor: p.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 未归类课程卡：列出没被算进任何要求项的课 + 原因。
class UnmatchedCoursesCard extends StatelessWidget {
  const UnmatchedCoursesCard({super.key, required this.courses});

  final List<UnmatchedCourse> courses;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return FluentCard(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) const FluentDivider(),
            FluentListRow(
              title: courses[i].course.name,
              description: courses[i].reason,
              leading: Icon(
                Icons.help_outline,
                size: 18,
                color: p.textTertiary,
              ),
              trailing: _CreditPair(
                top: '${creditText(courses[i].course.earned)} 学分',
                bottom: courses[i].course.code.isEmpty
                    ? '无课程代码'
                    : courses[i].course.code,
                bottomColor: p.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 尾部口径说明（逐条）。
class CreditProgressNotes extends StatelessWidget {
  const CreditProgressNotes({super.key, required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
            child: Text(
              '· $note',
              style: FluentType.caption.copyWith(color: p.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// 行尾的两行数字（上行主值、下行状态）。
class _CreditPair extends StatelessWidget {
  const _CreditPair({
    required this.top,
    required this.bottom,
    required this.bottomColor,
  });

  final String top;
  final String bottom;
  final Color bottomColor;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(top, style: FluentType.bodyStrong.copyWith(color: p.textPrimary)),
        const SizedBox(height: FluentSpacing.xs),
        Text(bottom, style: FluentType.caption.copyWith(color: bottomColor)),
      ],
    );
  }
}
