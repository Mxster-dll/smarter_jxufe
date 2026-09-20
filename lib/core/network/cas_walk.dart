/// 统一认证（CAS）换证链的**逐跳循环**唯一实现（2026-09-20 立 · 架构审查 ②）。
///
/// 背景：本仓有 6 个站点各自手写了一遍「跟 3xx Location、按 host 带 Cookie、
/// 记 trace、最多 N 跳、没有 Location 就收工」的循环。Cookie 罐与 trace 截断
/// 已各自收敛成 `HostCookieJar` / `clipForTrace`，**剩下这段循环仍在 6 处重复**
/// （read_credit 12 跳 / cxstar 15 跳 / tsgxs 14 跳 / libsp 8 跳 / chaoxing 8 跳 /
/// dzj 1(+1) 跳）。本文件把**循环机制**收成一份。
///
/// ## 这里只统一「机制」，不统一「站点语义」
///
/// 分三层（口径见 `docs/agents/33-横向地基件（跨模块唯一实现）.md` §33.4.1）：
/// 1. Cookie 罐 = `HostCookieJar` / `SessionCookieJar`（已收敛）；
/// 2. **换证循环 = 本文件**（跟跳、记 Cookie、trace、跳数上限、终止判定）；
/// 3. 站点钩子**各自保留** —— 拿 token 的三种姿势（回跳地址 / Set-Cookie / 正文）、
///    超星的网关桥接、入馆教育的 JS 跳转兜底与预热、dzj 的一跳后强取。
///
/// 所以本文件**不认识任何站点**，也不抛任何站点异常：钩子返回 `null` = 还没拿到，
/// 循环正常走完（无 Location 或撞上 [CasWalkSpec.maxHops]）时由调用方按自己的
/// 文案抛错 —— 错误提示是各站的门面，不该被地基件统一。
///
/// ## 两个容易做错的地方（实测踩过）
///
/// - **`send` 由调用方给**：`chaoxing` 走的是带节流 + 风控（202 挑战页）识别的
///   `ChaoxingHttpClient`，`cxstar` 要 `ResponseType.plain`，`dzj` 要写死 `Host`
///   与完整 UA —— 把 Dio 写死进本文件，就等于逼这 3 个站点放弃自己的发送语义。
/// - **返回 `CasWalkOutcome` 而不是 `T?`**：站点抛错时要把「最后一跳的状态码」
///   写进用户可见的提示（`（得到 [uid]，HTTP 200）`）。只返回 `T?` 会丢掉它，
///   于是各站又会自己再记一次最后一跳 —— 循环白收。
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'cookie_jar.dart';
import 'trace_text.dart';

/// 换证链的一跳（钩子看到的全部信息）。
///
/// ⚠ **请求前钩子**里 [response] / [setCookieNames] 为空，只有 [url] / [host] 可用；
/// 请求后才填齐。用 [hasResponse] 区分，别去读空值再猜。
class CasWalkStep {
  const CasWalkStep({
    required this.index,
    required this.url,
    required this.host,
    this.response,
    this.setCookieNames = '',
  });

  /// 0 起的跳数。
  final int index;

  /// 本跳请求的绝对地址。
  final String url;

  /// [url] 的 host（Cookie 归属、Referer 都用它）。
  final String host;

  /// 本跳响应（请求前钩子为 null）。
  final Response<dynamic>? response;

  /// 本跳 `Set-Cookie` 的**名字**（逗号分隔；**绝不含值** —— 值就是凭据）。
  final String setCookieNames;

  bool get hasResponse => response != null;

  int get statusCode => response?.statusCode ?? 0;

  /// 本跳的 `Location`（空串 / 缺失都归一成 null）。
  String? get location {
    final raw = response?.headers.value('location');
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  bool get hasLocation => location != null;

  /// 正文文本（非字符串响应转成字符串；请求前钩子为 null）。
  String? get bodyText {
    final raw = response?.data;
    if (raw == null) return null;
    return raw is String ? raw : raw.toString();
  }

  /// 本跳的 `Set-Cookie` 原始列表（站点要自己从 Cookie 里挑 token 时用）。
  List<String>? get setCookies => response?.headers['set-cookie'];
}

/// 钩子对「下一跳」的决定。
///
/// - 返回 `null` = **按 `Location` 继续**（绝大多数跳）；
/// - [CasHopGoto] = **改跳别处**（不跟 `Location`）—— 网关桥接、JS 跳转兜底这类
///   「下一个地址是页面里算出来的、不是响应头给的」情形用它；
/// - [CasHopFinish] = **拿到结果，收工**。
///
/// 三种之外没有第四种：钩子不许自己发请求再悄悄继续（那等于把循环抄进钩子）。
sealed class CasHopAction<T> {
  const CasHopAction();
}

/// 改跳 [url]（相对地址会按当前地址解析）。
final class CasHopGoto<T> extends CasHopAction<T> {
  const CasHopGoto(this.url);

