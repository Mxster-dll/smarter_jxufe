/// 学习通 HTTP 薄封 —— 统一「带罐请求 + 吸收 Set-Cookie + 跳转与过期判定」。
///
/// 三个数据源（换证 / 课程·作业 / 通知）共用它，避免各写一遍 Cookie 拼装。
///
/// 三条口径：
/// 1. **自己跟随重定向**（`followRedirects: false`）：换证链要逐跳看 `Set-Cookie`，
///    而 Cookie 归属域只有服务端知道，交给 Dio 自动跟就跟丢了；
/// 2. 每次响应都 [SessionCookieJar.absorb]（Dio 已把 `set-cookie` 按行切开）；
/// 3. **过期判定**看「是否被踢回 `passport2.chaoxing.com/login`」——比看状态码可靠
///    （学习通登录态失效给的是 302 而不是 401）。
///
/// ⚠ `followRedirects:` 是**业务请求**用的（课程 / 作业 / 通知）：学习通的业务页
/// 经常会先给一个 302（带会话 token 再回跳），**不跟就跟了个空页**。换证链**不要**开它
/// —— 那条链要自己逐跳判定。实测：`/visit/stucoursemiddle` 不跟跳转 → 0 字节 →
/// 所有课都「没有作业」（见 `tool/chaoxing_smoke.dart` 的 `--diag`）。
///
/// ⚠⚠ **第四条口径：风控挑战页（2026-09-19 实测，见 [ensureUsable]）**。
/// 请求过密时超星会回 `202` + 4527 B 的「【9010】操作异常，请输入图片中的验证码」页
/// ——**它长得像一次成功响应**（`validateStatus` 全放行），但内容里没有作业入口、
/// 没有课程、没有 JSON。首版把它当成「这门课没有作业」→ 静默丢作业、并把残缺快照
/// 写进缓存（用户报「作业、课程有时刷新会刷新没」）。所以**每个业务响应都必须过
/// [ensureUsable]**，风控页要抛 [ChaoxingChallengedException] 而不是当空结果。
library;

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_cookie_jar.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_limits.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';

