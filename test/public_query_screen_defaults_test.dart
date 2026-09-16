/// 公共查询页的**接线守卫**：卡片纯白（取主题色）+「打开页面按账号预填」。
///
/// 纯匹配规则在 `public_query_defaults_test.dart` 里守着；这里守「页面真的接上了」：
/// ① 卡片底色 = 主题的 `colorScheme.surface`（而不是 M3 Card 默认的
/// `surfaceContainerLow`）；② 打开页面即把账号的 校区/年级/学院/专业/班级 填进筛选条件；
/// ③ 校区偏好匹配不上教务选项时留空，不猜。
///
/// 公共查询的每个 provider 都换成**实测数据的固定假值** → 全程零网络、零 Hive
/// （真 provider 会 `Hive.openBox`，在 widget 测试里会把错误同步抛进 `ref.read`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_profile_provider.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_query_screen.dart';

/// 与 app 主题同口径的极简主题：surface = **纯白**，surfaceContainerLow = 略灰
/// （后者是 Material Card 的默认取色，正是本页要覆盖掉的那个）。
ThemeData _theme() => ThemeData(
  colorScheme: const ColorScheme.light(
    surface: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFAFA),
  ),
);

const _term = PublicQueryTerm(xn: 2026, xqM: 0, name: '2026-2027学年第一学期');

/// 校区 `MsSchoolArea` 实测 6 条原文。
const _campuses = <PublicQueryOption>[
  PublicQueryOption(code: '05', name: '深圳校区'),
  PublicQueryOption(code: '06', name: '北京校区'),
  PublicQueryOption(code: '07', name: '上海校区'),
  PublicQueryOption(code: '1', name: '蛟桥园校区'),
  PublicQueryOption(code: '3', name: '麦庐园校区'),
  PublicQueryOption(code: '4', name: '枫林园校区'),
];

/// 学院 `MsYXB`（实测 44 条，取真实的前几条 + 计算机）。
const _colleges = <PublicQueryOption>[
  PublicQueryOption(code: '0032', name: '[007]产业经济研究院（规制与竞争研究中心）'),
  PublicQueryOption(code: '00', name: '[010]经济管理与创业模拟实验教学中心'),
  PublicQueryOption(code: '01', name: '[023]教务处'),
  PublicQueryOption(code: '44', name: '[143]计算机与人工智能学院'),
];

/// 专业 `MsYXB_Specialty`（实测 9 条，全量）。
const _majors = <PublicQueryOption>[
  PublicQueryOption(code: '1842', name: '[08090D2]计算机科学与技术(拔尖实验班)'),
  PublicQueryOption(code: '4405', name: '[08090D5]计算机科学与技术'),
  PublicQueryOption(code: '4402', name: '[080912TK]网络空间安全'),
  PublicQueryOption(code: '4403', name: '[E0809925]计算机科学与技术(第二学士学位)'),
];

/// 班级选择器（`nj=2025&xqdm=3` 麦庐园，实测 83 条，取计算机相关真实条目）。
const _classes = <PublicQueryOption>[
  PublicQueryOption(code: '2508090D21', name: '[2508090D21]计算机科学与技术(拔尖实验班)251'),
  PublicQueryOption(code: '2508090D51', name: '[2508090D51]计算机科学与技术251'),
  PublicQueryOption(code: '2508090D52', name: '[2508090D52]计算机科学与技术252'),
  PublicQueryOption(code: '2508090D53', name: '[2508090D53]计算机科学与技术253'),
];

/// 真实学籍（`studentinfo` 缓存实测值）+「我的校区」= 麦庐园校区。
const _profile = PublicQueryAccountProfile(
  enrollYear: '2025',
  college: '计算机与人工智能学院',
  major: '计算机科学与技术',
  className: '计算机科学与技术252',
  campusName: '麦庐园校区',
);

/// 记录 family provider 实际收到的参数（用来验证「年级用的是学籍入学年」）。
final List<String> _collegeYears = [];
final List<String> _majorKeys = [];
final List<PublicQueryRequest> _classRequests = [];

/// 假班级列表（**真实语义**：班级码只出现在配套校区的列表里）。
///
/// 实测 2026-09-14：`nj=2025&xqdm=3`（麦庐园）83 条含该班；`xqdm=4`/`xqdm=1` 不含；
/// 不带 `xqdm` 179 条含该班。跨校区纠正靠这个差异才会被触发。
List<PublicQueryOption> _campusAwareClasses(PublicQueryRequest request) {
  if (request.campusCode.isEmpty) return _classes;
  return request.campusCode == '3' ? _classes : const [];
}

/// 可替换的班级给法（个别用例要模拟「只能不带校区才查得到」）。
List<PublicQueryOption> Function(PublicQueryRequest request) _classListFor =
    _campusAwareClasses;

List<Override> _overrides({PublicQueryAccountProfile profile = _profile}) => [
  publicQueryAccountProfileProvider.overrideWith((ref) async => profile),
  publicQueryTermsProvider.overrideWith((ref) async => const [_term]),
  publicQueryCampusesProvider.overrideWith((ref) async => _campuses),
  publicQueryTrainLevelsProvider.overrideWith(
    (ref) async => const [PublicQueryOption(code: '05', name: '本科')],
  ),
  publicQueryCollegesProvider.overrideWith((ref, year) async {
    _collegeYears.add(year);
    return _colleges;
  }),
  publicQueryMajorsProvider.overrideWith((ref, key) async {
    _majorKeys.add(key);
    return _majors;
  }),
  publicQueryComboBoxProvider.overrideWith((ref, request) async {
    _classRequests.add(request);
    return _classListFor(request);
  }),
  publicQueryBuildingsProvider.overrideWith(
    (ref, campusCode) async => const <PublicQueryOption>[],
  ),
  publicQueryReportProvider.overrideWith(
    (ref, request) async => const PublicQueryResult(html: '', timetables: []),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Override>? overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides ?? _overrides(),
      child: MaterialApp(theme: _theme(), home: const PublicQueryScreen()),
    ),
  );
  await _settle(tester);
}

