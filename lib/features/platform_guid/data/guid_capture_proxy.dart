import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 纯 Dart HTTPS 中间人代理（零外部依赖）。
///
/// 用途：捕获微信小程序「智慧江财」与 wxcourse.jxufe.* 通信时请求里携带的
/// 平台用户标识（platformUsername=GUID），供 App 内「获取平台标识」使用。
///
/// 工作原理（利用 dart:io 自带的 SecureServerSocket，无需 mitmproxy）：
///  1. 本地起普通 HTTP 代理端口，接收客户端的 `CONNECT host:443`；
///  2. 命中目标域（wxcourse.jxufe.edu.cn / wxcourse.jxufe.cn）时：
///     a. 以客户端身份连接真实服务器（SecureSocket.connect，验证真证书）；
///     b. 本地另开一个回环 SecureServerSocket（bind loopback:0），把微信
///        连接上来的字节泵进该回环端口 —— 微信的 TLS ClientHello 因此被
///        我们自签证书（构造时注入的 [tlsContext]）服务端握手；
///     c. accept 得到解密后的明文连接，与真实服务器连接双向转发，并在
///        转发字节流中扫描 platformUsername=GUID；
///  3. 其余域名直接 TCP 隧道透传（不解密）。
///
/// 实现约束：dart 的 Socket 是单订阅流 —— 每个连接只 listen 一次，头部
/// （CONNECT 请求）解析与后续数据转发在同一个监听里完成。
class GuidCaptureProxy {
  GuidCaptureProxy({
    required SecurityContext tlsContext,
    this.listenPort = 8899,
    Set<String>? targetHosts,
  })  : _tlsContext = tlsContext,
        _targetHosts = targetHosts ?? defaultTargetHosts;

  static const Set<String> defaultTargetHosts = {
    'wxcourse.jxufe.edu.cn',
    'wxcourse.jxufe.cn',
  };

  final SecurityContext _tlsContext;
  final int listenPort;
  final Set<String> _targetHosts;

  ServerSocket? _server;
  final Set<Socket> _live = <Socket>{};
  bool _captured = false;
  bool _stopping = false;

