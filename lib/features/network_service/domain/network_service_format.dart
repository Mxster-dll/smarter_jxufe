/// 网络服务的纯格式化工具（无 Flutter 依赖，便于单测）。
///
/// 服务端各字段单位不统一（时长有分钟与秒、流量有 MB 与字节、时间有毫秒与文本），
/// 展示层一律走这里，避免各页面各写一套换算。
library;

/// 流量（MB）→ 可读文本：≥1024 MB 用 GB。
String networkFormatFlow(double mb) {
  if (mb <= 0) return '0 MB';
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${_trimNum(mb)} MB';
}

/// 时长（分钟）→ 「X 天 Y 小时 Z 分」（服务端用量口径为分钟）。
String networkFormatMinutes(int minutes) {
  if (minutes <= 0) return '0 分钟';
  final days = minutes ~/ (60 * 24);
  final hours = (minutes % (60 * 24)) ~/ 60;
  final mins = minutes % 60;
  final parts = <String>[
    if (days > 0) '$days 天',
    if (hours > 0) '$hours 小时',
    if (mins > 0 && days == 0) '$mins 分',
  ];
  return parts.isEmpty ? '0 分钟' : parts.join(' ');
}

/// 时长（秒，在线会话口径）→ 可读文本。
String networkFormatSeconds(int seconds) => networkFormatMinutes(seconds ~/ 60);

/// 字节 → MB / GB（在线会话的上/下行流量是字节字符串）。
String networkFormatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  return networkFormatFlow(bytes / (1024 * 1024));
}

String _trimNum(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// `yyyy-MM-dd`（null → 空串）。
String networkFormatDate(DateTime? date) {
  if (date == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// `yyyy-MM-dd HH:mm`。
String networkFormatDateTime(DateTime? date) {
  if (date == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${networkFormatDate(date)} ${two(date.hour)}:${two(date.minute)}';
}

/// `yyyy-MM-dd HH:mm:ss`（明细用）。
String networkFormatDateTimeFull(DateTime? date) {
  if (date == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${networkFormatDateTime(date)}:${two(date.second)}';
}

/// 密码掩码（与「我的邮箱」同款：等长星号）。
String networkMaskPassword(String password) =>
    password.isEmpty ? '' : '*' * password.length;

/// MAC 加连字符（`24B2B9A1B1C5` → `24-B2-B9-A1-B1-C5`）；已带分隔符则原样返回。
String networkFormatMac(String mac) {
  final raw = mac.trim();
  if (raw.isEmpty || raw.contains('-') || raw.contains(':')) return raw;
  if (raw.length != 12) return raw;
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i += 2) {
    if (i > 0) buffer.write('-');
    buffer.write(raw.substring(i, i + 2));
  }
  return buffer.toString();
}
