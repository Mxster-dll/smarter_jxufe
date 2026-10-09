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
        // 「校内关系」五维人数（2026-10-01 从概览里拆成自己的 provider）：
        // 同上，不固定就会去打网络；要验胶囊的用例自己 override。
        dzjPeerCountsProvider.overrideWith(
          (ref) async => const <String, int>{},
        ),
        ...overrides,
      ],
      child: const MaterialApp(home: DataCenterScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 名单两路人数的一份固定值（融合后 8 目都铺得出来）。
///
/// 校内关系：同年级 900 / 同班 45 / 同年级同专业 30 / 舍友 3 / 同学院同生日 12；
/// 相关人员：同班级 47 / 同宿舍 2 / 同专业 746 / 同学院 1897 / 同天入校 7716 / 同天生日 17。
/// —— 四对同关系的人数**刻意各不相同**：融合的是入口，不是数字。
List<Override> dcPeerCountOverrides() => [
  dzjPeerCountsProvider.overrideWith(
    (ref) async => const {
      'grade': 900,
      'class': 45,
      'major': 30,
      'dorm': 3,
      'college': 12,
    },
  ),
  dzjRelatedCountsProvider.overrideWith(
    (ref) async => const {
      'relatedClass': 47,
      'relatedDorm': 2,
      'relatedMajor': 746,
      'relatedCollege': 1897,
      'enrollDay': 7716,
      'birthday': 17,
    },
  ),
];

/// 与 [dcPeerCountOverrides] 配套的**行集**：同班 / 舍友是**合并式**，方格与弹层都会
/// 去读这两对的两份名单 → 不 override 就会打真网络。
///
/// 同班：校内关系 2 行（张三 / 李四）+ 相关人员 2 行（张三 / 王五）→ 合并去重 3 人；
/// 舍友：校内关系 1 行（张三）+ 相关人员 2 行（张三 / 赵六）→ 合并去重 2 人。
List<Override> dcPeerRowOverrides() => [
  dzjPeersProvider(DzjPeerDimension.classGroup).overrideWith(
    (ref) async => const [
      DzjPeer(userId: '2202500001', name: '张三', className: '软件工程 251 班'),
      DzjPeer(userId: '2202500002', name: '李四', className: '软件工程 251 班'),
    ],
  ),
  dzjPeersProvider(DzjPeerDimension.relatedClass).overrideWith(
    (ref) async => const [
      DzjPeer(userId: '2202500001', name: '张三', college: '软件与物联网工程学院'),
      DzjPeer(userId: '2202500003', name: '王五', college: '计算机学院'),
    ],
  ),
  dzjPeersProvider(DzjPeerDimension.dorm).overrideWith(
    (ref) async => const [
      DzjPeer(userId: '2202500001', name: '张三', dorm: '蛟桥园 3 栋 412'),
    ],
  ),
  dzjPeersProvider(DzjPeerDimension.relatedDorm).overrideWith(
    (ref) async => const [
      DzjPeer(userId: '2202500001', name: '张三', college: '软件与物联网工程学院'),
      DzjPeer(userId: '2202500004', name: '赵六', college: '软件与物联网工程学院'),
    ],
  ),
];

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

    testWidgets('融合网格：8 目同屏，一个关系只出现一次（不再有第二张名单卡）', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          ...dcPeerCountOverrides(),
          ...dcPeerRowOverrides(),
          // 派生那一目也要铺得出来（pumpDataCenter 默认把它固定成 0 = 不铺）
          dzjGradeCollegeCountProvider.overrideWith((ref) async => 726),
        ],
      );

      // 一张卡：只有卡标题「校内关系」，不再有「同学名单 / 相关人员」两个分节
      expect(find.text('校内关系'), findsOneWidget);
      expect(find.text('同学名单'), findsNothing);
      expect(find.text('相关人员'), findsNothing);

      // 10 目都在；**只有同义的两对**里的「另一份」不再是独立方格
      for (final r in DzjPeerRelation.values) {
        expect(find.byKey(Key('dzjPeer-${r.key}')), findsOneWidget, reason: r.key);
      }
      for (final gone in ['relatedClass', 'relatedDorm']) {
        expect(find.byKey(Key('dzjPeer-$gone')), findsNothing, reason: gone);
      }
      // ⚠ 用户 2026-10-09 纠正的那条：子集关系各占一格，不许被并掉
      expect(find.text('同年级同专业'), findsOneWidget);
      expect(find.text('同专业同学'), findsOneWidget);
      expect(find.text('同学院同生日'), findsOneWidget);
      expect(find.text('同学院同学'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-major')), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-relatedMajor')), findsOneWidget);

      // 同义的两格显示的是**合并去重后**的人数（fixture：同班 2+2→3、舍友 1+2→2），
      // 不是服务端计数（45 / 3）—— 用户 2026-10-09 拍板「方格预取并显示合并后的真实人数」。
      expect(find.text('3 人'), findsOneWidget); // 同班同学
      expect(find.text('2 人'), findsOneWidget); // 舍友

      await tester.tap(find.byKey(const Key('dzjPeer-class')));
      await tester.pumpAndSettle();

      expect(find.text('同班同学名单'), findsOneWidget);
      expect(
        find.textContaining('名单来自校内关系 + 相关人员（合并去重）'),
        findsOneWidget,
      );
      expect(find.textContaining('已合并：校内关系 2 行 · 相关人员 2 行'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      // 只在「相关人员」里收录的人也在（带小标）—— 信息归并，不是把人丢掉
      expect(find.text('王五'), findsOneWidget);
      expect(find.textContaining('仅「相关人员」名单收录'), findsOneWidget);
    });

    testWidgets('两份都失败 → 卡上一条错误文案 + 一枚「重新读取」', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjPeerCountsProvider.overrideWith(
            (ref) async => throw Exception('校内关系人数加载失败'),
          ),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => throw Exception('相关人员数据加载失败，请稍后重试'),
          ),
        ],
      );

      expect(find.textContaining('读取失败：'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerRetry')), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-class')), findsNothing);
      // 两张卡时代的老 key 不许复活
      expect(find.byKey(const Key('dzjRelatedRetry')), findsNothing);
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

    // ---- 2026-10-09 融合（用户：「这两个功能本身就很极高的相似度，那不如直接融合为一个
    //      功能。所有的卡片统一样式，然后重复的卡片不重复显示，可以归并的信息就归并显示」）----

    testWidgets('一份网格按人数降序（10 目同排；同人数保持目序）', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          ...dcPeerCountOverrides(),
          ...dcPeerRowOverrides(),
          dzjGradeCollegeCountProvider.overrideWith((ref) async => 726),
        ],
      );

      // 阅读顺序（先上后下、同行先左后右）——只比 dx 会在换行时假绿。
      List<String> orderOf(List<String> keys) {
        final list = [...keys];
        list.sort((a, b) {
          final pa = tester.getTopLeft(find.byKey(Key('dzjPeer-$a')));
          final pb = tester.getTopLeft(find.byKey(Key('dzjPeer-$b')));
          final byY = pa.dy.compareTo(pb.dy);
          return byY != 0 ? byY : pa.dx.compareTo(pb.dx);
        });
        return list;
      }

      expect(
        orderOf([
          'birthday',
          'class',
          'grade',
          'college',
          'enrollDay',
          'major',
          'dorm',
          'gradeCollege',
          'relatedMajor',
          'relatedCollege',
        ]),
        [
          'enrollDay', // 7716
          'relatedCollege', // 1897（**它自己那一目**，不是「同学院同生日」的）
          'grade', // 900
          'relatedMajor', // 746（同上：不借给「同年级同专业」）
          'gradeCollege', // 726
          'class', // 45
          'major', // 30（自己那一份）
          'birthday', // 17
          'college', // 12
          'dorm', // 3
        ],
      );
    });

    testWidgets('同义两对是**合并式**：页面上没有来源切换控件，方格人数 = 合并后', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          ...dcPeerCountOverrides(),
          ...dcPeerRowOverrides(),
        ],
      );

      // 「切换式」的痕迹全没了：没有 ⇄、没有「另一份 N 人」
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.textContaining('另一份'), findsNothing);
      // 方格上是合并后的人数，而不是那两份的计数（45 / 47 / 3 / 2）
      expect(find.text('3 人'), findsOneWidget); // 同班：2 + 2 去重 → 3
      expect(find.text('2 人'), findsOneWidget); // 舍友：1 + 2 去重 → 2
      expect(find.text('45 人'), findsNothing);
      expect(find.text('47 人'), findsNothing);
      // 脚注交代这是合并来的
      expect(find.textContaining('同班 / 舍友 = 两份名单已合并去重'), findsOneWidget);
    });

    testWidgets('计数只有另一份时也照铺，但人数仍是**合并后**的（不是那一份的计数）', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          // 「校内关系」那一份只回了同年级 —— 同班 / 舍友 / 同专业 / 同学院全缺
          dzjPeerCountsProvider.overrideWith(
            (ref) async => const {'grade': 900},
          ),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => const {'relatedClass': 47},
          ),
          ...dcPeerRowOverrides(),
        ],
      );

      // 「同班同学」那一格在（计数来自另一份），但人数 = 合并去重后的 3，不是 47
      expect(find.byKey(const Key('dzjPeer-class')), findsOneWidget);
      expect(find.text('3 人'), findsOneWidget);
      expect(find.text('47 人'), findsNothing);

      await tester.tap(find.byKey(const Key('dzjPeer-class')));
      await tester.pumpAndSettle();
      expect(find.text('同班同学名单'), findsOneWidget);
      expect(find.textContaining('已合并：校内关系 2 行 · 相关人员 2 行'), findsOneWidget);
      // 服务端计数 47 > 取回 2 行 → 如实说「只列已取回的部分」
      expect(find.textContaining('只列已取回的部分；服务端计数 相关人员 47'), findsOneWidget);
    });

    testWidgets('一份失败不连坐：脚注如实说「那一份没取到」，另一份照铺', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          dzjPeerCountsProvider.overrideWith(
            (ref) async => throw Exception('校内关系人数加载失败'),
          ),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => const {'enrollDay': 7716, 'birthday': 17},
          ),
        ],
      );

      // 只剩「相关人员」独有的两目铺得出来
      expect(find.byKey(const Key('dzjPeer-enrollDay')), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-birthday')), findsOneWidget);
      expect(find.byKey(const Key('dzjPeer-class')), findsNothing);
      expect(find.byKey(const Key('dzjPeer-dorm')), findsNothing);
      // 失败不静默：脚注写明是哪一份没取到、为什么
      expect(find.textContaining('「校内关系」那一份没取到'), findsOneWidget);
      expect(find.textContaining('校内关系人数加载失败'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerRetry')), findsOneWidget);
    });

    testWidgets('占比条：只画在行集不跨年级的目上，分母写进脚注', (tester) async {
      await pumpDataCenter(
        tester,
        overrides: [
          dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
          ...dcPeerCountOverrides(),
          ...dcPeerRowOverrides(),
          dzjGradeCollegeCountProvider.overrideWith((ref) async => 726),
        ],
      );

      // 画：同班同学 / 同年级同专业 / 同年级同学院（同班必然同年级）
      for (final key in ['class', 'major', 'gradeCollege']) {
        expect(find.byKey(Key('dzjPeerBar-$key')), findsOneWidget, reason: key);
      }
      // 不画：舍友 / 同学院同生日 / 同年级 / 同专业同学 / 同学院同学 / 同天入校 / 同天生日
      // （行集会跨年级；「同年级同专业」有约束但那条约束就是年级，仍然可画）
      for (final key in [
        'dorm',
        'college',
        'grade',
        'relatedMajor',
        'relatedCollege',
        'enrollDay',
        'birthday',
      ]) {
        expect(find.byKey(Key('dzjPeerBar-$key')), findsNothing, reason: key);
      }
      // 一份卡只有一条脚注（分母 = 同年级 900 人）
      expect(find.textContaining('占比条 = 占同年级 900 人'), findsOneWidget);
    });
  });
}