  /// 捕获到 platformUsername（GUID）时回调一次。
  GuidCapturedCallback? onGuid;

  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    _captured = false;
    _stopping = false;
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      listenPort,
    );
    _server!.listen(_onConn, onError: (_) {});
  }

  Future<void> stop() async {
    _stopping = true;
    final srv = _server;
    _server = null;
    try {
      await srv?.close();
    } catch (_) {}
    for (final s in List<Socket>.of(_live)) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _live.clear();
  }

  // ------------------------------------------------------------------
  // 连接处理（单订阅）
  // ------------------------------------------------------------------

  bool _isTarget(String host) {
    final h = host.toLowerCase();
    if (_targetHosts.contains(h)) return true;
    return _targetHosts.any(
      (t) => t.startsWith('*.') && h.endsWith(t.substring(1)),
    );
  }

  Future<void> _onConn(Socket client) async {
    _live.add(client);
    final headBytes = <int>[];
    var headParsed = false;
    final outbox = <List<int>>[];
    bool sinkSet = false;
    void Function(List<int>)? sink;

    // 把数据转发到已建立的目标（目标就绪前排入 outbox）。
    void send(List<int> data) {
      if (sinkSet) {
        try {
          sink!(data);
        } catch (_) {}
      } else {
        outbox.add(data);
      }
    }

    client.listen(
      (data) {
        if (!headParsed) {
          headBytes.addAll(data);
          final text = latin1.decode(headBytes, allowInvalid: true);
          if (_hasHeaderEnd(text)) {
            headParsed = true;
            _handleConnect(client, text, send, (s) {
              sink = s;
              sinkSet = true;
              for (final o in outbox) {
                try {
                  s(o);
                } catch (_) {}
              }
              outbox.clear();
            });
          }
        } else {
          send(data);
        }
      },
      onDone: () => client.destroy(),
      onError: (_) => client.destroy(),
      cancelOnError: true,
    );
  }

  bool _hasHeaderEnd(String text) => text.contains('\r\n\r\n');

  /// 解析 CONNECT 并按其目标分派（tunnel / MITM）。
  void _handleConnect(
    Socket client,
    String headText,
    void Function(List<int>) send,
    void Function(void Function(List<int>)) establish,
  ) {
    final lines = const LineSplitter().convert(headText);
    final first = lines.isEmpty ? '' : lines.first;
    final parts = first.split(' ');
    if (parts.length < 3 || parts[0].toUpperCase() != 'CONNECT') {
      client.destroy();
      return;
    }
    final authority = parts[1];
    final colon = authority.lastIndexOf(':');
    final host = colon > 0 ? authority.substring(0, colon) : authority;
    final port =
        colon > 0 ? int.tryParse(authority.substring(colon + 1)) ?? 443 : 443;

    if (_isTarget(host)) {
      unawaited(_mitm(client, host, port, send, establish));
    } else {
      unawaited(_tunnel(client, host, port, establish));
    }
  }

  // ------------------------------------------------------------------
  // 非目标域：纯隧道透传
  // ------------------------------------------------------------------

  Future<void> _tunnel(
    Socket client,
    String host,
    int port,
    void Function(void Function(List<int>)) establish,
  ) async {
    Socket up;
    try {
      up = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
    } catch (_) {
      client.destroy();
      return;
    }
    _live.add(up);
    client.write('HTTP/1.1 200 Connection established\r\n\r\n');
    establish((d) => up.add(d));
    up.listen(
      (d) => client.add(d),
      onDone: () => client.destroy(),
      onError: (_) => client.destroy(),
      cancelOnError: true,
    );
  }

  // ------------------------------------------------------------------
  // 目标域：MITM
  // ------------------------------------------------------------------

  Future<void> _mitm(
    Socket client,
    String host,
    int port,
    void Function(List<int>) send,
    void Function(void Function(List<int>)) establish,
  ) async {
    SecureSocket up;
    try {
      up = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 12),
      );
    } catch (_) {
      client.destroy();
      return;
    }
    _live.add(up);

    // 回环 TLS 前端：接收转发来的 ClientHello 并完成服务端握手。
    SecureServerSocket sslServer;
    Socket loop;
    try {
      sslServer = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        _tlsContext,
      );
      loop = await Socket.connect(
        InternetAddress.loopbackIPv4,
        sslServer.port,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      up.destroy();
      client.destroy();
      return;
    }
    _live.add(loop);
    // 回环 TLS 前端的握手/密文回复送回客户端。
    loop.listen(
      (d) => client.add(d),
      onDone: () => client.destroy(),
      onError: (_) => client.destroy(),
      cancelOnError: true,
    );
    // 客户端后续字节（TLS 密文）→ 回环 TLS 前端。
    establish((d) => loop.add(d));

    // 管道就绪后再放行客户端开始 TLS 握手。
    client.write('HTTP/1.1 200 Connection established\r\n\r\n');

    SecureSocket down;
    try {
      down = await sslServer.first.timeout(const Duration(seconds: 20));
    } catch (_) {
      unawaited(sslServer.close());
      up.destroy();
      client.destroy();
      loop.destroy();
      _live.remove(loop);
      return;
    }
    unawaited(sslServer.close());
    _live.remove(loop);
    _live.add(down);

    // 明文应用层：down(微信侧解密) <-> up(真实服务器)，下行扫描。
    final scanBuf = BytesBuilder(copy: false);
    down.listen(
      (data) {
        if (_stopping) return;
        if (!_captured) {
          scanBuf.add(data);
          _scan(scanBuf);
        }
        up.add(data);
      },
      onDone: () => up.destroy(),
      onError: (_) => up.destroy(),
      cancelOnError: true,
    );
    up.listen(
      (data) {
        if (_stopping) return;
        try {
          down.add(data);
        } catch (_) {}
      },
      onDone: () => down.destroy(),
      onError: (_) => down.destroy(),
      cancelOnError: true,
    );
  }

  // ------------------------------------------------------------------
  // 扫描
  // ------------------------------------------------------------------

  static final RegExp _guidRe = RegExp(
    r'platformUsername=([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
  );

  /// 在累积字节中扫描 platformUsername=GUID；命中触发 [onGuid]。
  void _scan(BytesBuilder buf) {
    var bytes = buf.toBytes();
    if (bytes.length > 65536) {
      final keep = bytes.sublist(bytes.length - 16384);
      buf.clear();
      buf.add(keep);
      bytes = keep;
    }
    final text = latin1.decode(bytes, allowInvalid: true);
    final m = _guidRe.firstMatch(text);
    if (m == null) return;
    _captured = true;
    final guid = m.group(1)!;
    onGuid?.call(guid);
  }
}

/// 捕获回调。
typedef GuidCapturedCallback = void Function(String guid);
