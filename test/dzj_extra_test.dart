/// 数据中心**补充模块**（本学期课程 / 图书馆座位预约 / 助学金与勤工助学）+ 第二张名单卡
/// （「相关人员」）· 守卫。
///
/// 立项口径（用户 2026-09-19 三轮原话）：「学生数据中心还有很多信息没有加入，比如：
/// 基本信息 关联同学 指导教师 学业信息 奖助贷勤 校内活动 住宿信息 校园消费 图书服务
/// 数字活动 我希望可以把基本信息并入「我的」页 其他的，都显示在数据中心内」。
///
/// 本文件守四件事：
/// 1. 三个服务端组件的列名 → 条目（**真实回包形状**，2026-09-19 真会话实测）；
/// 2. 模块表（key / 标题 / 图标 / 空态文案）不重不漏、`fromKey` 能反查；
/// 3. 卡片四态（加载 / 失败 / 空 / 有数据）都讲得清，**空数据也照样有卡**
///    —— 悄悄不画会让人以为没接上；
/// 4. 「相关人员」六维真的落在数据中心页面上（点人数 → 该维度的名单弹层）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';

/// 挂数据中心页（概览固定为空，只验补充卡与名单卡）。
///
/// ⚠ 视口必须开得足够高：数据中心是 `ListView`（**懒构建**），默认 800×600 只会建出
/// 前两三张卡 —— 补充卡与「相关人员」卡都在页面下方，找不到不是没渲染，是**没构建**。
Future<void> pumpDataCenter(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountProvider.overrideWith((ref) => '2202500001'),
        dataCenterOverviewProvider.overrideWith(
          (ref) async => const DataCenterOverview(),
        ),
        // 子页面清单卡（页面树）——本文件不验它，固定成空树，别让它去打网络。
        dzjPageTreeProvider.overrideWith(
          (ref) async => const DzjPageTree(roots: [], subPages: []),
        ),
        // 「同年级同学院」人数（数据中心那一枚派生胶囊 / 成绩页排名分母）：
        // 账号非空时它真会去开数据中台会话（要 Hive）→ 这里固定 0 = 本文件不画那枚胶囊；
        // 要验它自己的测试在下面单独 override 成 726。
        dzjGradeCollegeCountProvider.overrideWith((ref) async => 0),
        ...overrides,
      ],
      child: const MaterialApp(home: DataCenterScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('行解析（真实回包形状）', () {
    test('本学期课程：kcmc / kcxf / kclb / khfs', () {
      final item = dzjCourseItem({
        'xn': '2026',
        'xq': '第一学期',
        'kcmc': '计算机网络',
        'kclb': '必修课',
        'khfs': '考试',
        'xdxz': '正常',
        'kcxf': 4.0,
      })!;
      expect(item.label, '计算机网络');
      expect(item.value, '4 学分'); // 4.0 → 「4」（不显示「4.0 学分」）
      expect(item.detail, '必修课 · 考试');
      // 没有课程名的行丢掉
      expect(dzjCourseItem({'kcxf': 2.0}), isNull);
      // 缺类别 / 考核方式 → 说明行不留空的分隔符
      final bare = dzjCourseItem({'kcmc': 'Linux操作系统', 'kcxf': 2.5})!;
      expect(bare.value, '2.5 学分');
      expect(bare.detail, '');
    });

    test('图书馆座位预约：ndkh / mc / khnd', () {
      final item = dzjSeatItem({
        'khnd': '2026-08-07 12:03:03~2026-08-07 22:00:00',
        'ndkh': '麦庐园图书馆-麦庐园-三楼东',
        'mc': '自动签到',
      })!;
      expect(item.label, '麦庐园图书馆-麦庐园-三楼东');
      expect(item.value, '自动签到');
      expect(item.detail, startsWith('2026-08-07 12:03:03~'));
      // 三个字段全空 → 丢掉
      expect(dzjSeatItem(const <String, dynamic>{}), isNull);
    });

    test('助学金 / 勤工助学：zxjlb·hdnf·shzt / gwmc·gwssdw·sgnf', () {
      final grant = dzjGrantItem({
        'zxjlb': '国家助学金',
        'hdnf': '获得年份：2026年',
        'shzt': '已通过(3300元)',
      })!;
      expect(grant.label, '国家助学金');
      expect(grant.value, '已通过(3300元)');
      expect(grant.detail, '获得年份：2026年');

      final work = dzjWorkStudyItem({
        'gwmc': '图书馆助理',
        'gwssdw': '图书馆',
        'sgnf': '2026年',
      })!;
      expect(work.label, '图书馆助理');
      expect(work.value, '图书馆');
      expect(work.detail, '2026年');

      // 关键列缺失 → 丢掉（不能让一行空标题占位）
      expect(dzjGrantItem({'shzt': '已通过'}), isNull);
      expect(dzjWorkStudyItem({'sgnf': '2026年'}), isNull);
    });

    test('文本 / 数字容错：null 与字符串 "null" 都当空；整数不写小数', () {
      expect(dzjText(null), '');
      expect(dzjText('null'), '');
      expect(dzjText('  甲  '), '甲');
      expect(dzjNumText(3.0), '3');
      expect(dzjNumText(2.5), '2.5');
      expect(dzjNumText('4'), '4');
      expect(dzjNumText('必修'), '必修');
      expect(dzjNumText(null), '');
    });

    test('行集 → 条目集：坏行丢掉、顺序保持', () {
      final items = dzjItemsOf(const [
        {'kcmc': '甲课'},
        {'kcxf': 3.0}, // 没课名 → 丢
        {'kcmc': '乙课'},
      ], dzjCourseItem);
      expect([for (final i in items) i.label], ['甲课', '乙课']);
    });
  });

  group('模块表', () {
    test('三块：课程 / 座位预约 / 奖助贷勤（key 唯一、文案与图标齐）', () {
      expect(
        [for (final m in DzjExtraModule.values) m.key],
        ['courses', 'seat', 'aid'],
      );
      expect(
        [for (final m in DzjExtraModule.values) m.title],
        ['本学期课程', '图书馆座位预约', '助学金与勤工助学'],
      );
      for (final m in DzjExtraModule.values) {
        expect(m.emptyText.trim(), isNotEmpty);
        expect(m.icon, isA<IconData>());
      }
      expect(DzjExtraModule.fromKey('seat'), DzjExtraModule.seat);
      expect(DzjExtraModule.fromKey('nope'), isNull);
    });

    test('整份结果按模块 key 查块；没拿到的模块缺席（不是空块）', () {
      const info = DzjExtraInfo(
        blocks: {
          'courses': DzjExtraBlock(
            module: DzjExtraModule.courses,
            items: [DzjInfoItem(label: '甲课', value: '3 学分')],
            total: 11,
          ),
        },
      );
      expect(info.block(DzjExtraModule.courses)!.total, 11);
      // 服务端没给 → null（界面据此走空态，而不是画一个「0 条」）
      expect(info.block(DzjExtraModule.seat), isNull);
      expect(info.isEmpty, isFalse);
      expect(DzjExtraInfo.empty.isEmpty, isTrue);
    });
  });

  group('数据中心页面', () {
    testWidgets('三张补充卡恒定渲染：没数据也有卡 + 空态文案', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjRelatedCountsProvider.overrideWith((ref) async => const {}),
        ],
      );

      for (final m in DzjExtraModule.values) {
        expect(find.text(m.title), findsOneWidget);
        expect(find.text(m.emptyText), findsOneWidget);
      }
    });

    testWidgets('有数据 → 条目行 + 「共 N 条 · 只列最近 M 条」', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith(
            (ref) async => const DzjExtraInfo(
              blocks: {
                'seat': DzjExtraBlock(
                  module: DzjExtraModule.seat,
                  items: [
                    DzjInfoItem(
                      label: '麦庐园图书馆-麦庐园-三楼东',
                      value: '自动签到',
                      detail: '2026-08-07 12:03:03~22:00:00',
                    ),
                  ],
                  total: 52,
                ),
              },
            ),
          ),
          dzjRelatedCountsProvider.overrideWith((ref) async => const {}),
        ],
      );

      expect(find.text('麦庐园图书馆-麦庐园-三楼东'), findsOneWidget);
      expect(find.text('自动签到'), findsOneWidget);
      expect(find.textContaining('共 52 条 · 只列最近 1 条'), findsOneWidget);
      // 没拿到的模块仍给空态（缺席 ≠ 消失）
      expect(find.text(DzjExtraModule.courses.emptyText), findsOneWidget);
    });

    testWidgets('读取失败 → 文案 + 该模块的重试按钮', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith(
            (ref) async => throw Exception('请先登录后再查看个人数据中心'),
          ),
          dzjRelatedCountsProvider.overrideWith((ref) async => const {}),
        ],
      );

      expect(
        find.textContaining('读取失败：请先登录后再查看个人数据中心'),
        findsNWidgets(DzjExtraModule.values.length),
      );
      expect(
        find.byKey(const Key('dzjExtraRetry-courses')),
        findsOneWidget,
      );
    });

    testWidgets('「相关人员」六维：点人数开该维度名单（第二张名单卡真在页面上）', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => const {
              'relatedDorm': 3,
              'relatedCollege': 1897,
              'relatedMajor': 746,
              'relatedClass': 48,
              'enrollDay': 7716,
              'birthday': 17,
            },
          ),
          dzjPeersProvider(DzjPeerDimension.relatedDorm).overrideWith(
            (ref) async => const [
              DzjPeer(
                userId: '2202500002',
                name: '同学乙',
                college: '计算机学院',
                sex: '男性',
              ),
            ],
          ),
        ],
      );

      expect(find.text('相关人员'), findsOneWidget);
      expect(find.text('1897 人'), findsOneWidget);
      expect(find.text('同天入校同学'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dzjPeer-relatedDorm')));
      await tester.pumpAndSettle();

      expect(find.text('同宿舍同学名单'), findsOneWidget);
      expect(find.textContaining('名单来自相关人员'), findsOneWidget);
      expect(find.text('同学乙'), findsOneWidget);
      expect(find.text('2202500002'), findsOneWidget);
      expect(find.textContaining('计算机学院 · 男性'), findsOneWidget);
    });

    testWidgets('「相关人员」读取失败 → 卡上有错误文案与重试', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => throw Exception('相关人员数据加载失败，请稍后重试'),
          ),
        ],
      );

      expect(find.textContaining('读取失败：相关人员数据加载失败'), findsOneWidget);
      expect(find.byKey(const Key('dzjRelatedRetry')), findsOneWidget);
    });

    testWidgets('「同年级同学院」：人数到手就画那一枚胶囊，点开是它自己的名单', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjRelatedCountsProvider.overrideWith((ref) async => const {}),
          // 用户 2026-09-20 立项：同年级名单再按本人学院筛 = 726 人（实测）
          dzjGradeCollegeCountProvider.overrideWith((ref) async => 726),
          dzjPeersProvider(DzjPeerDimension.gradeCollege).overrideWith(
            (ref) async => const [
              DzjPeer(
                userId: '2202500008',
                name: '陈语嫣',
                grade: '2025',
                college: '计算机学院',
                sex: '女性',
              ),
            ],
          ),
        ],
      );

      expect(find.text('同年级同学院'), findsOneWidget);
      expect(find.text('726 人'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-gradeCollege')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dzjPeer-gradeCollege')));
      await tester.pumpAndSettle();

      expect(find.text('同年级同学院名单'), findsOneWidget);
      expect(find.textContaining('名单来自校内关系'), findsOneWidget);
      expect(find.text('陈语嫣'), findsOneWidget);
      expect(find.text('2202500008'), findsOneWidget);
    });

    testWidgets('人数取不到（null）→ 那一枚胶囊不画，也不谎报 0 人', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjRelatedCountsProvider.overrideWith((ref) async => const {}),
          dzjGradeCollegeCountProvider.overrideWith((ref) async => null),
        ],
      );

      expect(find.byKey(const Key('dzjPeer-gradeCollege')), findsNothing);
      expect(find.text('同年级同学院'), findsNothing);
    });
  });
}
