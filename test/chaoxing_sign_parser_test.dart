/// 学习通「签到」解析与状态字典（纯函数，无网络）。
///
/// 覆盖 2026-10-09 真机侦察到的三件事：
/// 1. 清单接口 `POST widget/pcpick/stu/activeList` 的字段形态（`startList` / `endList`、
///    `activeType == 2` 才是签到、`userStatus` 实测恒为 null）；
/// 2. 详情页 `widget/sign/pcStuSignController/preSign` 的「签到成功」+ `#st` 时刻；
/// 3. 状态码字典（`0 未签 / 1 已签 / 2 代签 / 4 请假 / 5 缺勤 / 7 病假 / 8 事假 /
///    9 迟到 / 10 早退 / 11 签到已过期`）——出自站方 `util2.js`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_sign_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Object? _signJson() => jsonDecode(fixture('chaoxing_sign_list.json'));

List<ChaoxingSign> _signs() => parseChaoxingSigns(
  _signJson(),
  courseId: '260000001',
  courseName: '261学期 示例课程',
);

void main() {
  group('签到清单解析', () {
    test('只认 activeType == 2（选人等别的活动不进列表）', () {
      final signs = _signs();
      // fixture：startList 1 条签到 + 1 条「选人」；endList 3 条签到 + 1 条缺 id
      expect(signs.length, 4, reason: '选人与缺 id 的都要丢掉');
      expect(signs.every((s) => s.typeName != '选人'), isTrue);
      expect(signs.any((s) => s.activeId == '6000000000002'), isFalse);
    });

    test('字段口径：id / 类型名 / 起止时间 / 签到人数 / 班级', () {
      final first = _signs().first;
      expect(first.activeId, '6000000000001', reason: '按开始时间倒序 → 进行中那条在前');
      expect(first.typeName, '二维码签到');
      expect(first.courseId, '260000001');
      expect(first.classId, '150000001', reason: '详情请求要带 classId');
      expect(first.courseName, '261学期 示例课程');
      expect(first.startAt, DateTime(2026, 10, 9, 15));
      expect(first.endAt, DateTime(2026, 10, 9, 16));
      expect(first.attendCount, 12);
    });

    test('userStatus 缺失 → 状态未知（**不是**未签）', () {
      final signs = _signs();
      expect(signs.every((s) => s.status == ChaoxingSignStatus.unknown), isTrue);
      expect(signs.every((s) => s.statusLoaded), isFalse);
    });

    test('服务端哪天开始给 userStatus 也认（码值字典）', () {
      final json = _signJson() as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      final list = (data['endList'] as List).cast<Map<String, dynamic>>();
      list[0]['userStatus'] = 1; // 已签
      list[1]['userStatus'] = 5; // 缺勤
      final signs = parseChaoxingSigns(
        json,
        courseId: '260000001',
        courseName: '261学期 示例课程',
      );
      final byId = {for (final s in signs) s.activeId: s};
      expect(byId['6000000000003']!.status, ChaoxingSignStatus.signed);
      expect(byId['6000000000003']!.statusLoaded, isTrue);
      expect(byId['6000000000004']!.status, ChaoxingSignStatus.absent);
    });

    test('缺 starttimeStr 时用 createtimeStr 兜（都缺才 null）', () {
      final signs = _signs();
      final noStart = signs.firstWhere((s) => s.activeId == '6000000000005');
      expect(noStart.startAt, DateTime(2026, 9, 21, 19, 41, 35));
    });

    test('容错：非 Map / 缺 data / 单条坏数据都只丢那一条', () {
      expect(parseChaoxingSigns(null, courseId: 'c', courseName: 'n'), isEmpty);
      expect(parseChaoxingSigns('nope', courseId: 'c', courseName: 'n'), isEmpty);
      expect(
        parseChaoxingSigns({'data': 'nope'}, courseId: 'c', courseName: 'n'),
        isEmpty,
      );
      expect(
        parseChaoxingSigns(
          {
            'data': {
              'endList': [
                'bad',
                {'id': '1', 'activeType': '2', 'starttimeStr': '2026-01-01 08:00:00'},
              ],
            },
          },
          courseId: 'c',
          courseName: 'n',
        ).length,
        1,
        reason: '字符串项跳过、activeType 是字符串 "2" 也要认',
      );
    });

    test('result == 1 才算成功（其余形态一律不认）', () {
      expect(chaoxingSignListOk({'result': 1}), isTrue);
      expect(chaoxingSignListOk({'result': '1'}), isTrue);
      expect(chaoxingSignListOk({'result': 0}), isFalse);
      expect(chaoxingSignListOk({'msg': '获取列表成功'}), isFalse);
      expect(chaoxingSignListOk(null), isFalse);
    });

    test('清单按开始时间倒序（进行中那条 fixture 恰好最新）', () {
      final signs = _signs();
      for (var i = 1; i < signs.length; i++) {
        final a = signs[i - 1].startAt, b = signs[i].startAt;
        if (a == null || b == null) continue;
        expect(a.isAfter(b) || a.isAtSameMomentAs(b), isTrue);
      }
    });
  });

  group('签到状态字典', () {
    test('码值 → 状态（含实测全表）', () {
      expect(ChaoxingSignStatus.fromCode(0), ChaoxingSignStatus.unsigned);
      expect(ChaoxingSignStatus.fromCode(1), ChaoxingSignStatus.signed);
      expect(ChaoxingSignStatus.fromCode(2), ChaoxingSignStatus.proxy);
      expect(ChaoxingSignStatus.fromCode(4), ChaoxingSignStatus.leave);
      expect(ChaoxingSignStatus.fromCode(5), ChaoxingSignStatus.absent);
      expect(ChaoxingSignStatus.fromCode(7), ChaoxingSignStatus.sickLeave);
      expect(ChaoxingSignStatus.fromCode(8), ChaoxingSignStatus.personalLeave);
      expect(ChaoxingSignStatus.fromCode(9), ChaoxingSignStatus.late);
      expect(ChaoxingSignStatus.fromCode(10), ChaoxingSignStatus.earlyLeave);
      expect(ChaoxingSignStatus.fromCode(11), ChaoxingSignStatus.expired);
      expect(ChaoxingSignStatus.fromCode(null), ChaoxingSignStatus.unknown);
      expect(ChaoxingSignStatus.fromCode(99), ChaoxingSignStatus.unknown);
      expect(ChaoxingSignStatus.fromCode('1'), ChaoxingSignStatus.signed);
    });

    test('文案 → 状态（「未签到」不许被「签到」抢先命中）', () {
      expect(ChaoxingSignStatus.fromText('签到成功'), ChaoxingSignStatus.signed);
      expect(ChaoxingSignStatus.fromText('已签到'), ChaoxingSignStatus.signed);
      expect(ChaoxingSignStatus.fromText('未签到'), ChaoxingSignStatus.unsigned);
      expect(ChaoxingSignStatus.fromText('缺勤'), ChaoxingSignStatus.absent);
      expect(ChaoxingSignStatus.fromText('迟到'), ChaoxingSignStatus.late);
      expect(ChaoxingSignStatus.fromText('早退'), ChaoxingSignStatus.earlyLeave);
      expect(ChaoxingSignStatus.fromText('请假'), ChaoxingSignStatus.leave);
      expect(ChaoxingSignStatus.fromText('病假'), ChaoxingSignStatus.sickLeave);
      expect(ChaoxingSignStatus.fromText('事假'), ChaoxingSignStatus.personalLeave);
      expect(ChaoxingSignStatus.fromText('代签'), ChaoxingSignStatus.proxy);
      expect(ChaoxingSignStatus.fromText('签到已过期'), ChaoxingSignStatus.expired);
      expect(ChaoxingSignStatus.fromText(''), ChaoxingSignStatus.unknown);
      expect(ChaoxingSignStatus.fromText('莫名其妙'), ChaoxingSignStatus.unknown);
    });

    test('三档归类：isSigned / isAbsent / isKnown', () {
      expect(ChaoxingSignStatus.signed.isSigned, isTrue);
      expect(ChaoxingSignStatus.proxy.isSigned, isTrue);
      expect(ChaoxingSignStatus.late.isSigned, isFalse);
      expect(ChaoxingSignStatus.unsigned.isAbsent, isTrue);
      expect(ChaoxingSignStatus.absent.isAbsent, isTrue);
      expect(ChaoxingSignStatus.expired.isAbsent, isTrue);
      expect(ChaoxingSignStatus.leave.isAbsent, isFalse);
      expect(ChaoxingSignStatus.unknown.isKnown, isFalse);
    });
  });

  group('签到详情页解析', () {
    const base = ChaoxingSign(
      activeId: '6000000000003',
      courseId: '260000001',
      classId: '150000001',
      courseName: '261学期 示例课程',
      typeName: '二维码签到',
      attendCount: 64,
    );

    test('「签到成功」+ 签到时刻（真机页面形态）', () {
      final sign = chaoxingSignDetailFromPage(
        fixture('chaoxing_sign_detail.html'),
        base: base,
      );
      expect(sign.status, ChaoxingSignStatus.signed);
      expect(sign.statusLoaded, isTrue);
      expect(sign.signedAt, DateTime(2026, 10, 8, 18, 26, 25));
      expect(sign.activeId, '6000000000003', reason: '键与其它字段不能被换掉');
      expect(sign.attendCount, 64);
    });

    test('认不出状态 → 保持「状态未知」，不许退化成未签', () {
      final sign = chaoxingSignDetailFromPage(
        '<html><body><span class="greenColor">别的东西</span></body></html>',
        base: base,
      );
      expect(sign.status, ChaoxingSignStatus.unknown);
      expect(sign.statusLoaded, isFalse);
    });

    test('清单缺开始时间时用详情页的 setDate 兜底', () {
      final sign = chaoxingSignDetailFromPage(
        fixture('chaoxing_sign_detail.html'),
        base: base,
      );
      expect(sign.startAt, DateTime(2026, 10, 8, 18, 26));
    });

    test('未签那档也认（按文案字典，不按 CSS 类名）', () {
      final sign = chaoxingSignDetailFromPage(
        '<div><span class="redColor">未签到</span></div>',
        base: base,
      );
      expect(sign.status, ChaoxingSignStatus.unsigned);
      expect(sign.statusLoaded, isTrue);
      expect(sign.signedAt, isNull);
    });
  });

  group('签到模型', () {
    test('key = courseId/activeId；toJson/fromJson 往返', () {
      final sign = _signs().first;
      expect(sign.key, '260000001/6000000000001');
      final back = ChaoxingSign.fromJson(jsonDecode(jsonEncode(sign.toJson())));
      expect(back.activeId, sign.activeId);
      expect(back.classId, sign.classId);
      expect(back.startAt, sign.startAt);
      expect(back.endAt, sign.endAt);
      expect(back.attendCount, sign.attendCount);
      expect(back.status, sign.status);
      expect(back.statusLoaded, sign.statusLoaded);
    });

    test('旧缓存缺字段 → 默认值，不抛', () {
      final back = ChaoxingSign.fromJson({'activeId': '1', 'courseId': '2'});
      expect(back.classId, '');
      expect(back.attendCount, 0);
      expect(back.status, ChaoxingSignStatus.unknown);
      expect(back.statusLoaded, isFalse);
      expect(back.startAt, isNull);
    });

    test('isOpenAt：有结束时间看结束、没结束时间看开始', () {
      final open = _signs().first;
      expect(open.isOpenAt(DateTime(2026, 10, 9, 15, 30)), isTrue);
      expect(open.isOpenAt(DateTime(2026, 10, 9, 16, 1)), isFalse);
    });

    test('durationText（45 秒 / 8 分钟 / 1 小时 20 分）', () {
      ChaoxingSign at(DateTime s, DateTime e) => ChaoxingSign(
        activeId: 'x',
        courseId: 'y',
        startAt: s,
        endAt: e,
      );
      expect(
        at(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 8, 0, 45)).durationText,
        '45 秒',
      );
      expect(
        at(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 8, 8)).durationText,
        '8 分钟',
      );
      expect(
        at(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 9, 20)).durationText,
        '1 小时 20 分',
      );
      expect(
        at(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 9)).durationText,
        '1 小时',
      );
    });
  });
}