/// 有限帧推进（**不要用 `pumpAndSettle`**）：页面 loading 卡里的
/// `CircularProgressIndicator` 是无限动画，`pumpAndSettle` 会一直挂到默认 10 分钟超时。
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// 轮询到条件成立（预填是异步链，帧数不确定）。
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 20));
}

/// 页面里所有 `DropdownButton<String>` 当前选中的值（下拉项的文本都在树里，
/// 只有 `value` 才代表「真的选中了」）。
List<String?> _dropdownValues(WidgetTester tester) => tester
    .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
    .map((d) => d.value)
    .toList();

void main() {
  setUp(() {
    _collegeYears.clear();
    _majorKeys.clear();
    _classRequests.clear();
    _classListFor = _campusAwareClasses;
  });

  group('卡片纯白', () {
    testWidgets('卡片底色 = 主题的 surface（纯白），不是 Card 默认的 surfaceContainerLow', (
      tester,
    ) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);

      final card = find.byType(Card).first;
      final scheme = Theme.of(tester.element(card)).colorScheme;
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.surfaceContainerLow, const Color(0xFFFAFAFA));

      final material = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(material.color, const Color(0xFFFFFFFF));
      expect(material.color, isNot(scheme.surfaceContainerLow));
    });

    testWidgets('卡片仍有 outline 细边框（白卡压纯白底也看得见分界）', (tester) async {
      await _pump(tester);
      final card = tester.widget<Card>(find.byType(Card).first);
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.side.width, greaterThan(0));
      expect(shape.side.color.a, greaterThan(0.0));
    });
  });

  group('按账号预填', () {
    testWidgets('打开页面即填齐 校区/年级/学院/专业/班级（校区按配套的那个取）', (tester) async {
      await _pump(tester);
      await _waitFor(tester, () => _classRequests.isNotEmpty);
      await _settle(tester);

      expect(tester.takeException(), isNull);
      // 校区 = 麦庐园校区（code 3）；年级 = 学籍入学年 2025（不是学年 2026）
      expect(_dropdownValues(tester), contains('3'));
      expect(_dropdownValues(tester), contains('2025'));
      // 学院 / 专业 / 班级三级都按账号值填上
      expect(find.text('计算机与人工智能学院'), findsWidgets);
      expect(find.text('计算机科学与技术'), findsWidgets); // 专业行（不是拔尖班）
      expect(find.text('计算机科学与技术252'), findsWidgets); // 班级行（剥掉 [码] 前缀）

      // 取列表用的参数必须配套：年级 = 2025 级、专业按 年级|学院=44、班级按 xqdm=3
      expect(_collegeYears, contains('2025'));
      expect(_collegeYears, isNot(contains('2026')));
      expect(_majorKeys, contains('2025|44'));
      expect(_classRequests.length, 1, reason: '校区偏好命中时不该再多试别的校区');
      expect(_classRequests.first.campusCode, '3');
      expect(_classRequests.first.grade, '2025');
      expect(_classRequests.first.departmentCode, '44');
      expect(_classRequests.first.majorCode, '4405');
    });

    testWidgets('「我的校区」匹配不上教务选项（青山园校区）时逐个校区试到对的那个', (tester) async {
      await _pump(
        tester,
        overrides: _overrides(
          profile: const PublicQueryAccountProfile(
            enrollYear: '2025',
            college: '计算机与人工智能学院',
            major: '计算机科学与技术',
            className: '计算机科学与技术252',
            campusName: '青山园校区',
          ),
        ),
      );
      await _waitFor(
        tester,
        () => _classRequests.map((r) => r.campusCode).contains('3'),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      // 没猜校区：先按各校区逐个试（顺序 = 教务列表顺序），最后命中麦庐园（3）
      expect(_classRequests.map((r) => r.campusCode), isNot(contains('')));
      expect(_classRequests.map((r) => r.campusCode), contains('3'));
      expect(_classRequests.length, greaterThan(1));
      expect(_dropdownValues(tester), contains('3'));
      expect(find.text('计算机科学与技术252'), findsWidgets);
    });

    testWidgets('校区与班级的配套关系确认不了时：班级照填、校区留空（不猜）', (tester) async {
      // 模拟「只有不限校区才查得到」的数据形态
      _classListFor = (request) =>
          request.campusCode.isEmpty ? _classes : const [];

      await _pump(tester);
      await _waitFor(
        tester,
        () => _classRequests.map((r) => r.campusCode).contains(''),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('计算机科学与技术252'), findsWidgets);
      // 校区没有猜成「我的校区」（麦庐园），保持「全部 / 不限」
      expect(_dropdownValues(tester), isNot(contains('3')));
      expect(_dropdownValues(tester), contains(''));
    });

    testWidgets('学籍与校区都取不到时不做任何预填，也不抛异常', (tester) async {
      await _pump(
        tester,
        overrides: _overrides(profile: const PublicQueryAccountProfile()),
      );
      await _settle(tester, frames: 20);
      expect(tester.takeException(), isNull);
      expect(_classRequests, isEmpty);
      expect(_dropdownValues(tester), isNot(contains('3')));
      expect(find.text('公共查询'), findsOneWidget);
    });
  });
}
