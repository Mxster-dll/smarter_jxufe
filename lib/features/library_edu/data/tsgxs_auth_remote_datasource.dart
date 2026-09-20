import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cas_walk.dart';
import 'package:smarter_jxufe/core/network/cookie_jar.dart';
import 'package:smarter_jxufe/core/network/trace_text.dart';
import 'package:smarter_jxufe/features/library_edu/data/anti_corruption/tsgxs_exam_parser.dart';

/// tsgxs(图书馆新生入馆教育,ASP.NET)会话已失效/被顶下线。
class TsgxsSessionExpiredException extends SessionExpiredException {
  TsgxsSessionExpiredException([super.message = '入馆教育会话已过期']);
}

/// 入馆教育(tsgxs.jxufe.cn)会话建立远程数据源。
///
/// 统一认证链(实测 2026-09-10):
/// 1. TGC → ssl CAS service 入口 → 带 ticket 的 casapi 回调地址
///    (由 [AuthRepository.getServiceRedirectUrl] 完成);
/// 2. casapi 校验 ticket → 302 `/Index/Info` → 200 纯跳转页,正文仅
///    `<script>window.location.href='http://tsgxs.jxufe.cn/web/User/cblogin
///    ?userid=…&name=…&xyname=…'</script>`;
/// 3. **跨域进入 tsgxs 前必须预热**:匿名访问 tsgxs 登录页(带 `from=0`
///    才返回 200 登录页),取得 tsgxs 自己签发的 `ASP.NET_SessionId`
///    与 `uid`;
/// 4. cblogin 把学号/姓名/学院绑定到该会话,签发 `uid`(鉴权 cookie,单点
///    登录:同一账号再次登录会把先前会话顶下线,表现为 103B 页面
///    `alert('您的账号已在别处登录…')`)。
///
/// 关键约束:**Cookie 必须按域隔离**。casapi(nczxst.com)与 tsgxs 都会签发
/// 同名 `ASP.NET_SessionId`,若把 casapi 的会话 cookie 一起发给 tsgxs,
/// 会破坏 tsgxs 会话(实测返回登录页而非已登录页)。故此处维护按 host
/// 分组的 cookie jar,只向对应 host 发送其自身 cookie。
class TsgxsAuthRemoteDataSource {
  final Dio _dio;

  TsgxsAuthRemoteDataSource(this._dio);

  /// tsgxs 在统一认证中的 CAS service 入口（service 内嵌 casapi targetUrl）。
  static const String casServiceUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=http%3a%2f%2fcasapi.nczxst.com%2fIndex%2fLogin'
      '%3ftargetUrl%3d%7bbase64%7d'
      'aHR0cDovL2Nhc2FwaS5uY3p4c3QuY29tL0luZGV4L0luZm8%3d';

  /// tsgxs 业务域 host(会话 cookie 的归属域)。
  static const String tsgxsHost = 'tsgxs.jxufe.cn';

  /// 默认皮肤(书生版,登录页 `input[name=tid]` 的 checked 项)。
  static const String _defaultThemeId = '5d037bb3-12c5-4554-a3c2-d128766dd025';

  /// 会话 Cookie 是否已含鉴权标识 `uid`(缺 uid = 匿名态,业务接口会 302
  /// 到 `/web/user/logout`)。
  static bool hasUid(String cookie) =>
      RegExp(r'(?:^|;\s*)uid=[^;]+').hasMatch(cookie);

