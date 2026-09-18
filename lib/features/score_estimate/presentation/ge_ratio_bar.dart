/// 分数估计 · 构成占比条。
///
/// 一条双色比例条：平时分（左）与期末成绩（右）按占比分色；平时分内部
/// **按各分项「分值上限」的比例断开为若干段**（段间留 [geBarGap] 空隙）。
/// 每段从段中心引出一条 45°/135° 斜线，斜线终点即该段标注文字的近端顶角
/// —— 因此竖直位移恒等于水平位移；方向按下述规则择向：
///
/// - 段中心落在条**左半**→ 先试右下 45°，右半 → 先试左下 135°；
/// - 该方向放不下（越界或与已放置的标注相交）→ 换另一方向；
/// - 仍放不下 → 加深一级（每级 [geCalloutStep]），最多 [geCalloutMaxLevel] 级。
///
/// 于是「竖直距离」按避让需要逐段加深，斜线始终是严格的 45°/135°。
/// 点击整块区域（条 + 标注）打开 [showGeRatioSheet] 设置平时/期末比例。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/app_theme.dart';
import '../../../design/feature_palette.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';

// ---- 布局常量（唯一出处，测试直接引用） ----

/// 引出线每级位移：竖直 = 水平 = 该值（保证 45°/135°）。
const double geCalloutStep = 11;

/// 引出线常规最深级数（竖直最远 4 × 11 = 44px）。
const int geCalloutMaxLevel = 4;

/// 全段都塞不下时额外允许的级数（避免极端分项数把标注叠在一起）。
const int geCalloutExtraLevel = 2;

/// 标注文字行高。
const double geCalloutLabelHeight = 14;

/// 相邻标注之间的最小水平间距。
const double geCalloutMinGap = 5;

/// 分段条默认高度（详情页）/ 紧凑高度（列表页细条）。
const double geRatioBarHeight = 18;
const double geRatioBarThinHeight = 6;

/// 段与段之间的空隙宽度（「断开」的视觉来源）。
const double geBarGap = 2;

// ---- 分段模型 ----

/// 分段类型。
enum GeRatioSegmentKind {
  /// 平时分的一个分项（按分值上限切分平时段）。
  part,

  /// 期末成绩。
  finalScore,
}

/// 构成占比条里的一段。
@immutable
class GeRatioSegment {
  /// 标注文字，如「考勤 5」「期末 70%」。
  final String label;

  /// 占整条宽度的比例（0~1）；各段之和恒为 1。
  final double fraction;

  final GeRatioSegmentKind kind;

  /// 对应 [GeCourse.parts] 的下标；期末段与「待配置」段为 -1。
  final int partIndex;

  /// 平时占比 > 0 但没有可用分项（未配置，或各分项分值上限合计为 0）。
  final bool pending;

  const GeRatioSegment({
    required this.label,
    required this.fraction,
    required this.kind,
    this.partIndex = -1,
    this.pending = false,
  });

  bool get isPart => kind == GeRatioSegmentKind.part;

  @override
  String toString() =>
      'GeRatioSegment($label, ${(fraction * 100).toStringAsFixed(2)}%, '
      '${kind.name}${pending ? ', pending' : ''})';
}

/// 按 [dailyPercent] 与各分项 [GePart.cap] 切分构成占比。
///
/// - 平时占比 > 0 且至少一个分项有正分值 → 平时段按分值上限切成 N 段；
/// - 平时占比 > 0 但无可用分项 → 一整段「待配置」；
/// - 平时占比 = 0 / 期末占比 = 0 时对应那一段不出现（合计恒为 100%）。
List<GeRatioSegment> geRatioSegments({
  required List<GePart> parts,
  required double dailyPercent,
}) {
  final dp = (dailyPercent.isFinite ? dailyPercent : 30.0).clamp(0.0, 100.0);
  final dpFraction = dp / 100;
  final segments = <GeRatioSegment>[];

  if (dpFraction > 0) {
    final caps = [
      for (final p in parts) (p.cap.isFinite && p.cap > 0) ? p.cap : 0.0,
    ];
    final total = caps.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      segments.add(
        GeRatioSegment(
          label: '平时 ${geFmt(dp)}% · 待配置分项',
          fraction: dpFraction,
          kind: GeRatioSegmentKind.part,
          pending: true,
        ),
      );
    } else {
      for (var i = 0; i < parts.length; i++) {
        if (caps[i] <= 0) continue;
        final name = parts[i].name.trim();
        segments.add(
          GeRatioSegment(
            label:
                '${name.isEmpty ? '分项 ${i + 1}' : name} ${geFmt(parts[i].cap)}',
            fraction: dpFraction * caps[i] / total,
            kind: GeRatioSegmentKind.part,
            partIndex: i,
          ),
        );
      }
    }
  }

  if (dpFraction < 1) {
    segments.add(
      GeRatioSegment(
        label: '期末 ${geFmt(100 - dp)}%',
        fraction: 1 - dpFraction,
        kind: GeRatioSegmentKind.finalScore,
      ),
    );
  }

  return segments;
}

