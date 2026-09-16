/// 畅想之星阅读器域模型与纯函数（签名 / 单页口令）。
///
/// 逆向结论（2026-09-14 实测，见 reverse_engineering/畅想之星接口.md §7）：
/// - 阅读器接口全部要 `nonce/stime/sign` 三参数，签名算法来自
///   `p.cxstar.com/readerv2/static/js/main.b5875c38.js`：
///   `sign = md5('123456' + nonce + stime).toUpperCase()`（密钥 `123456` 硬编码）；
///   缺三参数恒 404（IIS 404 页）。
/// - 每页正文是**独立的单页 AES-128 加密 PDF**，用户口令 =
///   `md5('<bookId>-<pageno>')`（小写 hex，逐页不同）——已用 pikepdf/qpdf
///   与 pypdf 两套实现验证 p1/p49/p60/p100 四页均可解密。
/// - 阅读时长由**服务端**按在线阅读行为累计（取内容/翻页都会计入），
///   客户端不上报时长；会话内定期轻量请求即可持续入账（60s 心跳实测有效）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// 签名密钥（前端硬编码，逆向所得；原样为 base64 `MTIzNDU2`）。
const String cxstarSignSecret = '123456';

/// 江西财经大学在畅想之星的机构号（`pinst`），`/api/user` 的 `schoolId` 同值。
const String cxstarJxufePinst = '1cdceffd0000020bce';

/// 一次签名的三参数。
class CxstarReaderSign {
  final String nonce;
  final int stime;
  final String sign;

  const CxstarReaderSign({
    required this.nonce,
    required this.stime,
    required this.sign,
  });

  Map<String, String> toQuery() => {
    'nonce': nonce,
    'stime': '$stime',
    'sign': sign,
  };
}

/// 生成签名：`md5('123456' + nonce + stime).toUpperCase()`。
///
/// [nonce] / [stimeSeconds] 仅测试注入用；默认随机 UUID v4 与当前秒级时间戳。
CxstarReaderSign cxstarReaderSign({String? nonce, int? stimeSeconds}) {
  final n = nonce ?? const Uuid().v4();
  final t = stimeSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final digest = md5.convert(utf8.encode('$cxstarSignSecret$n$t'));
  return CxstarReaderSign(
    nonce: n,
    stime: t,
    sign: digest.toString().toUpperCase(),
  );
}

/// 单页 PDF 的用户口令：`md5('<bookId>-<pageno>')`（小写 hex）。
String cxstarPdfPassword(String bookId, int pageNo) =>
    md5.convert(utf8.encode('$bookId-$pageNo')).toString();

/// 阅读会话（`GET /api/books/{id}/read`）。
class CxstarReadSession {
  final String title;

  /// 本次请求的页码（服务端回显）。
  final int page;
  final int paragraph;
  final int totalPage;

  /// 试读页数（≤ 该页免登录可读，超出的页会带页级 token）。
  final int trialPage;

  /// 本次阅读记录 id（进度上报会带上）。
  final String logId;

  /// 平台水印文案（服务端下发，如「江西财经大学」）。
  final String watermark;
  final bool isbuy;
  final bool isBorrowMode;

  const CxstarReadSession({
    this.title = '',
    this.page = 1,
    this.paragraph = 0,
    this.totalPage = 0,
    this.trialPage = 0,
    this.logId = '',
    this.watermark = '',
    this.isbuy = false,
    this.isBorrowMode = false,
  });

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  factory CxstarReadSession.fromJson(Map<String, dynamic> json) =>
      CxstarReadSession(
        title: '${json['title'] ?? ''}',
        page: _int(json['page']),
        paragraph: _int(json['paragraph']),
        totalPage: _int(json['totalPage']),
        trialPage: _int(json['trialPage']),
        logId: '${json['logId'] ?? ''}',
        watermark: '${json['watermark'] ?? ''}',
        isbuy: json['isbuy'] == true,
        isBorrowMode: json['isBorrowMode'] == true,
      );
}

/// 目录条目（`GET /api/books/{id}/catalog?filetype=0`）。
class CxstarCatalogNode {
  final String title;

  /// 目录页码（服务端给的定位页码，用于跳转）。
  final int page;
  final List<CxstarCatalogNode> children;

  const CxstarCatalogNode({
    this.title = '',
    this.page = 0,
    this.children = const [],
  });

  factory CxstarCatalogNode.fromJson(Map<String, dynamic> json) =>
      CxstarCatalogNode(
        title: '${json['title'] ?? ''}',
        page: CxstarReadSession._int(json['page']),
        children: [
          for (final c in (json['children'] as List?) ?? const [])
            if (c is Map) CxstarCatalogNode.fromJson(c.cast<String, dynamic>()),
        ],
      );

  /// 目录里可跳转的条目（页码 > 0 且标题非空）。
  bool get jumpable => page > 0 && title.trim().isNotEmpty;
}

/// 阅读器取数所需的会话上下文（个人令牌 + 机构号）。
class CxstarReaderContext {
  final String token;
  final String pinst;

  const CxstarReaderContext({required this.token, required this.pinst});
}
