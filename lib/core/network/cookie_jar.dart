/// 会话 Cookie 罐 —— **按域匹配**的唯一实现（2026-09-20 从学习通模块提取）。
///
/// 为什么需要它（而不是「一个 host 一个桶」）：超星系（学习通 / 图书馆 libsp）的
/// passport 会话是**域级 Cookie**（`Domain=.chaoxing.com`，实测 19 个中的
/// `UID/_uid/_d/vc3/uf/uname/fid/p_auth_token/xxtenc/cx_p_token/DSSTASH_LOG`），
/// 必须同时发给 `i.chaoxing.com`、`mooc1.chaoxing.com`、`notice.chaoxing.com`；
/// 而换证链中间那几跳（`unified-auth.chaoxing.com` 的 `JSESSIONID`/`firstReferer`/
/// `route`）是 **host-only**，绝不能串给业务域 —— 混发会把会话搞坏。
///
/// 本仓历史上有 8 个「换证 + Cookie 罐」实现，其中 7 份是
/// `Map<host, Map<name, value>>` + 逐字相同的 `_store` / `_cookieHeader` /
/// `_cookieNamesOf` / `_clip` 私有工具，只有学习通这一份做对了 Cookie 语义
/// （存 `Domain` 属性、取时按域后缀匹配、同名时更具体的域优先）。
/// 架构审查后把它提上来当**唯一实现**：新站点一律用它，别再写第 9 份。
///
/// 两个类**按语义选**，不要凭手感：
/// - [SessionCookieJar]：**认 `Domain=` 属性**（域级 Cookie 要跨子域发送）。
///   超星系（学习通 / 图书馆 libsp）必须用它 —— passport 是 `.chaoxing.com` 域级。
/// - [HostCookieJar]：**不认 `Domain=`**，谁下发的只发给谁（`Map<host,…>` 逐字等价）。
///   给「单一 host 上换证」的站点（畅想之星 / 阅读学分 / 入馆教育 / libsp 的换证链）
///   用 —— 它们历史上就是这个语义，换成域感知会**扩大 Cookie 投递范围**，
///   属于没必要的运行时行为变更。
///
/// ⚠ 罐里装的全是凭据：[namesOf] / [HostCookieJar.namesOf] 只报**名字**用于诊断，
/// **任何值都不许进日志**（[setCookieNames] 也是为此而存在）。
library;

import 'package:dio/dio.dart';

/// 把响应的 `Set-Cookie` 头渲染成**只有名字**的逗号串（诊断 / trace 用）。
///
/// 存在的理由：手写 `setCookies.map((c) => c.split(';').first)` 会打出
/// `name=value` —— **把凭据写进日志**（入馆教育换证链实测踩到 3 处）。
/// 空列表默认返回**空串**（调用方惯用 `names.isNotEmpty ? … : ''` 抑制后缀）；
/// 需要 `(无)` 这种占位文案的调用点显式传 `empty: '(无)'`（历史上入馆教育如此）。
String setCookieNames(List<String>? setCookies, {String empty = ''}) =>
    setCookies == null || setCookies.isEmpty
    ? empty
    : setCookies.map((c) => c.split(';').first.split('=').first).join(',');

/// 换证链 / 业务请求共用的罐接口 —— **两种语义各自实现，调用方只按能力用**。
///
/// 存在的理由：[walkCasRedirects]（`lib/core/network/cas_walk.dart`）要同时服务
/// 「host 分桶」的站点（阅读学分 / 畅想之星 / 入馆教育 / libsp 换证链）与
/// 「域感知」的站点（学习通 / 图书馆会话），而两个类的吸收签名本来就不同
/// （一个吃 host、一个吃 `Uri` —— 域感知必须知道 URL 才能判 host-only Cookie 归谁）。
/// 接口取 `Uri` 形态：host 分桶那份丢掉 query 用 `url.host` 即可。
///
/// ⚠ 只收「吸收 / 拼头 / 是否为空」三件事：`namesOf` 两边签名不同
/// （域感知无参、host 分桶要 host），硬凑一个名字只会让人用错。
abstract interface class CookieJar {
  /// 吸收一次响应的 `Set-Cookie`（[url] = 本次请求地址）。
  void absorbUrl(Uri url, List<String>? setCookie);

