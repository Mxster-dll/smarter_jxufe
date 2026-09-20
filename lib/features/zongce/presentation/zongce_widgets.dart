/// 综测页「渲染工具箱」（2026-09-20 从 `zongce_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `_ZongceScreenState` 的 27 个渲染成员（约 1250 行）—— 逐个核实**全是纯函数**：
/// 不碰 `setState` / `_store` / `_manual` / `ref` / `widget`，最多只用显式回调
/// （`ValueChanged<double> onChanged` / `VoidCallback onTap`），故整体外提是**零语义改动**的搬运。
/// 三处随行件（都是 State 的字段 / 取值器，靠 State 的隐式 `context`）：
/// `Color get _schemeColor` → **`zcSchemeColor(context)` 函数**；`static const _yuColors` → 顶层
/// **`zcYuColors`**；`zcCheck` 补显式 `BuildContext context` 首参。
/// 唯一会写库的 `zcResultCard` 原调 `_editWeights(r.weights)` → 改成**注入回调** `onEditWeights`。
/// 命名：私有 `_x` → 公开 `zcX`（`_` 是库私有，跨文件不可见）。`zongce_screen.dart` 仍是页面本体
/// （数据 / 生命周期 / 五育卡组装 / 结果卡调用）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/design/status_palette.dart';

import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_tip_data.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_weights.dart';

import 'package:smarter_jxufe/features/zongce/presentation/widgets/rule_tip.dart';

import 'package:smarter_jxufe/shared/widgets/count_stepper.dart';

/// 原 `_ZongceScreenState._yuColors`。
const Map<String, Color> zcYuColors = <String, Color>{
    'd': ZongceTone.deyu,
    'z': ZongceTone.zhiyu,
    't': ZongceTone.tiyu,
    'm': ZongceTone.meiyu,
    'l': ZongceTone.laoyu,
  };

/// 原 `_ZongceScreenState._materialRuleIds`。
const Map<ZcTypeId, List<String>> zcMaterialRuleIds = <ZcTypeId, List<String>>{
    ZcTypeId.deed: ['r22'],
    ZcTypeId.eduCon: ['r23'],
    ZcTypeId.eduPart: ['r24'],
    ZcTypeId.servicePost: ['r27', 'r25', 'r26'],
    ZcTypeId.honorP: ['r28'],
    ZcTypeId.honorG: ['r29', 'r30'],
    ZcTypeId.contest: ['r77', 'r37', 'r38', 'r39', 'r40', 'r41'],
    ZcTypeId.paper: ['r42', 'r43'],
    ZcTypeId.foreign: ['r44'],
    ZcTypeId.startup: ['r45'],
    ZcTypeId.sportComp: ['r54'],
    ZcTypeId.psych: ['r55'],
    ZcTypeId.sportTeam: ['r56'],
    ZcTypeId.artsComp: ['r60'],
    ZcTypeId.media: ['r61'],
    ZcTypeId.artAct: ['r62'],
    ZcTypeId.social: ['r67'],
    ZcTypeId.laborAct: ['r68'],
    ZcTypeId.dorm: ['r69'],
  };

/// 主题强调色（原 State 的 `Color get _schemeColor => Theme.of(context).colorScheme.primary`）。
Color zcSchemeColor(BuildContext context) => Theme.of(context).colorScheme.primary;

