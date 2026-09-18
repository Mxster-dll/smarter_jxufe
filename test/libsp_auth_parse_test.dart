// 图书馆订阅词云同步 · 网关页解析 / 节流闸门 / 摘要文案守卫。
//
// `parseGatewayBridgeParams` 是这一层唯一「靠正则吃别人页面」的逻辑，也是我在
// 真实侦察中真踩过的坑：页内 `data: data,` 右侧是**标识符**而不是字面量，
// 不回代 var 声明就会把变量名 `data`（4 个字符）当成签名值传过去 →
// 服务端回 `{"msg":"参数错误","status":false}`。下面的 fixture 就是按真实页面结构
// 复刻的（含 `success: function (data) { … }` 这个容易骗过正则的嵌套块）。

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';

/// 真实「跳转中…」页的结构复刻（值用等长假 token）。
const String kGatewayPageFixture = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"></meta>
    <title>跳转中...</title>
</head>
<body>
</body>
<script type="text/javascript" src="/js/jquery-3.6.0.min.js"></script>
<script>
    \$(function () {
        var isXxtLogin = "";
        var url = "/login_auth/cas/jxufe/login";
        var msg = "";
        var firstReferer = "";
        var data = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        var time = "1789578631574";
        var enc = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
        var res = 0;
        jQuery.ajax({
            type: "get",
            url: url,
            async: false,
            data: {
                data: data,
                time: time,
                enc: enc,
                displayName: '某同学',
                userRole: '3',
                group1: '',
                mobilePhone: '',
                gender: '',
                userid: ''
            },
            dataType: "json",
            success: function (data) {
                if (data.status) {
                    res = 2;
                }
            }
        });
    });