/// 一段的引出线与标注位置。
@immutable
class GeCallout {
  final GeRatioSegment segment;

  /// 斜线起点 x（该段中心）。
  final double anchorX;

  /// 条底边 y（斜线起点 y）。
  final double barBottom;

  /// 标注矩形（左上角 + 宽 + 固定行高 [geCalloutLabelHeight]）。
  final double labelLeft;
  final double labelTop;
  final double labelWidth;

  /// +1 = 向右下 45°，-1 = 向左下 135°。
  final int direction;

  /// 实际级数（竖直位移 ≈ 级数 × [geCalloutStep]，被边界夹紧时可能更小）。
  final int level;

  const GeCallout({
    required this.segment,
    required this.anchorX,
    required this.barBottom,
    required this.labelLeft,
    required this.labelTop,
    required this.labelWidth,
    required this.direction,
    required this.level,
  });

  /// 斜线终点 x（标注近端顶角）：向右下取左边界，向左下取右边界。
  double get elbowX => direction > 0 ? labelLeft : labelLeft + labelWidth;

  double get labelRight => labelLeft + labelWidth;

  /// 斜线水平位移（恒等于 [drop]）。
  double get run => (elbowX - anchorX).abs();

  /// 斜线竖直位移 = 标注顶边与条底边的距离。
  double get drop => labelTop - barBottom;

  Rect get rect =>
      Rect.fromLTWH(labelLeft, labelTop, labelWidth, geCalloutLabelHeight);

  @override
  String toString() =>
      'GeCallout(${segment.label}, x=$labelLeft, y=$labelTop, w=$labelWidth, '
      'dir=$direction, level=$level)';
}

/// 计算每段标注的位置（纯函数，便于单测）。
///
/// [labelWidths] 与 [segments] 等长（由调用方按当前文字样式量得）；
/// [width] 为条可用宽度；[barBottom] 为条底边 y（通常 = 条高）。
List<GeCallout> geCalloutLayout({
  required List<GeRatioSegment> segments,
  required List<double> labelWidths,
  required double width,
  required double barBottom,
}) {
  final out = <GeCallout>[];
  final placed = <Rect>[];
  var cursor = 0.0;

  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final segWidth = width * seg.fraction;
    final anchorX = cursor + segWidth / 2;
    cursor += segWidth;

    final labelWidth = (i < labelWidths.length ? labelWidths[i] : 0.0).clamp(
      0.0,
      width <= 0 ? 0.0 : width,
    );
    // 左半段优先右下（45°），右半段优先左下（135°）。
    final prefer = anchorX <= width / 2 ? 1 : -1;

    GeCallout? chosen;
    final maxLevel = geCalloutMaxLevel + geCalloutExtraLevel;
    for (var level = 1; level <= maxLevel && chosen == null; level++) {
      for (final dir in [prefer, -prefer]) {
        final candidate = _fit(
          seg: seg,
          anchorX: anchorX,
          labelWidth: labelWidth,
          width: width,
          barBottom: barBottom,
          level: level,
          direction: dir,
          placed: placed,
        );
        if (candidate != null) {
          chosen = candidate;
          break;
        }
      }
    }
    // 兜底：所有级数与方向都冲突时，取最深一级的优先方向（宁可相邻也不丢标注）。
    chosen ??=
        _fit(
          seg: seg,
          anchorX: anchorX,
          labelWidth: labelWidth,
          width: width,
          barBottom: barBottom,
          level: maxLevel,
          direction: prefer,
          placed: const [],
        ) ??
        GeCallout(
          segment: seg,
          anchorX: anchorX,
          barBottom: barBottom,
          labelLeft: 0,
          labelTop: barBottom,
          labelWidth: labelWidth,
          direction: prefer,
          level: maxLevel,
        );

    out.add(chosen);
    placed.add(chosen.rect);
  }

  return out;
}

