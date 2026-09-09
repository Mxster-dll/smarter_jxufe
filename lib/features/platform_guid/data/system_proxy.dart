import 'dart:io';

/// Windows 用户级系统代理（HKCU Internet Settings）读写。
///
/// 仅影响当前 Windows 用户；改注册表后无需管理员权限，微信等新进程即生效
/// （已在运行的进程不会刷新，需重启——见捕获流程 UI 提示）。
class SystemProxy {
  SystemProxy._();

  static const String _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// 读取当前代理状态（ProxyEnable + ProxyServer 原值）。
  static Future<({bool enabled, String server})> read() async {
    final en = await Process.run(
      'reg',
      ['query', _regPath, '/v', 'ProxyEnable'],
    );
    final sv = await Process.run(
      'reg',
      ['query', _regPath, '/v', 'ProxyServer'],
    );
    var enabled = false;
    if (en.exitCode == 0) {
      final line = (en.stdout as String)
          .split('\n')
          .firstWhere((l) => l.contains('ProxyEnable'), orElse: () => '');
      enabled = line.trim().endsWith('0x1');
    }
    var server = '';
    if (sv.exitCode == 0) {
      final line = (sv.stdout as String)
          .split('\n')
          .firstWhere((l) => l.contains('ProxyServer'), orElse: () => '');
      final idx = line.lastIndexOf('REG_SZ');
      if (idx >= 0) server = line.substring(idx + 6).trim();
    }
    return (enabled: enabled, server: server);
  }

  /// 开启系统代理指向本机代理端口。
  static Future<bool> enable(String host, int port) async {
    final r1 = await Process.run('reg', [
      'add', _regPath, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '$host:$port',
      '/f',
    ]);
    final r2 = await Process.run('reg', [
      'add', _regPath, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f',
    ]);
    return r1.exitCode == 0 && r2.exitCode == 0;
  }

  /// 关闭系统代理（还原 [enabled]/[server] 原状）。
  static Future<void> restore({
    required bool enabled,
    required String server,
  }) async {
    await Process.run('reg', [
      'add', _regPath, '/v', 'ProxyEnable', '/t', 'REG_DWORD',
      '/d', enabled ? '1' : '0', '/f',
    ]);
    if (enabled && server.isNotEmpty) {
      await Process.run('reg', [
        'add', _regPath, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', server,
        '/f',
      ]);
    }
  }
}