/// 学习通请求薄封。
class ChaoxingHttpClient {
  ChaoxingHttpClient(
    this._dio, {
    this.minRequestInterval = chaoxingMinRequestInterval,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Dio _dio;

  /// 业务请求之间的**最小间隔**（[throttle] 为真时生效）。
  ///
  /// 实测口径（2026-09-19，同一会话同一批课程详情页）：
  /// - 稳态 **1 请求/秒 × 20 个 → 0 次风控**；
  /// - 突发 **8 / 16 并发 → 0 次**，**24 并发 → 24/24 全中**；
  /// - 触发后**至少 60 秒**不恢复（每秒探测一次，60 次全中）→ **重试只会延长窗口**。
  ///
  /// 所以既不能靠重试、也不能靠「多发几次总能成功」，只能**主动压速率**。
  /// 260 ms ≈ 3.8 请求/秒上限（35 门课 × 2 请求 ≈ 18 秒，与首版体感同量级）。
  final Duration minRequestInterval;

  final DateTime Function() _now;

  /// 下一个可用的发送格（原子预定制；`null` = 还没发过业务请求）。
  DateTime? _nextSlotAt;

  /// 学习通登录页 host（会话失效时会被踢到这里）。
  static const String passportHost = 'passport2.chaoxing.com';

  /// 业务请求最多跟几跳重定向（实测 1~2 跳）。
  static const int maxRedirectHops = 5;

  /// 风控挑战页的状态码（实测就是 `202`，不是 200/403）。
  static const int challengeStatus = 202;

  /// 挑战页正文特征（`<title>提示页面</title>` + 下面两句之一）。
  static const List<String> challengeMarkers = [
    '请输入图片中的验证码',
    '【9010】',
  ];

  /// 发一个 GET，并把响应里的 Cookie 收进 [jar]。
  ///
  /// [jar] 为 null 时只发不带 Cookie 的请求（换证第一步用）。
  /// [followRedirects] = true 时自己跟 3xx（业务页要用；**换证链不要开**）：
  /// 每一跳都重新按目标域取 Cookie、吸收新的 `Set-Cookie`，
  /// 但**被踢回登录页的 302 原样返回**（留给调用方的 `ensureAlive` 判失效重换）。
  /// [throttle] = true 时先等够 [minRequestInterval]（**业务请求传 true**；
  /// 换证链是一次性的几步，不必也不该被压）。
  Future<Response<dynamic>> get(
    String url, {
    SessionCookieJar? jar,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    String? referer,
    Duration timeout = const Duration(seconds: 25),
    bool followRedirects = false,
    bool throttle = false,
    List<String>? trace,
  }) async {
    if (throttle) await _waitTurn();
    var current = url;
    var currentQuery = query;

    for (var hop = 0; ; hop++) {
      final uri = Uri.parse(current);
      final response = await _send(
        uri,
        currentQuery,
        jar,
        headers,
        referer,
        timeout,
      );
      if (!followRedirects || hop >= maxRedirectHops) return response;

      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return response;
      if (isLoginRedirect(response)) return response;

      current = uri.resolve(location).toString();
      currentQuery = null; // 已并进 URL
      trace?.add('跟跳[$hop] ${response.statusCode} → ${Uri.parse(current).host}');
    }
  }

  /// 单跳请求（含 Cookie 拼装与吸收）。
  Future<Response<dynamic>> _send(
    Uri uri,
    Map<String, dynamic>? query,
    SessionCookieJar? jar,
    Map<String, String>? headers,
    String? referer,
    Duration timeout,
  ) async {
    final cookie = jar?.headerFor(uri.host) ?? '';
    try {
      final response = await _dio.get<dynamic>(
        uri.toString(),
        queryParameters: query,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
          receiveTimeout: timeout,
          headers: {
            if (cookie.isNotEmpty) 'Cookie': cookie,
            'Referer': referer ?? 'https://${uri.host}/',
            'User-Agent': kChaoxingUserAgent,
            if (headers != null) ...headers,
          },
        ),
      );
      jar?.absorbResponse(uri, response);
      return response;
    } on DioException catch (e) {
      throw ChaoxingSessionException(
        '学习通请求失败（${uri.host}）：${e.message ?? e.type.name}',
      );
    }
  }

  /// 响应是否被踢回登录页（会话失效）。
  static bool isLoginRedirect(Response<dynamic> response) {
    if (response.statusCode != 301 &&
        response.statusCode != 302 &&
        response.statusCode != 303 &&
        response.statusCode != 307) {
      return false;
    }
    final location = response.headers.value('location') ?? '';
    return location.contains(passportHost);
  }

  /// 200 但正文其实是登录页（少数接口这么干：不跳转，直接吐登录壳）。
  static bool looksLikeLoginPage(String body) =>
      body.contains('passport2.chaoxing.com/login') ||
      body.contains('请输入手机号') ||
      body.contains('用户登录');

  /// 响应是不是**风控挑战页**。
  ///
  /// 双重判据：状态码 `202`（实测超星风控专用），**或**正文带挑战特征
  /// （`请输入图片中的验证码` / `【9010】`）——只看状态码会在改码时失手，
  /// 只看正文会在改文案时失手。
  static bool isChallengePage(Response<dynamic> response, [String? body]) {
    if (response.statusCode == challengeStatus) return true;
    final text = body ?? response.data?.toString() ?? '';
    return challengeMarkers.any(text.contains);
  }

  /// 业务响应可用性总闸：**风控页 → 抛**，登录跳转 → 抛。
  ///
  /// ⚠ 顺序要紧：挑战页先判 —— 它既不是登录页也不是业务页，落到任何一个
  /// 「空结果」分支都会变成静默丢数据。
  static void ensureUsable(Response<dynamic> response, [String? body]) {
    if (isChallengePage(response, body)) {
      throw ChaoxingChallengedException(
        '学习通触发了安全验证（${response.statusCode} · '
        '操作异常，请输入图片中的验证码），本次取数已中止',
      );
    }
    ensureAlive(response);
  }

  /// 会话失效则抛 [ChaoxingSessionExpiredException]。
  static void ensureAlive(Response<dynamic> response) {
    if (isLoginRedirect(response)) {
      throw ChaoxingSessionExpiredException('学习通会话已失效（被踢回登录页）');
    }
  }

  /// 业务请求排队：**先原子预定一格**，再睡到那一格。
  ///
  /// ⚠ 不能写成「看上次发出时刻 → 睡够 → 记下时刻」：那样 4 条 lane 会**同时**
  /// 读到同一个 `last`、算出同一个 `wait`、一起醒来一起发 —— 实测退化成
  /// **4 请求 / 260ms**（35 门课 64 个请求只花 4.3 秒，风控照样触发）。
  /// 现在读-改-写是**同步完成**的（中间没有 `await`），每条 lane 拿到互不相同的一格，
  /// 总速率才真的被压在 `1 / minRequestInterval` 以下。
  Future<void> _waitTurn() async {
    final now = _now();
    var slot = _nextSlotAt ?? now;
    if (slot.isBefore(now)) slot = now;
    _nextSlotAt = slot.add(minRequestInterval);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
}

/// 学习通 PC 端 UA（与探针一致；网关页会按 UA 判断 `ChaoXingStudy`，PC UA 走 web 分支）。
const String kChaoxingUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
