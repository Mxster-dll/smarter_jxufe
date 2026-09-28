/// 分数估计 · 课程详情页的三类卡片。
///
/// 用户口径（2026-09-26）：「估计页改成这样：（以下每个序号代表一个卡片）
/// 2. 当前课程成绩现状（对目前的占比卡片增强，不仅显示占比，还要显示各部分成绩；
///    然后此部分还要支持 1.给出预估期末成绩，计算最终成绩；2.给出预估总评，
///    反推期末成绩范围）；2、3 中间要显示一个标题"平时成绩"；3. 作业成绩卡片
///    （让用户选择，可以直接取消此卡片，也就是说这门课没有作业）；
/// 4-x. 若干平时成绩构成卡片，是用户自己添加的，添加按钮也是一个卡片，
///    显示在此部分的最后一个」。
///
/// 落到本文件：
/// - [GeCourseStatusCard] = 卡片 2（占比条 + 各部分成绩 + 期末预估 + 目标反推）；
/// - [GePartCard] = 卡片 3 / 4-x（一个平时分项一张卡；「作业」那张只是多一行学习通读数
///   与一枚来源芯片，**不再是默认存在的独立卡片** —— 用户从「添加平时分项」浮窗
///   里选「作业」预设才出现，删掉它这门课就是没有作业）；
/// - [GeAddPartCard] = 末尾那张添加卡。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/app_theme.dart';
import '../../../design/feature_palette.dart';
import '../domain/ge_chaoxing_sync.dart';
import '../domain/ge_engine.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';
import 'ge_ratio_bar.dart';

/// 卡片 2 · 当前课程成绩现状。
///
/// 两个输入行各自独立：**给期末 → 算最终成绩**、**给目标总评 → 反推期末范围**。
/// 两个控制器由调用方（课程详情页 State）持有与释放 —— 本件不自建、不 dispose。
class GeCourseStatusCard extends StatelessWidget {
  final GeCourse course;

  /// 当前测算快照（`geCalc(course)`；由调用方算好传入，避免一处算两遍）。
  final GeCalc calc;

  final TextEditingController finalCtrl;
  final TextEditingController goalCtrl;

  /// 培养方案学分与课程学分不一致时的提示（null = 不提示）。
  final String? planCreditHint;

  /// 期末分变更（null = 清空）。
  final ValueChanged<double?> onFinalChanged;

  /// 目标总评输入变化：调用方 `setState` 让反推结果跟着重算。
  final VoidCallback onGoalChanged;

  /// 点占比条 / 标题右侧 → 打开比例设置弹层。
  final VoidCallback onOpenRatio;

