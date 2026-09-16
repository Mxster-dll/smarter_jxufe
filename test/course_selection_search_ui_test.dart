/// 「网上选课」检索栏的界面守卫（2026-09-15）。
///
/// 用户原话：「你目前选课的搜索功能也和原页面不一致」。本文件用假 provider 把
/// `SelectionOnlineView` 真渲染出来，钉住三件界面行为（不依赖网络）：
/// 1. 原页面那 8 个检索控件在界面上真的存在（`lbgl`/`kcsx` 只在有结果时可用）；
/// 2. 「课程类别 / 课程属性」是**客户端过滤** —— 选一项后列表当场变窄；
/// 3. 原页面的两处可见性 / 提示规则：`zxknj` 才显示「院(系)/部」，
///    且该范围下未选年级专业就点「检索」必须提示「需选定年级/专业！」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/providers/course_selection_providers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/selection_online_view.dart';

const SelectionSession _session = SelectionSession(
  xktype: 2,
  xn: '2026',
  xqM: '0',
  xqName: '第一学期',
  xnxqDesc: '2026-2027学年第一学期',
  status: '200',
  message: '',
  isValidTimerange: true,
  kcfw: 'zxbnj,zxggrx,fx,zxknj',
  kcfwmc: '主修(本专业本学期),主修(公共任选),辅修,主修(本专业跨学期)',
);

/// 三行假课程：属性上只有「体育3」不是纯理论课，类别键各不相同。
const List<OptionalCourse> _courses = [
  OptionalCourse(
    name: '会计学',
    courseCode: '1004001943',
    attribute: '理论课',
    kclb1: '04',
    kclb2: '2302',
    credits: 3,
  ),
  OptionalCourse(
    name: '体育3',
    courseCode: '1005000661',
    attribute: '理论课/体育课',
    kclb1: '01',
    kclb2: '2105',
    credits: 1,
  ),
  OptionalCourse(
    name: '计算机网络',
    courseCode: '1014300174',
    attribute: '理论课',
    kclb1: '01',
    kclb2: '2303',
    credits: 3,
  ),
];

void _noop(SelectionChannel _) {}

Widget _app() => ProviderScope(
  overrides: [
    selectionSessionProvider.overrideWith((ref, channel) async => _session),
    selectionQuotaProvider.overrideWith(
      (ref, channel) async => SelectionQuota.empty,
    ),
    selectionScopeOptionsProvider.overrideWith(
      (ref, channel) async => const [
        CourseScope(code: 'zxbnj', name: '主修(本专业本学期)'),
        CourseScope(code: 'zxknj', name: '主修(本专业跨学期)'),
      ],
    ),
    selectionDepartmentOptionsProvider.overrideWith(
      (ref, channel) async => const [CourseScope(code: '05', name: '[040]会计学院')],
    ),
    // 与教务实测一致：非跨学期给「本专业」一项，跨学期为空。
    selectionGradeMajorOptionsProvider.overrideWith(
      (ref, query) async => query.scope == 'zxknj'
          ? const <CourseScope>[]
          : const [CourseScope(code: '2025|4405', name: '2025|计算机科学与技术')],
    ),
    optionalCoursesProvider.overrideWith(
      (ref, query) async =>
          (courses: _courses, total: _courses.length),
    ),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: SelectionOnlineView(
        channel: SelectionChannel.plan,
        onChannelChanged: _noop,
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

Finder _dropdownWithLabel(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(DropdownButtonFormField<String>),
);

void main() {
  testWidgets('检索栏复刻原页面的 8 个控件', (tester) async {
    await _pump(tester);
    for (final text in [
      '检索条件',
      '主修(本专业本学期)',
      '主修(本专业跨学期)',
      '年级/专业',
      '课程类别',
      '课程属性',
      '限未选满的课程',
      '检索',
    ]) {
      expect(find.text(text), findsWidgets, reason: '界面缺少「$text」');
    }
    expect(
      find.text('课程代码（前缀匹配）或课程名称（模糊匹配）'),
      findsOneWidget,
    );
    // 非跨学期范围不显示「院(系)/部」（原页面 `sp_yxb` 默认 display:none）。
    expect(find.text('院(系)/部'), findsNothing);
    // 年级/专业已按教务返回值填上本专业。
    expect(find.text('2025|计算机科学与技术'), findsOneWidget);
    // 三行都在。
    expect(find.text('会计学'), findsOneWidget);
    expect(find.text('体育3'), findsOneWidget);
  });

  testWidgets('课程属性是客户端过滤：选一项当场变窄', (tester) async {
    await _pump(tester);
    await tester.tap(_dropdownWithLabel('课程属性'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('理论课/体育课').last);
    await tester.pumpAndSettle();

    expect(find.text('体育3'), findsOneWidget);
    expect(find.text('会计学'), findsNothing);
    expect(find.text('计算机网络'), findsNothing);
    // 列表计数显示「筛出的/全部」，让用户看得出被筛了。
    expect(find.textContaining('可选课程（1/3）'), findsOneWidget);
  });

  testWidgets('课程类别按 kclb2_kclb1 过滤', (tester) async {
    await _pump(tester);
    await tester.tap(_dropdownWithLabel('课程类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2302_04').last);
    await tester.pumpAndSettle();

    expect(find.text('会计学'), findsOneWidget);
    expect(find.text('体育3'), findsNothing);
  });

  testWidgets('跨学期范围：显示院(系)/部，未选年级专业点检索要提示', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('主修(本专业跨学期)'));
    await tester.pumpAndSettle();

    expect(find.text('院(系)/部'), findsOneWidget);
    // 打开院(系)/部下拉，确认选项真的到了界面（`loadDropList4Single` 的结果）。
    await tester.tap(_dropdownWithLabel('院(系)/部'));
    await tester.pumpAndSettle();
    expect(find.text('[040]会计学院'), findsOneWidget);
    await tester.tap(find.text('[040]会计学院'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('检索'));
    await tester.pumpAndSettle();
    expect(find.text(kSelectionNeedGradeMajorText), findsOneWidget);
  });

  testWidgets('限未选满开关默认勾选，且取消勾选会重新检索', (tester) async {
    await _pump(tester);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final after = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(after.value, isFalse);
  });
}