  final String url;
}

/// 拿到 [value]，收工。
final class CasHopFinish<T> extends CasHopAction<T> {
  const CasHopFinish(this.value);

  final T value;
}

/// 请求**前**钩子（返回 `null` = 照发这一跳）。
///
/// `cxstar` 用它处理「CAS 回跳地址本身就带 `?token=…`」那一档（发请求前就拿到结果）；
/// 也可以在请求前改跳（`CasHopGoto`）—— 这一跳就不会发出去。
///
/// ⚠ 允许 `await`：网关桥接要在钩子里多打一到两次请求（那是**站点私有子协议**，
/// 不是 Location 驱动的一跳），所以钩子是异步的。
typedef CasWalkPreHook<T> =
    FutureOr<CasHopAction<T>?> Function(CasWalkStep step);

/// 请求**后**钩子（返回 `null` = 按 `Location` 继续）。
///
/// 各站的分工：`read_credit` 判「没有 Location 且 Cookie 已带 `uid`+`token`」；
/// `cxstar` 从 Set-Cookie / 正文取 JWT；`libsp` / `chaoxing` 跑网关桥接（异步）；
/// `tsgxs` 处理 JS 跳转兜底与手工补写 `uid`。
typedef CasWalkPostHook<T> =
    FutureOr<CasHopAction<T>?> Function(CasWalkStep step);

/// 走完（或走断）换证链的结果。
class CasWalkOutcome<T> {
  const CasWalkOutcome({
    required this.result,
    required this.last,
    required this.hops,
    required this.finalUrl,
    required this.exhausted,
  });

  /// 钩子给出的结果；null = 走到头也没拿到（调用方按自己的文案抛错）。
  final T? result;

  /// 最后一跳（用于错误文案里的状态码 / 最终地址）；一跳没走成时为 null。
  final CasWalkStep? last;

  /// 实际走了几跳。
  final int hops;

  /// 停下时的地址。
  final String finalUrl;

  /// true = 是**撞上 [CasWalkSpec.maxHops] 上限**停的（不是链路自然结束）。
  ///
  /// 这一位是给诊断用的：自然结束 = 「票被拒 / 需要重新登录」，
  /// 撞上限 = 「链路成环或服务端行为变了」—— 两者的处理方式完全不同。
  final bool exhausted;

  bool get hasResult => result != null;

  /// 最后一跳的状态码（没有响应时 0）。
  int get lastStatusCode => last?.statusCode ?? 0;
}

/// 换证循环的可调项（站点差异全在这里，别往循环体里加 `if`）。
class CasWalkSpec {
  const CasWalkSpec({
    this.maxHops = 12,
    this.tracePrefix = '跳',
    this.traceUrlMax = 120,
    this.traceLocationMax = 80,
  });

  /// 跳数上限（各站实测口径：read_credit 12 / cxstar 15 / tsgxs 14 / libsp 8 / chaoxing 8）。
  final int maxHops;

  /// trace 行前缀（全仓一律 `跳`）。
  final String tracePrefix;

  /// trace 里 URL 的截断宽度。
  final int traceUrlMax;

