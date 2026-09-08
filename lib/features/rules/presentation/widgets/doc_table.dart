import 'package:flutter/material.dart';

import '../../domain/doc_blocks.dart';

/// 公文表格卡（自绘合并表版）：
/// 以物理列网格布局，支持 colspan/rowspan 合并（锚格跨区、洞槽跳过、
/// 合并区内网格线按“锚同一性”跳段）；内容超宽时横向滚动；斑马纹
/// 以行带实现，跨行锚格按其起始行着色覆盖洞区。
class DocTable extends StatelessWidget {
  final TableData data;
  final double cellFontSize;
  final bool zebra;

  const DocTable({
    super.key,
    required this.data,
    this.cellFontSize = 13,
    this.zebra = true,
  });

  static const _padX = 8.0;
  static const _padYHeader = 8.0;
  static const _padYBody = 6.5;
  static const _minCellH = 10.0;

  TextStyle _style(BuildContext context, {required bool header}) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: cellFontSize,
      height: 1.45,
      fontWeight: header ? FontWeight.w600 : FontWeight.w400,
      color: header
          ? scheme.onPrimaryContainer
          : scheme.onSurface.withValues(alpha: 0.92),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final C = data.columnCount;
    final R = data.rowCount;
    if (C == 0 || R <= 0) return const SizedBox.shrink();

    // 序号列（表头含「序号」）→ 窄列居中。
    final seqCol = data.headers.indexWhere((h) => h.contains('序号'));

    final headerStyle = _style(context, header: true);
    final bodyStyle = _style(context, header: false);

