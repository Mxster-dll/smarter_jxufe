/// 学习通（超星）会话建立 · 统一认证链（实测 2026-09-19 抓通）。
///
/// **零密码**：只要 App 已登录过，`TGC` 就在 `auth.hive` 里。
///
/// 完整链路：
/// 1. `AuthRepository.getServiceRedirectUrl(casServiceUrl)` —— 用已有 TGC 向学校 CAS
///    换票，返回跳出 CAS 域后的地址：
///    `https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index?ticket=ST-…`；
/// 2. 网关消费票据 → 302 回 `/login_auth/cas/jxufe/index` → 200 一张「跳转中…」页
///    （约 3.2 KB），页内 JS 带 `data` / `time` / `enc` 三个签名值；
/// 3. 按页内脚本原样重放 `GET /login_auth/cas/jxufe/login?data=…&time=…&enc=…`
///    → `{"status":true}`（失败时 `{"msg":"参数错误","status":false}`）；**这一步就会
///    下发 `.chaoxing.com` 域的 passport Cookie**；
/// 4. 跳 `https://i.chaoxing.com?data=…&time=…&enc=…` → 302 `/base?t=…` → 200 学习空间
///    首页；这一页里带着收件箱 token，顺手抠出来（**省掉一次请求**）。
///
/// ⚠ 与 `libsp`（图书馆）那条链路的**唯一差别是 refer**：那边 refer 写图书馆的
/// `/find/sso/login/jxufe/0?pageType=0`，这边写学习空间根地址。网关页的
/// `jumpToRefer(firstReferer, …)` 把 refer **原样回显**，所以落点完全由客户端决定。
library;

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/cas_walk.dart';
import 'package:smarter_jxufe/core/network/trace_text.dart';
import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_notice_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_cookie_jar.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';

/// 学习通统一认证数据源。
class ChaoxingAuthRemoteDataSource {
  ChaoxingAuthRemoteDataSource(this._http);

  final ChaoxingHttpClient _http;

  /// 换证链最多跟多少跳（实测 5~6 跳）。
  static const int maxHops = 8;