</script>
</html>
''';

void main() {
  group('网关跳转页解析', () {
    test('标识符必须回代成 var 声明的值（不是变量名本身）', () {
      final params = LibspAuthRemoteDataSource.parseGatewayBridgeParams(
        kGatewayPageFixture,
      );
      expect(params['data'], 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(params['time'], '1789578631574');
      expect(params['enc'], 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
      expect(params['data'], isNot('data'), reason: '踩过的坑：不能把变量名当值');
      expect(params['time'], isNot('time'));
      expect(params['enc'], isNot('enc'));
    });

    test('用户信息字段按字面量原样取出（含末尾空格）', () {
      final params = LibspAuthRemoteDataSource.parseGatewayBridgeParams(
        kGatewayPageFixture,
      );
      expect(params['displayName'], '某同学');
      expect(params['userRole'], '3');
      expect(params['group1'], '');
      expect(params['mobilePhone'], '');
    });

    test('页面里没有 ajax 块 → 返回空（调用方据此报「页面结构可能已改版」）', () {
      expect(
        LibspAuthRemoteDataSource.parseGatewayBridgeParams('<html>改版了</html>'),
        isEmpty,
      );
    });

    test('CAS service 必须是超星网关那个（图书馆域名不在白名单里）', () {
      expect(
        LibspAuthRemoteDataSource.casServiceUrl,
        contains('unified-auth.chaoxing.com'),
      );
      expect(
        LibspAuthRemoteDataSource.casServiceUrl,
        contains(
          'https%3A%2F%2Funified-auth.chaoxing.com%2Flogin_auth%2Fcas%2Fjxufe%2Findex',
        ),
        reason: 'service 要 URL 编码后内嵌在 CAS 登录地址里',
      );
      expect(
        LibspAuthRemoteDataSource.casServiceUrl,
        isNot(contains('findjxufe.libsp.cn')),
      );
    });

    test('会话 Cookie 名是 SESSION（Spring Session），不是 JSESSIONID', () {
      expect(LibspAuthRemoteDataSource.sessionCookieName, 'SESSION');
      expect(
        LibspAuthRemoteDataSource.hasSession('SESSION=abc; route=x'),
        isTrue,
      );
      expect(LibspAuthRemoteDataSource.hasSession('JSESSIONID=abc'), isFalse);
      expect(LibspAuthRemoteDataSource.hasSession(''), isFalse);
    });
  });

  group('节流闸门（Q12）', () {
    final now = DateTime(2026, 9, 17, 14, 0);
    const gate = LibspSyncGate();

    test('从没同步过 → 允许自动上传', () {
      expect(gate.allowsAuto(const LibspSyncState(enabled: true), now), isTrue);
      expect(gate.remainingCooldown(const LibspSyncState(), now), Duration.zero);
      expect(gate.remainingToday(const LibspSyncState(), now), libspDailyUploadLimit);
    });

    test('60 秒窗口内不再自动上传，并报出还要等多久', () {
      final state = LibspSyncState(
        enabled: true,
        lastUploadedAt: now.subtract(const Duration(seconds: 20)).millisecondsSinceEpoch,
      );
      expect(gate.allowsAuto(state, now), isFalse);
      expect(gate.remainingCooldown(state, now), const Duration(seconds: 40));
    });

    test('窗口按「上一次真的写成功」计时：满 60 秒即放行', () {
      final state = LibspSyncState(
        enabled: true,
        lastUploadedAt: now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch,
      );
      expect(gate.allowsAuto(state, now), isTrue);
      expect(gate.remainingCooldown(state, now), Duration.zero);
    });

    test('每日上限：到量后只允许手动同步', () {
      final state = LibspSyncState(
        enabled: true,
        lastUploadedAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        dailyCount: libspDailyUploadLimit,
        dailyCountDay: 20260917,
      );
      expect(gate.allowsAuto(state, now), isFalse);
      expect(gate.remainingToday(state, now), 0);
    });

    test('跨天自动归零计数', () {
      final state = LibspSyncState(
        enabled: true,
        lastUploadedAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        dailyCount: libspDailyUploadLimit,
        dailyCountDay: 20260916,
      );
      expect(gate.allowsAuto(state, now), isTrue);
      expect(gate.remainingToday(state, now), libspDailyUploadLimit);
    });

    test('afterUpload 落窗口起点 + 计数 + 清错误', () {
      final next = gate.afterUpload(
        const LibspSyncState(enabled: true, lastError: '上次失败了'),
        now,
        cloudGeneratedAt: 12345,
      );
      expect(next.lastUploadedAt, now.millisecondsSinceEpoch);
      expect(next.lastCloudGeneratedAt, 12345);
      expect(next.lastError, isNull, reason: '成功必须清掉错误');
      expect(next.dailyCount, 1);
      expect(next.dailyCountDay, 20260917);
      expect(next.enabled, isTrue, reason: '别把开关改掉了');
    });
  });

  group('状态持久化', () {
    test('JSON 往返不丢字段，脏数据回落默认值', () {
      const state = LibspSyncState(
        enabled: true,
        lastUploadedAt: 1,
        lastCloudGeneratedAt: 2,
        lastError: 'x',
        dailyCount: 3,
        dailyCountDay: 20260917,
      );
      final back = LibspSyncState.fromJson(state.toJson());
      expect(back.enabled, isTrue);
      expect(back.lastUploadedAt, 1);
      expect(back.lastCloudGeneratedAt, 2);
      expect(back.lastError, 'x');
      expect(back.dailyCount, 3);
      expect(back.dailyCountDay, 20260917);

      expect(LibspSyncState.fromJson(null).enabled, isFalse);
      expect(LibspSyncState.fromJson('坏数据').enabled, isFalse);
      expect(LibspSyncState.fromJson(<String, dynamic>{}).dailyCount, 0);
    });
  });

  group('恢复摘要文案（不做盲盒覆盖）', () {
    test('列出时间、课程数、偏好项与云端词条数', () {
      final summary = LibspCloudSummary(
        generatedAt: DateTime(2026, 9, 17, 14, 22).millisecondsSinceEpoch,
        courseCount: 10,
        prefEntryCount: 5,
        hasZongce: true,
        trim: const LibspTrimReport(),
        account: '2000000000',
        wordCount: 21,
        foreignCount: 2,
      );
      expect(summary.label, contains('2026-09-17 14:22'));
      expect(summary.label, contains('10 门课'));
      expect(summary.label, contains('5 项偏好'));
      expect(summary.label, contains('综测填写项'));
      expect(summary.label, contains('21 条同步词'));
      expect(summary.label, contains('你自己的 2 条订阅词'));
    });

    test('被精简过的快照要在摘要里说出来', () {
      final summary = LibspCloudSummary(
        generatedAt: 0,
        courseCount: 3,
        prefEntryCount: 0,
        hasZongce: false,
        trim: const LibspTrimReport(droppedCourses: 30, droppedDeadlines: 12),
        account: 'a',
      );
      expect(summary.label, contains('已精简'));
      expect(summary.label, contains('30 门课程'));
      expect(summary.label, contains('12 条截止日期'));
    });
  });
}
