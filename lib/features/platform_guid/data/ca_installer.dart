import 'dart:io';

/// App 自带 MITM 根证书的安装 / 检测（Windows 用户级 Root 证书库）。
///
/// 证书主体固定为「Smarter JXUFE Local CA」（assets/capture_certs/ca.cer，
/// 见 tools/_gen_mitm_certs.py）。安装一次后长期有效；换 CA 需先手动移除旧证书。
class CaInstaller {
  CaInstaller._();

  static const String subject = 'Smarter JXUFE Local CA';

  /// 是否已安装到当前用户的 Root 证书库。
  static Future<bool> isInstalled() async {
    final r = await Process.run('certutil', ['-user', '-store', 'Root']);
    if (r.exitCode != 0) return false;
    return (r.stdout as String).contains(subject);
  }

  /// 安装 [derFile]（DER 编码的 .cer）到当前用户 Root 证书库。
  static Future<bool> install(String derFile) async {
    final r = await Process.run('certutil', [
      '-user',
      '-addstore',
      'Root',
      derFile,
    ]);
    return r.exitCode == 0;
  }
}
