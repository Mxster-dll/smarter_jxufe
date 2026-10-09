/// 学年时间线（**一根单轴**）：一条轴 = 一个学年，学段 / 假期是轴上的实心段。
///
/// 用户 2026-10-09 裁定（否掉两版「一行一段」的卡片后）：「直接用 fluent-design
/// 设计一根单轴时间线」。于是：
///
/// - **轴**（4px 圆角轨道，Fluent ProgressBar 的形制）= 学年窗口，横贯整张卡；
/// - **段**（同一根轴上的圆角实心条）= 学段 / 假期，首尾相接，长度 ∝ 真实天数；
/// - **待公布** = 段的终点未知 → 画成**虚线段**（Fluent 的「未定」语汇：描边不填充），
///   而不是画到某个假日期上；
/// - **今天** = 轴上唯一的 accent 强标记（圆点 + 胶囊签），其余一律中性色；
/// - 标签挂在轴的两侧（在校段在上、放假段在下），月份刻度在轴下方压尾。
///
/// 为什么整块用一个 [CustomPaint]：标签要**按轴位置居中并夹在卡内**（窄卡上
/// 学期名 + 起止两段文字的宽度只有画的时候才知道），用 widget 摆位就得先量一遍再
/// 摆一遍；一次画完还能保证标签与段严格对齐。字体 / 颜色全部从
/// `fluent(context)` 与 [FluentType] 取（Fluent 的第 3 处采用点，见 §13），
/// 所以本文件里没有任何字面色值。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time_timeline.dart';

/// 学年时间线。数据由 [schoolTimelineSegments] / [schoolTimelineAxis] 备好（纯函数）。
class SchoolYearTimeline extends StatelessWidget {
  const SchoolYearTimeline({
    super.key,
    required this.axis,
    required this.segments,
    this.today,
    this.todayNote,
  });

  /// 轴范围（学年窗口）。
  final SchoolTimelineAxis axis;

  /// 轴上的段（时间顺序）。
  final List<SchoolTimelineSegment> segments;

  /// 今天的日期；不在轴上 / 为 null 时不画标记。
  final DateTime? today;

  /// 今天标记的补充说明（如「第 5 教学周」）。
  final String? todayNote;

