import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_grid.dart';

/// 宫格磁贴排版守卫（第 2 条）：
/// 「每个卡片要一样宽高，提示文本不足 1 行也显示为 2 行高，超过 2 行的显示省略号」。
///
/// 这里用真渲染尺寸断言 —— 只读源码里的常量（cardHeight）证明不了渲染结果，
/// 必须量 `RenderBox`。
void main() {
  HomeServiceEntry entry(
    String title,
    String subtitle, {
    VoidCallback? onTap,
    HomeServiceGroup group = HomeServiceGroup.ims,
    Color accent = const Color(0xFFC3282E),
  }) => HomeServiceEntry(
    icon: Icons.abc,
    title: title,
    subtitle: subtitle,
    group: group,
    accent: accent,
    builder: () => const SizedBox.shrink(),
    onTap: onTap ?? () {},
  );

  Future<void> pumpGrid(
    WidgetTester tester,
    List<HomeServiceEntry> entries, {
    double width = 1200,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeServiceGrid(entries: entries),
          ),
        ),
      ),
    );
  }

  const shortText = '校历';
  const oneLineSubtitle = '学期教学周历';
  const longSubtitle =
      '按教师/班级/教室/课程随时随地查询全校课表，并支持多班对照找出共同空课时间（这段文案一定会超过两行）';

  testWidgets('宽屏：所有磁贴等宽等高', (tester) async {
    final entries = [
      entry(shortText, oneLineSubtitle),
      entry('公共查询', longSubtitle),
      entry('选课', ''),
      entry('成绩', '成绩单与学分预警 · 毕业达标进度'),
    ];
    await pumpGrid(tester, entries);

    final sizes = [
      for (final e in entries) tester.getSize(find.byKey(Key('homeTile-${e.title}'))),
    ];
    for (final size in sizes) {
      expect(size.height, HomeServiceGrid.cardHeight);
    }
    expect(sizes.map((s) => s.width).toSet().length, 1, reason: '列宽应一致');
    expect(sizes.map((s) => s.height).toSet().length, 1, reason: '行高应一致');
    expect(tester.takeException(), isNull);
  });

  testWidgets('副标题不足 1 行也占 2 行高（空文案同样占位）', (tester) async {
    final entries = [
      entry(shortText, oneLineSubtitle),
      entry('选课', ''),
    ];
    await pumpGrid(tester, entries);

    for (final e in entries) {
      final box = tester.getSize(find.byKey(Key('homeSubtitleBox-${e.title}')));
      expect(
        box.height,
        HomeServiceGrid.subtitleLineHeight * 2,
        reason: '${e.title} 的副标题区应恒为 2 行高',
      );
    }
    // 两者磁贴高度完全一致 —— 文案长度不参与排版。
    expect(
      tester.getSize(find.byKey(Key('homeTile-$shortText'))).height,
      tester.getSize(find.byKey(const Key('homeTile-选课'))).height,
    );
  });

  testWidgets('超过 2 行的文案：maxLines = 2 + 省略号', (tester) async {
    await pumpGrid(tester, [entry('公共查询', longSubtitle)]);

    final text = tester.widget<Text>(find.text(longSubtitle));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏（手机）：紧凑磁贴同样等高且不溢出', (tester) async {
    final entries = [
      entry(shortText, oneLineSubtitle),
      entry('学生个人数据中心', longSubtitle),
      entry('选课', ''),
    ];
    await pumpGrid(tester, entries, width: 360);

    for (final e in entries) {
      final size = tester.getSize(find.byKey(Key('homeTile-${e.title}')));
      expect(size.height, HomeServiceGrid.compactCardHeight, reason: e.title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击磁贴触发对应入口', (tester) async {
    var tapped = '';
    await pumpGrid(tester, [
      entry(shortText, oneLineSubtitle, onTap: () => tapped = shortText),
    ]);
    await tester.tap(find.byKey(const Key('homeTile-校历')));
    expect(tapped, '校历');
  });

  testWidgets('磁贴悬停提示 = 副标题全文（截断后仍可读全）', (tester) async {
    await pumpGrid(tester, [entry('公共查询', longSubtitle)]);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('homeTile-公共查询')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, longSubtitle);
  });
}
