/// 校内关系 / 相关人员**名单**（学生个人数据中心）· 守卫。
///
/// 立项口径（用户 2026-09-19）：「学生个人数据中心，是可以看到同寝室人员、同班级
/// 等等，我希望你都支持查询这些信息」→ 卡片上的「3 人 / 48 人」要能点开看**是谁**；
/// 同日二轮又点名了学校**第二个**页面：「数据中心有两个可以查看相关同学的地方……
/// 这两个部分的同学名单我都要，但是后者可以查看学号班级和年级，前者只能看姓名学院；
/// 我希望都放入学生数据中心」→ 两个组件（[DzjPeerSource]）共用一套维度表与弹层。
///
/// 本文件守四件事：
/// 1. 服务端行 → [DzjPeer] 的列名容错（列名没有文档，`select *` 的列随表走）；
/// 2. 「校内关系」五维的键与 `DataCenterOverview.peerCounts` 严格一致
///    （「48 人」与名单长度对得上）；
/// 3. 两个组件的 id / 指标位不串（串了就会「点同班看舍友」）；
/// 4. 弹层的四态（加载 / 名单 / 空 / 失败）都讲得清。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_peer_sheet.dart';

/// 一行学生记录（与 `select * from t_xssj_bzks` 的列名同形）。
Map<String, dynamic> srow({
  Object? username = '张三',
  Object? userid = '2202500001',
  Object? ssbj = '软件工程 251 班',
  Object? sszy = '软件工程',
  Object? ssdz = '蛟桥园 3 栋 412',
  Object? ssdw = '软件与物联网工程学院',
  Object? sznj = '2025',
}) => {
  'username': username,
  'userid': userid,
  'ssbj': ssbj,
  'sszy': sszy,
  'ssdz': ssdz,
  'ssdw': ssdw,
  'sznj': sznj,
};

DzjPeer peer(String name, {String id = ''}) =>
    DzjPeer(userId: id, name: name);

