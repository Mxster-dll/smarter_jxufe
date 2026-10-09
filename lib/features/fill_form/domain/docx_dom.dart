/// WordprocessingML（`word/document.xml`）的**低层读写口径**。
///
/// 只做三件事，全部按 `w:` 命名空间精确匹配（**不看前缀**，只看 namespace URI）：
/// 找子元素、读段落纯文本、把一段文本写回段落。
///
/// ⚠ 为什么写回要「塌成一个 run」：Word 会把一句话按拼写检查/格式切成任意多个
/// `<w:r>`（实测「学年加权」+「平均成绩」就是两个 run），逐 run 替换必然错位。
/// 表单格里的文字格式是齐的（同一格同一字体），所以**保留第一个 run 的 `rPr`、
/// 其余 run 删除**是安全且唯一可行的写法。
///
/// ⚠ **新建元素一律用 `XmlName.fromString('w:xxx')`（只有前缀），不要传 namespaceUri**：
/// `package:xml` 在序列化时给「带 namespaceUri 的名字」写出来的是
/// `<http://schemas…:w:t>`（实测），Word/python-docx 直接报
/// `Failed to parse QName 'http:'`。只带前缀时它会老老实实写 `w:t`，
/// 而根元素上本来就声明了 `xmlns:w`。
library;

import 'package:xml/xml.dart';

/// WordprocessingML 主命名空间。
const String kWordNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// 该元素是不是 `w:<local>`。
bool isW(XmlElement e, String local) =>
    e.name.local == local && e.name.namespaceUri == kWordNs;

/// 直接子元素里第一个 `w:<local>`。
XmlElement? childW(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (isW(c, local)) return c;
  }
  return null;
}

/// 直接子元素里全部 `w:<local>`。
Iterable<XmlElement> childrenW(XmlElement e, String local) =>
    e.childElements.where((c) => isW(c, local));

/// `w:<local>` 属性值（没有 → 空串）。属性在 OOXML 里一律带 `w:` 前缀。
String attrW(XmlElement e, String local) =>
    e.getAttribute(local, namespace: kWordNs) ?? '';

/// 段落纯文本：拼全部 `<w:t>`，`<w:tab>` 记制表符、`<w:br>/<w:cr>` 记换行。
///
/// - **不跨嵌套段落**（`w:txbxContent` 里的文本框段落自带 `<w:p>`，不是本段的文字）；
/// - 跳过 `w:instrText`（域代码，不是给人看的文字）。
String paragraphText(XmlElement p) {
  final buf = StringBuffer();
  void walk(XmlNode node) {
    for (final c in node.children) {
      if (c is! XmlElement) continue;
      if (isW(c, 'p') || isW(c, 'instrText')) continue;
      if (isW(c, 't')) {
        buf.write(c.innerText);
        continue;
      }
      if (isW(c, 'tab')) {
        buf.write('\t');
        continue;
      }
      if (isW(c, 'br') || isW(c, 'cr')) {
        buf.write('\n');
        continue;
      }
      walk(c);
    }
  }

  walk(p);
  return buf.toString();
}

/// 单元格纯文本：全部段落用换行拼接（**与 python-docx 看到的 `cell.text` 同口径**）。
String cellText(XmlElement tc) {
  final parts = <String>[];
  for (final p in childrenW(tc, 'p')) {
    parts.add(paragraphText(p));
  }
  return parts.join('\n');
}

/// 段落里第一个 `w:r/w:rPr` 的克隆（写新文本时继承字体字号）。
///
/// 找不到 run 时退回 `w:pPr/w:rPr`（**段落标记的字符格式** —— Word 里这就是
/// 「这一段默认长什么样」，空格的 `<w:pPr>` 里正好带着我们要的字体）。
XmlElement? paragraphRunProps(XmlElement p) {
  for (final r in childrenW(p, 'r')) {
    final rPr = childW(r, 'rPr');
    if (rPr != null) return rPr.copy();
  }
  final pPr = childW(p, 'pPr');
  final rPr = pPr == null ? null : childW(pPr, 'rPr');
  return rPr?.copy();
}

/// 造一个 `<w:r>`：`rPr`（可空）+ 若干 `<w:t xml:space="preserve">`。
///
/// 文本里的 `\n` 会变成 `<w:br/>` —— Word 的 `<w:t>` **不认换行符**，
/// 直接塞 `\n` 会渲染成一个空格（多行材料清单全靠这条）。
XmlElement buildRun(String text, {XmlElement? rPr}) {
  final kids = <XmlNode>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) kids.add(XmlElement(XmlName.fromString('w:br')));
    kids.add(
      XmlElement(XmlName.fromString('w:t'), [
        XmlAttribute(XmlName.fromString('xml:space'), 'preserve'),
      ], [
        XmlText(lines[i]),
      ]),
    );
  }
  final r = XmlElement(XmlName.fromString('w:r'), const [], kids);
  if (rPr != null) r.children.insert(0, rPr.copy());
  return r;
}

/// 把 [fresh] 插到 [node] 后面（`package:xml` 没有 insertAfter，只有 children.insert）。
void insertAfterNode(XmlNode node, XmlNode fresh) {
  final parent = node.parent;
  if (parent == null) return;
  final kids = parent.children;
  final at = kids.indexOf(node);
  if (at < 0 || at == kids.length - 1) {
    kids.add(fresh);
  } else {
    kids.insert(at + 1, fresh);
  }
}

/// 取段落里第一个**直接子** `w:r`（不含超链接里的）。
XmlElement? firstRun(XmlElement p) {
  for (final c in p.childElements) {
    if (isW(c, 'r')) return c;
  }
  return null;
}

/// 把段落文本**整体替换**成 [text]：
/// 保留第一个 run 的字符格式，其余 run 删除（见文件头口径）。
///
/// 段落里本来一个 run 都没有时，按 [fallbackRPr] / 段落自身 `pPr/rPr` 新建一个；
/// 插入位置 = `pPr` 之后（`pPr` 必须是第一个子元素，否则 Word 打不开）。
void setParagraphText(XmlElement p, String text, {XmlElement? fallbackRPr}) {
  final runs = [for (final c in p.childElements) if (isW(c, 'r')) c];
  final rPr = runs.isNotEmpty
      ? paragraphRunProps(p) ?? fallbackRPr?.copy()
      : fallbackRPr?.copy() ?? paragraphRunProps(p);
  for (final r in runs) {
    r.remove();
  }
  final run = buildRun(text, rPr: rPr);
  final pPr = childW(p, 'pPr');
  if (pPr != null) {
    insertAfterNode(pPr, run);
  } else {
    p.children.insert(0, run);
  }
}

/// 在段落**末尾追加**一段文字（用于「标签：」后面填值，保留标签原文）。
void appendParagraphText(XmlElement p, String text, {XmlElement? fallbackRPr}) {
  final rPr = paragraphRunProps(p) ?? fallbackRPr?.copy();
  p.children.add(buildRun(text, rPr: rPr));
}

/// 造一个空的 `w:p`（克隆模版的 `pPr`，这样新段落与邻居同字体同缩进）。
XmlElement buildParagraph({XmlElement? template}) {
  final p = XmlElement(XmlName.fromString('w:p'));
  final pPr = template == null ? null : childW(template, 'pPr');
  if (pPr != null) p.children.add(pPr.copy());
  return p;
}

/// 段落是否「空」（只有空白 / 全角空格）。
bool isBlankParagraph(XmlElement p) => paragraphText(p).trim().isEmpty;