  /// 拼 [host] 的 `Cookie` 请求头；没有则空串。
  String headerFor(String host);

  /// 罐里一个 Cookie 都没有 = 还没换过证。
  bool get isEmpty;
}

/// 极简 Cookie 罐（域感知）。
class SessionCookieJar implements CookieJar {
  SessionCookieJar();

  /// 域（小写、去掉前导点）→ Cookie 名 → 值。
  final Map<String, Map<String, String>> _byDomain = {};

  /// 吸收一次响应的 `Set-Cookie`。
  ///
  /// [url] 是本次请求的地址 —— 没有 `Domain` 属性的 Cookie 按 host-only 归属它。
  void absorb(Uri url, List<String>? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return;
    for (final raw in setCookie) {
      final parts = raw.split(';');
      final pair = parts.first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (name.isEmpty) continue;

      String? domain;
      for (final attr in parts.skip(1)) {
        final t = attr.trim();
        if (t.toLowerCase().startsWith('domain=')) {
          domain = _normalizeDomain(t.substring('domain='.length).trim());
          break;
        }
      }
      final key = (domain == null || domain.isEmpty)
          ? _normalizeDomain(url.host)
          : domain;
      if (key.isEmpty) continue;
      if (value.isEmpty) {
        _byDomain[key]?.remove(name);
        continue;
      }
      _byDomain.putIfAbsent(key, () => <String, String>{})[name] = value;
    }
  }

  /// 从 `Response` 里读 `set-cookie` 并吸收（Dio 的 header 值已按行切开）。
  void absorbResponse(Uri url, Response<dynamic> response) =>
      absorb(url, response.headers['set-cookie']);

  /// [CookieJar] 接口实现（`Uri` 形态 —— 域感知必须知道 URL）。
  @override
  void absorbUrl(Uri url, List<String>? setCookie) => absorb(url, setCookie);

  /// 给 [host] 拼 `Cookie` 头：host-only 的同名 Cookie + 所有能匹配它的域级 Cookie。
  ///
  /// 同名时**更具体的域优先**（host-only 覆盖 `.chaoxing.com`），与浏览器一致 ——
  /// 实现上按域长度**升序**合并，长域后写，自然压过短的。
  @override
  String headerFor(String host) {
    final h = _normalizeDomain(host);
    final matched = [
      for (final entry in _byDomain.entries)
        if (_domainMatches(entry.key, h)) entry,
    ]..sort((a, b) => a.key.length.compareTo(b.key.length));
    final out = <String, String>{};
    for (final entry in matched) {
      out.addAll(entry.value);
    }
    if (out.isEmpty) return '';
    return out.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// [host] 下是否带某个 Cookie（判活用，如 `_uid` / `SESSION`）。
  bool has(String host, String name) =>
      headerFor(host).contains(RegExp('(?:^|;\\s*)${RegExp.escape(name)}='));

  /// [host] 下是否带了 [names] 里的**任意一个**（多套身份 Cookie 名并存时用）。
  bool hasAny(String host, Iterable<String> names) =>
      names.any((n) => has(host, n));

  /// 各域下的 Cookie **名字**（诊断用；值永不外泄）。
  Map<String, List<String>> namesOf() => {
    for (final e in _byDomain.entries) e.key: e.value.keys.toList()..sort(),
  };

  /// 罐里一个 Cookie 都没有 = 还没换过证。
  @override
  bool get isEmpty => _byDomain.isEmpty;

  Map<String, dynamic> toJson() => {
    for (final e in _byDomain.entries) e.key: Map<String, String>.from(e.value),
  };

  /// 从缓存恢复（脏数据 / 非 Map 一律跳过，不抛）。
  factory SessionCookieJar.fromJson(Object? json) {
    final jar = SessionCookieJar();
    if (json is! Map) return jar;
    for (final entry in json.entries) {
      final domain = _normalizeDomain(entry.key.toString());
      final value = entry.value;
      if (domain.isEmpty || value is! Map) continue;
      final bucket = jar._byDomain.putIfAbsent(domain, () => <String, String>{});
      for (final kv in value.entries) {
        bucket[kv.key.toString()] = kv.value.toString();
      }
    }
    return jar;
  }

  /// 小写化并去掉前导点：`.chaoxing.com` → `chaoxing.com`。
  static String _normalizeDomain(String domain) {
    var d = domain.trim().toLowerCase();
    while (d.startsWith('.')) {
      d = d.substring(1);
    }
    return d;
  }

  /// Cookie 域 [cookieDomain] 是否覆盖主机 [host]。
  static bool _domainMatches(String cookieDomain, String host) {
    if (host == cookieDomain) return true;
    if (!host.endsWith(cookieDomain)) return false;
    // 必须是**标签边界**上的后缀：`xchaoxing.com` 不能被 `chaoxing.com` 命中。
    return host[host.length - cookieDomain.length - 1] == '.';
  }

  @override
  String toString() {
    final n = namesOf();
    return 'SessionCookieJar(${n.entries.map((e) => '${e.key}:${e.value.length}').join(', ')})';
  }
}

/// 极简 Cookie 罐：**按请求 host 分桶**，不解析 `Domain=` 属性。
///
/// 逐字等价于本仓 7 个站点历史上各自私有的
/// `_store` / `_cookieHeader` / `_cookieNamesOf` 三件套（2026-09-20 收敛）：
/// 谁下发的 Cookie 就只发给谁，同名覆盖，没有过期时间与路径概念 ——
/// **换证链只走一跳之内的场景够用**，跨子域会话请用 [SessionCookieJar]。
class HostCookieJar implements CookieJar {
  HostCookieJar();