/// 挂一个「打开名单弹层」的宿主页并点开。
Future<void> openSheet(
  WidgetTester tester, {
  required List<Override> overrides,
  DzjPeerDimension dimension = DzjPeerDimension.dorm,
  int? count,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const Key('openSheet'),
                onPressed: () =>
                    showDzjPeerSheet(context, dimension: dimension, count: count),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openSheet')));
  await tester.pumpAndSettle();
}

void main() {
  group('行解析（列名容错）', () {
    test('标准列名 → 全字段', () {
      final p = DzjPeer.fromRow(srow())!;
      expect(p.userId, '2202500001');
      expect(p.name, '张三');
      expect(p.className, '软件工程 251 班');
      expect(p.major, '软件工程');
      expect(p.dorm, '蛟桥园 3 栋 412');
      expect(p.college, '软件与物联网工程学院');
      expect(p.grade, '2025');
    });

    test('真实回包（2026-09-19 实测）：ykth 学号 + 随维度走的那一列', () {
      // 舍友维度（index 3）实测行：只有 学号/姓名/校区/性别
      final roommate = DzjPeer.fromRow({
        'ykth': '2202500002',
        'username': '同学乙',
        'ssxq': '麦庐园校区',
        'sex': '男性',
      })!;
      expect(roommate.userId, '2202500002');
      expect(roommate.name, '同学乙');
      expect(roommate.sex, '男性');
      expect(roommate.subtitle, '麦庐园校区 · 男性');

      // 同班维度（index 1）实测行
      final mate = DzjPeer.fromRow({
        'ykth': '2202500005',
        'username': '同学戊',
        'sznj': '2025',
        'ssbj': '25计算机2班',
        'sex': '男性',
      })!;
      expect(mate.grade, '2025');
      expect(mate.subtitle, '2025 · 25计算机2班 · 男性');

      // 同年级同专业维度（index 2）实测行
      final sameMajor = DzjPeer.fromRow({
        'ykth': '2202500006',
        'username': '万东旭',
        'sszy': '计算机科学与技术',
      })!;
      expect(sameMajor.subtitle, '计算机科学与技术');

      // 同年级维度（index 0）实测行
      final sameGrade = DzjPeer.fromRow({
        'ykth': '2202500007',
        'username': '乐琳云',
        'ssdw': 'VR学院',
      })!;
      expect(sameGrade.subtitle, 'VR学院');
    });

    test('别名列名 / 大写 / 中文列名都能认', () {
      expect(DzjPeer.fromRow({'xm': '李四', 'xh': '1'})!.name, '李四');
      expect(DzjPeer.fromRow({'XM': '王五', 'XH': '2'})!.name, '王五');
      expect(DzjPeer.fromRow({'姓名': '赵六', '学号': '3'})!.name, '赵六');
      expect(
        DzjPeer.fromRow({'cnname': '钱七', 'user_id': 4, 'bj': '251'})!.name,
        '钱七',
      );
    });

    test('非字符串值转字符串、空值跳过、脏行丢弃', () {
      final p = DzjPeer.fromRow({'username': '孙八', 'userid': 2025001})!;
      expect(p.userId, '2025001');
      // 姓名列为空白 → 回落学号
      expect(DzjPeer.fromRow({'username': '   ', 'userid': '9'})!.name, '9');
      // 姓名与学号都取不到 → 这行没用
      expect(DzjPeer.fromRow({'ssbj': '251 班'}), isNull);
      expect(DzjPeer.fromRow(const <String, dynamic>{}), isNull);
      expect(DzjPeer.fromRow({'username': ''}), isNull);
    });

    test('真实回包（2026-09-19 实测）：「相关人员」组件只有 姓名/性别/卡号/学院', () {
      // 组件 u:af43933a919c index 0「同宿舍同学」实测行（另有列名 `kh` 的形式）
      final related = DzjPeer.fromRow({
        'username': '同学丙',
        'userid': '2202500003',
        'dept': '计算机学院',
        'sex': '男性',
      })!;
      expect(related.userId, '2202500003');
      expect(related.name, '同学丙');
      expect(related.college, '计算机学院');
      expect(related.subtitle, '计算机学院 · 男性');
      // 该组件没有班级/年级列 → 不会凭空多出内容
      expect(related.className, '');
      expect(related.grade, '');

      // `kh`（校园卡号）也是学号别名
      expect(DzjPeer.fromRow({'username': '同学丁', 'kh': '2202500004'})!.userId,
          '2202500004');
      // 同天生日维度姓名**脱敏**，照原样显示
      expect(DzjPeer.fromRow({'username': '甲**', 'dept': '某学院'})!.name, '甲**');
    });

    test('subtitle：年级 · 班级 · 专业 · 宿舍 · 校区 · 学院 · 性别，拿到几列拼几列', () {
      // 服务端每个维度只给一两列（见上两条真实回包），这里用「全都有」的行验拼接顺序
      expect(
        DzjPeer.fromRow(srow())!.subtitle,
        '2025 · 软件工程 251 班 · 软件工程 · 蛟桥园 3 栋 412 · 软件与物联网工程学院',
      );
      expect(
        DzjPeer.fromRow({'username': '甲', 'ssdw': '某学院'})!.subtitle,
        '某学院',
      );
      expect(DzjPeer.fromRow({'username': '乙'})!.subtitle, '');
    });

    test('排序：姓名（UTF-16 码点序，不是拼音）→ 学号兜底，与输入顺序无关', () {
      final a = DzjPeer.sorted([
        peer('丙', id: '3'),
        peer('甲', id: '1'),
        peer('甲', id: '0'),
        peer('乙', id: '2'),
      ]);
      // 中文按码点排：丙(U+4E19) < 乙(U+4E59) < 甲(U+7532)；同姓名按学号
      expect(
        [for (final p in a) '${p.name}${p.userId}'],
        ['丙3', '乙2', '甲0', '甲1'],
      );
    });
  });

  group('维度表', () {
    test('校内关系五维：键与数据中心 peerCounts 一一对应（顺序 = 卡片铺排）', () {
      final dims = DzjPeerDimension.relationDims;
      expect([for (final d in dims) d.key], [
        'grade',
        'class',
        'major',
        'dorm',
        'college',
      ]);
      expect([for (final d in dims) d.label], [
        '同年级',
        '同班同学',
        '同年级同专业',
        '舍友',
        '同学院同生日',
      ]);
      expect(DzjPeerDimension.fromKey('dorm'), DzjPeerDimension.dorm);
      expect(DzjPeerDimension.fromKey('nope'), isNull);
    });

    test('相关人员六维：独立键 + 独立指标位（与校内关系不撞）', () {
      final dims = DzjPeerDimension.relatedDims;
      expect(dims, hasLength(6));
      expect([for (final d in dims) d.key], [
        'relatedDorm',
        'relatedCollege',
        'relatedMajor',
        'relatedClass',
        'enrollDay',
        'birthday',
      ]);
      expect([for (final d in dims) d.label], [
        '同宿舍同学',
        '同学院同学',
        '同专业同学',
        '同班级同学',
        '同天入校同学',
        '同天生日同学',
      ]);
      // 指标位 = 组件内 index，六维必须是 0..5（与学校页面 timeList 顺序一致）
      expect([for (final d in dims) d.slot], [0, 1, 2, 3, 4, 5]);
      // 两个组件 id 都不能写错（写错就是「点同班看舍友」）
      expect(DzjPeerSource.relation.componentId, 'u:fcd2d17a9131');
      expect(DzjPeerSource.related.componentId, 'u:af43933a919c');
      for (final d in dims) {
        expect(d.source, DzjPeerSource.related);
      }
      expect(
        [for (final d in DzjPeerDimension.relationDims) d.slot],
        [0, 1, 2, 3, 4],
      );
    });

    test('全维度键唯一（否则卡片 key 会撞、点击串维度）', () {
      final keys = [for (final d in DzjPeerDimension.values) d.key];
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('每个维度都有图标（弹层与数据中心胶囊共用）', () {
      for (final d in DzjPeerDimension.values) {
        expect(dzjPeerIcon(d), isA<IconData>());
      }
    });
  });

  group('「同年级同学院」（派生维度 · 用户 2026-09-20 立项）', () {
    const derived = DzjPeerDimension.gradeCollege;

    test('定义：复用「同年级」那一路行集 + 服务端过滤谓词 + pageSize 上限', () {
      expect(derived.key, 'gradeCollege');
      expect(derived.label, '同年级同学院');
      expect(derived.source, DzjPeerSource.relation);
      expect(derived.slot, DzjPeerDimension.grade.slot);
      expect(derived.filterSql, dzjCollegeFilterSql);
      expect(derived.limit, dzjMaxPeerPageSize);
      // 实测上限：`pageSize` 给 2000/8000 都回「50000 分数数据量不能大于500」
      expect(dzjMaxPeerPageSize, 500);
    });

    test('不在「校内关系五维」里（那一组的键必须与 peerCounts 一一对应）', () {
      expect(
        DzjPeerDimension.relationDims,
        isNot(contains(derived)),
      );
      expect(DzjPeerDimension.filteredDims, [derived]);
      expect(DzjPeerDimension.fromKey('gradeCollege'), derived);
    });

    test('谓词用服务端占位符取本人学院 —— 本地学籍的名字对不上（实测回 0 人）', () {
      expect(dzjCollegeFilterSql, contains('ssdw='));
      expect(dzjCollegeFilterSql, contains('t_xssj_bzks'));
      // `#{U_用户名}` 由服务端按会话解析；客户端**不许**把「计算机与人工智能学院」拼进去
      expect(dzjCollegeFilterSql, contains('#{U_用户名}'));
      expect(dzjCollegeFilterSql, isNot(contains('计算机')));
    });

    test('请求体：只有它带 filterConfig，其余维度一律空表（原样行集）', () {
      final fc = DzjApiRemoteDataSource.peerFilterOf(derived);
      expect(fc, hasLength(1));
      final entry = fc.single! as Map<String, Object?>;
      expect(entry['filterType'], 'sql');
      expect(entry['type'], 'VARCHAR2');
      expect(entry['values'], [dzjCollegeFilterSql]);
      for (final d in DzjPeerDimension.values) {
        if (d == derived) continue;
        expect(DzjApiRemoteDataSource.peerFilterOf(d), isEmpty, reason: d.key);
        expect(d.filterSql, isNull, reason: d.key);
        expect(d.limit, 300, reason: d.key);
      }
    });
  });

  group('名单弹层', () {
    testWidgets('渲染姓名 / 学号 / 班级，标题带人数', (tester) async {
      await openSheet(
        tester,
        count: 3,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.dorm).overrideWith(
            (ref) async => [
              const DzjPeer(
                userId: '2202500001',
                name: '张三',
                className: '软件工程 251 班',
                dorm: '蛟桥园 3 栋 412',
              ),
              const DzjPeer(userId: '2202500004', name: '李四'),
            ],
          ),
        ],
      );

      expect(find.text('舍友名单'), findsOneWidget);
      // 卡片上写 3 人（服务端 total），实际只取回 2 行 → 明说「已列出前 2 人」
      expect(find.textContaining('共 3 人 · 已列出前 2 人'), findsOneWidget);
      expect(find.textContaining('名单来自校内关系'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('2202500001'), findsOneWidget);
      expect(find.textContaining('软件工程 251 班'), findsOneWidget);
    });

    testWidgets('「相关人员」维度：标题 / 行 / 出处都按该组件走', (tester) async {
      await openSheet(
        tester,
        dimension: DzjPeerDimension.relatedClass,
        count: 48,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.relatedClass).overrideWith(
            (ref) async => const [
              DzjPeer(
                userId: '2202500003',
                name: '同学丙',
                college: '计算机学院',
                sex: '男性',
              ),
            ],
          ),
        ],
      );

      expect(find.text('同班级同学名单'), findsOneWidget);
      expect(find.textContaining('名单来自相关人员'), findsOneWidget);
      expect(find.text('同学丙'), findsOneWidget);
      expect(find.text('2202500003'), findsOneWidget);
      // 该名单只有姓名/学院（+性别）→ 副标题里不会冒出班级年级
      expect(find.textContaining('计算机学院 · 男性'), findsOneWidget);
    });

    testWidgets('名单为空 → 明确说没有，并给「重试」', (tester) async {
      var calls = 0;
      await openSheet(
        tester,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.dorm).overrideWith((ref) async {
            calls++;
            return calls == 1
                ? const <DzjPeer>[]
                : const [DzjPeer(userId: '1', name: '张三')];
          }),
        ],
      );

      expect(find.textContaining('没有查到'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerRetry')), findsOneWidget);

      // 重试 → 重新拉取（不是显示旧缓存）
      await tester.tap(find.byKey(const Key('dzjPeerRetry')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('张三'), findsOneWidget);
    });

    testWidgets('读取失败 → 错误文案 + 重试按钮', (tester) async {
      await openSheet(
        tester,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.classGroup).overrideWith(
            (ref) async => throw Exception('请先登录后再查看个人数据中心'),
          ),
        ],
        dimension: DzjPeerDimension.classGroup,
      );

      expect(find.textContaining('名单读取失败：请先登录后再查看个人数据中心'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerRetry')), findsOneWidget);
    });

    test('错误文案去掉 Exception: 前缀', () {
      expect(friendlyErrorText(Exception('会话失效')), '会话失效');
      expect(friendlyErrorText('裸字符串'), '裸字符串');
    });
  });
}
