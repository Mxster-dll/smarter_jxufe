import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 设备画像仓库。
///
/// 提供与智慧江财统一认证（CAS / MFA）交互时需要的「设备指纹」。
/// 服务端以 fpVisitorId 区分可信设备：同一次 detect 命中已信任的
/// fpVisitorId 即可放行免二次验证，因此该值必须**同一台设备稳定**、
/// **不同设备互不相同**，否则「信任此设备」会串号或失效。
class DeviceProfileRepository {
  const DeviceProfileRepository();

  String get userAgent =>
      // "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36";
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0";

  /// 确定性设备指纹：由本机稳定属性排序序列化后取 SHA-256 前 32 位十六进制。
  ///
  /// 生成规则（与浏览器指纹思路一致）：
  /// 1. 收集一组跨重启稳定、跨设备有区分度的属性；
  /// 2. 按键名排序后 JSON 序列化（消除字段顺序抖动）；
  /// 3. SHA-256 摘要取前 32 个十六进制字符作为 fpVisitorId。
  ///
  /// 不引入随机盐、不做持久化缓存 —— 纯函数保证同一设备每次计算
  /// 结果一致（免 MFA 信任长期有效）；OS 升级 / 换机时指纹自然变化，
  /// 等价于浏览器指纹的失效语义，届时重新勾选信任即可。
  String get fpVisitorId {
    try {
      final components = <String, String>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'processors': '${Platform.numberOfProcessors}',
        'host': Platform.localHostname.toLowerCase(),
      };
      final keys = components.keys.toList()..sort();
      final buffer = StringBuffer();
      for (final k in keys) {
        buffer.write(k);
        buffer.write('=');
        buffer.write(components[k]);
        buffer.write('&');
      }
      final digest = sha256.convert(utf8.encode(buffer.toString()));
      return digest.toString().substring(0, 32);
    } catch (_) {
      // 极端环境（属性读取失败）下退化为稳定占位，避免每次生成不同值。
      return 'fpc000000000000000000000000000001';
    }
  }
}
