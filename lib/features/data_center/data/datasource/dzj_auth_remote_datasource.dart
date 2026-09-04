import 'package:dio/dio.dart';

/// 竹简数据中台一次会话的凭证。
///
/// [session] 为服务端签发的 SESSION cookie 值；
/// [fixedSalt] 为随会话下发的 AES 密钥派生盐（Base64 编码 16 字节）。
class DzjSession {
  final String session;
  final String fixedSalt;

  const DzjSession({required this.session, required this.fixedSalt});

  Map<String, String> get cookieHeader => {
    'SESSION': session,
    'fixedSalt': fixedSalt,
    'enableTransEncrypt': 'true',
    'isLoggedIn': 'true',
    'loginType': 'CAS',
  };
}

/// 竹简数据中台会话已失效（需重新走统一认证换取）。
class DzjSessionExpiredException implements Exception {
  final String message;
  DzjSessionExpiredException([this.message = '个人数据中心会话已过期']);

  @override
  String toString() => 'DzjSessionExpiredException: $message';
}

/// 竹简数据中台会话建立远程数据源。
///
/// 统一认证链：TGC → CAS service 入口 302 → 带 ticket 的 dzj 回调地址
/// （由 [AuthRepository.getServiceRedirectUrl] 完成）→ 访问 ticket 地址，
/// dzj 服务端 302 回无 ticket 应用地址并下发会话 Cookie
/// （SESSION / fixedSalt / enableTransEncrypt / isLoggedIn / loginType）。
class DzjAuthRemoteDataSource {
  final Dio _dio;

  DzjAuthRemoteDataSource(this._dio);

  /// 携带 [ticketUrl]（含 `?ticket=ST-...`）访问数据中台，
  /// 完成一次会话建立，返回服务端下发的 [DzjSession]。
  Future<DzjSession> establishSession(String ticketUrl) async {
    final response = await _dio.get(
      ticketUrl,
      options: Options(
        headers: {
          'Host': 'dzj.jxufe.edu.cn',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
              ' (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36'
              ' Edg/150.0.0.0',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,'
              'image/avif,image/webp,*/*;q=0.8',
          'Referer':
              'https://ssl.jxufe.edu.cn/cas/login?service='
              'https%3A%2F%2Fdzj.jxufe.edu.cn%2Fapp%2F66eef481a9a3',
        },
        followRedirects: false,
      ),
    );

    final status = response.statusCode ?? 0;

    // 服务端应 302 回无 ticket 的应用地址，同时 Set-Cookie 会话凭证
    if (status >= 300 && status < 400) {
      final session = _extractSetCookie(response.headers);
      if (session != null) return session;

      // 有 Location 但没给齐会话 cookie：继续跟随一次，看下一跳是否补发
      final location = response.headers.value('location');
      if (location != null) {
        final follow = await _dio.get(
          location,
          options: Options(
            headers: {
              'Host': 'dzj.jxufe.edu.cn',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
                  ' AppleWebKit/537.36 (KHTML, like Gecko)'
                  ' Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0',
            },
            followRedirects: false,
          ),
        );
        final second = _extractSetCookie(follow.headers);
        if (second != null) return second;
      }
    }

    throw DzjSessionExpiredException('建立个人数据中心会话失败（status=$status）');
  }

  /// 从响应 Set-Cookie 头中提取 [DzjSession]。
  ///
  /// dzj 可能在同一响应中下发多条 Set-Cookie（SESSION / fixedSalt /
  /// enableTransEncrypt / isLoggedIn / loginType）。dio 将多条 cookie
  /// 以 List 提供（也可能合并进单串），统一拼合后按名称正则扫描取值。
  DzjSession? _extractSetCookie(Headers headers) {
    final values = headers['set-cookie'];
    if (values == null) return null;

    final all = values.join('\n');
    final re = RegExp(r'(SESSION|fixedSalt)=([^;\n]+)');
    String? session;
    String? fixedSalt;
    for (final m in re.allMatches(all)) {
      if (m.group(1) == 'SESSION') session = m.group(2)?.trim();
      if (m.group(1) == 'fixedSalt') fixedSalt = m.group(2)?.trim();
    }

    if (session == null ||
        session.isEmpty ||
        fixedSalt == null ||
        fixedSalt.isEmpty) {
      return null;
    }
    return DzjSession(session: session, fixedSalt: fixedSalt);
  }
}