String zcFmt(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// 加权成绩保留 2 位（用户 2026-09-17：「综测页智育用的加权成绩保留 2 位」）。
String zcFmt2(double v) => v.toStringAsFixed(2);

Color zcGradeColor(BuildContext context, ZcGrade g) {
  switch (g) {
    case ZcGrade.ok:
      return ZongceTone.gradeOk;
    case ZcGrade.good:
      return ZongceTone.gradeGood;
    case ZcGrade.pass:
      return ZongceTone.gradePass;
    case ZcGrade.fail:
      return ZongceTone.gradeFail;
  }
}

/// 从计分明细按前缀求合计（徽章数值的权威来源，含 cap/取最高等引擎规则）。
double zcSumDetail(ZcCalcResult r, List<String> prefixes) {
  var s = 0.0;
  for (final d in r.details) {
    for (final p in prefixes) {
      if (d.label.startsWith(p)) {
        s += d.value;
        break;
      }
    }
  }
  return s;
}

Widget zcResultCard(
  BuildContext context,
  ZcCalcResult r,
  List<ZcMaterial> mats, {
  required void Function(ZcWeights) onEditWeights,
}) {
  final scheme = Theme.of(context).colorScheme;
  final avg = r.average;
  final rows = [
    ('德育', r.deyu, r.gD),
    ('智育', r.zhiyu, r.gZ),
    ('体育', r.tiyu, r.gT),
    ('美育', r.meiyu, r.gM),
    ('劳育', r.laoyu, r.gL),
  ];
  return zcCard(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.tint(context, scheme.primary, 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.assessment_outlined,
                color: scheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  zcLabelTip(
                    context,
                    '测评结果',
                    tipKey: 'overall',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '填写/录入后自动计算，实时更新',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
            zcGradeChip(context, r.overall, big: true),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final it in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              it.$1,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.outline,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${zcFmt(it.$2)} 分',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: zcGradeColor(
                                context,
                                it.$3,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              it.$3.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: zcGradeColor(context, it.$3),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 总评成绩 = 五育加权（用户 2026-09-18：「综测不是直接算平均分，
                // 而是有一个总评成绩，这个成绩的占比由班主任定，应该让用户自行
                // 设置」）→ 点胶囊弹占比设置；平均分降级为下面那行小字。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '总评成绩',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    KeyedSubtree(
                      key: const Key('zcTotalChip'),
                      child: zcValueTap(
                        context,
                        text: '${zcFmt2(r.total)} 分',
                        onTap: () => onEditWeights(r.weights),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '占比 ${r.weights.label}',
                  key: const Key('zcTotalWeightsLabel'),
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
                const SizedBox(height: 4),
                zcStatLine(
                  '五育平均',
                  '${zcFmt(avg)} 分',
                  context: context,
                ),
                const SizedBox(height: 4),
                zcStatLine(
                  '加权成绩',
                  r.weightMissing ? '未获取' : '${zcFmt2(r.weightUsed)} 分',
                  context: context,
                ),
                const SizedBox(height: 4),
                zcStatLine('材料条数', '${mats.length} 条', context: context),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

Widget zcStatLine(
  String label,
  String value, {
  required BuildContext context,
  bool emphasize = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 11.5, color: scheme.outline)),
      const SizedBox(width: 8),
      Text(
        value,
        style: TextStyle(
          fontSize: emphasize ? 16 : 12.5,
          fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          color: emphasize ? zcSchemeColor(context) : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

Widget zcGradeChip(BuildContext context, ZcGrade g, {bool big = false}) {
  final color = zcGradeColor(context, g);
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: big ? 14 : 8,
      vertical: big ? 6 : 2,
    ),
    decoration: BoxDecoration(
      color: AppColors.tint(context, color, 0.12),
      borderRadius: BorderRadius.circular(big ? 10 : 6),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '综合等次',
          style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
        ),
        Text(
          g.label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: big ? 16 : 11,
          ),
        ),
      ],
    ),
  );
}

/// 育卡外框：白卡 + 语义色图标头 + 实时分数徽章。
Widget zcYuCard(
  BuildContext context, {
  required String dim,
  required IconData icon,
  required String name,
  required String meta,
  required double score,
  required ZcGrade grade,
  required List<Widget> sections,
  String? headerTipKey,
}) {
  final scheme = Theme.of(context).colorScheme;
  final color = zcYuColors[dim] ?? scheme.primary;
  return Container(
    decoration: BoxDecoration(
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 卡片头（同原网页 .card>header）
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.tint(context, color, 0.045),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            border: Border(
              bottom: BorderSide(color: AppColors.tintBorder(context, color, 0.16)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, color, 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    zcLabelTip(
                      context,
                      name,
                      tipKey: headerTipKey,
                      tipColor: color,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      meta,
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              // 实时分数徽章（同原网页 header .live）
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      zcFmt(score),
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' 分 · ${grade.label}',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections,
          ),
        ),
      ],
    ),
  );
}

/// 把若干个条款点 key 合成一个悬停按钮的内容（同一行既挂分区点又挂行点）。
List<String> zcTipIdsOf(List<String> keys) => [
  for (final k in keys) ...?zcTipRefs[k],
];

/// 行首：标签文字 + **紧跟在文字右侧**的条款依据悬停按钮。
///
/// 用户 2026-09-18：「对于综测页所有的悬浮提示位置都改到左端文本的右侧旁」——
/// 从前 `Row([Expanded(Text(label)), RuleTip, …])` 会把 `?` 推到整行最右端，
/// 与它解释的文字隔了半屏。统一改用本件：`Row(min, [Flexible(Text), ?])`
/// 套在 `Expanded(child: Align(centerLeft, …))` 里 —— 文字与 `?` 贴在一起、
/// 整体靠左，行尾的分值 / 控件仍在最右侧。
Widget zcLabelTip(
  BuildContext context,
  String label, {
  String? tipKey,
  List<String>? tipIds,
  TextStyle? style,
  Color? tipColor,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(label, style: style)),
      if (tipKey != null) RuleTip(tipKey: tipKey, color: tipColor, size: 13.5),
      if (tipKey == null && tipIds != null && tipIds.isNotEmpty)
        RuleTip(ids: tipIds, color: tipColor, size: 13.5),
    ],
  );
}

/// 胶囊内的数值文字（`zcValueTap` 的自适应 / 定宽两个分支共用）。
Widget zcValueTapText(String text, ColorScheme scheme, bool muted) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: muted ? scheme.outline : scheme.primary,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);

