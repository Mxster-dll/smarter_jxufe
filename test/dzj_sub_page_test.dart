/// 数据中心**子页面**（学校「个人数据中心」下的九个页面）· 守卫。
///
/// 立项口径（用户 2026-09-19 五轮原话）：「我希望个人数据中心里加子页面
/// https://dzj.jxufe.edu.cn/app/66eef481a9a3/13ba9ece95a8 … 这样的，一共有十个这样的
/// 子页面，我希望你找到获取这十个子页面链接的方式，并把这十个子页面中除了『基本信息』
/// 整合到我的里面，其余九个子页面都做成 app 数据中心里的子页面」。
///
/// 本文件守四件事：
/// 1. **发现方式**：页面树来自 `manageTreeByVersion` 的真回包形状
///    （`{tree:[{menuName,pageKey,menuType,children}]}`）→ 十个内容页里剔掉首页与
///    「基本信息」= 九个，顺序照服务端；
/// 2. **解析容错**：脏节点 / 缺字段 / 重复 key 不崩、不重复；
/// 3. **通用渲染口径**：kpi 走 `data/get`、明细走 `data/list`（本文件测解析层：
///    数据块识别、中文列名、敏感列丢弃、占位符组件整块丢掉）；
/// 4. **页面真渲染**：卡片标题 / 聚合值 / 明细行 / 「前 N 条」提示四态都上屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_body.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_sub_page_screen.dart';

/// 实测回包（2026-09-19，账号 2202500001）—— 照抄结构，**不动一个 pageKey**。
Map<String, Object?> realTreeResponse() => <String, Object?>{
  'tree': <Object?>[
    {'menuName': '个人首页', 'pageKey': '82e98baafb40', 'menuType': 'C'},
    {
      'menuName': '个人数据',
      'pageKey': 'c62ddfc1d7b4',
      'menuType': 'M',
      'children': <Object?>[
        {'menuName': '基本信息', 'pageKey': '13ba9ece95a8', 'menuType': 'C'},
        {'menuName': '关联同学', 'pageKey': '228583a5077f', 'menuType': 'C'},
        {'menuName': '指导教师', 'pageKey': '5184364197bf', 'menuType': 'C'},
        {'menuName': '学业信息', 'pageKey': '93a9c73e6828', 'menuType': 'C'},
        {'menuName': '奖助贷勤', 'pageKey': '5c1d1223128d', 'menuType': 'C'},
        {'menuName': '校内活动', 'pageKey': '9d64a7e96921', 'menuType': 'C'},
        {'menuName': '住宿信息', 'pageKey': '5a675070f942', 'menuType': 'C'},
        {'menuName': '校园消费', 'pageKey': '45f25a665810', 'menuType': 'C'},
        {'menuName': '图书服务', 'pageKey': '45e51f9362c7', 'menuType': 'C'},
        {'menuName': '数字活动', 'pageKey': '5bd85d95750d', 'menuType': 'C'},
      ],
    },
  ],
};