    TextPainter measure(String t, TextStyle st, {double? width}) {
      return TextPainter(
        text: TextSpan(text: t, style: st),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width ?? double.infinity);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          // ---- 列权重：每列取覆盖该列格（跨列锚按 cs 分摊）的最大自然宽 ----
          final weight = List<double>.filled(C, 0);
          for (var r = 0; r < R; r++) {
            for (var c = 0; c < C; c++) {
              final sp = data.spanAt(r, c);
              final txt = data.cell(r, c);
              if (txt.isEmpty) continue; // 洞槽/真空槽不贡献
              final cs = sp?.colSpan ?? 1;
              final w = measure(txt, r == 0 ? headerStyle : bodyStyle).width +
                  _padX * 2;
              final share = w / cs;
              for (var k = 0; k < cs; k++) {
                if (c + k < C && share > weight[c + k]) weight[c + k] = share;
              }
            }
          }
          for (var c = 0; c < C; c++) {
            if (weight[c] < _minCellH + _padX * 2) {
              weight[c] = _minCellH + _padX * 2;
            }
          }
          final sumW = weight.fold<double>(0, (a, b) => a + b);
          // 表宽：内容自然宽 > 可用宽 → 横向滚动；否则按权重比例铺满。
          final tableW = sumW > maxW ? sumW : maxW;
          final colX = List<double>.filled(C + 1, 0);
          for (var c = 0; c < C; c++) {
            colX[c + 1] = colX[c] + tableW * weight[c] / sumW;
          }

          // ---- 行高 ----
          final padY = List<double>.filled(R, _padYHeader);
          for (var r = 1; r < R; r++) {
            padY[r] = _padYBody;
          }
          final baseH = List<double>.filled(R, 0);
          // rs==1 格直接贡献行高；rs>1 锚暂存后统一处理。
          final tallSpans = <(int, int, double)>[]; // (r, c, 文本高含 pad)
          for (var r = 0; r < R; r++) {
            for (var c = 0; c < C; c++) {
              if (data.coveredBySpan(r, c) && data.spanAt(r, c) == null) {
                continue; // 洞槽
              }
              final sp = data.spanAt(r, c);
              final cs = sp?.colSpan ?? 1;
              final rs = sp?.rowSpan ?? 1;
              if (r + rs > R) continue; // 防御：越界锚忽略
              final txt = data.cell(r, c);
              final colW = colX[c + cs] - colX[c];
              double h;
              if (txt.isEmpty) {
                h = _minCellH + padY[r] * 2;
              } else {
                final avail = (colW - _padX * 2).clamp(8.0, double.infinity);
                h = measure(txt, r == 0 ? headerStyle : bodyStyle,
                            width: avail).height +
                    padY[r] * 2;
              }
              if (rs <= 1) {
                if (h > baseH[r]) baseH[r] = h;
              } else {
                tallSpans.add((r, c, h));
              }
            }
          }
          // 跨行锚：需要高度超出既有行高和 → 差值加到最后一行。
          for (final (r, c, h) in tallSpans) {
            final sp = data.spanAt(r, c)!;
            final spanH = baseH.sublist(r, r + sp.rowSpan).fold<double>(
                0, (a, b) => a + b);
            if (h > spanH) {
              baseH[r + sp.rowSpan - 1] += h - spanH;
            }
          }
          final rowY = List<double>.filled(R + 1, 0);
          for (var r = 0; r < R; r++) {
            rowY[r + 1] = rowY[r] + baseH[r];
          }
          final totalH = rowY[R];

          // ---- 锚同一性网格（线跳段判定）----
          // id：锚=锚序号+1；洞=所在锚 id；真空=-1。
          final idGrid = List<int>.filled(R * C, -1);
          var anchorSeq = 0;
          for (var r = 0; r < R; r++) {
            for (var c = 0; c < C; c++) {
              final sp = data.spanAt(r, c);
              if (sp == null || idGrid[r * C + c] != -1) continue;
              if (sp.colSpan <= 1 && sp.rowSpan <= 1) {
                idGrid[r * C + c] = -1;
                continue;
              }
              final id = ++anchorSeq;
              for (var dr = 0; dr < sp.rowSpan && r + dr < R; dr++) {
                for (var dc = 0; dc < sp.colSpan && c + dc < C; dc++) {
                  idGrid[(r + dr) * C + c + dc] = id;
                }
              }
            }
          }
          int idAt(int r, int c) =>
              (r < 0 || r >= R || c < 0 || c >= C) ? -1 : idGrid[r * C + c];

          final zebraColor = scheme.surfaceContainerLow;
          final headerColor = scheme.primaryContainer;
          final plainColor = scheme.surface;

          // ---- 背景层 ----
          final bg = <Widget>[];
          // 行带：表头行整行、body 奇数行斑马。
          for (var r = 0; r < R; r++) {
            if (baseH[r] <= 0) continue;
            if (r == 0 || (zebra && r.isOdd)) {
              bg.add(Positioned(
                left: 0,
                top: rowY[r],
                width: tableW,
                height: baseH[r],
                child: ColoredBox(
                  color: r == 0 ? headerColor : zebraColor,
                ),
              ));
            }
          }
          // 合并锚格：整块着色（覆盖内部行带/洞区），色取锚起始行语义。
          for (var r = 0; r < R; r++) {
            for (var c = 0; c < C; c++) {
              final sp = data.spanAt(r, c);
              if (sp == null) continue;
              if (sp.colSpan <= 1 && sp.rowSpan <= 1) continue;
              final spanH = rowY[r + sp.rowSpan] - rowY[r];
              if (spanH <= 0) continue;
              final spanW = colX[c + sp.colSpan] - colX[c];
              Color color;
              if (r == 0) {
                color = headerColor;
              } else if (zebra && r.isOdd) {
                color = zebraColor;
              } else {
                color = plainColor;
              }
              bg.add(Positioned(
                left: colX[c],
                top: rowY[r],
                width: spanW,
                height: spanH,
                child: ColoredBox(color: color),
              ));
            }
          }

          // ---- 网格线层 ----
          final lineColor = scheme.outlineVariant;
          final innerLine = lineColor.withValues(alpha: 0.6);
          bg.add(CustomPaint(
            size: Size(tableW, totalH),
            painter: _GridPainter(
              R: R,
              C: C,
              rowY: rowY,
              colX: colX,
              idAt: idAt,
              outer: lineColor,
              inner: innerLine,
            ),
          ));

          // ---- 文字层 ----
          final textLayer = <Widget>[];
          for (var r = 0; r < R; r++) {
            for (var c = 0; c < C; c++) {
              final sp = data.spanAt(r, c);
              // 洞槽跳过（锚起点正常渲染）
              if (sp == null && data.coveredBySpan(r, c)) {
                continue;
              }
              final cs = sp?.colSpan ?? 1;
              final rs = sp?.rowSpan ?? 1;
              if (r + rs > R || c + cs > C) continue;
              final txt = data.cell(r, c);
              if (txt.isEmpty) continue;
              final isHeader = r == 0;
              final cellW = colX[c + cs] - colX[c];
              final cellH = rowY[r + rs] - rowY[r];
              final vCenter = rs > 1; // 跨行锚格垂直居中，与 PDF 观感一致
              textLayer.add(Positioned(
                left: colX[c],
                top: rowY[r],
                width: cellW,
                height: cellH,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _padX,
                    vertical: isHeader ? _padYHeader : _padYBody,
                  ),
                  child: Align(
                    alignment: vCenter
                        ? Alignment.centerLeft
                        : Alignment.topLeft,
                    child: Text(
                      txt,
                      style: isHeader ? headerStyle : bodyStyle,
                      textAlign: c == seqCol ? TextAlign.center : TextAlign.left,
                    ),
                  ),
                ),
              ));
            }
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: totalH,
              child: Stack(children: [...bg, ...textLayer]),
            ),
          );
        },
      ),
    );
  }
}