/// 试放一段：返回 null 表示越界或与已放置标注相交。
GeCallout? _fit({
  required GeRatioSegment seg,
  required double anchorX,
  required double labelWidth,
  required double width,
  required double barBottom,
  required int level,
  required int direction,
  required List<Rect> placed,
}) {
  if (width <= 0) return null;
  final run = geCalloutStep * level;
  final nearX = anchorX + direction * run;
  final rawLeft = direction > 0 ? nearX : nearX - labelWidth;
  final maxLeft = math.max(0.0, width - labelWidth);
  final left = rawLeft.clamp(0.0, maxLeft);
  final elbowX = direction > 0 ? left : left + labelWidth;
  // 竖直位移由水平位移导出 → 斜线严格 45°/135°。
  final top = barBottom + (elbowX - anchorX).abs();
  final rect = Rect.fromLTWH(left, top, labelWidth, geCalloutLabelHeight);
  if (rect.left < -0.5 || rect.right > width + 0.5) return null;
  for (final r in placed) {
    if (r.inflate(geCalloutMinGap).overlaps(rect)) return null;
  }
  return GeCallout(
    segment: seg,
    anchorX: anchorX,
    barBottom: barBottom,
    labelLeft: left,
    labelTop: top,
    labelWidth: labelWidth,
    direction: direction,
    level: level,
  );
}

// ---- 组件 ----

/// 段颜色：平时分 = 模块靛蓝（未配置时浅色），期末 = 中性蓝灰。
///
/// 取 `BuildContext` 而非静态 [FeaturePalette]：三段色都要随亮度解析
/// （深色下自动提亮档），否则深底上整条读不出。
Color geRatioSegmentColor(BuildContext context, GeRatioSegment seg) =>
    geRatioSegmentColorOf(FeatureColors.of(context), seg);

/// [geRatioSegmentColor] 的无 context 版本（`CustomPainter` 里只能拿到色表）。
Color geRatioSegmentColorOf(FeatureColors f, GeRatioSegment seg) {
  if (!seg.isPart) return f.scoreEstimateFinal;
  return seg.pending ? f.scoreEstimatePending : f.scoreEstimate;
}

/// 纯分段条（列表页细条 / 详情页条体，不含引出线与标注）。
class GeRatioBar extends StatelessWidget {
  final List<GePart> parts;
  final double dailyPercent;
  final double height;

  /// 段间空隙；传 0 表示无缝。
  final double gap;

  /// 圆角，缺省为高度的一半（胶囊）。
  final double? radius;

