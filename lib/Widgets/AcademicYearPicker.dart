import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class AcademicYearPicker extends StatefulWidget {
  final int startYear, endYear;
  final ValueChanged<int>? onChanged;

  const AcademicYearPicker(
    this.startYear,
    this.endYear, {
    super.key,
    this.onChanged,
  }) : assert(startYear <= endYear);

  @override
  State<AcademicYearPicker> createState() => _AcademicYearPickerState();
}

class _AcademicYearPickerState extends State<AcademicYearPicker> {
  late final String fullText = () {
    List<String> years = [];
    for (int y = widget.startYear; y <= widget.endYear + 1; y++) {
      years.add(y.toString());
    }
    return years.join('-');
  }();

  // 所有连字符在字符串中的索引
  late final List<int> hyphenIndices = () {
    List<int> indices = [];
    for (int i = 0; i < fullText.length; i++) {
      if (fullText[i] == '-') indices.add(i);
    }
    return indices;
  }();

  // 连字符在水平方向的位置（相对于文本左边缘），每次 build 时重新计算
  List<double> hyphenPositions = [];

  double _offsetX = 0.0;
  double _dragStartX = 0.0;
  double _dragStartOffset = 0.0;
  final double viewportWidth = 300;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapToHyphen(hyphenIndices.length - 1);
    });
  }

  // 计算每个连字符的水平位置（使用指定样式）
  void _computeHyphenPositions(TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: fullText, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);

    hyphenPositions = hyphenIndices.map((idx) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(baseOffset: idx, extentOffset: idx + 1),
      );
      if (boxes.isNotEmpty) {
        return boxes.first.left;
      }
      return 0.0;
    }).toList();
  }

  void _snapToNearest() {
    if (hyphenPositions.isEmpty) return;
    double viewportCenter = viewportWidth / 2;
    double targetTextPos = viewportCenter - _offsetX;

    int bestIndex = 0;
    double minDist = double.infinity;
    for (int i = 0; i < hyphenPositions.length; i++) {
      double dist = (hyphenPositions[i] - targetTextPos).abs();
      if (dist < minDist) {
        minDist = dist;
        bestIndex = i;
      }
    }
    _snapToHyphen(bestIndex);
  }

  void _snapToHyphen(int index) {
    if (index < 0 || index >= hyphenPositions.length) return;
    double viewportCenter = viewportWidth / 2;
    double targetOffset = viewportCenter - hyphenPositions[index];
    setState(() {
      _offsetX = targetOffset;
    });

    final selectedRange = _getYearRangeFromIndex(index);
    widget.onChanged?.call(int.parse(selectedRange.substring(0, 4)));
  }

  String _getYearRangeFromIndex(int hyphenIndex) {
    final hyphenPos = hyphenIndices[hyphenIndex];
    final start = hyphenPos - 4;
    final end = hyphenPos + 4;
    return fullText.substring(start, end + 1);
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      double delta = event.scrollDelta.dy;
      setState(() {
        _offsetX += delta;
      });
      _snapToNearest();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartOffset = _offsetX;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    double delta = details.localPosition.dx - _dragStartX;
    setState(() {
      _offsetX = _dragStartOffset + delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _snapToNearest();
  }

  @override
  Widget build(BuildContext context) {
    // 定义样式（局部变量，每次 build 重新创建）
    final normalStyle = const TextStyle(fontSize: 20, color: Colors.blueGrey);
    final highlightStyle = const TextStyle(
      fontSize: 20,
      color: Colors.blue,
      fontWeight: FontWeight.bold,
    );

    // 重新计算连字符位置
    _computeHyphenPositions(normalStyle);

    double viewportCenter = viewportWidth / 2;
    double targetTextPos = viewportCenter - _offsetX;
    int centerHyphenIndex = 0;
    if (hyphenPositions.isNotEmpty) {
      double minDist = double.infinity;
      for (int i = 0; i < hyphenPositions.length; i++) {
        double dist = (hyphenPositions[i] - targetTextPos).abs();
        if (dist < minDist) {
          minDist = dist;
          centerHyphenIndex = i;
        }
      }
    }

    int hyphenIdx = hyphenIndices[centerHyphenIndex];
    int highlightStart = hyphenIdx - 4;
    int highlightEnd = hyphenIdx + 4;
    highlightStart = highlightStart.clamp(0, fullText.length - 1);
    highlightEnd = highlightEnd.clamp(0, fullText.length - 1);

    List<TextSpan> spans = [];
    if (highlightStart > 0) {
      spans.add(
        TextSpan(
          text: fullText.substring(0, highlightStart),
          style: normalStyle,
        ),
      );
    }
    spans.add(
      TextSpan(
        text: fullText.substring(highlightStart, highlightEnd + 1),
        style: highlightStyle,
      ),
    );
    if (highlightEnd < fullText.length - 1) {
      spans.add(
        TextSpan(
          text: fullText.substring(highlightEnd + 1),
          style: normalStyle,
        ),
      );
    }

    return MouseRegion(
      child: Listener(
        onPointerSignal: _handleScroll,
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Container(
            width: viewportWidth,
            height: 60,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: _offsetX,
                  child: RichText(
                    text: TextSpan(children: spans),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