  /// host → Cookie 名 → 值。
  final Map<String, Map<String, String>> _byHost = {};

  /// 吸收某 host 响应的 `Set-Cookie`（同名覆盖；值**不做 trim**，与历史逐字一致）。
  void absorb(String host, List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return;
    final map = _byHost.putIfAbsent(host, () => <String, String>{});
    for (final raw in setCookies) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) {
        map[first.substring(0, eq).trim()] = first.substring(eq + 1);
      }
    }
  }

  /// 从 `Response` 里读 `set-cookie` 并吸收（host 取自 [url]）。
  void absorbResponse(String url, Response<dynamic> response) =>
      absorb(Uri.parse(url).host, response.headers['set-cookie']);

  /// [CookieJar] 接口实现（只取 `url.host` —— 本罐本来就不认域属性）。
  @override
  void absorbUrl(Uri url, List<String>? setCookie) =>
      absorb(url.host, setCookie);

  /// 手工写入一个 Cookie。
  ///
  /// 少数平台把身份标识放在**跳转地址**而不是 `Set-Cookie` 里（入馆教育实测：
  /// `success=-2` 的回跳串带 `uid`，服务端却不发同名 Cookie），上层拿到值后
  /// 需要补写进来供后续业务请求携带 —— 这条路径不许改成直接操作内部 Map。
  void set(String host, String name, String value) {
    _byHost.putIfAbsent(host, () => <String, String>{})[name] = value;
  }

  /// 拼 [host] 的 `Cookie` 请求头；没有则空串（调用方按空串跳过该头）。
  @override
  String headerFor(String host) {
    final map = _byHost[host];
    if (map == null || map.isEmpty) return '';
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// [host] 下已收到的 Cookie **名字**列表（诊断用；`(空)` 是历史文案）。
  String namesOf(String host) {
    final map = _byHost[host];
    if (map == null || map.isEmpty) return '(空)';
    return map.keys.join(',');
  }

  /// [host] 下某个 Cookie 的值（不存在 / 空串一律 null，不返回空串）。
  String? valueOf(String host, String name) {
    final value = _byHost[host]?[name];
    return (value == null || value.isEmpty) ? null : value;
  }

  /// [host] 下是否有该 Cookie 且非空。
  bool has(String host, String name) => valueOf(host, name) != null;

  /// 罐里一个 Cookie 都没有 = 还没换过证。
  @override
  bool get isEmpty => _byHost.isEmpty;

  /// 各 host 下的 Cookie **名字**（诊断用；值永不外泄）。
  Map<String, List<String>> allNames() => {
    for (final e in _byHost.entries) e.key: e.value.keys.toList()..sort(),
  };

  Map<String, dynamic> toJson() => {
    for (final e in _byHost.entries) e.key: Map<String, String>.from(e.value),
  };

  @override
  String toString() {
    final n = allNames();
    return 'HostCookieJar(${n.entries.map((e) => '${e.key}:${e.value.length}').join(', ')})';
  }
}
