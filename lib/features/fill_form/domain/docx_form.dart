/// 「填表助手」的门面：**导入 docx → 扫描待填项 → 导出填好的 docx**。
///
/// 用法：
/// ```dart
/// final form = DocxForm.fromBytes(bytes);          // 不是 .docx → null
/// for (final f in form!.scan.fields) { … }          // 给用户逐项确认/编辑
/// final out = form.export({'t0.r0.c1': '张三', …}); // 导出新 docx
/// ```
///
/// ⚠ [export] **不修改本对象**：它每次从原始字节重新解包、重新解析、重新扫描，
/// 再按 [DocxField.id] 对位写值。所以同一份 `DocxForm` 可以导出任意多次，
/// 每次都是「从干净的模板开始填」，不会叠加。
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'docx_apply.dart';
import 'docx_dom.dart';
import 'docx_fields.dart';
import 'docx_package.dart';
import 'docx_scan.dart';

/// 一份已导入的 docx 表单。
class DocxForm {
  DocxForm._(this._bytes, this.scan, this.title, this.paragraphCount);

  final Uint8List _bytes;

  /// 扫描结果（待填项 + 清单表）。
  final DocxScan scan;

  /// 文档标题（正文里第一段非空文字），给 UI 显示。
  final String title;

  /// 正文段落数（UI 用来给一句「共 N 段 / M 表」的概览）。
  final int paragraphCount;

  /// 导入。**不是 .docx（含旧版 .doc）→ null**。
  static DocxForm? fromBytes(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final pkg = DocxPackage.fromBytes(data);
    if (pkg == null) return null;
    final raw = pkg.readUtf8(kDocxDocumentPart);
    if (raw == null) return null;
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(raw);
    } catch (_) {
      return null;
    }
    final scan = docxScan(doc);
    return DocxForm._(data, scan, _titleOf(doc), _countParagraphs(doc));
  }

  /// 导出：把 [values]（field id → 文本）写进一份**新**文档，返回 docx 字节。
  ///
  /// 返回值给不出（包坏了）时返回 null。
  Uint8List? export(Map<String, String> values) {
    final pkg = DocxPackage.fromBytes(_bytes);
    if (pkg == null) return null;
    final raw = pkg.readUtf8(kDocxDocumentPart);
    if (raw == null) return null;
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(raw);
    } catch (_) {
      return null;
    }
    // 重新扫描一遍再写：id 是**位置**派生的，同一份字节重扫必然得到同一批 id；
    // 这一步同时保证了「写的是新解析出来的元素」。
    final fresh = docxScan(doc);
    final ids = {for (final f in fresh.fields) f.id};
    final remapped = <String, String>{
      for (final e in values.entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    docxApplyValues(fresh, remapped);
    pkg.writeUtf8(kDocxDocumentPart, doc.toXmlString());
    return pkg.toBytes();
  }

  /// 导出后建议的文件名（`XXX.docx` → `XXX_已填写.docx`）。
  String suggestedFileName(String originalName) {
    var base = originalName.trim();
    if (base.toLowerCase().endsWith('.docx')) {
      base = base.substring(0, base.length - 5);
    }
    if (base.isEmpty) base = '表单';
    return '${base}_已填写.docx';
  }
}

String _titleOf(XmlDocument doc) {
  final candidates = <String>[];
  for (final root in doc.childElements) {
    final body = childW(root, 'body');
    if (body == null) continue;
    for (final p in childrenW(body, 'p')) {
      final t = paragraphText(p).trim();
      if (t.isNotEmpty) candidates.add(t);
      if (candidates.length >= 5) break;
    }
  }
  if (candidates.isEmpty) return '';
  // 第一段常常只是「表1：」这种编号 —— 优先取够长的那个。
  for (final c in candidates) {
    if (c.length >= 6) return c.length > 40 ? c.substring(0, 40) : c;
  }
  final first = candidates.first;
  return first.length > 40 ? first.substring(0, 40) : first;
}

int _countParagraphs(XmlDocument doc) {
  var n = 0;
  for (final root in doc.childElements) {
    final body = childW(root, 'body');
    if (body == null) continue;
    for (final p in childrenW(body, 'p')) {
      if (paragraphText(p).trim().isNotEmpty) n++;
    }
  }
  return n;
}
