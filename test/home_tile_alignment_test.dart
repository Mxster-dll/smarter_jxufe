import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 首页宫格守卫：`_items(context)` 与顶层 `const _tileColors` 必须按索引一一对齐。
///
/// AGENTS.md §3 的铁律——渲染取 `_tileColors[i % _tileColors.length]`，
/// 只增删一侧会让后面所有磁贴错色（曾因「我的」磁贴删除而差点错位）。
/// 这里读源码做静态计数，比 widget 测试更早发现错位。
void main() {
  test('首页宫格条目数与功能分色数一致', () {
    final file = File('lib/features/home/presentation/home_screen.dart');
    expect(file.existsSync(), isTrue, reason: '找不到 ${file.path}');
    final lines = file.readAsLinesSync();

    // 宫格条目：`_items` 里每项以「缩进 + _HomeItem(」开头（类构造是 `const _HomeItem(`，不会命中）。
    final itemCount = lines
        .where((l) => RegExp(r'^\s*_HomeItem\($').hasMatch(l))
        .length;

    // 分色列表：`const _tileColors = <Color>[` 到对应 `];` 之间的 FeaturePalette 常量行。
    final start = lines.indexWhere((l) => l.startsWith('const _tileColors'));
    expect(start, greaterThan(0), reason: '找不到 _tileColors 定义');
    final end = lines.indexWhere((l) => l.trim() == '];', start);
    expect(end, greaterThan(start), reason: '_tileColors 未正常闭合');
    final colorCount = lines
        .sublist(start + 1, end)
        .where((l) => l.trimLeft().startsWith('FeaturePalette.'))
        .length;

    expect(itemCount, greaterThan(10), reason: '宫格条目数解析异常（$itemCount）');
    expect(
      colorCount,
      itemCount,
      reason:
          '宫格条目数（$itemCount）与 _tileColors 条目数（$colorCount）不一致：'
          '增删磁贴必须同步增删 _tileColors（AGENTS.md §3）',
    );
  });
}