  const GeRatioBar({
    super.key,
    required this.parts,
    required this.dailyPercent,
    this.height = geRatioBarHeight,
    this.gap = geBarGap,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final segments = geRatioSegments(parts: parts, dailyPercent: dailyPercent);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Row(
          // ⚠ 必须 stretch：Row 默认 center 会给「无子 ColoredBox」松高度约束，
          // 高度塌成 0 → 整条隐形（旧版 8px 双色条正是这个写法，一直没画出来）。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0 && gap > 0) SizedBox(width: gap),
              Expanded(
                flex: math.max(1, (segments[i].fraction * 10000).round()),
                child: ColoredBox(
                  color: geRatioSegmentColor(context, segments[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分段条 + 45°/135° 引出线标注；[onTap] 非空时整块可点（打开比例设置弹层）。
class GeRatioChart extends StatelessWidget {
  final List<GePart> parts;
  final double dailyPercent;
  final VoidCallback? onTap;
  final double barHeight;

  const GeRatioChart({
    super.key,
    required this.parts,
    required this.dailyPercent,
    this.onTap,
    this.barHeight = geRatioBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = geRatioSegments(parts: parts, dailyPercent: dailyPercent);
    final style = TextStyle(
      fontSize: 11,
      height: 1.15,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    // 量宽用的样式必须与 Text 实际渲染的一致（Text 会把 style 合进 DefaultTextStyle）。
    final measureStyle = DefaultTextStyle.of(context).style.merge(style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320.0;
        final widths = [
          for (final s in segments) _measure(s.label, measureStyle, width),
        ];
        final callouts = geCalloutLayout(
          segments: segments,
          labelWidths: widths,
          width: width,
          barBottom: barHeight,
        );
        var height = barHeight + geCalloutLabelHeight;
        for (final c in callouts) {
          height = math.max(height, c.labelTop + geCalloutLabelHeight);
        }

        final content = SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: GeRatioBar(
                  parts: parts,
                  dailyPercent: dailyPercent,
                  height: barHeight,
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _LeaderPainter(
                    callouts: callouts,
                    barBottom: barHeight,
                    // 色表在 build 里解析好带进 painter（CustomPainter 拿不到 context）。
                    colors: FeatureColors.of(context),
                  ),
                ),
              ),
              for (final c in callouts)
                Positioned(
                  left: c.labelLeft,
                  top: c.labelTop,
                  width: c.labelWidth,
                  height: geCalloutLabelHeight,
                  child: Text(
                    c.segment.label,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: c.direction > 0
                        ? TextAlign.left
                        : TextAlign.right,
                  ),
                ),
            ],
          ),
        );

        if (onTap == null) return content;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        );
      },
    );
  }

  static double _measure(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return math.min(tp.width.ceilToDouble(), maxWidth);
  }
}

class _LeaderPainter extends CustomPainter {
  final List<GeCallout> callouts;
  final double barBottom;
  final FeatureColors colors;

  _LeaderPainter({
    required this.callouts,
    required this.barBottom,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in callouts) {
      final color = geRatioSegmentColorOf(colors, c.segment);
      canvas.drawLine(
        Offset(c.anchorX, barBottom),
        Offset(c.elbowX, c.labelTop),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      // 起点圆点：标示该斜线属于条上的哪一段。
      canvas.drawCircle(
        Offset(c.anchorX, barBottom),
        1.6,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LeaderPainter oldDelegate) =>
      !identical(oldDelegate.callouts, callouts) ||
      oldDelegate.barBottom != barBottom ||
      oldDelegate.colors != colors;
}

// ---- 比例设置弹层 ----

/// 常用平时占比快捷项（期末 = 100 − 平时）。
const List<int> geRatioPresets = [0, 20, 30, 40, 50, 60];

/// 打开「平时 / 期末占比」设置弹层；[onChanged] 每次调整都回调（即时生效）。
Future<void> showGeRatioSheet(
  BuildContext context, {
  required List<GePart> parts,
  required double dailyPercent,
  required ValueChanged<double> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GeRatioSheet(
      parts: parts,
      dailyPercent: dailyPercent,
      onChanged: onChanged,
    ),
  );
}

/// 比例设置面板（滑动条 + 手输 + 常用比例）。
class GeRatioSheet extends StatefulWidget {
  final List<GePart> parts;
  final double dailyPercent;
  final ValueChanged<double> onChanged;

  const GeRatioSheet({
    super.key,
    required this.parts,
    required this.dailyPercent,
    required this.onChanged,
  });

  @override
  State<GeRatioSheet> createState() => _GeRatioSheetState();
}

class _GeRatioSheetState extends State<GeRatioSheet> {
  late double _dp;
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _dp = widget.dailyPercent.clamp(0.0, 100.0);
    _ctrl = TextEditingController(text: '${_dp.round()}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _apply(double v, {bool syncText = true}) {
    final clamped = v.clamp(0.0, 100.0);
    setState(() => _dp = clamped);
    if (syncText) _ctrl.text = '${clamped.round()}';
    widget.onChanged(clamped);
  }

  /// 手输平时占比（0-100 整数）；空串或非法则回写当前值。
  void _applyText() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null) {
      _ctrl.text = '${_dp.round()}';
      return;
    }
    _apply(v.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // ⚠ 本方法内 `fp` 是「期末占比」的局部变量（见下），会遮蔽顶层 `fp(context)`，
    // 故这里用 `FeatureColors.of(context)` 取色。
    final colors = FeatureColors.of(context);
    final fp = 100 - _dp;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '平时 / 期末占比',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '平时分与期末成绩合计 100%，拖动或手输都会立即生效。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              GeRatioChart(
                parts: widget.parts,
                dailyPercent: _dp,
                barHeight: 16,
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.scoreEstimate,
                  inactiveTrackColor: scheme.surfaceContainerHighest,
                  thumbColor: colors.scoreEstimate,
                  overlayColor: AppColors.tint(
                    context,
                    colors.scoreEstimate,
                    0.12,
                  ),
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                ),
                child: Slider(
                  value: _dp.clamp(0, 100),
                  max: 100,
                  divisions: 10,
                  label: '平时 ${geFmt(_dp)}%',
                  onChanged: _apply,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '总评 = 平时均分 × ${geFmt(_dp)}% + 期末 × ${geFmt(fp)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      onSubmitted: (_) => _applyText(),
                      onTapOutside: (_) {
                        _focus.unfocus();
                        _applyText();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '常用比例（平时 / 期末）',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final v in geRatioPresets)
                    ChoiceChip(
                      label: Text(
                        v == 0 ? '0 / 100' : '$v / ${100 - v}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _dp.round() == v,
                      onSelected: (_) => _apply(v.toDouble()),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
