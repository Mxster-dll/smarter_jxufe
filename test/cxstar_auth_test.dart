/// 畅想之星会话层单测：token 提取（地址 / Cookie / 正文）、打码、
/// 会话来源语义。
///
/// 真实抓包事实（2026-09-12，见 reverse_engineering/畅想之星接口.md）：
/// 个人 JWT 出现在 CAS 回跳地址 query（`?token=`）或 Set-Cookie `mtoken`；
/// 业务接口用 `Authorization: Bearer <JWT>`；IP 免密登录是公用账号。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/data/cxstar_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';

/// 形态逼真的假 JWT（非真实令牌）。
const _jwt =
    'eyJhbGciOiJIUzI1NiJ9.eyJ1aWQiOiI1MTdfMjIwMjUwMjUxMyIsImxvZ2luVHlwZSI6N30'
    '.-_abcdefghijklmnop';

void main() {
  group('token 形态判定', () {
    test('JWT 形态识别', () {
      expect(CxstarAuthRemoteDataSource.looksLikeToken(_jwt), isTrue);
      expect(CxstarAuthRemoteDataSource.looksLikeToken(''), isFalse);
      expect(CxstarAuthRemoteDataSource.looksLikeToken('V1MMWX'), isFalse);
      expect(CxstarAuthRemoteDataSource.looksLikeToken(null), isFalse);
      // 非 JWT 的普通会话串不算 token（早期误当成令牌的形态）。
      expect(CxstarAuthRemoteDataSource.looksLikeToken('abc.def.ghi'), isFalse);
    });

    test('从回跳地址 query 取 token', () {
      final uri = Uri.parse('https://m.cxstar.com/?token=$_jwt&from=ua');
      expect(CxstarAuthRemoteDataSource.tokenFromUri(uri), _jwt);
      expect(
        CxstarAuthRemoteDataSource.tokenFromUri(
          Uri.parse('https://m.cxstar.com/user?mtoken=$_jwt'),
        ),
        _jwt,
      );
      expect(
        CxstarAuthRemoteDataSource.tokenFromUri(
          Uri.parse('https://m.cxstar.com/user?r=12345'),
        ),
        isNull,
      );
      expect(
        CxstarAuthRemoteDataSource.tokenFromUri(
          Uri.parse('https://m.cxstar.com/?token=not-a-jwt'),
        ),
        isNull,
      );
    });

    test('从 Set-Cookie 取 token（实测 cookie 名 mtoken）', () {
      expect(
        CxstarAuthRemoteDataSource.tokenFromCookies(['mtoken=$_jwt; path=/; HttpOnly']),
        _jwt,
      );
      expect(
        CxstarAuthRemoteDataSource.tokenFromCookies([
          'ASP.NET_SessionId=abc123; path=/',
          'Verification=xyz; path=/',
        ]),
        isNull,
      );
      expect(CxstarAuthRemoteDataSource.tokenFromCookies(const []), isNull);
      expect(CxstarAuthRemoteDataSource.tokenFromCookies(null), isNull);
    });

    test('正文只在非 SPA 壳时取 token', () {
      expect(
        CxstarAuthRemoteDataSource.tokenFromBody('{"code":"1","token":"$_jwt"}'),
        _jwt,
      );
      // SPA 壳地址（回到前端页面）→ 不采信，避免把 localStorage 里的旧串当新会话。
      expect(
        CxstarAuthRemoteDataSource.tokenFromBody(
          '<html><body><div id="root"></div><script>window.token="$_jwt"</script></body></html>',
        ),
        isNull,
      );
      expect(CxstarAuthRemoteDataSource.tokenFromBody(''), isNull);
    });

    test('打码只留头尾', () {
      final masked = CxstarAuthRemoteDataSource.maskToken(_jwt);
      expect(masked.contains(_jwt), isFalse);
      expect(masked.startsWith(_jwt.substring(0, 12)), isTrue);
      expect(masked.endsWith(_jwt.substring(_jwt.length - 6)), isTrue);
      expect(CxstarAuthRemoteDataSource.maskToken('short'), '***');
    });

    test('会话 key 按账号隔离', () {
      expect(CxstarAuthLocalDataSource.keyOf('2000000000'), 'cxstar_tk_2000000000');
      expect(CxstarAuthLocalDataSource.boxName, 'cxstar');
    });
  });

  group('会话来源语义', () {
    test('仅 IP 公用账号不是个人数据', () {
      expect(CxstarSessionSource.unifiedAuth.isPersonal, isTrue);
      expect(CxstarSessionSource.manualToken.isPersonal, isTrue);
      expect(CxstarSessionSource.ipShared.isPersonal, isFalse);
      expect(CxstarSessionSource.unifiedAuth.label, '统一身份认证');
      expect(CxstarSessionSource.ipShared.description, contains('全校聚合'));
    });

    test('CxstarOverview.personal 由来源推导', () {
      const user = CxstarUser(userId: 'u', userName: '517_2000000000', realName: '某同学');
      const summary = CxstarReadSummary(readCount: 12, readMinutes: 1321);
      const overview = CxstarOverview(
        user: user,
        summary: summary,
        records: [],
        source: CxstarSessionSource.unifiedAuth,
      );
      expect(overview.personal, isTrue);
      const shared = CxstarOverview(
        user: user,
        summary: summary,
        records: [],
        source: CxstarSessionSource.ipShared,
        fallbackNote: '未能通过统一身份认证取得畅想之星会话',
      );
      expect(shared.personal, isFalse);
      expect(shared.fallbackNote, isNotNull);
    });
  });
}