/// 画表格线：外框全画；内线按段两侧锚 id 相同（合并区内部）跳过。
class _GridPainter extends CustomPainter {
  final int R;
  final int C;
  final List<double> rowY;
  final List<double> colX;
  final Color outer;
  final Color inner;
  final int Function(int r, int c) idAt;

  _GridPainter({
    required this.R,
    required this.C,
    required this.rowY,
    required this.colX,
    required this.idAt,
    required this.outer,
    required this.inner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..color = outer
      ..strokeWidth = 1;
    final innerPaint = Paint()
      ..color = inner
      ..strokeWidth = 1;

    // 横线（行间隙，含外框顶/底）
    for (var j = 0; j <= R; j++) {
      final y = rowY[j];
      var x0 = 0.0;
      for (var i = 0; i < C; i++) {
        final x1 = colX[i + 1];
        final isOuter = j == 0 || j == R;
        if (!isOuter) {
          final topId = idAt(j - 1, i);
          final botId = idAt(j, i);
          if (topId >= 0 && topId == botId) {
            x0 = x1;
            continue; // 合并区内横线段跳过
          }
        }
        canvas.drawLine(Offset(x0, y), Offset(x1, y),
            isOuter ? outerPaint : innerPaint);
        x0 = x1;
      }
      // 最右侧可能残留合并跳过导致线段断裂，逐段处理已覆盖；
    }
    // 竖线（列间隙，含外框左/右）
    for (var i = 0; i <= C; i++) {
      final x = colX[i];
      var y0 = 0.0;
      for (var j = 0; j < R; j++) {
        final y1 = rowY[j + 1];
        final isOuter = i == 0 || i == C;
        if (!isOuter) {
          final leftId = idAt(j, i - 1);
          final rightId = idAt(j, i);
          if (leftId >= 0 && leftId == rightId) {
            y0 = y1;
            continue; // 合并区内竖线段跳过
          }
        }
        canvas.drawLine(Offset(x, y0), Offset(x, y1),
            isOuter ? outerPaint : innerPaint);
        y0 = y1;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.R != R ||
      old.C != C ||
      old.rowY != rowY ||
      old.colX != colX ||
      old.outer != outer ||
      old.inner != inner;
}