Future<void> pumpSubPage(
  WidgetTester tester, {
  required DzjSubPageData data,
  String pageKey = '5184364197bf',
  String title = '指导教师',
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentAccountProvider.overrideWith((ref) => '2202500001'),
        dzjPageTreeProvider.overrideWith(
          (ref) async => DzjPageTree.parse(realTreeResponse()),
        ),
        dzjSubPageProvider.overrideWith((ref, key) async => data),
      ],
      child: MaterialApp(
        home: DzjSubPageScreen(pageKey: pageKey, title: title),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('子页面清单（服务端页面树）', () {
    test('真回包 → 九个可做页面的子页面，首页与「基本信息」被剔除', () {
      final tree = DzjPageTree.parse(realTreeResponse());
      expect(tree.subPages.length, 9);
      expect(
        tree.subPages.map((n) => n.title).toList(),
        ['关联同学', '指导教师', '学业信息', '奖助贷勤', '校内活动', '住宿信息', '校园消费', '图书服务', '数字活动'],
      );
      expect(tree.subPages.map((n) => n.pageKey).toList(), [
        '228583a5077f',
        '5184364197bf',
        '93a9c73e6828',
        '5c1d1223128d',
        '9d64a7e96921',
        '5a675070f942',
        '45f25a665810',
        '45e51f9362c7',
        '5bd85d95750d',
      ]);
      // 「基本信息」只以 pageKey 形式被剔（标题对名也认）
      expect(
        tree.subPages.any((n) => n.pageKey == dzjBasicInfoPageKey),
        isFalse,
      );
      expect(tree.subPages.any((n) => n.pageKey == dzjHomePageKey), isFalse);
      // 首页仍在树里（只是不做子页面）
      expect(tree.totalPages, 11);
    });

    test('裸数组 / 单节点 / 脏数据都能解析（不崩）', () {
      expect(DzjPageTree.parse(null).isEmpty, isTrue);
      expect(DzjPageTree.parse('nope').isEmpty, isTrue);
      expect(DzjPageTree.parse(<Object?>[]).isEmpty, isTrue);
      final bare = DzjPageTree.parse(<Object?>[
        {'menuName': '住宿信息', 'pageKey': '5a675070f942', 'menuType': 'C'},
        'garbage',
        {'menuName': '无 key', 'menuType': 'C'},
      ]);
      expect(bare.subPages.length, 1);
      expect(bare.subPages.single.title, '住宿信息');
      final single = DzjPageTree.parse(<String, Object?>{
        'tree': {'menuName': '图书服务', 'pageKey': '45e51f9362c7', 'menuType': 'C'},
      });
      expect(single.subPages.single.pageKey, '45e51f9362c7');
    });

    test('同名 / 同 key 只留第一次出现；标题缺失回落 pageKey', () {
      final tree = DzjPageTree.parse(<String, Object?>{
        'tree': <Object?>[
          {'menuName': '校内活动', 'pageKey': '9d64a7e96921', 'menuType': 'C'},
          {'menuName': '校内活动（重复）', 'pageKey': '9d64a7e96921', 'menuType': 'C'},
          {'pageKey': 'abcd1234ef56', 'menuType': 'C'},
        ],
      });
      expect(tree.subPages.length, 2);
      expect(tree.subPages.first.title, '校内活动');
      expect(tree.subPages.last.title, 'abcd1234ef56');
    });

    test('容器页（menuType=M）不算子页面，但它的 children 算', () {
      final tree = DzjPageTree.parse(realTreeResponse());
      expect(tree.roots.first.isContainer, isFalse);
      expect(tree.roots[1].isContainer, isTrue);
      expect(tree.roots[1].children.length, 10);
    });
  });

  group('页面定义 → 数据块（通用解析）', () {
    Map<String, Object?> body(List<Object?> nodes) => <String, Object?>{
      'pageKey': 'x',
      'body': nodes,
    };

    test('排版件与非数据件被跳过，数据件按祖先标题命名', () {
      final parsed = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:aaaaaaaaaaaa',
            'label': 'container',
            'body': [
              {
                'id': 'u:bbbbbbbbbbbb',
                'label': 'custom-title-text-renderer',
                'title': '任课教师情况',
              },
              {
                'id': 'u:cccccccccccc',
                'label': 'common-table-renderer',
                'title': '| 任课教师情况',
                'dataSql': 'select a from t_x where ykth=1',
                'commonTableFieldSet': [
                  {'fieldName': 'kcmc', 'fieldColumnName': '课程名'},
                ],
              },
            ],
          },
        ]),
      );
      expect(parsed.blocks.length, 1);
      final b = parsed.blocks.single;
      expect(b.id, 'u:cccccccccccc');
      expect(b.kind, DzjBlockKind.list); // 表格 → 先试 data/list
      expect(b.labelOf('kcmc'), '课程名');
      expect(b.labelOf('unknown'), 'unknown');
    });

    test('占位符组件（select * from t_sys_user）整块丢掉并计入 skipped', () {
      final parsed = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:dddddddddddd',
            'label': 'common-table-renderer',
            'title': '近一月门禁记录详情',
            'dataSql': 'select * from t_sys_user',
          },
          {
            'id': 'u:eeeeeeeeeeee',
            'label': 'timer-renderer',
            'title': '最近轨迹',
            'selectArea': 'select * from t_sys_user where 1=1',
          },
          {
            'id': 'u:ffffffffffff',
            'label': 'zj-card',
            'title': '近月总进',
            'selectArea': 'select count(*) cs from t_ry_mjjl where userid=1',
          },
        ]),
      );
      expect(parsed.blocks.length, 1);
      expect(parsed.blocks.single.title, '近月总进');
      expect(parsed.skipped, 2);
    });

    test('同一组件出现多次只算一块；超出上限的部分不再进列表', () {
      final many = <Object?>[
        for (var i = 0; i < DzjPageBody.maxBlocks + 5; i++)
          {
            'id': 'u:${i.toString().padLeft(12, '0')}',
            'label': 'zj-card',
            'title': '指标 $i',
            'selectArea': 'select $i as cs',
          },
      ];
      final parsed = DzjPageBody.parse('x', body(many));
      expect(parsed.blocks.length, DzjPageBody.maxBlocks);
      // 被砍掉的条数要如实记下来（界面上给一句「另有 N 个模块未展开」），
      // 不能再像从前那样恒为 0 —— 用户 2026-09-20 七轮就是被「悄悄少了内容」坑到的。
      expect(parsed.truncated, 5);

      final dupe = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:111111111111',
            'label': 'zj-card',
            'title': '甲',
            'selectArea': 'select 1 as cs',
          },
          {
            'id': 'u:111111111111',
            'label': 'zj-card',
            'title': '甲（副本）',
            'selectArea': 'select 1 as cs',
          },
        ]),
      );
      expect(dupe.blocks.length, 1);
    });

    test('非 Map / 无 body → 空页面（不是异常）', () {
      expect(DzjPageBody.parse('x', null).isEmpty, isTrue);
      expect(DzjPageBody.parse('x', 'oops').isEmpty, isTrue);
      expect(DzjPageBody.parse('x', <String, Object?>{}).isEmpty, isTrue);
    });

    test('组件类型名就算带数据：字段里没有 SQL 也算一块（排名卡 / 学分卡这类）', () {
      // 用户 2026-09-20 七轮：「你很多页面就只显示几个数据项」—— 实测「学业信息」页的
      // 排名卡 `m-rank-renderer`、「我的学分」`stuCredits-renderer` 自身字段里**没有任何
      // SQL / 列配置**（取数口径存在服务端的组件定义里），只按「字段里有没有 SQL」筛会
      // 整块漏掉。现在按类型名兜一层。
      expect(dzjLabelCarriesData('m-rank-renderer'), isTrue);
      expect(dzjLabelCarriesData('stuCredits-renderer'), isTrue);
      expect(dzjLabelCarriesData('dvecustom-universalringchart-renderer'), isTrue);
      expect(dzjLabelCarriesData('zj-card'), isTrue);
      // 纯排版件与标题件仍要被排除。
      expect(dzjLabelCarriesData('custom-title-text-renderer'), isFalse);
      expect(dzjLabelCarriesData('anchor-title-renderer'), isFalse);
      expect(dzjLabelCarriesData('container'), isFalse);
      expect(dzjLabelCarriesData(''), isFalse);

      final parsed = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:00000000000a',
            'label': 'm-rank-renderer',
            'title': '年级排名',
          },
          {
            'id': 'u:00000000000b',
            'label': 'custom-title-text-renderer',
            'title': '学业情况',
          },
        ]),
      );
      expect(parsed.blocks.length, 1);
      expect(parsed.blocks.single.title, '年级排名');
    });

    test('上限从 24 提到 60：靠后的数据块不再被整片砍掉', () {
      // 「学业信息」页真实卡在上限上（24 块里只有 2 块有数据），而该页有 13 个节点
      // 真能取到数 —— 被砍掉的正是靠后的选课表 / 成绩表 / 排名卡。九页里候选最多的是
      // 校内活动 54 个，60 之后一个不落。
      expect(DzjPageBody.maxBlocks, greaterThanOrEqualTo(54));
    });

    test('名单类组件（data-xiangguan-render 的 timeList）→ 每路一块 + slot + 中文列名', () {
      final parsed = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:af43933a919c',
            'label': 'data-xiangguan-render',
            'title': '相关人员',
            'timeList': [
              {
                'cardTitle': '同宿舍同学',
                'selectArea': 'select count(*) as num from t_xssj_bzks where 1=1',
                'selectArea1': 'select username,userid from t_xssj_bzks',
                'firstColumns1': {
                  'sex': '性别',
                  'username': '姓名',
                  'userid': '校园卡号',
                  'dept': '所属学院',
                },
                'firstColumns': {'num': '人数'},
              },
              {
                'cardTitle': '同天生日同学',
                'selectArea1': 'select SUBSTR(username,1,1)||\'**\' as username from t_xssj_bzks',
                'firstColumns1': {'username': '姓名'},
              },
            ],
          },
        ]),
      );
      expect(parsed.blocks.length, 2);
      expect(parsed.blocks.first.title, '同宿舍同学');
      expect(parsed.blocks.first.id, 'u:af43933a919c');
      expect(parsed.blocks.first.slot, 0);
      expect(parsed.blocks.first.kind, DzjBlockKind.list);
      expect(parsed.blocks.first.labelOf('userid'), '校园卡号');
      expect(parsed.blocks.first.labelOf('num'), '人数');
      expect(parsed.blocks.last.title, '同天生日同学');
      expect(parsed.blocks.last.slot, 1);
      // 普通组件 slot = -1（走 data/list 或无 index 的 data/get）
      final plain = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:94cf8d7765b0',
            'label': 'zj-card',
            'title': '本学期已选课程',
            'selectArea': 'select count(*) as ms from t_bzks_xkxx',
          },
        ]),
      );
      expect(plain.blocks.single.slot, -1);
    });

    test('占位符 SQL 判定', () {
      expect(dzjIsPlaceholderSql('select * from t_sys_user'), isTrue);
      expect(dzjIsPlaceholderSql('SELECT * FROM T_SYS_USER WHERE 1=1'), isTrue);
      expect(dzjIsPlaceholderSql('select * from'), isTrue);
      expect(dzjIsPlaceholderSql('select'), isTrue);
      expect(dzjIsPlaceholderSql(''), isFalse);
      expect(
        dzjIsPlaceholderSql('select count(*) cs from t_xssj_bzks where userid=1'),
        isFalse,
      );
    });
  });

  group('取到的数据 → 展示（标签 / 值 / 敏感列）', () {
    test('聚合值：单字段用卡片标题当标签；数字去掉多余的 .0', () {
      final fields = dzjFieldsOf(<String, dynamic>{'cs': 15}, title: '参加竞赛总数');
      expect(fields.single.key, '参加竞赛总数');
      expect(fields.single.value, '15');
      expect(dzjValueText(79.4), '79.4');
      expect(dzjValueText(81.0), '81');
      expect(dzjValueText(null), '');
      expect(dzjValueText('暂无数据'), '暂无数据');
    });

    test('聚合值：密码类键丢弃、空值不占行、中文键原样用', () {
      final fields = dzjFieldsOf(<String, dynamic>{
        'password': 'x',
        'dke_op_type': '',
        '姓名': '同学甲',
      }, title: '姓名');
      expect(fields.length, 1);
      expect(fields.single.key, '姓名');
      expect(fields.single.value, '同学甲');
    });

    test('明细行：列名翻中文、敏感列丢弃、空行不占行', () {
      const block = DzjBlock(
        id: 'u:cccccccccccc',
        title: '任课教师情况',
        kind: DzjBlockKind.list,
        labels: {'kcmc': '课程名', 'rkjs': '任课教师'},
      );
      final rows = dzjRowsOf(<Object?>[
        {'kcmc': '体育1', 'rkjs': '教师乙', 'password': 'x'},
        {'kcmc': '', 'rkjs': ''},
        'garbage',
      ], block);
      expect(rows.length, 1);
      expect(rows.single.map((e) => '${e.key}=${e.value}').toList(),
          ['课程名=体育1', '任课教师=教师乙']);
    });

    test('{pageInfo: [...]} 包装也能读；行数上限生效', () {
      const block = DzjBlock(id: 'u:1', title: 'x', kind: DzjBlockKind.list);
      final rows = dzjRowsOf(<String, Object?>{
        'pageInfo': <Object?>[
          for (var i = 0; i < 50; i++) {'kcmc': '课 $i'},
        ],
        'total': 50,
      }, block, limit: 30);
      expect(rows.length, 30);
    });
  });

  group('数据对象通道（表格明细的唯一可用路子）', () {
    Map<String, Object?> body(List<Object?> nodes) => <String, Object?>{
      'pageKey': 'x',
      'body': nodes,
    };

    Map<String, Object?> tbl(Map<String, Object?> extra) => <String, Object?>{
      'id': 'u:f85c95577ecf',
      'label': 'common-table-renderer',
      'title': '学科竞赛',
      'querySql': 'userid=#{U_用户名}',
      'commonTableFieldSet': <Object?>[
        {'dataField': 'BSMC', 'dataFieldId': '1', 'fieldName': 'bsmc'},
        {'dataField': 'HDSJ', 'dataFieldId': '2', 'fieldName': 'hdsj'},
      ],
      ...extra,
    };

    test('modelChoose.dataObjectId 是首选（objectselect 是坏 id，绝不能用）', () {
      final obj = dzjDataObjectOf(
        tbl({
          'modelChoose': {'dataObjectId': '1215f9f029904cf3abf263e797b2dd10'},
          'objectselect': '9000000026007907',
        }),
      );
      expect(obj.objectId, '1215f9f029904cf3abf263e797b2dd10');
      expect(obj.filterSql, 'userid=#{U_用户名}');
      expect(obj.fields.length, 2);
      expect(obj.fields.first['dataField'], 'BSMC');
    });

    test('没有 dataObjectId 时退回 model_json 里的 tableId（奖助贷勤那批表）', () {
      final obj = dzjDataObjectOf(
        tbl({
          'querySql': 'ykth=#{U_用户名}',
          'modelChoose': {
            'id': 23,
            'model_json':
                '[{"id":"1763033846585","tableId":"3e41c8d0c2c64b27ac28efae4f47facc",'
                    '"table":"t_xssj_qgzx"}]',
          },
        }),
      );
      expect(obj.objectId, '3e41c8d0c2c64b27ac28efae4f47facc');
    });

    test('占位符 SQL / 坏 model_json → 一律不成通道', () {
      expect(
        dzjDataObjectOf(
          tbl({
            'querySql': 'select * from t_sys_user',
            'modelChoose': {'dataObjectId': 'abc'},
          }),
        ).objectId,
        '',
      );
      expect(
        dzjDataObjectOf(
          tbl({
            'modelChoose': {'model_json': '{截断的脏 json'},
          }),
        ).objectId,
        '',
      );
    });

    test('块上暴露三件套 + 判定：缺一不可', () {
      final parsed = DzjPageBody.parse(
        'x',
        body([
          tbl({'modelChoose': {'dataObjectId': 'obj1'}}),
          // 只有数据对象、没有行过滤 SQL → 不许走（留空会回传全校几万行）
          {
            'id': 'u:111111111111',
            'label': 'common-table-renderer',
            'title': '无过滤',
            'modelChoose': {'dataObjectId': 'obj2'},
            'commonTableFieldSet': <Object?>[
              {'dataField': 'A'},
            ],
          },
        ]),
      );
      final withObj = parsed.blocks.firstWhere((b) => b.id == 'u:f85c95577ecf');
      expect(withObj.hasDataObject, isTrue);
      expect(withObj.dataObjectId, 'obj1');
      expect(withObj.filterSql, 'userid=#{U_用户名}');
      expect(withObj.fieldList, isNotEmpty);
      final noFilter = parsed.blocks.firstWhere((b) => b.id == 'u:111111111111');
      expect(noFilter.hasDataObject, isFalse);
    });

    test('中文列名在 fieldName 里（真实表格字段清单形状）+ showData:false 的列整列挡掉', () {
      // 实测回包：`{"dataFieldId":"…","dataField":"BSMC","fieldName":"比赛名称",
      // "fieldType":"varchar","isKey":0,"isNullAble":1,"showData":false}`
      // —— `showData` 才是「这张表显不显示这一列」的开关（审计列全是 false）。
      final parsed = DzjPageBody.parse(
        'x',
        body([
          {
            'id': 'u:f85c95577ecf',
            'label': 'common-table-renderer',
            'title': '通用表格',
            'querySql': 'userid=#{U_用户名}',
            'modelChoose': {'dataObjectId': 'obj1'},
            'commonTableFieldSet': <Object?>[
              {'dataField': 'WID', 'fieldName': 'wid', 'showData': false},
              {'dataField': 'XM', 'fieldName': '姓名', 'showData': false},
              {'dataField': 'BSMC', 'fieldName': '比赛名称', 'showData': true},
              {'dataField': 'JSLBCC', 'fieldName': '竞赛类别层次', 'showData': true},
              {'dataField': 'HDSJ', 'fieldName': '活动时间', 'showData': true},
              {'dataField': 'DKE_OP_TS', 'fieldName': 'dke_op_ts', 'showData': false},
            ],
          },
        ]),
      );
      final b = parsed.blocks.single;
      expect(b.labelOf('bsmc'), '比赛名称', reason: '回包是小写列名，清单里给的是中文名');
      expect(b.labelOf('jslbcc'), '竞赛类别层次');
      expect(b.labelOf('hdsj'), '活动时间');
      expect(b.declares('dke_op_ts'), isFalse);
      expect(b.declares('xm'), isFalse, reason: 'showData:false 的姓名列不显示');
      expect(b.declares('wid'), isFalse);

      final rows = dzjRowsOf(<Object?>[
        {
          'bsmc': '蓝桥杯全国软件和信息技术专业人才大赛',
          'jslbcc': 'II类省赛',
          'hdsj': '2026',
          'jsdf': 0,
          'jgbz': '【省赛】一等奖',
          'xm': '同学甲',
          'userid': '2202500001',
          'id': 58382,
          'wid': 'fa34',
          'dke_op_ts': '1784835859523',
          'dke_op_type': 'd',
          'dke_op_id': '1784749433117',
          'clrq': '2026-01-01',
          'czlx': 'u',
        },
      ], b);
      expect(rows.length, 1);
      expect(
        rows.single.map((e) => e.key).toList(),
        ['比赛名称', '竞赛类别层次', '活动时间'],
        reason: '只留这张表声明要显示的列；jsdf/jgbz 没声明、审计列与姓名列被 showData:false 挡掉',
      );
      expect(rows.single.first.value, '蓝桥杯全国软件和信息技术专业人才大赛');
      expect(rows.single[1].value, 'II类省赛');
    });

    test('列名大小写无关 + 只认声明过的列（审计列挡掉）', () {
      final parsed = DzjPageBody.parse(
        'x',
        body([
          tbl({
            'modelChoose': {'dataObjectId': 'obj1'},
            'commonTableFieldSet': <Object?>[
              {'dataField': 'BSMC', 'fieldName': 'bsmc', 'fieldColumnName': '比赛名称'},
              {'dataField': 'HDSJ', 'fieldName': 'hdsj', 'fieldColumnName': '活动时间'},
            ],
          }),
        ]),
      );
      final b = parsed.blocks.single;
      expect(b.labelOf('bsmc'), '比赛名称', reason: '回包是小写列名，定义里是大写');
      expect(b.labelOf('BSMC'), '比赛名称');
      expect(b.declares('bsmc'), isTrue);
      expect(b.declares('dke_op_id'), isFalse, reason: '审计列不许上屏');

      // 真实回包形状 → 只留声明的两列 + 丢掉 wid / 审计列 / 空值
      final rows = dzjRowsOf(<Object?>[
        {
          'bsmc': '蓝桥杯全国软件和信息技术专业人才大赛',
          'hdsj': '2026',
          'jsdf': 0,
          'jgbz': '【国赛】一等奖',
          'wid': 'fa34',
          'dke_op_id': 'x',
          'dke_op_ts': '2026-01-01',
          'clrq': null,
        },
      ], b);
      expect(rows.length, 1);
      expect(rows.single.map((e) => e.key).toList(), ['比赛名称', '活动时间']);
      expect(rows.single.first.value, '蓝桥杯全国软件和信息技术专业人才大赛');
    });
  });

  group('子页面渲染', () {
    testWidgets('聚合值 + 明细 + 「前 N 条」提示都上屏', (tester) async {
      const data = DzjSubPageData(
        pageKey: '5184364197bf',
        title: '指导教师',
        skipped: 3,
        blocks: [
          DzjBlockData(
            block: DzjBlock(id: 'u:ffffffffffff', title: '班主任', kind: DzjBlockKind.kpi),
            fields: [MapEntry('班主任', '李老师')],
          ),
          DzjBlockData(
            block: DzjBlock(
              id: 'u:cccccccccccc',
              title: '任课教师情况',
              kind: DzjBlockKind.list,
            ),
            rows: [
              [MapEntry('课程名', '体育1'), MapEntry('任课教师', '教师乙')],
              [MapEntry('课程名', '军事理论'), MapEntry('任课教师', '教师寅')],
            ],
          ),
        ],
      );
      await pumpSubPage(tester, data: data);

      expect(find.text('指导教师'), findsWidgets);
      expect(find.text('班主任'), findsWidgets);
      expect(find.text('李老师'), findsOneWidget);
      expect(find.text('任课教师情况'), findsOneWidget);
      expect(find.text('2 条'), findsOneWidget);
      expect(find.text('体育1'), findsOneWidget);
      expect(find.textContaining('任课教师 教师乙'), findsOneWidget);
      expect(find.byKey(const Key('dzjBlock-u:cccccccccccc')), findsOneWidget);
      expect(find.textContaining('数据来源：学校「个人数据中心 › 指导教师」'), findsOneWidget);
      expect(find.textContaining('1 项指标 / 1 张明细'), findsOneWidget);
    });

    testWidgets('明细 25 条 → 全铺出来（上限 50，不再砍在 20）', (tester) async {
      // 用户 2026-09-20 七轮：「就只能看到参加几次，看不到每次参加的内容」——
      // 明细上限 20 → 50（选课 37 条、任课教师 37 条从前都被截在 20）。
      final rows = <List<MapEntry<String, String>>>[
        for (var i = 0; i < 25; i++) [MapEntry('课程名', '课 $i')],
      ];
      await pumpSubPage(
        tester,
        data: DzjSubPageData(
          pageKey: '5184364197bf',
          title: '指导教师',
          blocks: [
            DzjBlockData(
              block: const DzjBlock(
                id: 'u:cccccccccccc',
                title: '任课教师情况',
                kind: DzjBlockKind.list,
              ),
              rows: rows,
            ),
          ],
        ),
      );
      expect(find.text('25 条'), findsOneWidget);
      expect(find.text('课 19'), findsOneWidget);
      expect(find.text('课 24'), findsOneWidget, reason: '第 25 条也要看得见');
      expect(find.textContaining('此处列出前'), findsNothing, reason: '25 ≤ 50，不该有截断提示');
    });

    testWidgets('明细 60 条 → 列前 50 条并说明总数', (tester) async {
      final rows = <List<MapEntry<String, String>>>[
        for (var i = 0; i < 60; i++) [MapEntry('课程名', '课 $i')],
      ];
      await pumpSubPage(
        tester,
        data: DzjSubPageData(
          pageKey: '93a9c73e6828',
          title: '学业信息',
          blocks: [
            DzjBlockData(
              block: const DzjBlock(
                id: 'u:e9afd54487e9',
                title: '选课情况',
                kind: DzjBlockKind.list,
              ),
              rows: rows,
            ),
          ],
        ),
      );
      expect(find.text('60 条'), findsOneWidget);
      expect(find.text('课 49'), findsOneWidget);
      expect(find.textContaining('共 60 条，此处列出前 50 条'), findsOneWidget);
    });

    testWidgets('一块都没数据 → 空态（不假装有值）', (tester) async {
      await pumpSubPage(
        tester,
        data: const DzjSubPageData(
          pageKey: '45f25a665810',
          title: '校园消费',
          skipped: 12,
          blocks: [
            DzjBlockData(
              block: DzjBlock(id: 'u:1', title: '消费概况', kind: DzjBlockKind.kpi),
              failed: true,
            ),
          ],
        ),
      );
      expect(find.text('这一页的模块学校侧暂无数据'), findsOneWidget);
      expect(find.textContaining('共识别 1 个模块'), findsOneWidget);
    });

    testWidgets('读取失败 → 文案 + 重试按钮', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAccountProvider.overrideWith((ref) => '2202500001'),
            dzjSubPageProvider.overrideWith(
              (ref, key) async => throw Exception('「指导教师」数据加载失败，请稍后重试'),
            ),
          ],
          child: const MaterialApp(
            home: DzjSubPageScreen(pageKey: '5184364197bf', title: '指导教师'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('「指导教师」数据加载失败'), findsOneWidget);
      expect(find.byKey(const Key('dzjSubRetry')), findsOneWidget);
    });
  });

  group('图标', () {
    test('九个页面的图标各自可辨（不全是同一个通用图标）', () {
      final icons = <IconData>{
        for (final t in const [
          '关联同学',
          '指导教师',
          '学业信息',
          '奖助贷勤',
          '校内活动',
          '住宿信息',
          '校园消费',
          '图书服务',
          '数字活动',
        ])
          dzjSubPageIcon(t),
      };
      expect(icons.length, 9);
      expect(dzjSubPageIcon('不认识的名字'), Icons.dashboard_customize_outlined);
    });
  });
}