  /// 一次性写完的高度：今天胶囊带 + 上学段标签带 + 轴 + 下假期标签带 + 月份刻度带。
  ///
  /// 全部按 Fluent 的 4px 栅格排（4 / 8 / 12 / 16），没有 5 / 7 / 10 这类值。
  static const double height = 136;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    // ⚠ 画布里的文字**必须继承页面字体**：`FluentType.*` 只给了字体回退链、没有
    // `fontFamily`，而 CustomPaint 不在 `DefaultTextStyle` 的继承链里 —— 不显式接上，
    // 换字体（测试 / 自定义主题）时画布里的字会退回引擎默认（widget 测试里就是方块）。
    final fontFamily = DefaultTextStyle.of(context).style.fontFamily ??
        Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return Semantics(
      label: _semanticsLabel(),
      // 标签是按像素摆的，窄卡上可能比卡片还宽 → 裁掉，别糊到卡片外面。
      child: ClipRect(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
          painter: _TimelinePainter(
            axis: axis,
            segments: segments,
            today: today,
            todayNote: todayNote,
            fontFamily: fontFamily,
            // 明度阶梯（数据永远比家具深）：学期 = accent 淡染 > 假期 = 14% 描边色 >
            // 轴轨道 = 8% 描边色。轨道取 `subtleTertiary`（6%）在浅色卡上几乎看不见，
            // 「一根轴」的读法会散掉。
            track: p.strokeControlDefault,
            termFill: p.accent.withValues(alpha: .55),
            breakFill: p.strokeControlSecondary,
            openStroke: p.strokeControlSecondary,
            textPrimary: p.textPrimary,
            textSecondary: p.textSecondary,
            textTertiary: p.textTertiary,
            accent: p.accent,
            accentSubtle: p.accentSubtle,
            onAccent: p.textOnAccentPrimary,
            divider: p.strokeDivider,
          ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final b = StringBuffer('学年时间线');
    for (final s in segments) {
      b.write('；${s.name} ${s.rangeText}');
      if (s.note != null) b.write('（${s.note}）');
    }
    return b.toString();
  }
}

/// 画笔：一次画完「月份刻度 → 轴 → 段 → 标签 → 今天」。
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.axis,
    required this.segments,
    required this.today,
    required this.todayNote,
    required this.fontFamily,
    required this.track,
    required this.termFill,
    required this.breakFill,
    required this.openStroke,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSubtle,
    required this.onAccent,
    required this.divider,
  });

  final SchoolTimelineAxis axis;
  final List<SchoolTimelineSegment> segments;
  final DateTime? today;
  final String? todayNote;
  final String? fontFamily;

  final Color track, termFill, breakFill, openStroke;
  final Color textPrimary, textSecondary, textTertiary;
  final Color accent, accentSubtle, onAccent, divider;

  // ── 带位（4px 栅格）────────────────────────────────────────────
  static const double _chipBandTop = 0;
  static const double _chipHeight = 20;
  static const double _upperLabelTop = 24;
  static const double _trackTop = 64;
  static const double _trackHeight = 4;
  static const double _lowerLabelTop = 76;
  static const double _rulerTop = 112;
  static const double _tickTop = 68;

  @override
  void paint(Canvas canvas, Size size) {
    final x0 = 0.0;
    final x1 = size.width;
    double xOf(double f) => x0 + f * (x1 - x0);

    _paintRuler(canvas, size, xOf);
    _paintTrack(canvas, xOf);
    _paintSegments(canvas, xOf);
    _paintLabels(canvas, size, xOf);
    if (today != null) _paintToday(canvas, size, xOf);
  }

  // ── 月份刻度：细线 + 月名（相邻月名放不下就隔一个画）────────────
  void _paintRuler(Canvas canvas, Size size, double Function(double) xOf) {
    final tick = Paint()
      ..color = divider
      ..strokeWidth = 1;
    var lastLabelRight = double.negativeInfinity;
    var month = DateTime(axis.start.year, axis.start.month);
    while (!month.isAfter(axis.end)) {
      final x = xOf(axis.fractionOf(month));
      canvas.drawLine(
        Offset(x, _tickTop),
        Offset(x, _rulerTop),
        tick,
      );
      final tp = _text('${month.month}月', FluentType.caption, textTertiary);
      final left = x - tp.width / 2;
      if (left > lastLabelRight + 6 && x + tp.width / 2 < size.width) {
        tp.paint(canvas, Offset(left, _rulerTop));
        lastLabelRight = x + tp.width / 2;
      }
      month = DateTime(month.year, month.month + 1);
    }
  }

  // ── 轴：一条圆角轨道（学年窗口）────────────────────────────────
  void _paintTrack(Canvas canvas, double Function(double) xOf) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        xOf(0),
        _trackTop,
        xOf(1) - xOf(0),
        _trackHeight,
      ),
      const Radius.circular(_trackHeight / 2),
    );
    canvas.drawRRect(r, Paint()..color = track);
  }

  // ── 段：已知跨度 = 实心圆角条；待公布 = 描边虚线条 ──────────────
  void _paintSegments(Canvas canvas, double Function(double) xOf) {
    for (final s in segments) {
      final (a, b) = axis.spanOf(s);
      final left = xOf(a);
      final right = math.max(xOf(b), left + 2); // 短于 2px 的段也留一个可见头
      final rect = Rect.fromLTWH(
        left,
        _trackTop,
        right - left,
        _trackHeight,
      );
      final radius = Radius.circular(_trackHeight / 2);
      if (s.isOpen) {
        // 待公布：虚线段**越往后越淡**（α 1 → .3）——否则一条虚线一路画到轴尾，
        // 会被读成「这段一直持续到八月」。淡出 = 「长度未知」，尾端不加端点。
        _strokeDashed(canvas, RRect.fromRectAndRadius(rect, radius), openStroke);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius),
          Paint()
            ..color = s.kind == SchoolTimelineKind.term ? termFill : breakFill,
        );
      }
    }
  }

  /// 虚线段：[color] 沿长度线性淡出（α 1 → .3）。
  void _strokeDashed(Canvas canvas, RRect rrect, Color color) {
    final w0 = rrect.left;
    final w = math.max(rrect.width, 1.0);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final t = (d / w).clamp(0.0, 1.0);
        base.color = color.withValues(alpha: 1 - .7 * t);
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 3.2, metric.length)),
          base,
        );
        d += 6.4;
      }
    }
    // `w0` 只用于让「淡出按段的起点算」这件事显式：段越长，尾端越淡。
    assert(w0 >= 0);
  }

  // ── 标签：在校段挂轴上方、放假段挂轴下方；按段居中、防重叠、必要时拉引线 ──
  //
  // 一段只有 5 天时（如「第二阶段」），它的标签比它自己宽几十倍 —— 直接按段居中会
  // 和邻座标签叠在一起。做法是**贪心让位**：同一侧按 x 排序，后者至少让开 12px；
  // 让位后若中心偏离段中心超过 8px，就画一条 1px 引线把标签接回它自己的段
  //（Gantt 的老办法，读者不会把标签认到隔壁段上）。
  void _paintLabels(Canvas canvas, Size size, double Function(double) xOf) {
    for (final above in const [true, false]) {
      final row = <_LabelBox>[];
      for (final s in segments) {
        if ((s.kind == SchoolTimelineKind.term) != above) continue;
        final (a, b) = axis.spanOf(s);
        final nameTp = _text(s.name, FluentType.bodyStrong, textPrimary);
        final dateTp = _text(
          s.note == null ? s.rangeText : '${s.rangeText} · ${s.note}',
          FluentType.caption,
          s.isOpen ? accent : textSecondary,
        );
        row.add(
          _LabelBox(
            segmentCenter: (xOf(a) + xOf(b)) / 2,
            name: nameTp,
            date: dateTp,
            top: above ? _upperLabelTop : _lowerLabelTop,
            anchorY: above ? _trackTop.toDouble() : (_trackTop + _trackHeight),
          ),
        );
      }
      if (row.isEmpty) continue;
      row.sort((p, q) => p.segmentCenter.compareTo(q.segmentCenter));

      var prevRight = double.negativeInfinity;
      for (final box in row) {
        final w = math.max(box.name.width, box.date.width);
        // ⚠ 夹取的**上下界必须先自己排好序**：`clamp(lower, upper)` 在 lower > upper 时
        // 直接抛 `ArgumentError`（实测：标签一宽、卡片一窄，`prevRight + 12` 就超过
        // `size.width - w` → 全量跑时字体不同才暴露）。标签比卡片还宽时上界只能是 0，
        // 此时允许左沿压回 0（宁可溢出，也不崩）。
        final maxLeft = math.max(0.0, size.width - w);
        final minLeft = prevRight.isFinite
            ? math.min(prevRight + 12, maxLeft)
            : 0.0;
        final left = (box.segmentCenter - w / 2)
            .clamp(minLeft, maxLeft)
            .toDouble();
        prevRight = left + w;
        box
          ..blockWidth = w
          ..left = left;
      }
      // 先画引线（在标签下面），再画文字
      for (final box in row) {
        final labelCenter = box.left + box.blockWidth / 2;
        if ((labelCenter - box.segmentCenter).abs() <= 8) continue;
        final line = Paint()
          ..color = divider
          ..strokeWidth = 1;
        final fromY = box.top + 34;
        canvas.drawLine(
          Offset(labelCenter, fromY),
          Offset(box.segmentCenter, box.anchorY),
          line,
        );
      }
      for (final box in row) {
        final nameLeft =
            box.left + (box.blockWidth - box.name.width) / 2;
        final dateLeft =
            box.left + (box.blockWidth - box.date.width) / 2;
        box.name.paint(canvas, Offset(nameLeft, box.top));
        box.date.paint(canvas, Offset(dateLeft, box.top + 18));
      }
    }
  }

  // ── 今天：轴上圆点 + 上方胶囊签（唯一 accent 强标记）─────────────
  void _paintToday(Canvas canvas, Size size, double Function(double) xOf) {    final f = axis.fractionOf(today!);
    if (f <= 0 || f >= 1) return;
    final x = xOf(f);
    final cy = _trackTop + _trackHeight / 2;
    canvas.drawCircle(Offset(x, cy), 4.5, Paint()..color = accent);
    canvas.drawCircle(
      Offset(x, cy),
      2.0,
      Paint()..color = onAccent,
    );

    final label = todayNote == null ? '今天' : '今天 · $todayNote';
    // ⚠ 胶囊 = Fluent 的「淡染底 + accent 字」徽标（见 `fluent_controls.dart` 的序号徽标），
    // **不是**实心 accent 底 —— 实心底上写白字在这一档淡染底色上等于看不见（实测踩过）。
    final tp = _text(label, FluentType.caption, accent);
    const padX = 8.0;
    final w = tp.width + padX * 2;
    final left = (x - w / 2).clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, _chipBandTop, w, _chipHeight),
      const Radius.circular(4), // Fluent ControlCornerRadius
    );
    canvas.drawRRect(rect, Paint()..color = accentSubtle);
    tp.paint(
      canvas,
      Offset(left + padX, _chipBandTop + (_chipHeight - tp.height) / 2),
    );
  }

  TextPainter _text(String s, TextStyle style, Color color) => TextPainter(
    text: TextSpan(
      text: s,
      style: style.copyWith(color: color, fontFamily: fontFamily),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.axis.start != axis.start ||
      old.axis.end != axis.end ||
      old.segments != segments ||
      old.today != today ||
      old.todayNote != todayNote ||
      old.accent != accent ||
      old.track != track;
}

/// 一个待排布的标签：名称 + 起止两行，挂在轴的上/下侧。
class _LabelBox {
  _LabelBox({
    required this.segmentCenter,
    required this.name,
    required this.date,
    required this.top,
    required this.anchorY,
  });

  /// 它所属那一段的中心 x（引线要接回这里）。
  final double segmentCenter;
  final TextPainter name;
  final TextPainter date;

  /// 名称行的上沿（日期行 = top + 18）。
  final double top;

  /// 引线的落点 y（上侧标签落到轨道顶、下侧落到轨道底）。
  final double anchorY;

  /// 让位之后的左沿与块宽（两行按块宽居中）。
  double left = 0;
  double blockWidth = 0;
}
