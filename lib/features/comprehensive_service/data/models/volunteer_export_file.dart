import 'dart:convert';
import 'dart:typed_data';

/// 学校平台「学生活动时长统计」页导出的
/// **志愿服务时长认定登记表**（Word 原件）。
///
/// 来源：`GET /admin/tzz/StuVolWork/downloadInfo.do`（ssp.jxufe.edu.cn，
/// 需携带 `Cookie: JSESSIONID=...`），响应体为 OOXML（.doc/.docx）字节流，
/// 文件名由 `Content-Disposition` 给出。
///
/// 说明：学校页面上的这个按钮实际下发的是 Word，**没有 PDF 接口**；
/// App 侧只做「原样搬运 + 调起系统分享」，不改动文件内容。
class VolunteerExportFile {
  /// 文件原始字节（未做任何转换）。
  final Uint8List bytes;

  /// 文件名（已从 `Content-Disposition` 解析并做安全清洗）。
  final String fileName;

  /// MIME 类型，默认按 Word 处理。
  final String mimeType;

  const VolunteerExportFile({
    required this.bytes,
    required this.fileName,
    this.mimeType = kVolunteerExportMimeType,
  });

  int get sizeInBytes => bytes.length;

  @override
  String toString() =>
      'VolunteerExportFile($fileName, $sizeInBytes bytes, $mimeType)';
}

/// 未解析到文件名时的兜底名。
const String kVolunteerExportFallbackName = '志愿服务时长认定登记表.doc';

/// Word 文档 MIME（服务器返回的是 OOXML，用 msword 兼容面更广）。
const String kVolunteerExportMimeType = 'application/msword';

/// 从 `Content-Disposition` 解析文件名。
///
/// 依次尝试：
/// 1. RFC 5987 的 `filename*=UTF-8''%E9%99%88...`（百分号编码）；
/// 2. 普通 `filename="..."` / `filename=...`；
/// 3. 都拿不到 → [fallback]。
///
/// ⚠️ 关键：Dart 的 HttpClient 把响应头按 **latin1** 解码，而服务器发的是
/// UTF-8 字节（实测 `filename=某同学青年志愿者志愿服务时长认定登记表.doc`），
/// 直接使用会得到 `éçä»éå¹´...` 这样的乱码。因此这里在结果不含中文时
/// 反向做一次 `latin1.encode → utf8.decode` 还原。
String volunteerExportFileName(
  String? contentDisposition, {
  String fallback = kVolunteerExportFallbackName,
}) {
  final header = contentDisposition?.trim() ?? '';
  if (header.isEmpty) return fallback;

  String? raw;

  // 1) filename*=UTF-8''<pct-encoded>（可能带 charset/lang）
  final extended = RegExp(
    r"filename\*\s*=\s*([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (extended != null) {
    var value = extended.group(1)!.trim();
    // 形如 `UTF-8''<pct>` 或 `UTF-8'zh'<pct>`：取第二个单引号之后的部分
    final parts = value.split("'");
    if (parts.length >= 3) value = parts.sublist(2).join("'");
    value = value.replaceAll(RegExp(r'^"|"$'), '').trim();
    if (value.isNotEmpty) {
      try {
        raw = Uri.decodeComponent(value);
      } catch (_) {
        raw = value;
      }
    }
  }

  // 2) filename="..." / filename=...
  raw ??= () {
    final plain = RegExp(
      r'filename\s*=\s*("([^"]*)"|([^;]*))',
      caseSensitive: false,
    ).firstMatch(header);
    if (plain == null) return null;
    final value = (plain.group(2) ?? plain.group(3) ?? '').trim();
    return value.isEmpty ? null : value;
  }();

  if (raw == null || raw.isEmpty) return fallback;

  final name = _sanitizeExportFileName(_reviveUtf8Mojibake(raw));
  return name.isEmpty ? fallback : name;
}

/// 把 latin1 误解码出来的 UTF-8 字节还原成正确字符串。
///
/// 已经含中文（说明解码正确）时原样返回；反之尝试反向还原，
/// 还原失败（非法 UTF-8 序列）也原样返回。
String _reviveUtf8Mojibake(String value) {
  if (value.isEmpty) return value;
  if (RegExp(r'[\u2e80-\u9fff\u3000-\u303f\uff00-\uffef]').hasMatch(value)) {
    return value;
  }
  try {
    final bytes = latin1.encode(value);
    final decoded = utf8.decode(bytes);
    return decoded.isEmpty ? value : decoded;
  } catch (_) {
    return value;
  }
}

/// 清洗文件名：只取最后一段路径、去掉控制字符与非法字符、限制长度。
String _sanitizeExportFileName(String raw) {
  var name = raw.trim();

  // 丢掉路径部分，避免 `../../evil.doc` 这类穿越
  name = name.split(RegExp(r'[/\\]')).last.trim();

  // 控制字符与 Windows/Android 都不接受的文件名字符
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
  name = name.replaceAll(RegExp(r'[:*?"<>|]'), '_');

  // 开头的点（隐藏文件 / `..`）
  name = name.replaceFirst(RegExp(r'^\.+'), '').trim();

  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    final ext = (dot > 0 && name.length - dot <= 10) ? name.substring(dot) : '';
    name = name.substring(0, 120 - ext.length) + ext;
  }
  return name;
}