  const GeCourseStatusCard({
    super.key,
    required this.course,
    required this.calc,
    required this.finalCtrl,
    required this.goalCtrl,
    required this.onFinalChanged,
    required this.onGoalChanged,
    required this.onOpenRatio,
    this.planCreditHint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = 100 - course.dailyPercent;
    final hintStyle = TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpenRatio,
              borderRadius: BorderRadius.circular(6),
              child: geCardTitle(
                context,
                text: '当前课程成绩现状',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${geFmt(course.credits)} 学分 · 平时 '
                      '${geFmt(course.dailyPercent)}% / 期末 ${geFmt(percent)}%',
                      style: hintStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.tune, size: 14, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (planCreditHint != null) ...[
              const SizedBox(height: 2),
              Text(
                planCreditHint!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: fp(context).cardAccent,
                ),
              ),
            ],
            const SizedBox(height: 10),
            GeRatioChart(
              parts: course.parts,
              dailyPercent: course.dailyPercent,
              onTap: onOpenRatio,
            ),
            const SizedBox(height: 12),
            _scoreBlock(context),
            const SizedBox(height: 12),
            _rowLabel(context, '预估期末 · 算最终成绩'),
            const SizedBox(height: 6),
            _finalRow(context),
            const SizedBox(height: 12),
            _rowLabel(context, '预估总评 · 反推期末范围'),
            const SizedBox(height: 6),
            _goalRow(context),
            const SizedBox(height: 10),
            _goalResult(context),
          ],
        ),
      ),
    );
  }

  Widget _rowLabel(BuildContext context, String text) => Text(
    text,
    style: _geHintSmall(
      Theme.of(context).colorScheme,
    ).copyWith(fontWeight: FontWeight.w600),
  );

  /// 成绩现状块：平时 / 期末两块折算 + 总评 + 逐分项一行读数。
  Widget _scoreBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fp(context).cardAccent;
    final dp = course.dailyPercent;
    final fw = 100 - dp;
    final f = course.finalScore;
    final total = geTotalWithFinal(calc, f);
    final (lo, hi) = geTotalRange(calc);
    final under = total != null && total < 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricRow(
            context,
            label: '平时',
            expr: '均分 ${geFmt(calc.dailyMean)} × ${geFmt(dp)}%',
            value: '${geFmt(calc.dailyContrib)} 分',
          ),
          _metricRow(
            context,
            label: '期末',
            expr: f == null
                ? '未填 · 按 0 ~ 100 计'
                : '预估 ${geFmt(f, decimals: 1)} × ${geFmt(fw)}%',
            value: f == null
                ? '${geFmt(lo - calc.dailyContrib)} ~ '
                      '${geFmt(hi - calc.dailyContrib)} 分'
                : '${geFmt(calc.finalContrib(f))} 分',
          ),
          Divider(height: 14, color: scheme.outlineVariant),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                total == null
                    ? '${geFmt(lo)} ~ ${geFmt(hi)}'
                    : geFmt(total, decimals: 1),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  color: under ? scheme.error : accent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '分',
                style: _geHintSmall(scheme),
              ),
              const Spacer(),
              Text(
                total == null ? '总评区间（期末 0~100）' : '估计总评（满分 100）',
                style: _geHintSmall(scheme),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ((total ?? lo) / 100).clamp(0.0, 1.0),
              minHeight: 7,
              color: under ? scheme.error : accent,
              backgroundColor: AppColors.tint(context, accent, 0.12),
            ),
          ),
          if (course.parts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '各部分',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _partsBreakdown(context)),
              ],
            ),
          ],
          if (under) ...[
            const SizedBox(height: 6),
            Text(
              '低于及格线：距 60 还差 ${geFmt(60 - total)} 分（可看下方反推）',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 逐分项一行读数：`作业 13.9/15 · 考勤 5/5 · 表现 2.5/10`（不可编辑，改分项在卡片 4-x）。
  Widget _partsBreakdown(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final p in course.parts)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${p.name} ',
                style: _geHintSmall(scheme),
              ),
              Text(
                '${geFmt(gePartScore(p), decimals: 2)}/'
                '${geFmt(p.cap, decimals: 2)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _metricRow(
    BuildContext context, {
    required String label,
    required String expr,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              expr,
              style: _geHintSmall(scheme),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// 期末预估输入行（预设 + 清空）。
  Widget _finalRow(BuildContext context) {
    final finalScore = course.finalScore;
    return Row(
      children: [
        const Text('期末分', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: TextField(
            controller: finalCtrl,
            keyboardType: TextInputType.number,
            maxLength: 3,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              suffixText: '分',
              suffixStyle: TextStyle(fontSize: 12),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v.trim().isEmpty) {
                onFinalChanged(null);
                return;
              }
              var n = double.tryParse(v) ?? 0;
              if (n > 100) {
                n = 100;
                finalCtrl.text = '100';
                finalCtrl.selection = TextSelection.collapsed(offset: 3);
              }
              onFinalChanged(n);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final preset in const [60.0, 70.0, 80.0, 90.0])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    geFmt(preset),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () {
                    finalCtrl.text = geFmt(preset, decimals: 1);
                    onFinalChanged(preset);
                  },
                ),
              if (finalScore != null)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.close, size: 14),
                  label: const Text('清空', style: TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    finalCtrl.text = '';
                    onFinalChanged(null);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 目标总评输入行（预设）。
  Widget _goalRow(BuildContext context) => Row(
    children: [
      const Text('目标总评', style: TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      SizedBox(
        width: 76,
        child: TextField(
          controller: goalCtrl,
          keyboardType: TextInputType.number,
          maxLength: 3,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            isDense: true,
            counterText: '',
            suffixText: '分',
            suffixStyle: TextStyle(fontSize: 12),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onGoalChanged(),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final g in const [60.0, 70.0, 80.0, 90.0, 95.0])
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  g == 60 ? '60 及格' : geFmt(g),
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () {
                  goalCtrl.text = geFmt(g);
                  onGoalChanged();
                },
              ),
          ],
        ),
      ),
    ],
  );

  /// 反推结果：给目标总评 → 期末需要落在哪个区间。
  Widget _goalResult(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final goal = double.tryParse(goalCtrl.text.trim());

    if (course.parts.isEmpty) {
      return Text(
        '先添加平时分项并录入进度，即可反推期末需要考多少分。',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    if (goal == null || goal <= 0 || goal > 100) {
      return Text(
        '输入 0~100 的目标总评，实时反推期末需要多少分。',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }

    final need = geRequiredFinal(calc, goal);
    final fw = calc.finalWeight;
    final hasFinal = fw > 0;
    final gain = geFmt(calc.dailyCeiling - calc.dailyContrib, decimals: 1);

    final Color resultColor;
    final String headline;
    final String detail;

    switch (need.status) {
      case GeGoalStatus.reached:
        resultColor = AppColors.success(context);
        headline = '平时折算已达目标 · 期末区间 0 ~ 100 分';
        detail =
            '即使期末 0 分，总评也有 '
            '${geFmt(calc.dailyContrib)} 分（≥ 目标 ${geFmt(goal)}）。';
      case GeGoalStatus.ok:
        resultColor = scheme.primary;
        headline =
            '期末需 ≥ ${geFmt(need.requiredFinal, decimals: 1)} 分'
            '（即 ${geFmt(need.requiredFinal, decimals: 1)} ~ 100 分）';
        detail =
            '平时已折算 ${geFmt(calc.dailyContrib)} 分，距目标 '
            '${geFmt(goal)} 还差 ${geFmt(goal - calc.dailyContrib)} 总评点；'
            '期末占比 ${geFmt(100 - course.dailyPercent)}%，'
            '每考 1 分得 ${geFmt(fw * 100, decimals: 0)}%。';
      case GeGoalStatus.recoverByDaily:
        resultColor = AppColors.caution(context);
        headline = hasFinal
            ? '期末满分也差 ${geFmt(need.dailyGap, decimals: 1)} 分'
            : '总分还差 ${geFmt(need.dailyGap, decimals: 1)} 分';
        detail = hasFinal
            ? '期末按满分 100 计仍差 ${geFmt(need.dailyGap, decimals: 1)} 总评点，'
                  '但平时还能再挣的分项（正计数 / 直接分数）拿满可补 +$gain 分。'
            : '平时还能再挣的分项（正计数 / 直接分数）拿满可补 +$gain 分'
                  '（该课期末不占比例）。';
      case GeGoalStatus.impossible:
        resultColor = scheme.error;
        headline = hasFinal
            ? '上限仅 ${geFmt(need.maxTotal, decimals: 1)} 分，无法达到 ${geFmt(goal)}'
            : '平时全部做满也仅 ${geFmt(need.maxTotal, decimals: 1)} 分';
        detail = hasFinal
            ? '即使期末 100 分、剩余平时分项全部做满，总评最高也只有 '
                  '${geFmt(need.maxTotal, decimals: 1)} 分。'
            : '平时剩余分项全部做满后总评最高 '
                  '${geFmt(need.maxTotal, decimals: 1)} 分（该课期末不占比例）。';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tint(context, resultColor, 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resultColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: resultColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片 3 / 4-x · 单个平时成绩构成卡片（点卡改配置，步进器加减计数）。
class GePartCard extends StatelessWidget {
  final GeCourse course;
  final GePart part;

  /// 学习通这门课已批作业条数（0 = 没有 / 没缓存）。
  final int chaoxingCount;

  /// 「学习通同步」芯片的悬浮说明（取数时刻等）。
  final String chaoxingHint;

  final VoidCallback onTap;

  /// 步进：+1 / −1（正计数上下移动完成数；负计数上下移动剩余数）。
  final ValueChanged<int> onBump;

  const GePartCard({
    super.key,
    required this.course,
    required this.part,
    required this.onTap,
    required this.onBump,
    this.chaoxingCount = 0,
    this.chaoxingHint = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = gePartRatio(part);
    final score = gePartScore(part);
    final isDown = part.mode == GePartMode.down;
    final isScore = part.mode == GePartMode.score;
    final isChaoxing = part.source == gePartSourceChaoxing;
    final missed = part.target - part.current;

    final countLine = isChaoxing
        ? geChaoxingPartLine(course, part, chaoxingCount)
        : isScore
        ? '得分 ${geFmt(part.score, decimals: 2)} / 满分 ${part.target}'
        : isDown
        ? (missed <= 0
              ? '尚未扣减 · 剩余 ${part.current} / ${part.target}'
              : '已扣 $missed · 剩余 ${part.current} / ${part.target}')
        : '已完成 ${part.current} / ${part.target}';

    final ratioLine =
        '得分率 ${geFmt(ratio * 100, decimals: 1)}%'
        ' · 折算 ${geFmt(score, decimals: 2)} / ${geFmt(part.cap, decimals: 2)} 分';

    // 步进按钮语义随方向翻转
    final minusTip = isDown ? '记一次扣减（如缺勤）' : '撤销一次完成';
    final plusTip = isDown ? '撤销一次扣减' : '记一次完成（可超目标）';
    final minusEnabled = part.current > 0;
    final plusEnabled = isDown ? part.current < part.target : true;

    Widget stepBtn(
      IconData icon,
      bool enabled,
      String tip,
      VoidCallback onTap,
    ) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 19,
            color: enabled
                ? (isDown ? scheme.error : scheme.primary)
                : scheme.outlineVariant,
          ),
        ),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              GeModeBadge(mode: part.mode),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            part.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GeModeChip(mode: part.mode),
                        if (isChaoxing) ...[
                          const SizedBox(width: 6),
                          GeChaoxingChip(hint: chaoxingHint),
                        ],
                        if (part.note.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              part.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countLine,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      ratioLine,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ratio >= 1
                            ? AppColors.success(context)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (isScore)
                // 直接分数项没有步进语义：点整卡弹窗改分。
                Tooltip(
                  message: '点击修改得分',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 19,
                      color: scheme.outline,
                    ),
                  ),
                )
              else ...[
                stepBtn(
                  Icons.remove_circle_outline,
                  minusEnabled,
                  minusTip,
                  () => onBump(-1),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${part.current}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                stepBtn(
                  Icons.add_circle_outline,
                  plusEnabled,
                  plusTip,
                  () => onBump(1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 学习通来源分项的第二行：条数 + 均分 + 占比（作业在平时 / 总评里的份额）。
String geChaoxingPartLine(GeCourse course, GePart part, int count) {
  final avg = geFmt(part.score, decimals: 1);
  final head = count > 0 ? '学习通作业 $count 条 · 均分 $avg' : '学习通作业均分 $avg';
  final daily = geFmt(gePartDailyShare(course, part), decimals: 1);
  final total = geFmt(gePartTotalShare(course, part), decimals: 1);
  return '$head · 占平时 $daily%（总评 $total%）';
}

/// 平时成绩区最后一张卡：添加平时分项（作业 / 考勤 / 课堂表现 / 期中测验 / 实验报告 …）。
class GeAddPartCard extends StatelessWidget {
  final VoidCallback onTap;

  /// 一个分项都没有时把用法说明写在卡片里（原来挂在「平时分项」卡的空态上）。
  final bool showEmptyHint;

  const GeAddPartCard({
    super.key,
    required this.onTap,
    this.showEmptyHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fp(context).cardAccent;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      color: AppColors.tint(context, accent, 0.05),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 20, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    '添加平时分项',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '作业 / 考勤 / 课堂表现 / 期中测验 / 实验报告',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (showEmptyHint) ...[
                const SizedBox(height: 6),
                Text(
                  '还没有分项。选「作业」会接上学习通里这门课的已批作业均分；'
                  '考勤（负计数，从总课次向下扣）、课堂打卡（正计数，从 0 累计）、'
                  '期中测验或实验报告（直接分数，填满分与得分）也都有预设。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片里的灰字小字（字号 11.5 + `onSurfaceVariant`）—— 多处复用，别每处再拼一遍。
TextStyle _geHintSmall(ColorScheme scheme) =>
    TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);