  /// 建立会话：跟随换证链，返回会话（Cookie 罐 + 收件箱 token）。
  ///
  /// [trace] 非空时逐跳追加诊断行（**任何凭据值都不许写进去**）。
  Future<ChaoxingSession> establishSession(
    String ticketUrl, {
    List<String>? trace,
  }) async {
    final jar = SessionCookieJar();
    // 循环机制走地基件（`lib/core/network/cas_walk.dart`）；这里只留学习通私有子协议：
    // 落在网关域 → 重放桥接接口（**异步，且下一跳地址是页面里算出来的**）→ 改跳学习空间；
    // 落在学习空间 → 收工并建会话；落到别的主机 → 直接报错（不猜）。
    final outcome = await walkCasRedirects<ChaoxingSession>(
      startUrl: ticketUrl,
      jar: jar,
      // 发送语义留在本模块：`ChaoxingHttpClient` 带节流与风控（202 挑战页）识别。
      send: (url, _) => _http.get(url, jar: jar),
      spec: const CasWalkSpec(
        maxHops: maxHops,
        traceUrlMax: 110,
        traceLocationMax: 100,
      ),
      trace: trace,
      afterResponse: (step) async {
        // ① 先跟 Location（网关的 302 → 「跳转中…」页那一跳就靠它）。
        if (step.hasLocation) return null;

        // ② 落在「跳转中…」页：抠出 data/time/enc，重放桥接接口。
        if (step.host == ChaoxingEndpoints.gatewayHost) {
          final params = parseGatewayBridgeParams(step.bodyText ?? '');
          if (params.isEmpty) {
            throw ChaoxingSessionException(
              '学习通会话建立失败：网关跳转页里没有找到桥接参数（页面结构可能已改版）',
            );
          }
          trace?.add('   网关桥接参数：${params.keys.join(',')}');
          final login = await _http.get(
            'https://${ChaoxingEndpoints.gatewayHost}'
            '${ChaoxingEndpoints.gatewayLoginPath}',
            jar: jar,
            query: params,
            referer: step.url,
            headers: const {
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
          );
          final text = _body(login);
          if (!text.replaceAll(' ', '').contains('"status":true')) {
            throw ChaoxingSessionException(
              '学习通会话建立失败：网关身份桥接被拒（${clipForTrace(text, 160)}）',
            );
          }
          trace?.add('   网关身份桥接 status:true');

          // ③ 按页内 `jumpToRefer` 的规则**改跳**学习空间（不是跟 Location）。
          return CasHopGoto<ChaoxingSession>(
            '${ChaoxingEndpoints.spaceRefer}?data=${params['data']}'
            '&time=${params['time']}&enc=${params['enc']}',
          );
        }

        if (step.host != ChaoxingEndpoints.spaceHost) {
          throw ChaoxingSessionException(
            '学习通会话建立失败：换证链走到了意料之外的主机 ${step.host}',
          );
        }

        // ④ 学习空间：链路走完，这一页里带着收件箱 token（省掉一次请求）。
        final session = ChaoxingSession(
          jar: jar,
          noticeToken: chaoxingNoticeToken(step.bodyText ?? ''),
        );
        if (!session.isAlive) {
          throw ChaoxingSessionException(
            '学习通会话建立失败：未取得 passport Cookie'
            '（罐内域：${jar.namesOf().keys.join('、')}）',
          );
        }
        trace?.add(
          '   会话就位：passport ✓，收件箱 token '
          '${session.canFetchNotices ? '✓' : '✗'}',
        );
        return CasHopFinish<ChaoxingSession>(session);
      },
    );

    final session = outcome.result;
    if (session != null) return session;
    if (outcome.exhausted) {
      throw ChaoxingSessionException(
        '学习通会话建立失败：换证链跳数超过 $maxHops（链路成环或服务端行为变了）',
      );
    }
    throw ChaoxingSessionException(
      '学习通会话建立失败：换证链停在 ${Uri.parse(outcome.finalUrl).host}'
      '（HTTP ${outcome.lastStatusCode}），未取得学习空间会话',
    );
  }

  /// 从「跳转中…」页里抠出桥接参数（`data` / `time` / `enc` + 用户信息）。
  ///
  /// 页面结构：`var data = "…";` 之类的声明 + `jQuery.ajax({ data:{ data:data, … } })`。
  /// 右侧可能是字面量也可能是标识符 —— **标识符要回代到 var 声明**，否则会把
  /// 变量名当成值传过去（实测这会得到 `{"msg":"参数错误","status":false}`）。
  ///
  /// 与 `libsp_auth_remote_datasource.dart` 的同名方法逐字一致（两条链路的网关页
  /// 是同一个模板）；刻意各留一份：两边 refer 不同、演进节奏也不同，
  /// 抽到 core 会让「改一边」变成「两条链路一起炸」。
  static Map<String, String> parseGatewayBridgeParams(String html) {
    final decl = <String, String>{};
    for (final m in RegExp(r'''var\s+(\w+)\s*=\s*["']([^"']*)["']''').allMatches(html)) {
      decl[m.group(1)!] = m.group(2)!;
    }
    final block = RegExp(r'data:\s*\{(.*?)\}\s*,', dotAll: true).firstMatch(html);
    if (block == null) return const {};
    final out = <String, String>{};
    for (final m in RegExp(
      r'''(\w+)\s*:\s*(?:'([^']*)'|"([^"]*)"|([\w.\-]+))''',
    ).allMatches(block.group(1)!)) {
      final literal = m.group(2) ?? m.group(3);
      final bare = m.group(4);
      if (literal != null) {
        out[m.group(1)!] = literal;
      } else if (bare != null) {
        out[m.group(1)!] = decl[bare] ?? bare;
      }
    }
    return out;
  }

  static String _body(Response<dynamic> response) =>
      response.data?.toString() ?? '';

}
