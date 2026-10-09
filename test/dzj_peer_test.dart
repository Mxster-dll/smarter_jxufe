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
  // 默认用**只有一份名单**的维度（同年级同专业）。⚠ 别改回 `dorm` —— 同班 / 舍友
  // 现在是**合并式**（要同时读两份名单），默认成它们会让「普通名单」的用例悄悄
  // 走到合并路径上，缺 override 时直接打真网络。
  DzjPeerDimension dimension = DzjPeerDimension.major,
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
                onPressed: () => showDzjPeerSheet(
                  context,
                  dimension: dimension,
                  count: count,
                ),
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

  group('融合后的关系目（2026-10-09 · 一个关系只出现一次）', () {
    test('10 目：只有**同义**的两对能并，子集关系各占一目', () {
      expect(DzjPeerRelation.values, hasLength(10));
      expect([for (final r in DzjPeerRelation.values) r.key], [
        'grade',
        'gradeCollege',
        'class',
        'major',
        'relatedMajor',
        'dorm',
        'college',
        'relatedCollege',
        'enrollDay',
        'birthday',
      ]);
      // 能并的只有同义两对：同班 = 同班级（同班必然同年级）、舍友 = 同宿舍。
      expect(DzjPeerRelation.classGroup.primary, DzjPeerDimension.classGroup);
      expect(DzjPeerRelation.classGroup.twin, DzjPeerDimension.relatedClass);
      expect(DzjPeerRelation.dorm.primary, DzjPeerDimension.dorm);
      expect(DzjPeerRelation.dorm.twin, DzjPeerDimension.relatedDorm);
      // **白名单**：全仓能并的只有这两对。想加第三对，先回答一句
      // 「这两个行集是不是同一个集合」—— 子集关系（带额外约束的那一侧）一律不许并。
      expect(
        {
          for (final r in DzjPeerRelation.values)
            if (r.twin != null) r.key,
        },
        {'class', 'dorm'},
        reason: '用户 2026-10-09 两次纠正：'
            '「同年级同专业」≠「同专业」、「同学院同生日」≠「同学院同学」',
      );
      // ⚠ 用户 2026-10-09 当面纠正：这两对**不是同义**，不许并 ——
      // 「同年级同专业」= 同年级 ∧ 同专业（子集），「同专业同学」不限年级；
      // 「同学院同生日」同样多一个生日约束。并起来就是把口径偷换成另一个数。
      for (final key in ['major', 'college', 'relatedMajor', 'relatedCollege']) {
        final r = DzjPeerRelation.fromKey(key)!;
        expect(r.twin, isNull, reason: '$key 不许有另一份口径');
        expect(r.primary.key, key, reason: key);
      }
      expect(DzjPeerRelation.major.primary, DzjPeerDimension.major);
      expect(DzjPeerRelation.relatedMajor.primary, DzjPeerDimension.relatedMajor);
      expect(DzjPeerRelation.college.primary, DzjPeerDimension.college);
      expect(
        DzjPeerRelation.relatedCollege.primary,
        DzjPeerDimension.relatedCollege,
      );
      for (final key in ['grade', 'gradeCollege', 'enrollDay', 'birthday']) {
        expect(DzjPeerRelation.fromKey(key)!.twin, isNull, reason: key);
      }
      // 配对是「界面上一格」的事 → 挂在关系目上，维度层不再自带。
      expect(DzjPeerRelation.fromKey('dorm'), DzjPeerRelation.dorm);
    });

    test('融合不改写任何一路的组件与指标位（改了就「点同班看舍友」）', () {
      for (final r in DzjPeerRelation.values) {
        for (final d in [r.primary, if (r.twin != null) r.twin!]) {
          expect(DzjPeerDimension.fromKey(d.key), d, reason: d.key);
        }
      }
      expect(DzjPeerDimension.classGroup.source, DzjPeerSource.relation);
      expect(DzjPeerDimension.classGroup.slot, 1);
      expect(DzjPeerDimension.relatedClass.source, DzjPeerSource.related);
      expect(DzjPeerDimension.relatedClass.slot, 3);
      expect(DzjPeerDimension.relatedDorm.slot, 0);
      expect(DzjPeerDimension.relatedMajor.slot, 2);
      expect(DzjPeerDimension.relatedCollege.slot, 1);
    });

    test('占比条只画在「行集不跨年级」的四维上', () {
      expect(
        {for (final d in DzjPeerDimension.values) if (d.gradeScoped) d.key},
        {'class', 'major', 'gradeCollege', 'relatedClass'},
      );
      for (final d in DzjPeerDimension.values) {
        if (d.gradeScoped) continue;
        expect(
          dzjPeerGradeRatio(d, count: 1, gradeCount: 100),
          isNull,
          reason: '${d.key} 的行集会跨年级，拿同年级当分母是假比例',
        );
      }
    });

    test('占比：正常值；人数 0 / 分母缺失 / 分母 0 / 超 100% 一律不画', () {
      expect(
        dzjPeerGradeRatio(
          DzjPeerDimension.classGroup,
          count: 45,
          gradeCount: 900,
        ),
        closeTo(0.05, 1e-9),
      );
      expect(
        dzjPeerGradeRatio(
          DzjPeerDimension.classGroup,
          count: 900,
          gradeCount: 900,
        ),
        1.0,
      );
      expect(
        dzjPeerGradeRatio(DzjPeerDimension.classGroup, count: 0, gradeCount: 900),
        isNull,
      );
      expect(
        dzjPeerGradeRatio(
          DzjPeerDimension.classGroup,
          count: 45,
          gradeCount: null,
        ),
        isNull,
      );
      expect(
        dzjPeerGradeRatio(DzjPeerDimension.classGroup, count: 45, gradeCount: 0),
        isNull,
      );
      // 口径异常（行集不可能比同年级还大）→ 宁可不画，也不画一条满格的假条。
      expect(
        dzjPeerGradeRatio(
          DzjPeerDimension.classGroup,
          count: 1000,
          gradeCount: 900,
        ),
        isNull,
      );
    });

    test('铺排：按人数降序；同人数保持目序；没拿到的目不铺', () {
      final entries = DzjPeerEntry.build(
        relationCounts: const {'grade': 726, 'class': 45, 'major': 30, 'dorm': 4},
        relatedCounts: const {
          'relatedClass': 47,
          'relatedDorm': 3,
          'relatedMajor': 746,
          'relatedCollege': 1897,
          'enrollDay': 7716,
          'birthday': 17,
        },
        gradeCollege: 726,
      );
      // enrollDay 7716 > relatedCollege 1897 > relatedMajor 746 > grade 726
      // = gradeCollege 726（同人数 → 保持目序）> class 45 > major 30 > birthday 17 > dorm 4
      expect([for (final e in entries) e.relation.key], [
        'enrollDay',
        'relatedCollege',
        'relatedMajor',
        'grade',
        'gradeCollege',
        'class',
        'major',
        'birthday',
        'dorm',
      ]);
      final byKey = {for (final e in entries) e.relation.key: e};
      expect(byKey['class']!.dimension, DzjPeerDimension.classGroup);
      expect(byKey['class']!.count, 45);
      expect(byKey['class']!.twinCount, 47);
      expect(byKey['dorm']!.count, 4);
      expect(byKey['dorm']!.twinCount, 3);
      // 「同年级同专业」用**自己的** 30，不借「同专业同学」的 746；
      // 「同学院同生日」这一份没拿到 → **整目不铺**（不拿更大的行集冒充）。
      expect(byKey['major']!.count, 30);
      expect(byKey['major']!.twinCount, isNull);
      expect(byKey.containsKey('college'), isFalse);
      expect(byKey['relatedMajor']!.count, 746);
      expect(byKey['relatedCollege']!.count, 1897);
      expect(byKey['enrollDay']!.otherDimension, isNull);
    });

    test('只有同义的两对会回落；子集关系缺了就是不铺', () {
      final fell = DzjPeerEntry.build(
        relationCounts: const {'grade': 100},
        relatedCounts: const {'relatedClass': 47},
        gradeCollege: null,
      );
      final cls = fell.singleWhere((e) => e.relation.key == 'class');
      expect(cls.dimension, DzjPeerDimension.relatedClass);
      expect(cls.count, 47);
      expect(cls.twinCount, isNull);
      expect(cls.otherDimension, DzjPeerDimension.classGroup);

      final none = DzjPeerEntry.build(
        relationCounts: const {'grade': 100},
        relatedCounts: const {'relatedMajor': 746, 'relatedCollege': 1897},
        gradeCollege: null,
      );
      // 「同年级同专业」「同学院同生日」的主口径没数据 → 这两目**不铺**，
      // 绝不拿「同专业同学 / 同学院同学」的数顶替（它们各是各的一目）。
      expect([for (final e in none) e.relation.key], [
        'relatedCollege',
        'relatedMajor',
        'grade',
      ]);
      expect(none.any((e) => e.relation.key == 'major'), isFalse);
      expect(none.any((e) => e.relation.key == 'college'), isFalse);
    });

    test('合并：按学号去重、字段取并集、来源可追溯（没学号才回落到姓名）', () {
      final merged = dzjPeerMerge(
        primary: const [
          DzjPeer(userId: '1', name: '甲', className: '251 班', grade: '2025'),
          DzjPeer(userId: '2', name: '乙', className: '251 班'),
          DzjPeer(name: '丙'), // 没学号 → 以姓名当键
        ],
        primarySource: DzjPeerSource.relation,
        twin: const [
          DzjPeer(userId: '1', name: '甲', college: '计算机学院', sex: '男性'),
          DzjPeer(userId: '3', name: '丁', college: '计算机学院'),
          DzjPeer(name: '丙', college: '计算机学院'), // 同名 + 都没学号 → 并成一行
        ],
        twinSource: DzjPeerSource.related,
      );

      expect(merged.primaryRows, 3);
      expect(merged.twinRows, 3);
      // 4 个人：甲 / 乙 / 丙 / 丁（甲与丙被两份名单都收录，去重后不重复计）
      expect(merged.count, 4);

      final byId = {for (final r in merged.rows) r.peer.userId: r};
      final jia = byId['1']!;
      // 字段取并集：班级 / 年级来自校内关系，学院 / 性别来自相关人员
      expect(jia.peer.className, '251 班');
      expect(jia.peer.grade, '2025');
      expect(jia.peer.college, '计算机学院');
      expect(jia.peer.sex, '男性');
      expect(jia.sources, {DzjPeerSource.relation, DzjPeerSource.related});
      expect(jia.relatedOnly, isFalse);

      final ding = byId['3']!;
      expect(ding.relatedOnly, isTrue);
      expect(ding.sources, {DzjPeerSource.related});

      final bing = merged.rows.where((r) => r.peer.name == '丙').toList();
      expect(bing, hasLength(1));
      expect(bing.single.peer.college, '计算机学院');
      expect(bing.single.relatedOnly, isFalse);

      // 排序与 `DzjPeer.sorted` 同口径：姓名（码点序）→ 同名时学号
      expect([for (final r in merged.rows) r.peer.name], ['丁', '丙', '乙', '甲']);
    });

    test('没拿到的目不铺（不谎报 0 人）；真·0 人照铺、-1 当作没有', () {
      final entries = DzjPeerEntry.build(
        relationCounts: const {'class': 0, 'dorm': -1},
        relatedCounts: const {},
        gradeCollege: null,
      );
      expect([for (final e in entries) e.relation.key], ['class']);
      expect(entries.single.count, 0);
      expect(entries.single.twinCount, isNull);
    });

    test('同年级同学院：人数单独一问；0 与「没拿到」一样不铺', () {
      final drawn = DzjPeerEntry.build(
        relationCounts: const {},
        relatedCounts: const {},
        gradeCollege: 726,
      );
      expect([for (final e in drawn) e.relation.key], ['gradeCollege']);
      expect(drawn.single.count, 726);
      for (final value in [null, 0, -1]) {
        expect(
          DzjPeerEntry.build(
            relationCounts: const {},
            relatedCounts: const {},
            gradeCollege: value,
          ),
          isEmpty,
          reason: 'gradeCollege=$value 不该铺（口径同 2026-09-20 那轮）',
        );
      }
    });
  });

  group('名单弹层', () {
    testWidgets('渲染姓名 / 学号 / 班级，标题带人数', (tester) async {
      await openSheet(
        tester,
        count: 3,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.major).overrideWith(
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

      expect(find.text('同年级同专业名单'), findsOneWidget);
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
        // 用**只有一份名单**的那一维（同班级同学是合并式，不能拿来验"单一来源"）
        dimension: DzjPeerDimension.relatedMajor,
        count: 48,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.relatedMajor).overrideWith(
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

      expect(find.text('同专业同学名单'), findsOneWidget);
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
          dzjPeersProvider(DzjPeerDimension.major).overrideWith((ref) async {
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
          dzjPeersProvider(DzjPeerDimension.major).overrideWith(
            (ref) async => throw Exception('请先登录后再查看个人数据中心'),
          ),
        ],
      );

      expect(find.textContaining('名单读取失败：请先登录后再查看个人数据中心'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerRetry')), findsOneWidget);
    });

    test('错误文案去掉 Exception: 前缀', () {
      expect(friendlyErrorText(Exception('会话失效')), '会话失效');
      expect(friendlyErrorText('裸字符串'), '裸字符串');
    });

    testWidgets('合并式：同班打开是**一份合并名单**（按学号去重 + 字段取并集 + 只在一份里的加小标）', (tester) async {
      await openSheet(
        tester,
        dimension: DzjPeerDimension.classGroup,
        count: 3,
        overrides: [
          // 服务端计数与取回的行数一致（2 / 2）→ 副标题不带"只列已取回的部分"
          dzjPeerCountsProvider.overrideWith((ref) async => const {'class': 2}),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => const {'relatedClass': 2},
          ),
          dzjPeersProvider(DzjPeerDimension.classGroup).overrideWith(
            (ref) async => const [
              DzjPeer(
                userId: '2202500001',
                name: '张三',
                className: '软件工程 251 班',
                grade: '2025',
              ),
              DzjPeer(userId: '2202500002', name: '李四', className: '软件工程 251 班'),
            ],
          ),
          dzjPeersProvider(DzjPeerDimension.relatedClass).overrideWith(
            (ref) async => const [
              // 同一个人（学号相同）→ 去重，字段取并集
              DzjPeer(
                userId: '2202500001',
                name: '张三',
                college: '软件与物联网工程学院',
                sex: '男性',
              ),
              // 只在「相关人员」里收录的一个人
              DzjPeer(userId: '2202500003', name: '王五', college: '计算机学院'),
            ],
          ),
        ],
      );

      // 一份名单：**没有来源切换控件**（用户 2026-10-09：「不用做成切换式的」）
      expect(find.text('同班同学名单'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerSource-class')), findsNothing);
      expect(find.byKey(const Key('dzjPeerSource-relatedClass')), findsNothing);
      // 人数 = 合并去重后的行数，并把两份各多少行写清楚
      expect(
        find.textContaining('共 3 人 · 已合并：校内关系 2 行 · 相关人员 2 行'),
        findsOneWidget,
      );
      expect(
        find.textContaining('名单来自校内关系 + 相关人员（合并去重）'),
        findsOneWidget,
      );
      expect(find.textContaining('这里按学号合并去重'), findsOneWidget);
      // 张三：两条记录并成一行 —— 班级/年级（校内关系）+ 学院/性别（相关人员）都在
      expect(find.text('张三'), findsOneWidget);
      expect(
        find.textContaining('2025 · 软件工程 251 班 · 软件与物联网工程学院 · 男性'),
        findsOneWidget,
      );
      // 只在「相关人员」里收录的人带小标（信息归并，不是把人丢掉）
      expect(find.textContaining('计算机学院 · 仅「相关人员」名单收录'), findsOneWidget);
    });

    testWidgets('合并式：某一份被分页截断时，副标题如实写服务端计数', (tester) async {
      await openSheet(
        tester,
        dimension: DzjPeerDimension.dorm,
        count: 3,
        overrides: [
          dzjPeerCountsProvider.overrideWith((ref) async => const {'dorm': 4}),
          dzjRelatedCountsProvider.overrideWith(
            (ref) async => const {'relatedDorm': 9},
          ),
          dzjPeersProvider(DzjPeerDimension.dorm).overrideWith(
            (ref) async => const [DzjPeer(userId: '1', name: '张三')],
          ),
          dzjPeersProvider(DzjPeerDimension.relatedDorm).overrideWith(
            (ref) async => const [DzjPeer(userId: '2', name: '李四')],
          ),
        ],
      );

      expect(find.text('舍友名单'), findsOneWidget);
      expect(
        find.textContaining('共 2 人（只列已取回的部分；服务端计数 校内关系 4 · 相关人员 9）'),
        findsOneWidget,
      );
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
    });

    testWidgets('只有一份名单的维度：没有任何来源控件（合并只限同义的两对）', (tester) async {
      await openSheet(
        tester,
        dimension: DzjPeerDimension.grade,
        count: 900,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.grade).overrideWith(
            (ref) async => const [DzjPeer(userId: '2202500001', name: '张三')],
          ),
        ],
      );
      expect(find.text('同年级名单'), findsOneWidget);
      expect(find.textContaining('名单来自校内关系'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerSource-class')), findsNothing);
      expect(find.byKey(const Key('dzjPeerSource-relatedClass')), findsNothing);
      expect(find.textContaining('合并'), findsNothing);
    });

    testWidgets('本地筛选：只筛已取回的行，筛不到时说清是「已列出的这批里没有」且不发新请求', (tester) async {
      var calls = 0;
      await openSheet(
        tester,
        count: 3,
        overrides: [
          dzjPeersProvider(DzjPeerDimension.major).overrideWith((ref) async {
            calls++;
            return const [
              DzjPeer(
                userId: '2202500001',
                name: '张三',
                className: '软件工程 251 班',
              ),
              DzjPeer(userId: '2202500004', name: '李四'),
              DzjPeer(
                userId: '2202500005',
                name: '王五',
                college: '软件与物联网工程学院',
              ),
            ];
          }),
        ],
      );

      final filter = find.byKey(const Key('dzjPeerFilter'));
      expect(filter, findsOneWidget);

      // 按姓名
      await tester.enterText(filter, '李');
      await tester.pump();
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('张三'), findsNothing);
      expect(find.textContaining('已筛出 1 / 3 人'), findsOneWidget);

      // 按班级（副标题里的字段也参与匹配）
      await tester.enterText(filter, '软件工程 251');
      await tester.pump();
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsNothing);

      // 筛不到 → 不许说「没有这个人」（名单本身是分页取的）
      await tester.enterText(filter, '查无此人');
      await tester.pump();
      expect(find.textContaining('已列出的 3 人里没有匹配'), findsOneWidget);
      expect(find.byKey(const Key('dzjPeerFilterReset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dzjPeerFilterReset')));
      await tester.pumpAndSettle();
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('王五'), findsOneWidget);

      // 全程只有第一次那一个请求：筛选是纯本地的
      expect(calls, 1);
    });
  });
}
