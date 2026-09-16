/// 设置页「教务会话」卡的守卫 —— **探活优先、失效才换票**（用户 2026-09-15 裁定）。
///
/// 为什么要有这个口径：业务页面遇到「凭证已失效」本来就会自动换票
/// （`ImsAuthInterceptor` 认出 alert 页 → `ImsSession.renew()` 重试原请求），
/// 设置页这个按钮是给「怪状态」兜底的手动通道。如果按一下就无条件换票，
/// 每次都要多走一趟 CAS（取票 + 激活），而**探活只是一次几百字节的 GET**。
///
/// 本文件钉住三件事：
/// 1. 判定表（纯逻辑）：只有 alive 才 keepCurrent，其余（含判不出）都要换票；
/// 2. 探活的判据方向：宁可 `unknown`（进而照样换票）**也不能**把登录页当有效；
/// 3. 源码守卫：卡片确实是「先 probe 再按判定表 renew」，不是无条件 renew。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/auth/domain/ims_token_refresh.dart';

String _read(String path) => File(path).readAsStringSync();

/// 去掉注释后的源码（注释里允许解释被废弃的写法，只禁**代码里**出现）。
String _code(String path) {
  final source = _read(path);
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final newline = source.indexOf('\n', i);
      i = newline < 0 ? source.length : newline;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
    } else {
      buffer.write(source[i]);
      i++;
    }
  }
  return buffer.toString();
}

void main() {
  group('探活结论 → 动作（先探活、失效才换）', () {
    test('有效 → 什么都不做（一次多余往返都不发）', () {
      expect(
        imsTokenRefreshActionFor(ImsProbeResult.alive),
        ImsTokenRefreshAction.keepCurrent,
      );
    });

    test('已失效 → 换票', () {
      expect(
        imsTokenRefreshActionFor(ImsProbeResult.expired),
        ImsTokenRefreshAction.renew,
      );
    });

    test('本地没有令牌 → 换票', () {
      expect(
        imsTokenRefreshActionFor(ImsProbeResult.noSession),
        ImsTokenRefreshAction.renew,
      );
    });

    test('判不出（网络异常）→ 照样换票，不在按钮上原地报错', () {
      expect(
        imsTokenRefreshActionFor(ImsProbeResult.unknown),
        ImsTokenRefreshAction.renew,
      );
    });
  });

  group('探活响应判据（方向不能反）', () {
    test('教务的 JSON 信封算有效', () {
      expect(imsProbeBodyLooksValid('{"status":"200","nj":"2025"}'), isTrue);
      expect(imsProbeBodyLooksValid('  {"dwh":"44"}  '), isTrue);
    });

    test('空体 / 登录页 / 非 JSON 一律不算有效（宁可 unknown 也别骗用户）', () {
      expect(imsProbeBodyLooksValid(''), isFalse);
      expect(
        imsProbeBodyLooksValid('<html><body>统一身份认证</body></html>'),
        isFalse,
      );
      expect(imsProbeBodyLooksValid('[1,2,3]'), isFalse);
      expect(imsProbeBodyLooksValid('{不是 JSON}'), isFalse);
      // 547 字节失效 alert 页（UTF-8 被解出来的原文）
      expect(
        imsProbeBodyLooksValid("<script>alert('温馨提示：凭证已失效，请重新登录!');</script>"),
        isFalse,
      );
    });
  });

  group('展示口径', () {
    test('令牌掩码只露前 8 位', () {
      expect(maskImsToken('3C62725686D8F50E8498135F4273144B'), '3C627256…');
      expect(maskImsToken('ABCDEFGH'), 'ABCDEFGH');
      expect(maskImsToken('ABC'), 'ABC');
      expect(maskImsToken(''), '');
    });

    test('探活结论文案', () {
      expect(imsProbeLabel(ImsProbeResult.alive), '令牌有效');
      expect(imsProbeLabel(ImsProbeResult.expired), '令牌已失效');
      expect(imsProbeLabel(ImsProbeResult.noSession), '本地没有令牌');
      expect(imsProbeLabel(ImsProbeResult.unknown), contains('无法判定'));
    });

    test('按钮结果文案：有效时不谎称「已刷新」', () {
      expect(
        imsRefreshOutcomeText(probe: ImsProbeResult.alive, success: true),
        contains('未重复换票'),
      );
      expect(
        imsRefreshOutcomeText(probe: ImsProbeResult.expired, success: true),
        contains('已重新登录并换票'),
      );
      expect(
        imsRefreshOutcomeText(probe: ImsProbeResult.noSession, success: true),
        contains('已重新登录并换票'),
      );
      expect(
        imsRefreshOutcomeText(probe: ImsProbeResult.unknown, success: true),
        contains('已直接换票'),
      );
      expect(
        imsRefreshOutcomeText(probe: ImsProbeResult.alive, success: false),
        contains('刷新失败'),
      );
    });
  });

  group('源码守卫', () {
    test('ImsSession.probe()：会话门控端点 + 字节响应（不被拦截器偷换票）', () {
      final code = _code('lib/features/ims/auth/data/ims_session.dart');
      expect(code, contains('Future<ImsProbeResult> probe()'));
      expect(code, contains("'/jw/common/getStuGradeSpeciatyInfo.action'"));
      expect(code, contains('ResponseType.bytes'));
      expect(code, contains('jwSessionExpired(body)'));
      expect(code, contains('ImsProbeResult.expired'));
      expect(code, contains('ImsProbeResult.alive'));
      expect(code, contains('ImsProbeResult.noSession'));
      expect(code, contains('ImsProbeResult.unknown'));
    });

    test('设置页卡片：探活在 renew 之前，且 renew 必须过判定表', () {
      final code = _code(
        'lib/features/settings/presentation/settings_screen.dart',
      );
      expect(code, contains("'刷新登录令牌'"));
      expect(code, contains("'教务登录令牌（IMS 会话）'"));
      final probeAt = code.indexOf('await session.probe()');
      final renewAt = code.indexOf('await session.renew()');
      expect(probeAt, greaterThan(0), reason: '卡片必须先探活');
      expect(renewAt, greaterThan(probeAt), reason: '换票必须发生在探活之后');
      expect(
        code,
        contains(
          'if (imsTokenRefreshActionFor(probe) == ImsTokenRefreshAction.renew)',
        ),
        reason: 'renew 必须被判定表守住，不能无条件换票',
      );
    });

    test('判定表本身没有「alive 也换票」的分支', () {
      final code = _code('lib/features/ims/auth/domain/ims_token_refresh.dart');
      expect(
        code,
        contains('ImsProbeResult.alive => ImsTokenRefreshAction.keepCurrent'),
      );
    });
  });
}
