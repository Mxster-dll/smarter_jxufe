/// 学期码 `xxy` 与阵列选择器守卫（用户 2026-09-15 口径）。
///
/// 用户原话：「以阵列显示如下文本 251 261 271 / 252 262 272 / 253 263 273，
/// 其中 xxy 代表 xx-(xx+1) 学年，y=1 第一学期、y=2 第二学期、y=3 第二阶段；
/// 故阵列是固定三行，左右延伸，范围可选。」
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/shared/widgets/school_term_grid.dart';

void main() {
  group('学期码 xxy（用户 2026-09-15 口径）', () {
    test('编码：xq+1 作末位', () {
      expect(schoolTermCode(2026, 0), '261');
      expect(schoolTermCode(2026, 1), '262');
      expect(schoolTermCode(2026, 2), '263');
      expect(schoolTermCode(2025, 0), '251');
      expect(schoolTermCode(2025, 1), '252');
      expect(schoolTermCode(2025, 2), '253');
      expect(schoolTermCode(2027, 0), '271');
      expect(schoolTermCode(2017, 0), '171');
    });

    test('解码：用户示例阵列逐个还原', () {
      expect(schoolTermFromCode('251'), (xn: 2025, xq: 0));
      expect(schoolTermFromCode('252'), (xn: 2025, xq: 1));
      expect(schoolTermFromCode('253'), (xn: 2025, xq: 2));
      expect(schoolTermFromCode('261'), (xn: 2026, xq: 0));
      expect(schoolTermFromCode('263'), (xn: 2026, xq: 2));
      expect(schoolTermFromCode('271'), (xn: 2027, xq: 0));
    });

    test('解码：往返一致（2025~2030 × 三学段）', () {
      for (var xn = 2025; xn <= 2030; xn++) {
        for (var xq = 0; xq < 3; xq++) {
          expect(schoolTermFromCode(schoolTermCode(xn, xq)), (xn: xn, xq: xq));
        }
      }
    });

    test('解码：非法输入返回 null', () {
      expect(schoolTermFromCode(''), isNull);
      expect(schoolTermFromCode('26'), isNull);
      expect(schoolTermFromCode('2601'), isNull);
      expect(schoolTermFromCode('260'), isNull, reason: '末位 0 不是学段');
      expect(schoolTermFromCode('264'), isNull, reason: '末位 4 越界');
      expect(schoolTermFromCode('26x'), isNull);
      expect(schoolTermFromCode(' 261 '), (xn: 2026, xq: 0), reason: '两侧空白容错');
    });

    test('标签：第二阶段不再被写成「第二学期」', () {
      expect(schoolTermLabel(2026, 0), '2026-2027 学年第一学期');
      expect(schoolTermLabel(2026, 1), '2026-2027 学年第二学期');
      expect(schoolTermLabel(2026, 2), '2026-2027 学年第二阶段');
    });

    test('范围：入学年 ~ 当前学年（用户裁定）', () {
      expect(schoolTermPickerRange(enrollYear: 2025, currentYear: 2026), (
        startYear: 2025,
        endYear: 2026,
      ));
      // 学籍取不到 → 当前学年往前一个本科周期（4 年）
      expect(schoolTermPickerRange(enrollYear: null, currentYear: 2026), (
        startYear: 2022,
        endYear: 2026,
      ));
      // 不可信的入学年（晚于当前学年 / 非数字）同样退化
      expect(schoolTermPickerRange(enrollYear: 2030, currentYear: 2026), (
        startYear: 2022,
        endYear: 2026,
      ));
    });

    test('区间展开：学年 → 学段（列 = 学年、行 = 学段）', () {
      final terms = schoolTermsInRange(startYear: 2025, endYear: 2026);
      expect(terms.length, 6);
      expect(terms.first, (xn: 2025, xq: 0));
      expect(terms.last, (xn: 2026, xq: 2));
      expect(terms.map(schoolTermCode2).toList(), [
        '251',
        '252',
        '253',
        '261',
        '262',
        '263',
      ]);
      expect(schoolTermsInRange(startYear: 2026, endYear: 2026).length, 3);
    });
  });

  group('学期码阵列（SchoolTermGrid）', () {
    testWidgets('固定三行、列随范围左右延伸', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolTermGrid(
              startYear: 2025,
              endYear: 2026,
              selectedXn: 2026,
              selectedXq: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      for (final y in const [1, 2, 3]) {
        expect(
          find.byKey(Key('schoolTermRow-$y')),
          findsOneWidget,
          reason: '阵列恒为三行（学段）',
        );
      }
      for (final code in const ['251', '252', '253', '261', '262', '263']) {
        expect(find.text(code), findsOneWidget, reason: '两个学年（列）× 三学段');
      }

      // 单学年时只剩三格
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolTermGrid(
              startYear: 2025,
              endYear: 2025,
              selectedXn: 2025,
              selectedXq: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('261'), findsNothing);
      expect(find.text('251'), findsOneWidget);
    });

    testWidgets('点格子回传该学期，选中格高亮为主色', (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC3282E)),
      );
      final picked = <({int xn, int xq})>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SchoolTermGrid(
              startYear: 2025,
              endYear: 2026,
              selectedXn: 2025,
              selectedXq: 2,
              onSelected: picked.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('schoolTermCell-261')));
      expect(picked, [(xn: 2026, xq: 0)]);

      Material cellMaterial(String code) => tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(Key('schoolTermCell-$code')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(cellMaterial('253').color, theme.colorScheme.primary);
      expect(cellMaterial('251').color, isNot(theme.colorScheme.primary));
    });
  });

  group('学期选择器弹窗（showSchoolTermPicker）', () {
    Future<void> pumpHost(
      WidgetTester tester, {
      required void Function(({int xn, int xq})?) onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final r = await showSchoolTermPicker(
                    context,
                    startYear: 2025,
                    endYear: 2026,
                    selectedXn: 2026,
                    selectedXq: 0,
                  );
                  onResult(r);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('显示当前学期 + 阵列 + 口径说明，选中即关闭并回传', (tester) async {
      ({int xn, int xq})? result;
      await pumpHost(tester, onResult: (r) => result = r);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('选择学期'), findsOneWidget);
      expect(find.text('当前：2026-2027 学年第一学期（261）'), findsOneWidget);
      expect(find.byType(SchoolTermGrid), findsOneWidget);
      expect(
        find.textContaining('y=1 第一学期 / 2 第二学期 / 3 第二阶段'),
        findsOneWidget,
        reason: '学期码是自定义编码，弹窗必须自带口径说明',
      );

      await tester.tap(find.byKey(const Key('schoolTermCell-252')));
      await tester.pumpAndSettle();
      expect(result, (xn: 2025, xq: 1));
      expect(find.byType(SchoolTermGrid), findsNothing, reason: '选中后弹窗关闭');
    });

    testWidgets('取消返回 null', (tester) async {
      ({int xn, int xq})? result;
      await pumpHost(tester, onResult: (r) => result = r);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}

/// `schoolTermsInRange` 结果 → 学期码（仅测试内使用的小助手）。
String schoolTermCode2(({int xn, int xq}) term) =>
    schoolTermCode(term.xn, term.xq);
