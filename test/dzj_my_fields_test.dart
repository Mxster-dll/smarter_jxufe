import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_my_field_row.dart';

/// 「我的」页 × 学校个人数据中心（竹简）的字段合并口径 —— 用户 2026-09-20 七轮：
/// 「我的页不显示从数据中心添加的信息，我希望这部分数据要换个颜色显示，如果原来的地方
/// 就有数据，则不覆盖，如果与已有数据冲突，则显示为『冲突』，然后点击显示冲突详情」。
void main() {
  DzjFieldMerge merge(DzjMyField f, String local, String remote) =>
      DzjFieldMerge.of(f, local: local, remote: remote);

  group('合并规则（本地优先 / 换色 / 冲突）', () {
    test('两边都空 → empty（不占版面）', () {
      final m = merge(DzjMyField.headTeacher, '', '');
      expect(m.state, DzjFieldState.empty);
      expect(m.visible, isFalse);
      expect(m.value, '');
    });

    test('本地空、数据中心有 → fromCenter，用数据中心的值', () {
      final m = merge(DzjMyField.headTeacher, '', '教师甲');
      expect(m.state, DzjFieldState.fromCenter);
      expect(m.usesCenterValue, isTrue);
      expect(m.value, '教师甲');
      expect(m.visible, isTrue);
      expect(m.source, '个人首页');
    });

    test('两边一致 → same（显示本地值，不做任何装饰）', () {
      final m = merge(DzjMyField.name, '同学甲', '同学甲');
      expect(m.state, DzjFieldState.same);
      expect(m.usesCenterValue, isFalse);
      expect(m.isConflict, isFalse);
      expect(m.value, '同学甲', reason: '不覆盖：值仍是本地那一份');
    });

    test('两边都有但不同 → conflict，值仍取本地的', () {
      final m = merge(DzjMyField.college, '计算机科学与技术', '计算机学院');
      expect(m.state, DzjFieldState.conflict);
      expect(m.isConflict, isTrue);
      expect(m.value, '计算机科学与技术');
    });

    test('只有数据中心有值、本地有空白 → 仍算 fromCenter（空白不算值）', () {
      expect(merge(DzjMyField.dormScore, '   ', '79.4').state,
          DzjFieldState.fromCenter);
    });

    test('等值判定忽略首尾空白 / 全角空格 / 大小写（不当冲突）', () {
      expect(dzjSameValue('2202500001', ' 2202500001 '), isTrue);
      expect(dzjSameValue('同学甲', '同学甲\u3000'), isTrue);
      expect(dzjSameValue('E10', 'e10'), isTrue);
      expect(dzjSameValue('甲 乙', '甲  乙'), isTrue, reason: '压缩中间空白');
      expect(dzjSameValue('甲', '乙'), isFalse);
      expect(dzjSameValue('', ''), isFalse, reason: '两个空不是「一致」');
      expect(
        merge(DzjMyField.cardNo, '2202500001', '2202500001\u3000').state,
        DzjFieldState.same,
        reason: '学籍 XML 与竹简库常是同一个值的两种写法，别误判成冲突',
      );
    });

    test('★ 噪声冲突：尾部残留分隔符、性别「男/男性」都不算冲突', () {
      // 实测该账号真机上的 5 枚冲突里，这两条是纯措辞差异（用户点开也看不到信息）。
      expect(dzjSameValue('江西省\\', '江西省'), isTrue, reason: '学籍里籍贯写成「江西省\\」');
      expect(dzjSameValue('25计算机2班/', '25计算机2班'), isTrue);
      expect(dzjSameValue('男', '男性'), isTrue);
      expect(dzjSameValue('女', '女性'), isTrue);
      // ⚠ 真正不同的写法必须继续报冲突 —— 这三条正是实测该账号的冲突来源。
      expect(dzjSameValue('计算机与人工智能学院', '计算机学院'), isFalse);
      expect(dzjSameValue('计算机科学与技术252', '25计算机2班'), isFalse);
      expect(dzjSameValue('13800000002', '13800000001'), isFalse);
    });

    test('合并整表：顺序 = 枚举顺序，按标签取用', () {
      final merges = dzjMergeFields(
        local: {'姓名': '同学甲', '一卡通号': '', '院系': '计算机科学与技术'},
        remote: {'姓名': '同学甲', '一卡通号': '2202500001', '班主任': '教师甲'},
      );
      expect(merges.length, DzjMyField.values.length);
      final byLabel = dzjMergeMap(merges);
      expect(byLabel['姓名']!.state, DzjFieldState.same);
      expect(byLabel['一卡通号']!.state, DzjFieldState.fromCenter);
      expect(byLabel['院系']!.state, DzjFieldState.same, reason: '本地有值、数据中心没有 → 不算冲突');
      expect(byLabel['班主任']!.state, DzjFieldState.fromCenter);
      expect(byLabel['班主任电话']!.state, DzjFieldState.empty);
      expect(byLabel['宿舍评分']!.state, DzjFieldState.empty);
    });

    test('枚举里的组件 id / 字段名 / 来源都写全了（界面要靠它标注来源）', () {
      for (final f in DzjMyField.values) {
        expect(f.componentId.startsWith('u:'), isTrue, reason: f.name);
        expect(f.valueKey.isNotEmpty, isTrue, reason: f.name);
        expect(f.source.isNotEmpty, isTrue, reason: f.name);
        expect(f.label.isNotEmpty, isTrue, reason: f.name);
      }
      expect(DzjMyField.headTeacher.componentId, 'u:ee1581a17fe0');
      expect(DzjMyField.dormScore.source, '住宿信息');
    });

    test('冲突详情：两份值与来源都在（弹层按它渲染）', () {
      final m = merge(DzjMyField.college, '计算机科学与技术', '计算机学院');
      final d = dzjConflictOf(m);
      expect(d.label, '院系');
      expect(d.local, '计算机科学与技术');
      expect(d.remote, '计算机学院');
      expect(d.source, '个人首页');
    });
  });

  group('行渲染（换色 / 小标 / 冲突胶囊）', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Column(children: [child])),
    );

    testWidgets('本地空 → 用数据中心的值 + 数据中心小标 + 数据源色', (tester) async {
      final m = merge(DzjMyField.headTeacher, '', '教师甲');
      await tester.pumpWidget(
        wrap(DzjMyFieldRow(label: '班主任', value: '', dzj: m)),
      );
      expect(find.text('教师甲'), findsOneWidget);
      expect(find.byKey(const Key('dzjSourceTag')), findsOneWidget);
      final ctx = tester.element(find.text('教师甲'));
      final style = tester.widget<Text>(find.text('教师甲')).style!;
      expect(style.color, fp(ctx).dzjSource, reason: '用户七轮：这部分数据要换个颜色显示');
      expect(style.fontWeight, FontWeight.w600);
      expect(find.text('冲突'), findsNothing);
    });

    testWidgets('两边一致 → 只显示本地值，不加任何装饰', (tester) async {
      await tester.pumpWidget(
        wrap(
          DzjMyFieldRow(
            label: '姓名',
            value: '同学甲',
            dzj: merge(DzjMyField.name, '同学甲', '同学甲'),
          ),
        ),
      );
      expect(find.text('同学甲'), findsOneWidget);
      expect(find.byKey(const Key('dzjSourceTag')), findsNothing);
      expect(find.text('冲突'), findsNothing);
      final ctx = tester.element(find.text('同学甲'));
      expect(
        tester.widget<Text>(find.text('同学甲')).style!.color,
        Theme.of(ctx).colorScheme.onSurface,
        reason: '一致时不改颜色',
      );
    });

    testWidgets('冲突 → 显示本地值 + 「冲突」胶囊；点开弹层列出两份值', (tester) async {
      final m = merge(DzjMyField.college, '计算机科学与技术', '计算机学院');
      await tester.pumpWidget(
        wrap(DzjMyFieldRow(label: '院系', value: m.local, dzj: m)),
      );
      // 值仍是本地那一份（不覆盖）。
      expect(find.text('计算机科学与技术'), findsOneWidget);
      expect(find.text('计算机学院'), findsNothing, reason: '冲突时页面上不直接铺数据中心的值');
      final chip = find.byKey(const Key('dzjConflict-院系'));
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dzjConflictDialog')), findsOneWidget);
      expect(find.text('院系 · 数据冲突'), findsOneWidget);
      expect(find.textContaining('App 学籍（采用这一份）'), findsOneWidget);
      expect(find.textContaining('学校数据中心 › 个人首页（未采用）'), findsOneWidget);
      // 两份值都在弹层里。
      expect(find.text('计算机科学与技术'), findsWidgets);
      expect(find.text('计算机学院'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dzjConflictOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dzjConflictDialog')), findsNothing);
    });

    testWidgets('没有数据中心那一份时（dzj == null）与从前完全一样', (tester) async {
      await tester.pumpWidget(wrap(const DzjMyFieldRow(label: '专业', value: '计算机科学与技术')));
      expect(find.text('计算机科学与技术'), findsOneWidget);
      expect(find.byKey(const Key('dzjSourceTag')), findsNothing);
      expect(find.text('冲突'), findsNothing);
    });

    testWidgets('空值行显示「（无）」', (tester) async {
      await tester.pumpWidget(wrap(const DzjMyFieldRow(label: '曾用名', value: '')));
      expect(find.text('（无）'), findsOneWidget);
    });
  });
}
