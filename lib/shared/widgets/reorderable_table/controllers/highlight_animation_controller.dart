// lib/shared/widgets/reorderable_table/controllers/highlight_animation_controller.dart

import 'package:flutter/material.dart';

class HighlightAnimationController {
  final TickerProvider vsync;
  final VoidCallback onUpdate;

  late List<AnimationController> _rowControllers;
  late List<AnimationController> _colControllers;
  late List<Animation<double>> _rowAnimations;
  late List<Animation<double>> _colAnimations;

  static const _duration = Duration(milliseconds: 200);

  HighlightAnimationController({
    required this.vsync,
    required int rowCount,
    required int colCount,
    required this.onUpdate,
  }) {
    _init(rowCount, colCount);
  }

  void _init(int rowCount, int colCount) {
    _rowControllers = List.generate(
      rowCount,
      (_) =>
          AnimationController(vsync: vsync, duration: _duration)..value = 0.0,
    );
    _rowAnimations = _rowControllers
        .map((c) => c.drive(CurveTween(curve: Curves.easeOut)))
        .toList();

    _colControllers = List.generate(
      colCount,
      (_) =>
          AnimationController(vsync: vsync, duration: _duration)..value = 0.0,
    );
    _colAnimations = _colControllers
        .map((c) => c.drive(CurveTween(curve: Curves.easeOut)))
        .toList();

    for (var c in _rowControllers) {
      c.addListener(onUpdate);
    }
    for (var c in _colControllers) {
      c.addListener(onUpdate);
    }
  }

  void updateDimensions(int rowCount, int colCount) {
    dispose();
    _init(rowCount, colCount);
  }

  List<double> get rowProgresses => _rowAnimations.map((a) => a.value).toList();
  List<double> get colProgresses => _colAnimations.map((a) => a.value).toList();

  void animateRow(int newRow, int oldRow) {
    if (oldRow != -1 && oldRow < _rowControllers.length) {
      _rowControllers[oldRow].animateTo(0.0);
    }
    if (newRow != -1 && newRow < _rowControllers.length) {
      _rowControllers[newRow].animateTo(1.0);
    }
  }

  void animateCol(int newCol, int oldCol) {
    if (oldCol != -1 && oldCol < _colControllers.length) {
      _colControllers[oldCol].animateTo(0.0);
    }
    if (newCol != -1 && newCol < _colControllers.length) {
      _colControllers[newCol].animateTo(1.0);
    }
  }

  void reset() {
    for (var c in _rowControllers) {
      c.value = 0.0;
    }
    for (var c in _colControllers) {
      c.value = 0.0;
    }
  }

  void dispose() {
    for (var c in _rowControllers) {
      c.removeListener(onUpdate);
      c.dispose();
    }
    for (var c in _colControllers) {
      c.removeListener(onUpdate);
      c.dispose();
    }
  }
}
