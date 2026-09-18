/// DOCX（OOXML）最小读取器 —— 只做「从字节流里取表格单元格文本」这一件事。
///
/// 2026-09-18 加：志愿服务时长的**活动时间**原本从每行的「详情」页取
/// （`apply_one_detail.html`），但服务端现在对该页一律返回「出错了」
/// （实测 5/5 条记录、任何 header / type 变体都是同一张 51271 字节错误页），
/// 唯一还能拿到日期的地方是学校导出的
/// **《江西财经大学青年志愿者志愿服务时长认定登记表》Word 原件**
/// （`GET /admin/tzz/StuVolWork/downloadInfo.do`，App 早就能下载它）。
///
/// 不引第三方依赖：docx 就是一个 ZIP，`dart:io` 自带 `ZLibDecoder`，
/// 这里手写「中央目录 → 本地头 → raw deflate」的最小读取路径。
///
/// 只支持 STORE(0) 与 DEFLATE(8) 两种压缩方式（OOXML 只会用这两种），
/// 不支持 ZIP64 与加密 —— 拿不到就返回 null，调用方回退到旧路径。
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// 取出 `word/document.xml` 的文本；不是 docx / 缺该部件 → null。
String? docxDocumentXml(List<int> bytes) {
  final entry = _zipEntry(bytes, 'word/document.xml');
  if (entry == null) return null;
  return utf8.decode(entry, allowMalformed: true);
}

/// 字节 → 「行 → 单元格文本」；不是 docx → 空列表。
List<List<String>> docxTableRowsOfBytes(List<int> bytes) {
  final xml = docxDocumentXml(bytes);
  if (xml == null) return const [];
  return docxTableRows(xml);
}

/// 把正文 XML 切成「行 → 单元格文本」。
///
/// 依据 `</w:tr>` / `</w:tc>` 切分（OOXML 的闭合标签必然出现），
/// 单元格文本 = 该格内全部 `<w:t>` 文本依次拼接（Word 会把一句话拆成多个 run）。
/// `xml:space="preserve"` 的前后空格保留、首尾空白裁掉。
List<List<String>> docxTableRows(String documentXml) {
  final rows = <List<String>>[];
  for (final rowPiece in documentXml.split('</w:tr>')) {
    final pieces = rowPiece.split('</w:tc>');
    // 切分后最后一段是「本行结束到下一行开始」的残留标记，不是单元格。
    final cells = <String>[
      for (var i = 0; i < pieces.length - 1; i++) _cellText(pieces[i]),
    ];
    if (cells.isEmpty) continue;
    if (cells.every((c) => c.isEmpty)) continue;
    rows.add(cells);
  }
  return rows;
}

final RegExp _textRun = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', dotAll: true);

String _cellText(String piece) {
  final buffer = StringBuffer();
  for (final match in _textRun.allMatches(piece)) {
    buffer.write(match.group(1) ?? '');
  }
  return _unescape(buffer.toString()).trim();
}

String _unescape(String raw) {
  if (!raw.contains('&')) return raw;
  return raw.replaceAllMapped(RegExp(r'&(#x?[0-9A-Fa-f]+|[a-z]+);'), (m) {
    final body = m.group(1)!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    if (body.startsWith('#')) {
      final code = int.tryParse(body.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    return switch (body) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      _ => m.group(0)!,
    };
  });
}

/// 读取 ZIP 中央目录里指定名字的条目并解压；找不到 / 不支持 → null。
Uint8List? _zipEntry(List<int> bytes, String name) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final eocd = _findEndOfCentralDirectory(data);
  if (eocd < 0) return null;

  final count = _u16(data, eocd + 10);
  var offset = _u32(data, eocd + 16);
  for (var i = 0; i < count; i++) {
    if (offset + 46 > data.length) return null;
    if (!_hasSignature(data, offset, 0x01, 0x02)) return null;
    final method = _u16(data, offset + 10);
    final compressedSize = _u32(data, offset + 20);
    final nameLength = _u16(data, offset + 28);
    final extraLength = _u16(data, offset + 30);
    final commentLength = _u16(data, offset + 32);
    final localOffset = _u32(data, offset + 42);
    final entryName = utf8.decode(
      data.sublist(offset + 46, offset + 46 + nameLength),
      allowMalformed: true,
    );
    if (entryName == name) {
      return _readLocalEntry(data, localOffset, method, compressedSize);
    }
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return null;
}

Uint8List? _readLocalEntry(
  Uint8List data,
  int localOffset,
  int method,
  int compressedSize,
) {
  if (localOffset + 30 > data.length) return null;
  if (!_hasSignature(data, localOffset, 0x03, 0x04)) return null;
  final nameLength = _u16(data, localOffset + 26);
  final extraLength = _u16(data, localOffset + 28);
  final start = localOffset + 30 + nameLength + extraLength;
  if (start + compressedSize > data.length) return null;
  final raw = Uint8List.sublistView(data, start, start + compressedSize);
  if (method == 0) return Uint8List.fromList(raw);
  if (method != 8) return null;
  try {
    return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
  } catch (_) {
    return null;
  }
}

/// 从尾部往前找 EOCD（`PK\x05\x06`）；注释最长 65535 字节。
int _findEndOfCentralDirectory(Uint8List data) {
  final lowest = data.length - 22 - 65535;
  for (var i = data.length - 22; i >= (lowest < 0 ? 0 : lowest); i--) {
    if (_hasSignature(data, i, 0x05, 0x06)) return i;
  }
  return -1;
}

bool _hasSignature(Uint8List data, int at, int b1, int b2) =>
    at >= 0 &&
    at + 3 < data.length &&
    data[at] == 0x50 && // P
    data[at + 1] == 0x4b && // K
    data[at + 2] == b1 &&
    data[at + 3] == b2;

int _u16(Uint8List data, int at) =>
    at + 1 < data.length ? data[at] | (data[at + 1] << 8) : 0;

int _u32(Uint8List data, int at) => at + 3 < data.length
    ? data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24)
    : 0;