  /// 建立会话:跟随换证链,返回 **tsgxs 域**的 Cookie 串(如
  /// `ASP.NET_SessionId=…; from=0; uid=…`),供后续业务请求使用。
  ///
  /// [trace] 非空时逐跳追加诊断行,便于调试期观察完整链路。
  Future<String> establishSession(
    String ticketUrl, {
    List<String>? trace,
  }) async {
    final jar = HostCookieJar();
    // 循环机制走地基件（`lib/core/network/cas_walk.dart`，含「按当前 URL 作 Referer」
    // 与本平台特有的 14 跳上限 / trace 宽度）；这里只留本平台私有语义：
    // JS 跳转兜底（stub 页才有资格追）、跨域预热、补选皮肤后复验登录。
    final outcome = await walkCasRedirects<String>(
      startUrl: ticketUrl,
      jar: jar,
      send: casDioSender(_dio, refererIsCurrentUrl: true),
      spec: const CasWalkSpec(
        maxHops: 14,
        traceUrlMax: 140,
        traceLocationMax: 80,
      ),
      trace: trace,
      afterResponse: (step) async {
        if (step.hasLocation) return null;

        final body = step.bodyText ?? '';
        // 仅追踪“无 <html> 的纯跳转 stub 页”(casapi Info 页、tsgxs 的
        // 顶下线提示页),完整页面内的 location.href 属业务脚本,不得误追。
        final jsTarget = !body.contains('<html') || body.length < 400
            ? _jsRedirectUrl(body)
            : null;
        if (jsTarget != null) {
          final rawTarget = Uri.parse(step.url).resolve(jsTarget).toString();
          final targetHost = Uri.parse(rawTarget).host;
          trace?.add('    ↳ JS跳转 -> ${clipForTrace(rawTarget, 200)}');
          if (isKickedOffPage(body)) {
            throw TsgxsSessionExpiredException(
              '账号已在别处登录,入馆教育会话被顶下线,请重新建立会话',
            );
          }
          // 跨域进入 tsgxs 前预热:匿名取登录页,建立 tsgxs 自身会话
          // (登录页需带 from=0 才返回 200;/Web/User 匿名会 302 到根页,
          // 根页会下发 from=0,故先跟随后重取)。
          if (targetHost != step.host) {
            await _warmUp(jar, targetHost, trace);
          }
          // 改跳（这一跳的地址是页面里算出来的,不是响应头给的）。
          return CasHopGoto<String>(rawTarget);
        }

        if (trace != null) {
          final head = body.replaceAll(RegExp(r'\s+'), ' ').trim();
          trace.add(
            '终点页(${step.statusCode}) len=${body.length} '
            '头: ${head.substring(0, head.length > 240 ? 240 : head.length)}',
          );
        }
        if (isKickedOffPage(body)) {
          throw TsgxsSessionExpiredException(
            '账号已在别处登录,入馆教育会话被顶下线,请重新建立会话',
          );
        }
        // cblogin 才是登录本体;校验它是否真的下发登录态 uid。
        final loggedIn = await _verifyTsgxsLogin(jar, trace, step.url);
        final session = jar.headerFor(tsgxsHost);
        if (session.isEmpty) {
          throw TsgxsSessionExpiredException(
            '建立入馆教育会话失败：未取得 tsgxs 会话 Cookie '
            '(status=${step.statusCode})',
          );
        }
        if (!hasUid(session)) {
          throw TsgxsSessionExpiredException(
            '建立入馆教育会话失败：cblogin 未完成,会话 Cookie 仅'
            '[${jar.namesOf(tsgxsHost)}](缺 uid);'
            '逐跳诊断已写入 tsgxs_login_trace.log',
          );
        }
        if (!loggedIn) {
          throw TsgxsSessionExpiredException(
            '入馆教育登录未完成：补选皮肤后登录探测仍未通过;'
            '请重试,若持续失败请先用网页端登录一次该账号;'
            '逐跳诊断已写入 tsgxs_login_trace.log',
          );
        }
        return CasHopFinish<String>(session);
      },
    );

    final session = outcome.result;
    if (session != null) return session;
    throw TsgxsSessionExpiredException('建立入馆教育会话失败：重定向次数过多');
  }

