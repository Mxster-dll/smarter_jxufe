/// 「基本信息」表单（学校个人数据中心 › 基本信息，pageKey `13ba9ece95a8`）· 守卫。
///
/// 用户 2026-09-20 八轮原话：「基本信息页有大量的信息没有并入「我的」页」。
///
/// 这一页在 App 里**不单独做子页面**（五轮裁定：基本信息并入「我的」页），但它是最权威的
/// 字段源 —— 39 项学工系统登记值，其中家庭住址 / 证件类型 / 证件号码 / 所属校区 /
/// 学生身份 / 学生类型 / 通知书号 / 录取五项 / 预计毕业日期 / 毕业中学 / 当前状态 /
/// 学籍状态 / 宿舍地址等本地学籍缓存里都没有。
///
/// 端点（2026-09-20 用 CDP 抓浏览器真实请求确定，见 `%TEMP%\dzjprobe\cdp.py`）：
/// `POST /api/app/component/tsa/getFormData`，body 带 `dataObjectId` + 39 项 `fieldList`。
/// 组件的 `selectArea` 是占位符 `select * from t_sys_user`，`data/get` / `data/list` /
/// `data/search` 全都取不到 —— **只有这一个端点能出值**。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';

/// 真实回包（账号 2202500001，2026-09-20 实测）—— 照抄形状，值取代表性的几项。
Map<String, Object?> realFormResponse() => <String, Object?>{
  'data': <Object?>[
    {'fieldName': '一卡通号', 'value': '2202500001', 'key': 'USERID'},
    {'fieldName': '学号', 'value': '2202500001', 'key': 'XH'},
    {'fieldName': '姓名', 'value': '同学甲', 'key': 'USERNAME'},
    {'fieldName': '性别', 'value': '男性', 'key': 'XB'},
    {'fieldName': '家庭住址', 'value': '<REDACTED> 'key': 'JTZZ'},
    {'fieldName': '证件类型', 'value': '居民身份证', 'key': 'ZJLX'},
    {'fieldName': '所属校区', 'value': '麦庐园校区', 'key': 'SSXQ'},
    {'fieldName': '所属班级', 'value': '25计算机2班', 'key': 'SSBJ'},
    {'fieldName': '电子邮箱', 'value': '', 'key': 'DZYX'},
    {'fieldName': '银行账号', 'value': null, 'key': 'YHZH'},
    {'fieldName': '宿舍地址', 'value': '麦庐园校区示例宿舍楼1楼101室', 'key': 'SSDZ'},
    {'fieldName': 'wid', 'value': 'fa34071e04c5446eba497da900a92e16'},
    {'fieldName': '某个没登记的字段', 'value': '不该出现', 'key': 'XXX'},
  ],
};

void main() {
  group('字段表', () {
    test('39 项：列名 / 数据库列 / 字段 id 都写全、列名不重复', () {
      expect(dzjBasicFields.length, 39);
      final labels = <String>{};
      final ids = <String>{};
      for (final f in dzjBasicFields) {
        expect(f.label.isNotEmpty, isTrue);
        expect(f.dataField.isNotEmpty, isTrue, reason: f.label);
        expect(f.dataFieldId.isNotEmpty, isTrue, reason: f.label);
        expect(labels.add(f.label), isTrue, reason: '列名重复：${f.label}');
        expect(ids.add(f.dataFieldId), isTrue, reason: '字段 id 重复：${f.label}');
      }
    });

    test('用户点名要并入的那几项都在表里', () {
      final labels = <String>{for (final f in dzjBasicFields) f.label};
      for (final want in const <String>[
        '家庭住址', '证件类型', '证件号码', '所属校区', '学生身份', '学生类型',
        '是否预科生', '银行账号', '通知书号', '录取批次', '录取时间', '录取成绩',
        '录取志愿', '预计毕业日期', '毕业中学', '担任职务', '获得奖励', '当前状态',
        '学籍状态', '宿舍地址', '电子邮箱', '手机号码',
      ]) {
        expect(labels.contains(want), isTrue, reason: '缺字段：$want');
      }
    });
  });

  group('请求体', () {
    test('形状与浏览器抓到的一致（数据对象 + 数据源 + 39 项 fieldList）', () {
      final body = dzjBasicInfoRequest();
      expect(body['dataObjectId'], dzjBasicInfoDataObjectId);
      expect(body['datasourceID'], '1');
      expect(body['dbType'], 'postgresql');
      expect(body['schemaName'], 'usr_bsp');
      expect(body['componentId'], 'u:73ab7f26af38');
      final fl = body['fieldList']! as List<Object?>;
      expect(fl.length, 39);
      final first = fl.first! as Map<String, Object?>;
      expect(first['dataField'], 'USERID');
      expect(first['dataFieldId'], '365866254930058');
      expect(first['fieldName'], '一卡通号');
    });

    test('★ filterConfig 必须带用户谓词 —— 否则服务端回别的学生的数据', () {
      // 2026-09-20 实测（formdata4/5.py）：`filterConfig` 为空 / 只带 dataFilterSql /
      // 只在 fieldList 的字段上写 filter，服务端都回**留学生 留学生甲
      // （2202400001）**的整份基本信息；带 `filterType:'sql'` + `userid=#{U_用户名}`
      // 才稳定回本人（同学甲 / 2202500001）。
      final fc = dzjBasicInfoRequest()['filterConfig']! as List<Object?>;
      expect(fc.length, 1);
      final only = fc.single! as Map<String, Object?>;
      expect(only['filterType'], 'sql');
      expect(only['type'], 'VARCHAR2');
      expect(only['values'], <Object?>['userid=#{U_用户名}']);
    });
  });

  group('回包解析', () {
    test('按中文列名取值；空值 / null / wid / 未登记字段一律丢掉', () {
      final m = dzjBasicInfoFromJson(realFormResponse());
      expect(m['姓名'], '同学甲');
      expect(m['一卡通号'], '2202500001');
      expect(m['所属班级'], '25计算机2班');
      expect(m['家庭住址'], '<REDACTED>);
      expect(m.containsKey('电子邮箱'), isFalse, reason: '空串不算值');
      expect(m.containsKey('银行账号'), isFalse, reason: 'null 不算值');
      expect(m.containsKey('wid'), isFalse, reason: '表单实例 id 不是学生字段');
      expect(m.containsKey('某个没登记的字段'), isFalse, reason: '未登记的列名不许进界面');
    });

    test('脏数据不崩：非 Map / 缺 data / 行非 Map', () {
      expect(dzjBasicInfoFromJson(null), isEmpty);
      expect(dzjBasicInfoFromJson('不是 JSON'), isEmpty);
      expect(dzjBasicInfoFromJson(<Object?>[]), isEmpty);
      expect(
        dzjBasicInfoFromJson(<String, Object?>{
          'data': <Object?>['字符串行', 42, <String, Object?>{'fieldName': '姓名'}],
        }),
        isEmpty,
      );
    });

    test('★ 串号防线：回包里的一卡通号不是本人 → 整份丢弃', () {
      // 实测服务端在 filterConfig 缺失时回的就是别人（留学生甲 / 2202400001）。
      final other = <String, Object?>{
        'data': <Object?>[
          {'fieldName': '一卡通号', 'value': '2202400001'},
          {'fieldName': '姓名', 'value': '留学生甲'},
          {'fieldName': '家庭住址', 'value': '别人的家庭住址'},
        ],
      };
      expect(dzjBasicInfoFromJson(other, account: '2202500001'), isEmpty,
          reason: '宁可什么都不显示，也不能把别人的证件号/住址画到我的页');
      expect(dzjBasicInfoFromJson(other)['姓名'], '留学生甲',
          reason: '不传 account（未登录 / 无账号）时不校验，仍按原样解析');
      expect(
        dzjBasicInfoFromJson(realFormResponse(), account: '2202500001')['姓名'],
        '同学甲',
        reason: '本人那一份照常放行',
      );
      expect(
        dzjBasicInfoFromJson(realFormResponse(), account: ' 2202500001 ')['姓名'],
        '同学甲',
        reason: '账号两侧空白不算不一致',
      );
    });
  });

  group('与「我的」页的合并口径', () {
    test('把 39 项一起传进去：数据中心有值 → 上色；本地也有且不同 → 冲突', () {
      final remote = dzjBasicInfoFromJson(realFormResponse());
      final merges = dzjMergeFields(
        labels: <String>[
          for (final f in DzjMyField.values) f.label,
          for (final f in dzjBasicFields) f.label,
        ],
        local: <String, String>{
          '学号': '2202500001',
          '所属单位': '计算机与人工智能学院',
          '所属班级': '计算机科学与技术252',
        },
        remote: <String, String>{
          ...remote,
          '所属单位': '计算机学院',
        },
      );
      final byLabel = dzjMergeMap(merges);
      expect(byLabel.length, DzjMyField.values.length + 39 - 2,
          reason: '两份字段表有「姓名」「一卡通号」两个同名项，去重后 43 项');
      expect(byLabel['学号']!.state, DzjFieldState.same, reason: '同一个值不算冲突');
      expect(byLabel['所属班级']!.state, DzjFieldState.conflict, reason: '两个口径的班级名不同');
      expect(byLabel['所属单位']!.isConflict, isTrue);
      expect(byLabel['所属单位']!.value, '计算机与人工智能学院', reason: '冲突时仍显示本地值');
      expect(byLabel['家庭住址']!.state, DzjFieldState.fromCenter);
      expect(byLabel['家庭住址']!.usesCenterValue, isTrue);
      expect(byLabel['毕业中学']!.state, DzjFieldState.empty, reason: '回包里没有这一项');
    });

    test('来源标注：枚举那六个走各自来源，基本信息来的写「学工系统」', () {
      expect(dzjFieldSourceOf('班主任'), '个人首页');
      expect(dzjFieldSourceOf('宿舍评分'), '住宿信息');
      expect(dzjFieldSourceOf('家庭住址'), dzjBasicInfoSource);
      expect(dzjFieldSourceOf('宿舍地址'), dzjBasicInfoSource);
    });
  });
}
