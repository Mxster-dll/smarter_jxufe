/// bn 签名守卫（2026-10-10 立）。
///
/// 为什么值得单独钉住：这段算法是**逆向**得来的，服务端只在签名不对时回一句
/// 「参数非法篡改」（`code 10005`），没有任何细节 —— 一旦谁把拼接顺序、大小写、
/// 或「`bn_accessKey` 到底进不进请求体」改错，表现是**校历与请假同时静默失效**，
/// 排查成本极高。故这里用一个**独立实现算出的固定向量**对拍（密钥是合成值）。
///
/// 背景：平台 appSecret 自 2026-10-10 起不再硬编码在仓库里，改为构建参数
/// `--dart-define=BN_APP_SECRET=…` 注入（公开仓库不落第三方密钥），
/// 因此 [bnSignedBody] 也顺势变成「密钥可注入」→ 这段算法第一次变得可测。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/school_calendar/data/datasources/wxcal_remote_datasource.dart';

/// 合成密钥（**不是**真实平台 appSecret）：只用于把算法形状钉死。
const _testSecret = 'TESTSECRET0123456789';
const _testGuid = 'TESTGUID0001';
const _testAppid = '1576047674410';
const _testTs = 1735689600000;
const _testNonce = '0abcdefghijklm';
const _testParams = <String, dynamic>{'pageNum': '1', 'pageSize': '20'};

/// 金标准：由**独立实现**（Python hashlib）对该输入算出的 MD5 大写值。
///
/// 对应签名串（含顺序，供人工复核）：
/// ```
/// appid=1576047674410&bn_accessKey=TESTGUID0001&bn_nonce=0abcdefghijklm
/// &bn_timestamp=1735689600000&pageNum=1&pageSize=20&username=TESTGUID0001
/// &bn_secretKey=TESTSECRET0123456789
/// ```
const _goldenSign = 'E7EA4B021E9603536A1EE02A3A306B26';

void main() {
  test('算法对拍：固定输入 → 固定签名（独立实现算出的金标准）', () {
    expect(
      bnSignOf(
        secret: _testSecret,
        guid: _testGuid,
        appid: _testAppid,
        params: _testParams,
        timestampMs: _testTs,
        nonce: _testNonce,
      ),
      _goldenSign,
      reason: '签名算法被动过了。这段是逆向所得、服务端只回「参数非法篡改」，'
          '改动前请先用真机抓包核一遍（见 reverse_engineering/校历接口.md）。',
    );
  });

  group('签名形状与敏感性', () {
    String sign({
      String secret = _testSecret,
      String guid = _testGuid,
      Map<String, dynamic>? params,
      int ts = _testTs,
      String nonce = _testNonce,
    }) =>
        bnSignOf(
          secret: secret,
          guid: guid,
          appid: _testAppid,
          params: params ?? _testParams,
          timestampMs: ts,
          nonce: nonce,
        );

    test('是 32 位大写十六进制', () {
      expect(RegExp(r'^[0-9A-F]{32}$').hasMatch(sign()), isTrue,
          reason: '服务端认的是大写十六进制；小写或带横线都会被判非法。');
    });

    test('确定性：同输入同结果', () => expect(sign(), sign()));

    test('密钥、GUID、时间戳、nonce、业务参数任一变化 → 签名变化', () {
      final base = sign();
      expect(sign(secret: 'OTHER_SECRET_9876543210'), isNot(base));
      expect(sign(guid: 'TESTGUID0002'), isNot(base));
      expect(sign(ts: _testTs + 1), isNot(base));
      expect(sign(nonce: '0abcdefghijklN'), isNot(base));
      expect(sign(params: {..._testParams, 'pageNum': '2'}), isNot(base));
    });

    test('参数顺序不影响结果（内部按键名排序）', () {
      expect(
        sign(params: {'pageSize': '20', 'pageNum': '1'}),
        sign(params: {'pageNum': '1', 'pageSize': '20'}),
        reason: '拼接前必须按键名升序排 —— 依赖 Map 插入序会随调用方写法漂移。',
      );
    });
  });

  group('bnSignedBody：请求体边界', () {
    test('带密钥时产出完整三参数，且**不泄露** bn_accessKey / bn_secretKey', () {
      final body = bnSignedBody(
        guid: _testGuid,
        appid: _testAppid,
        params: const {'pageNum': 1, 'pageSize': 20},
        secret: _testSecret,
      );
      expect(body['bn_sign'], isA<String>());
      expect(RegExp(r'^[0-9A-F]{32}$').hasMatch(body['bn_sign'] as String), isTrue);
      expect(body['bn_timestamp'], isA<int>());
      expect((body['bn_nonce'] as String).length, 14);
      expect(body['username'], _testGuid);
      expect(body['appid'], _testAppid);
      // 业务参数原样透传
      expect(body['pageNum'], 1);
      expect(body['pageSize'], 20);
      // 边界：这两个**绝不能**出现在请求体里
      expect(body.containsKey('bn_accessKey'), isFalse,
          reason: 'bn_accessKey 只参与签名；发出去服务端会判参数异常。');
      expect(body.containsKey('bn_secretKey'), isFalse,
          reason: 'bn_secretKey 是密钥本体，发出去等于把平台密钥送给服务端日志。');
    });

    test('密钥为空 → 当场抛 StateError（不发必然被拒的请求）', () {
      expect(
        () => bnSignedBody(
          guid: _testGuid,
          appid: _testAppid,
          params: const {},
          secret: '   ',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('未用 --dart-define 注入时，bnSecretConfigured 为 false', () {
      // 测试进程没带 BN_APP_SECRET，因此这里必须为 false；
      // 带上 --dart-define=BN_APP_SECRET=x 跑时此断言会翻面（这正是它的用途）。
      expect(bnSecretConfigured, isFalse,
          reason: '仓库里不该有平台 appSecret；若这里为 true，说明它又被写回代码或测试参数里了。');
    });

    test('canUseLiveSource：缺任一样都不算「实时可用」', () {
      // 本构建没有 appSecret → 无论 GUID 填没填，都不该被当成实时可用。
      // （界面角标与仓库的取数分支共用这一条，防止「拿了离线快照却标实时」。）
      expect(canUseLiveSource(null), isFalse);
      expect(canUseLiveSource(''), isFalse);
      expect(canUseLiveSource('   '), isFalse);
      expect(canUseLiveSource('TESTGUID0001'), isFalse,
          reason: '没有 appSecret 时签名算不出来 —— 此时必须判为不可用。');
    });
  });
}
