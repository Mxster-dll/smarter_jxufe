import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_color_index.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';

/// 用户 2026-09-17：「我希望优先保证每门课程的颜色都不同，实在不行再重复」。
///
/// 从前两个视图的色号是 `entry.courseCode.hashCode.abs()` 再 `% 配色数` ——
/// **哈希取模下撞色是常态**（生日问题：10 门课塞 14 个槽位，完全不撞的概率只有
/// 约 4%），用户看到的重复就是这么来的。现在色号改由
/// `lib/features/ims/schedule/domain/schedule_color_index.dart` 按**课程身份**发：
/// 课程号去重 → 升序排序 → 依次 0,1,2,…，所以「课程数 ≤ 配色数」时必然互不相同。
///
/// 下面四组守卫：
/// 1. 发号口径（去重 / 排序 / 稳定 / 同课共用一色）；
/// 2. **互不相同**：N 门课拿 N 个不同的下标（≤ 配色数），超过才按下标取模重复；
/// 3. 旧口径确实会撞（反例留档，别改回去）；
/// 4. 两个视图真的吃这份表（渲染层两门课不同色 + 源码守卫）。
void main() {
  ScheduleEntry entry({
    required String courseCode,
    String? courseName,
    int startPeriod = 1,
    int endPeriod = 2,
    DayOfWeek day = DayOfWeek.monday,
  }) => ScheduleEntry(
    classCode: '$courseCode-01',
    className: '${courseName ?? courseCode}(01)',
    courseCode: courseCode,
    courseName: courseName ?? courseCode,
    totalHours: 48,
    credits: 3,
    studyNature: '必修',
    teacherCode: 'T1',
    teacherName: '张三',
    selectionStatus: '已选',
    isCrossMajor: false,
    hasTextbook: true,
    classTimes: [
      ClassTime(
        startWeek: 1,
        endWeek: 16,
        weekParity: WeekParity.every,
        dayOfWeek: day,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        classroom: '麦三教101',
      ),
    ],
  );

  /// 同一门课的第二个班次（课程号相同、班级号不同）。
  ScheduleEntry sibling(String courseCode) => ScheduleEntry(
    classCode: '$courseCode-02',
    className: '$courseCode(02)',
    courseCode: courseCode,
    courseName: courseCode,
    totalHours: 48,
    credits: 3,
    studyNature: '必修',
    teacherCode: 'T2',
    teacherName: '李四',
    selectionStatus: '已选',
    isCrossMajor: false,
    hasTextbook: true,
    classTimes: [
      ClassTime(
        startWeek: 1,
        endWeek: 16,
        weekParity: WeekParity.every,
        dayOfWeek: DayOfWeek.tuesday,
        startPeriod: 1,
        endPeriod: 2,
        classroom: '麦三教202',
      ),
    ],
  );

  final paletteSize = ScheduleTone.courseFills.length;

  group('发号口径（scheduleColorIndices）', () {
    test('课程号去重后升序发号 → 与输入顺序无关', () {
      final forward = scheduleColorIndices([
        entry(courseCode: 'A'),
        entry(courseCode: 'B'),
        entry(courseCode: 'C'),
      ]);
      final shuffled = scheduleColorIndices([
        entry(courseCode: 'C'),
        entry(courseCode: 'A'),
        entry(courseCode: 'B'),
      ]);
      // 排序发号：A=0 / B=1 / C=2，两次结果必须逐值相同 —— 换周、刷新、
      // 横竖版切换都不能让同一门课换色。
      expect(forward, {'A': 0, 'B': 1, 'C': 2});
      expect(shuffled, forward);
    });

    test('同一门课的多个班次共用一色（键 = 课程号）', () {
      final indices = scheduleColorIndices([
        entry(courseCode: 'A'),
        sibling('A'),
        entry(courseCode: 'B'),
      ]);
      // 两个班次 = 一门课 → 只占一个号，B 拿到 1 而不是 2。
      expect(indices, {'A': 0, 'B': 1});
      expect(indices[scheduleColorKeyOf(sibling('A'))], 0);
    });

    test('一门课的多个时间段 / 重复行只占一个号', () {
      final indices = scheduleColorIndices([
        entry(courseCode: 'A', startPeriod: 1, endPeriod: 2),
        entry(courseCode: 'A', startPeriod: 5, endPeriod: 6),
        entry(courseCode: 'A', day: DayOfWeek.friday),
      ]);
      expect(indices, {'A': 0});
    });

    test('课程号为空时退回班级号；键为空的脏数据不进表', () {
      final noCourseCode = ScheduleEntry(
        classCode: 'X-01',
        className: 'X(01)',
        courseCode: '',
        courseName: 'X',
        totalHours: 32,
        credits: 2,
        studyNature: '选修',
        teacherCode: 'T1',
        teacherName: '张三',
        selectionStatus: '已选',
        isCrossMajor: false,
        hasTextbook: false,
        classTimes: const [],
      );
      expect(scheduleColorKeyOf(noCourseCode), 'X-01');
      expect(scheduleColorIndices([noCourseCode]), {'X-01': 0});

      final blank = ScheduleEntry(
        classCode: '  ',
        className: '',
        courseCode: '',
        courseName: '',
        totalHours: 0,
        credits: 0,
        studyNature: '',
        teacherCode: '',
        teacherName: '',
        selectionStatus: '',
        isCrossMajor: false,
        hasTextbook: false,
        classTimes: const [],
      );
      expect(scheduleColorKeyOf(blank), '');
      expect(scheduleColorIndices([blank]), isEmpty);
    });
  });

  group('互不相同（用户的核心诉求）', () {
    test('课程数 ≤ 配色数 → 每门课一个不同的色', () {
      final entries = [
        for (var i = 0; i < paletteSize; i++) entry(courseCode: 'C$i'),
      ];
      final indices = scheduleColorIndices(entries);
      expect(indices.length, paletteSize);
      // 下标 = 0..paletteSize-1，取模后仍然两两不同。
      final colors = {
        for (final i in indices.values) i % paletteSize,
      };
      expect(colors.length, paletteSize, reason: '$paletteSize 门课没有拿到 $paletteSize 个不同的色');
    });

    test('超过配色数才重复，且是按下标取模地重复', () {
      final entries = [
        for (var i = 0; i < paletteSize + 3; i++) entry(courseCode: 'C$i'),
      ];
      final indices = scheduleColorIndices(entries);
      // 发号本身互不相同（0..paletteSize+2）；重复只发生在 `ScheduleTone` 内部的
      // `seed % 配色数` 那一步。
      expect(indices.length, paletteSize + 3);
      expect(indices.values.toSet().length, paletteSize + 3);
      expect(
        {for (final i in indices.values) i % paletteSize}.length,
        paletteSize,
        reason: '配色表没被用满',
      );
      // 号相差 paletteSize 的两门课必然同色（第 1 门 ↔ 第 15 门）。
      final codeOfIndex = {
        for (final e in indices.entries) e.value: e.key,
      };
      expect(
        codeOfIndex[0]!,
        isNot(codeOfIndex[1]!),
        reason: '发号不是一对一的',
      );
      expect(
        indices[codeOfIndex[0]!]! % paletteSize,
        indices[codeOfIndex[paletteSize]!]! % paletteSize,
      );
    });

    test('课表里真实规模的课程集合两两不同（12 门典型课表）', () {
      final entries = [
        for (var i = 0; i < 12; i++) entry(courseCode: '20260$i'),
      ];
      final indices = scheduleColorIndices(entries);
      expect(
        {for (final i in indices.values) i % paletteSize}.length,
        12,
        reason: '12 门课出现同色 → 又回到哈希取模那种撞色',
      );
    });
  });

  group('反例留档：旧口径（hashCode % 配色数）必然撞色', () {
    test('20 门课 → 哈希取模去重后 < 20（鸽子洞），身份发号则恰好用满配色表', () {
      final codes = [for (var i = 0; i < 20; i++) 'C$i'];
      // 旧口径：20 门课塞进 14 个槽位 → 由鸽子洞原理**必定**有重复。
      final hashed = {for (final c in codes) c.hashCode.abs() % paletteSize};
      expect(hashed.length, lessThan(codes.length));
      // 新口径：20 门课拿到 20 个互不相同的号，因此**前 14 门必然两两不同色**，
      // 只有第 15 门起才回到配色表开头。
      final indices = scheduleColorIndices([
        for (final c in codes) entry(courseCode: c),
      ]);
      expect(indices.values.toSet().length, codes.length);
      expect(
        {
          for (final i in indices.values.take(paletteSize)) i % paletteSize,
        }.length,
        paletteSize,
        reason: '前 $paletteSize 门课必须用满且只用一次配色表',
      );
      expect(
        {for (final i in indices.values) i % paletteSize}.length,
        paletteSize,
      );
    });
  });

  group('两个视图真的吃这份表', () {
    Color? fillColorOf(WidgetTester tester, Finder finder) {
      final container = tester.widget<Container>(
        find.ancestor(of: finder, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration;
      return decoration is BoxDecoration ? decoration.color : container.color;
    }

    testWidgets('竖版：同一周两门课的底色不同，且等于身份号对应的色', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? appDarkTheme : appLightTheme,
            home: Scaffold(
              body: ScheduleGridView(
                entries: [
                  entry(courseCode: 'A', courseName: '高等数学', endPeriod: 2),
                  entry(
                    courseCode: 'B',
                    courseName: '大学英语',
                    startPeriod: 5,
                    endPeriod: 6,
                  ),
                ],
                week: 2,
                weekMonday: DateTime(2026, 9, 7),
                showToggle: false,
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(ScheduleGridView));
        final a = fillColorOf(tester, find.text('高等数学'));
        final b = fillColorOf(tester, find.text('大学英语'));
        // 身份发号：'A' < 'B' → 0 / 1。
        expect(a?.toARGB32(), ScheduleTone.fill(context, 0).toARGB32());
        expect(b?.toARGB32(), ScheduleTone.fill(context, 1).toARGB32());
        expect(
          a?.toARGB32(),
          isNot(b?.toARGB32()),
          reason: 'dark=$dark：同一周两门课撞色了',
        );
      }
    });

    test('源码守卫：两视图都按课程身份取号，不再直接用哈希值', () {
      for (final path in [
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('final colorIndices = scheduleColorIndices(entries);'),
          isTrue,
          reason: '$path 没有按整学期课程表算身份号',
        );
        expect(
          src.contains('colorIndices[scheduleColorKeyOf(entry)]'),
          isTrue,
          reason: '$path 的色号没走身份表',
        );
        // 哈希只能出现在 `??` 兜底里，不许再当主路径。
        expect(
          src.contains('??\n        entry.courseCode.hashCode.abs()'),
          isTrue,
          reason: '$path 的哈希兜底没了（取不到键的脏数据会拿到 null 色号）',
        );
        // 身份表必须传给课格（少传一处 = 那一档又回到哈希取模）。
        expect(
          src.contains('colorIndices: colorIndices'),
          isTrue,
          reason: '$path 没有把身份表传给课格',
        );
      }
    });
  });
}