  /// trace 里 Location 的截断宽度。
  final int traceLocationMax;
}

/// 逐跳走完换证链（**唯一实现**）。
///
/// - 每跳：先跑 [beforeRequest] → 用 [send] 发请求 → 记 Cookie → 跑 [afterResponse]
///   → 记 trace → 有 `Location` 就跳下一跳，没有就收工；
/// - [jar] 由调用方持有（调用方最后要用它断言会话 / 取 Cookie 串）；
/// - [trace] 非空时逐跳追加诊断行（**只打 Set-Cookie 的名字，不打值**）；
/// - 抛出的只有 [send] 自己的异常（网络层），**本函数不抛站点异常**。
Future<CasWalkOutcome<T>> walkCasRedirects<T>({
  required String startUrl,
  required CookieJar jar,
  required Future<Response<dynamic>> Function(String url, String cookieHeader) send,
  CasWalkSpec spec = const CasWalkSpec(),
  CasWalkPreHook<T>? beforeRequest,
  CasWalkPostHook<T>? afterResponse,
  List<String>? trace,
}) async {
  var url = startUrl;
  CasWalkStep? step;
  var hops = 0;

  for (var hop = 0; hop < spec.maxHops; hop++) {
    final host = Uri.parse(url).host;

    // ① 请求前（站点可从回跳地址本身取东西 —— cxstar 的 `?token=`；也可改跳）。
    if (beforeRequest != null) {
      final action = await beforeRequest(
        CasWalkStep(index: hop, url: url, host: host),
      );
      if (action is CasHopFinish<T>) {
        return CasWalkOutcome<T>(
          result: action.value,
          last: step,
          hops: hops,
          finalUrl: url,
          exhausted: false,
        );
      }
      if (action is CasHopGoto<T>) {
        url = Uri.parse(url).resolve(action.url).toString();
        continue; // 这一跳不再发请求
      }
    }

    // ② 发请求（发送语义在调用方：Dio 选项 / 节流 / 写死 header 各不相同）。
    final response = await send(url, jar.headerFor(host));
    hops = hop + 1;

    // ③ 记 Cookie（按 host 归属 —— 谁下发的只发给谁）。
    final setCookies = response.headers['set-cookie'];
    jar.absorbUrl(Uri.parse(url), setCookies);

    step = CasWalkStep(
      index: hop,
      url: url,
      host: host,
      response: response,
      setCookieNames: setCookieNames(setCookies),
    );

    // ④ 记 trace（**排在钩子之前**：各站原来就是「先记这一跳，再打自己那行
    //    『取得个人 token…』」；顺序反了会让 trace 读起来因果颠倒）。
    _trace(trace, spec, step);

    // ⑤ 请求后（站点自己判成功 / 取 token / 跑网关桥接 / 认 JS 跳转）。
    if (afterResponse != null) {
      final action = await afterResponse(step);
      if (action is CasHopFinish<T>) {
        return CasWalkOutcome<T>(
          result: action.value,
          last: step,
          hops: hops,
          finalUrl: url,
          exhausted: false,
        );
      }
      if (action is CasHopGoto<T>) {
        url = Uri.parse(url).resolve(action.url).toString();
        continue; // 不跟 Location，按站点算出来的地址走
      }
    }

    // ⑥ 没有 Location = 链路自然结束（由调用方判「拿到没拿到」）。
    final location = step.location;
    if (location == null) {
      return CasWalkOutcome<T>(
        result: null,
        last: step,
        hops: hops,
        finalUrl: url,
        exhausted: false,
      );
    }
    url = Uri.parse(url).resolve(location).toString();
  }

  // 撞上跳数上限：与「自然结束」分开报（见 CasWalkOutcome.exhausted 的 doc）。
  return CasWalkOutcome<T>(
    result: null,
    last: step,
    hops: hops,
    finalUrl: url,
    exhausted: true,
  );
}

/// 常规站点的发送器：`followRedirects: false` + 状态码全放行 + 按 host 带 Cookie。
///
/// 默认 `Referer: https://<host>/`；[refererIsCurrentUrl] 时改成**当前完整 URL**
/// （入馆教育平台实测要求这样）。
///
/// 不走这个发送器的站点（保留自己的）：`chaoxing`（`ChaoxingHttpClient` 带节流与
/// 风控识别）、`dzj`（写死 `Host` 与完整 PC UA）。
Future<Response<dynamic>> Function(String url, String cookieHeader) casDioSender(
  Dio dio, {
  ResponseType? responseType,
  Map<String, String>? extraHeaders,
  bool refererIsCurrentUrl = false,
}) {
  return (url, cookieHeader) {
    final host = Uri.parse(url).host;
    return dio.get<dynamic>(
      url,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => true,
        responseType: responseType,
        headers: {
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          'Referer': refererIsCurrentUrl ? url : 'https://$host/',
          ...?extraHeaders,
        },
      ),
    );
  };
}

void _trace(List<String>? trace, CasWalkSpec spec, CasWalkStep step) {
  if (trace == null) return;
  final location = step.location;
  final names = step.setCookieNames;
  trace.add(
    '${spec.tracePrefix}[${step.index}] ${step.statusCode} '
    '${clipForTrace(step.url, spec.traceUrlMax)}'
    '${location != null ? ' -> ${clipForTrace(location, spec.traceLocationMax)}' : ''}'
    '${names.isNotEmpty ? '  Set-Cookie(${step.host}): $names' : ''}',
  );
}