  /// 校验 cblogin 是否真的完成,并在**首次登录**时补完「选皮肤(角色)」步骤。
  ///
  /// 实证(2026-09-10 App 逐跳诊断 + 登录页 JS):
  /// - `GET /web/User/cblogin?userid=…&name=…&xyname=…` → 302 `/Web/User`
  ///   且 `Set-Cookie: uid` —— 这是**已选过皮肤**的老账号;
  /// - 首次登录的账号得到的是 `/Web/User?success=-2&uid=…`:统一认证已通过,
  ///   但服务端**把 uid 放在跳转地址的查询串里、不下发 uid cookie**。登录页
  ///   JS 对该分支的处理是调用
  ///   `POST /Web/User/SelectTheme {uid, tid}`(Success=1 后跳 `/web/user/Index`);
  ///   未补这一步则会话始终是匿名态:首页/章节页仍 200,但
  ///   `/Web/Exam`、成绩、排行榜 一律 302 到 `/web/user/logout`。
  /// - `success=3`:学校已开启多次考试,网页端走 `POST /Web/User/RLogin {uid}`。
  ///
  /// 缺 uid 且无任何 uid 线索时本链无从补救(CAS 票据一次性),返回后由
  /// [establishSession] 抛错,上层重走整条换取链。
  Future<bool> _verifyTsgxsLogin(
    HostCookieJar jar,
    List<String>? trace,
    String currentUrl,
  ) async {
    final cookie = jar.headerFor(tsgxsHost);
    if (cookie.isEmpty) return false;
    final resp = await _dio.get(
      'http://$tsgxsHost/Web/User',
      options: Options(
        followRedirects: false,
        validateStatus: (s) => true,
        headers: {'Cookie': cookie, 'Referer': 'http://$tsgxsHost/'},
      ),
    );
    jar.absorb(tsgxsHost, resp.headers['set-cookie']);
    final body = resp.data?.toString() ?? '';
    if (isKickedOffPage(body)) {
      throw TsgxsSessionExpiredException('账号已在别处登录,入馆教育会话被顶下线,请重新建立会话');
    }
    var uid = jar.valueOf(tsgxsHost, 'uid');
    if (uid != null) {
      if (trace != null) {
        trace.add('    登录态校验 ${resp.statusCode} len=${body.length} 已登录(uid)');
      }
      return true;
    }
    // 未登录:从 success=-2 跳转地址 / 页面里找待激活的 uid。
    final pendingUid = parseTsgxsPendingUid(currentUrl) ?? _extractUid(body);
    if (pendingUid == null) {
      if (trace != null) {
        trace.add(
          '    登录态校验 ${resp.statusCode} len=${body.length} '
          '未登录且无 uid 线索(Cookie=[${jar.namesOf(tsgxsHost)}])',
        );
      }
      return false;
    }
    final success = Uri.tryParse(currentUrl)?.queryParameters['success'];
    if (success == '3') {
      // 学校开启多次考试:网页端确认后走 RLogin。
      await _postForm(
        jar,
        '/Web/User/RLogin',
        {'uid': pendingUid},
        trace,
        label: 'RLogin(多次考试)',
      );
    } else {
      final themeId = parseTsgxsThemeId(body) ?? _defaultThemeId;
      await _postForm(
        jar,
        '/Web/User/SelectTheme',
        {'uid': pendingUid, 'tid': themeId},
        trace,
        label: '补选皮肤(首次登录)',
        extra: 'tid=${clipForTrace(themeId, 8)}',
      );
    }
    // 服务端可能仍未下发 uid cookie(uid 只在跳转地址里),则按其给出的值
    // 补写为请求 Cookie —— 供后续业务接口携带鉴权标识。
    if (jar.valueOf(tsgxsHost, 'uid') == null) {
      jar.set(tsgxsHost, 'uid', pendingUid);
      if (trace != null) {
        trace.add('    服务端未下发 uid cookie,按 success 跳转地址里的 uid 补写');
      }
    }
    // 用只读的「我的成绩」页做登录探测(200=已登录,3xx=仍是匿名态)。
    final probe = await _dio.get(
      'http://$tsgxsHost/Web/Center/MyGrades',
      options: Options(
        followRedirects: false,
        validateStatus: (s) => true,
        headers: {'Cookie': jar.headerFor(tsgxsHost)},
      ),
    );
    jar.absorb(tsgxsHost, probe.headers['set-cookie']);
    // 实测(2026-09-11):被顶下线的会话对任何地址都返回 **HTTP 200 + 103 字节**
    // 提示页,匿名/伪造 uid 则 302 到 `/`。故判据必须是「200 且含成绩页标记」,
    // 只看状态码会把顶下线/匿名会话误判为已登录。
    final probeBody = probe.data?.toString() ?? '';
    final ok =
        probe.statusCode == 200 &&
        !isKickedOffPage(probeBody) &&
        (probeBody.contains('闯关用时') || probeBody.contains('我的成绩'));
    if (trace != null) {
      trace.add(
        '    登录探测 /Web/Center/MyGrades -> ${probe.statusCode} '
        'len=${probeBody.length} ${ok ? '已登录' : '仍未登录'}',
      );
    }
    return ok;
  }

