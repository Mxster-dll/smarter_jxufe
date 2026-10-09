/// .docx 的**唯一读写口径**：docx 就是一个 zip 包，本文件负责解包与重打包。
///
/// 用户 2026-10-07：「允许用户上传一个 docx 文档，然后自动识别有哪些项需要填，
/// 然后把能填的都填了……用户可以在自动填完后，再手动调整各部分文本」。
///
/// 口径（改动前先读）：
/// - **只认 `word/document.xml`**：正文（含表格、文本框）都在这里；页眉页脚
///   （`word/header*.xml` / `footer*.xml`）与批注等部件**原样保留但不解析**。
/// - 除 `word/document.xml` 外的**每一个条目都逐字节原样回写**（样式 / 编号 /
///   图片 / rels / `[Content_Types].xml` 都不动），否则 Word 会判定文档损坏。
/// - 解包失败（不是 zip、缺 `[Content_Types].xml`、缺 `word/document.xml`）一律
///   返回 null，由上层给用户一句「这看起来不是 .docx」。旧版 `.doc`（OLE 复合文档）
///   不是 zip，一定走这条路。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// docx 包内的正文部件名。
const String kDocxDocumentPart = 'word/document.xml';

/// `[Content_Types].xml` —— OPC 包的必要件，用它挡掉「随便一个 zip」。
const String kDocxContentTypesPart = '[Content_Types].xml';

/// 一个 .docx 包（条目名 → 字节，保序）。
class DocxPackage {
  DocxPackage._(this._names, this._bytes);

  /// 保序的条目名。
  final List<String> _names;
  final Map<String, Uint8List> _bytes;

  /// 解包失败返回 null（不是 zip / 不是 OPC 包 / 没有正文）。
  static DocxPackage? fromBytes(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final names = <String>[];
    final map = <String, Uint8List>{};
    for (final file in archive) {
      final name = file.name;
      // 目录条目不存内容（zip 里它们的 content 为空）。
      if (name.endsWith('/')) {
        names.add(name);
        map[name] = Uint8List(0);
        continue;
      }
      Uint8List data;
      try {
        data = file.content;
      } catch (_) {
        // 单个条目坏掉不该让整份文档不可用：留空字节，Word 侧通常仍能打开。
        data = Uint8List(0);
      }
      names.add(name);
      map[name] = data;
    }
    if (!map.containsKey(kDocxContentTypesPart)) return null;
    if (!map.containsKey(kDocxDocumentPart)) return null;
    return DocxPackage._(names, map);
  }

  /// 全部条目名（保序）。
  List<String> get entryNames => List.unmodifiable(_names);

  bool contains(String name) => _bytes.containsKey(name);

  /// 原始字节（没有该条目 → null）。
  Uint8List? read(String name) => _bytes[name];

  /// 覆盖/新增一个条目。
  void write(String name, List<int> data) {
    if (!_bytes.containsKey(name)) _names.add(name);
    _bytes[name] = data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// 按 UTF-8 读文本条目（没有该条目 → null）。
  String? readUtf8(String name) {
    final data = _bytes[name];
    if (data == null) return null;
    return utf8.decode(data, allowMalformed: true);
  }

  void writeUtf8(String name, String text) => write(name, utf8.encode(text));

  /// 重打包成 zip 字节。
  ///
  /// ⚠ 用 `CompressionType.deflate` 逐条重压；**空条目（目录）不压**，
  /// 否则部分解压器会拒。
  Uint8List toBytes() {
    final archive = Archive();
    for (final name in _names) {
      final data = _bytes[name] ?? Uint8List(0);
      if (name.endsWith('/')) {
        archive.add(ArchiveFile.directory(name));
        continue;
      }
      final file = ArchiveFile.bytes(name, data);
      file.compression = CompressionType.deflate;
      archive.add(file);
    }
    return ZipEncoder().encodeBytes(archive);
  }
}