/// 数值胶囊（`zcSubRow` 的 trailing）——基础分这类不可改的分数用它。
///
/// 用户 2026-09-18 四轮：「我希望显示胶囊而不是卡片，就和其他部分的加分汇总
/// 一样」→ 与分区徽章 [.zcBadge] **同款**：主色淡底（`AppColors.tint` 0.09）
/// + 圆角 999 + 主色 w700 字。旧的「圆角 8 + 细描边方框」（看着像卡片）已弃用。
Widget zcStaticChip(BuildContext context, String text, {Color? color}) {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
    decoration: BoxDecoration(
      color: AppColors.tint(context, c, 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// 单行分区（用户 2026-09-18：「基础分、民主评议分都只显示一行内容，都只有一个
/// 标题行，标题行最右侧显示分数，然后评议分点击可修改」）。
///
/// 行 = 序号圆块 + 标题 +「紧跟标题的条款按钮」+ 最右端的 [trailing]
/// （`60 分` 这样的胶囊，或可点的 `zcTapNumber`）。
///
/// ⚠ 这一行**不挂任何纯文字 Tooltip**（用户 2026-09-18 四轮：「我希望只有悬浮在
/// 指定区域的悬浮提示，没有另一个悬浮提示……那种卡片式的悬浮提示保留」）——
/// 「思想端正、遵纪守法……即认定」这类说明文字已整体撤掉，悬停只剩标题右侧的
/// `?`（[RuleTip] 卡片）。
Widget zcSubRow(
  BuildContext context,
  int? no,
  String title, {
  String? tipKey,
  List<String>? tipIds,
  Color? color,
  required Widget trailing,
}) {
  final c = color ?? zcSchemeColor(context);
  final row = Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Row(
      children: [
        // 序号方块；`no == null` 时同一 18px 槽位里画一个小圆点 —— 用于「挂在
        // 分区下面、但不需要单独编号」的行（如劳育「志愿服务时长」）。
        SizedBox(
          width: 18,
          height: 18,
          child: no == null
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$no',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: zcLabelTip(
              context,
              title,
              tipKey: tipKey,
              tipIds: tipIds,
              tipColor: c,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    ),
  );
  return row;
}

/// 分区标题（同原网页 .subhead：序号圆块 + 名称 + 可选徽章/右侧提示）。
Widget zcSub(
  BuildContext context,
  int no,
  String title, {
  Widget? badge,
  String? tip,
  String? tipKey,
  Color? color,
}) {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? zcSchemeColor(context);
  return Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            '$no',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: zcLabelTip(
              context,
              title,
              tipKey: tipKey,
              tipColor: c,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ?badge,
        if (tip != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              tip,
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
          ),
      ],
    ),
  );
}

/// 徽章（同原网页 .sub-badge：蓝底圆角胶囊；负值红、满值绿）。
Widget zcBadge(BuildContext context, String text, {Color? color}) {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
    decoration: BoxDecoration(
      color: AppColors.tint(context, c, 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

/// 一个编辑行：label（可选实时分值）+ 控件（输入 + 右侧灰规则说明）。
/// [tipKey] 非空时在标题行尾加「条款依据」悬停按钮。
Widget zcEditRow(
  BuildContext context,
  String label, {
  String? scoreText,
  Color? scoreColor,
  String? tipKey,
  required Widget child,
  String? note,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: zcLabelTip(
                  context,
                  label,
                  tipKey: tipKey,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
            ),
            if (scoreText != null)
              Text(
                scoreText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scoreColor ?? zcSchemeColor(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            child,
            if (note != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.outline,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

/// 智育「加分项」的一个小项（用户 2026-09-18：四类分开显示）。
///
/// 行 = 小项名 + 条款依据悬停 + 该小项分值；下面接该小项的材料行，
/// 一条都没有时给「去材料库录入」入口。**分值一律取引擎明细**
/// （`智育 · 学科竞赛`/`智育 · 论文/专利`/`智育 · 外语`/`智育 · 创业`），
/// 界面层不重算 —— 四小项之和 == 加分项总徽章 `extra`。
Widget zcExtraItem(
  BuildContext context, {
  required String label,
  required double value,
  required List<String> tipIds,
  required List<ZcMaterial> items,
  Set<String> highlightIds = const <String>{},
  Set<String> dimmedIds = const <String>{},
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: zcLabelTip(
                  context,
                  label,
                  tipIds: tipIds,
                  tipColor: scheme.primary,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value > 0 ? '+${zcFmt(value)} 分' : '0 分',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: value > 0 ? scheme.primary : scheme.outline,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          zcGoMaterials(context, text: '暂无该小项证明 · 去材料库录入')
        else
          for (final x in items)
            zcMatRow(
              context,
              x,
              highlighted: highlightIds.contains(x.id),
              dimmed: dimmedIds.contains(x.id),
            ),
      ],
    ),
  );
}

/// 「点击才输入」的数值件（用户 2026-09-18：「民主评议也改成点击才输入」）。
///
/// 页面上**不再常驻输入框**：数值本身是可点的胶囊，点开才弹输入框。
/// 次数类字段另走 `CountStepper`（左右三角增减 + 点数字输入）。
Widget zcValueTap(
  BuildContext context, {
  required String text,
  required VoidCallback onTap,
  String? tag,
  bool muted = false,
  double? width,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fixed = width != null;
  final accent = muted ? scheme.outline : scheme.primary;
  return SizedBox(
    width: width,
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      // 用户 2026-09-18 四轮：与「加分汇总」徽章同款（主色淡底 + 999 圆角），
      // 且**不再挂纯文字 Tooltip** —— 悬停提示只保留标题右侧 `?` 的条款卡片，
      // 可点性由胶囊里的铅笔图标表达。
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppColors.tint(context, accent, 0.09),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          // 自适应宽度（width == null）时 Row 收缩到内容宽 —— 胶囊贴合文字，
          // 与只读的 `zcStaticChip` 观感一致；定宽时仍用 Expanded 把尾巴推右。
          mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (fixed)
              Expanded(child: zcValueTapText(text, scheme, muted))
            else
              zcValueTapText(text, scheme, muted),
            if (tag != null) ...[
              const SizedBox(width: 6),
              zcSourceTag(context, tag),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: 13,
              color: accent.withValues(alpha: 0.75),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 「自动 / 手动」小标（让用户一眼看出这个值是不是自动带入的）。
Widget zcSourceTag(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(
      // 叠在同为主色淡底的数值胶囊上，0.10 会看不见 → 加深到 0.22。
      color: AppColors.tint(context, scheme.primary, 0.22),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
    ),
  );
}

/// 非空数值字段（评议分 / 体测分）：点击 → 弹输入框。
Widget zcTapNumber(
  BuildContext context, {
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
  double min = 0,
  double max = 20,
  bool integer = false,
  String? display,
  String? note,
  double? width,
}) {
  return zcValueTap(
    context,
    text: display ?? (integer ? value.round().toString() : zcFmt(value)),
    width: width,
    tag: note,
    muted: value <= 0,
    onTap: () async {
      final out = await promptNumberValue(
        context,
        title: '输入$label',
        label: label,
        initial: value,
        min: min,
        max: max,
        integer: integer,
        helper: '范围 ${zcFmt(min)} ~ ${zcFmt(max)}',
      );
      if (out.confirmed && !out.cleared && out.value != null) {
        onChanged(out.value!);
      }
    },
  );
}

/// 可空数值字段（加权成绩 / 志愿时长）：手动值 null = 用自动值。
Widget zcTapNumberOpt(
  BuildContext context, {
  required String label,
  required double? value,
  required double? autoValue,
  required ValueChanged<double?> onChanged,
  double min = 0,
  double max = 100,
  String? display,
  double? width,
}) {
  final manual = value != null;
  final shown = value ?? autoValue;
  return zcValueTap(
    context,
    // 手动值优先显示；没有手动值时才用调用方给的自动值文案（加权要 2 位小数）。
    text: manual
        ? zcFmt(value)
        : (display ?? (shown == null ? '未获取' : zcFmt(shown))),
    width: width,
    // 用户 2026-09-18 五轮：「加权和体测成绩不要显示『自动』字样」→
    // 自动带入的值**不挂标**，只有手动覆盖时才挂「手动」。
    tag: manual ? '手动' : null,
    muted: shown == null,
    onTap: () async {
      final out = await promptNumberValue(
        context,
        title: '输入$label',
        label: label,
        initial: value ?? autoValue,
        min: min,
        max: max,
        helper: '范围 ${zcFmt(min)} ~ ${zcFmt(max)}；留空用自动值',
        allowClear: manual,
      );
      if (!out.confirmed) return;
      if (out.cleared) {
        onChanged(null);
      } else if (out.value != null) {
        onChanged(out.value!);
      }
    },
  );
}

/// 下拉选择（在有限宽布局中直接用；卡内/Column 全宽安全）。
Widget zcFieldDrop<T>({
  required Key key,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
  String? label,
}) {
  return DropdownButtonFormField<T>(
    key: key,
    initialValue: value,
    isDense: true,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: const OutlineInputBorder(),
    ),
    items: items,
    onChanged: onChanged,
  );
}

Widget zcCheck(
  BuildContext context,
  String label,
  bool value,
  ValueChanged<bool> onChanged, {
  Color? color,
}) {
  return FilterChip(
    label: Text(label, style: const TextStyle(fontSize: 11.5)),
    selected: value,
    visualDensity: VisualDensity.compact,
    selectedColor: AppColors.tint(context, color ?? zcSchemeColor(context), 0.14),
    checkmarkColor: color ?? zcSchemeColor(context),
    labelStyle: TextStyle(
      color: value ? (color ?? zcSchemeColor(context)) : null,
      fontSize: 11.5,
    ),
    onSelected: onChanged,
  );
}

/// 材料只读行：名称 + 类型·档位 + 分值（自动来自材料库）。
///
/// [highlighted] = 这一条**最终计入了总分**（用户 2026-09-18：「综测智育竞赛
/// 加分要把最终贡献分数的项高亮一下」）；[dimmed] = 有分但被上限截掉、没计入。
Widget zcMatRow(
  BuildContext context,
  ZcMaterial m, {
  bool highlighted = false,
  bool dimmed = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final spec = zcTypeSpecOf[m.typeId];
  final v = zcMaterialValue(m);
  return Opacity(
    opacity: dimmed ? 0.55 : 1,
    child: Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: highlighted
          ? AppColors.tint(context, scheme.primary, 0.10)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.55)
            : AppColors.hairline(context, 0.5),
        width: highlighted ? 1.1 : 1,
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.description_outlined, size: 15, color: scheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      // 外语行标题 = **原文条目名**（`大学英语四级 ≥425`），不再
                      // 只显示证书名（用户 2026-09-18：「不能只显示『大学英语四级』
                      // 这样的证书名，要显示原文里『大学英语四级>=425』这样的加分
                      // 条目名」）。认不出（目录外 / 未填分 / 未达门槛）→ 证书名。
                      m.typeId == ZcTypeId.foreign
                          ? (zcForeignEntryLabel(
                                  name: m.name,
                                  rawScore: m.manualScore,
                                ) ??
                                m.displayName)
                          : m.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  RuleTip(
                    ids: zcMaterialRuleIds[m.typeId],
                    color: scheme.primary,
                    size: 13,
                  ),
                ],
              ),
              Text(
                '${spec?.label ?? ''} · ${m.optionLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
              // 竞赛条目补一行备注（用户 2026-09-18：「智育的竞赛条目上也要显示
              // 竞赛的备注信息」）——备注里放的是子项目/赛道/组别（`C++ B组`、
              // `2026 ICPC全国邀请赛（沈阳）`），不显示就分不清同一赛事的几条。
              if (m.typeId == ZcTypeId.contest && m.note.trim().isNotEmpty)
                Text(
                  m.note.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (v != null)
          Text(
            '+${zcFmt(v)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          Text('不计', style: TextStyle(fontSize: 11, color: scheme.outline)),
        if (highlighted) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '计入总分',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ] else if (dimmed) ...[
          const SizedBox(width: 6),
          Text(
            '未计入',
            style: TextStyle(fontSize: 9.5, color: scheme.outline),
          ),
        ],
      ],
    ),
    ),
  );
}

/// 「去材料库」跳转小按钮（附加分区空态 / 头部管理入口）。
Widget zcGoMaterials(BuildContext context, {String text = '去材料库管理'}) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MaterialsScreen())),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.open_in_new, size: 12, color: scheme.primary),
        ],
      ),
    ),
  );
}

Widget zcNoteCard(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: scheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '本测算为个人自评参考，依据江财学工字〔2024〕27 号；材料分值按证书盖章时间计入相应学年，在「材料库」中录入后自动带入。民主评议分与班级排名为预估值，最终以班级评议、学院核查与公示结果为准。',
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.outline,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 6),
        RuleTip(tipKey: 'general', size: 13),
      ],
    ),
  );
}

Widget zcCard(BuildContext context, Widget child) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: ShapeDecoration(
      shape: appCardShape(context),
      color: AppColors.card(context),
    ),
    child: child,
  );
}