  /// 表单 POST(表单编码),收集 Set-Cookie 并记录诊断。
  Future<void> _postForm(
    HostCookieJar jar,
    String path,
    Map<String, dynamic> data,
    List<String>? trace, {
    required String label,
    String extra = '',
  }) async {
    final resp = await _dio.post(
      'http://$tsgxsHost$path',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => true,
        headers: {'Cookie': jar.headerFor(tsgxsHost)},
      ),
    );
    jar.absorb(tsgxsHost, resp.headers['set-cookie']);
    if (trace != null) {
      final text = (resp.data?.toString() ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      trace.add(
        '    $label ${resp.statusCode} $extra '
        'Set-Cookie(${setCookieNames(resp.headers['set-cookie'], empty: '(无)')}): '
        '${text.length > 160 ? '${text.substring(0, 160)}…' : text}',
      );
    }
  }

  /// 从页面正文里兜底提取 uid(隐藏域 / JS 变量 / 链接参数)。
  static String? _extractUid(String body) {
    const patterns = [
      r'''[?&]uid=([0-9a-fA-F-]{36})''',
      r'''id=["']uid["'][^>]*value=["']([0-9a-fA-F-]{36})["']''',
      r'''(?:var\s+uid|["']uid["'])\s*[:=]\s*["']([0-9a-fA-F-]{36})["']''',
    ];
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(body)?.group(1);
      if (m != null && m.isNotEmpty) return m;
    }
    return null;
  }

  /// 预热目标域会话:先请求根页拿 `from`,再请求登录页拿会话与 `uid`。
  Future<void> _warmUp(
    HostCookieJar jar,
    String host,
    List<String>? trace,
  ) async {
    var warmUrl = 'http://$host/Web/User';
    for (var hop = 0; hop < 4; hop++) {
      final h = Uri.parse(warmUrl).host;
      final warmCookie = jar.headerFor(h);
      final warm = await _dio.get(
        warmUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => true,
          headers: {if (warmCookie.isNotEmpty) 'Cookie': warmCookie},
        ),
      );
      jar.absorb(h, warm.headers['set-cookie']);
      final loc = warm.headers.value('location');
      if (trace != null) {
        final names = setCookieNames(warm.headers['set-cookie']);
        trace.add(
          '    预热[$hop] ${warm.statusCode} ${clipForTrace(warmUrl, 110)}'
          '${loc != null && loc.isNotEmpty ? ' -> ${clipForTrace(loc, 60)}' : ''}'
          '${names.isNotEmpty ? '  Set-Cookie($h): $names' : ''}',
        );
      }
      if (loc == null || loc.isEmpty) break;
      warmUrl = Uri.parse(warmUrl).resolve(loc).toString();
    }
    // 根页已下发 from=0 后,再取一次登录页,取得 tsgxs 会话与 uid。
    final loginUrl = 'http://$host/Web/User';
    final loginCookie = jar.headerFor(host);
    final login = await _dio.get(
      loginUrl,
      options: Options(
        followRedirects: false,
        validateStatus: (s) => true,
        headers: {if (loginCookie.isNotEmpty) 'Cookie': loginCookie},
      ),
    );
    jar.absorb(host, login.headers['set-cookie']);
    if (trace != null) {
      final names = setCookieNames(login.headers['set-cookie']);
      trace.add(
        '    预热登录页 ${login.statusCode} ${clipForTrace(loginUrl, 110)}'
        '${names.isNotEmpty ? '  Set-Cookie($host): $names' : ''}',
      );
    }
  }

  /// 是否为“账号已在别处登录/被迫下线”提示页。
  ///
  /// 公开给同 feature 的 `tsgxs_api_remote_datasource.dart`：那边曾把同一判据
  /// 内联两遍（2026-09-20 收敛）。⚠ 文案是超星私有的，**刻意不进 `lib/core/`**
  /// —— 只有本 feature 用得到。
  static bool isKickedOffPage(String body) =>
      body.contains('已在别处登录') || body.contains('被迫下线');


  /// 从页面正文提取 JS 跳转目标（`location.href='…'` 或 `location.replace('…')`）。
  static String? _jsRedirectUrl(String body) {
    final href = RegExp(
      r'''location\.href\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body)?.group(1);
    if (href != null) return href;
    return RegExp(
      r'''location\.replace\(\s*['"]([^'"]+)['"]\s*\)''',
      caseSensitive: false,
    ).firstMatch(body)?.group(1);
  }
}
