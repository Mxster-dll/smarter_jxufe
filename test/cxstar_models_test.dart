import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';

void main() {
  group('畅想之星 · 统计解析', () {
    test('字符串数字也能解析（真实接口是字符串）', () {
      final s = CxstarReadSummary.fromJson(const {
        'readCount': '2160',
        'finishCount': '11',
        'noteCount': '0',
        'commentCount': '0',
        'readMinutes': '273329',
        'todayReadMinutes': '0',
        'level': 6,
      });
      expect(s.readCount, 2160);
      expect(s.finishCount, 11);
      expect(s.readMinutes, 273329);
      expect(s.todayReadMinutes, 0);
      expect(s.level, 6);
    });

    test('缺字段 / 脏值一律归零，不抛异常', () {
      final s = CxstarReadSummary.fromJson(const {'readCount': 'abc'});
      expect(s.readCount, 0);
      expect(s.finishCount, 0);
      expect(s.readMinutes, 0);
    });
  });

  group('畅想之星 · 账号口径', () {
    test('IPUSER 前缀 = 校园网公用账号', () {
      const u = CxstarUser(userName: 'IPUSERjxcdadmin', realName: 'IP用户');
      expect(u.isSharedIpAccount, isTrue);
      expect(u.displayName, 'IP用户');
    });

    test('真实姓名同样识别为公用账号', () {
      const u = CxstarUser(userName: 'x', realName: 'IP用户');
      expect(u.isSharedIpAccount, isTrue);
    });

    test('普通个人账号不是公用账号', () {
      const u = CxstarUser(userName: '2000000000', realName: '某同学');
      expect(u.isSharedIpAccount, isFalse);
      expect(u.displayName, '某同学');
    });

    test('无姓名时回退账号名', () {
      const u = CxstarUser(userName: '2000000000');
      expect(u.displayName, '2000000000');
    });
  });

  group('畅想之星 · 时长格式', () {
    test('分钟 → 小时 + 分', () {
      expect(cxstarDurationText(273329), '4555 小时 29 分');
      expect(cxstarDurationText(120), '2 小时');
      expect(cxstarDurationText(45), '45 分');
      expect(cxstarDurationText(0), '0 分');
      expect(cxstarDurationText(-5), '0 分');
    });

    test('小时紧凑值：≥100 小时取整，否则一位小数', () {
      expect(cxstarHoursText(14402), '240');
      expect(cxstarHoursText(60), '1.0');
      expect(cxstarHoursText(0), '0');
    });
  });

  group('畅想之星 · 阅读记录解析', () {
    test('readings 元素字段映射', () {
      final r = CxstarReadRecord.fromJson(const {
        'id': '1',
        'bookId': 'b1',
        'title': '某书',
        'author': '某人',
        'readingTime': '2026/9/11 20:47:51',
        'ifReadFinish': true,
      });
      expect(r.title, '某书');
      expect(r.author, '某人');
      expect(r.readingTime, '2026/9/11 20:47:51');
      expect(r.ifReadFinish, isTrue);
    });

    test('缺字段回退默认值', () {
      final r = CxstarReadRecord.fromJson(const {});
      expect(r.title, '');
      expect(r.ifReadFinish, isFalse);
    });
  });

  test('异常 message 直接可展示', () {
    const e = CxstarApiException('畅想之星接口异常（HTTP 500）');
    expect('$e', '畅想之星接口异常（HTTP 500）');
  });
}
