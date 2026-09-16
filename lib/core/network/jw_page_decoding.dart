/// 教务（强智）页面解码口径 —— 一处实现，公共查询 / 选课 / 课表 共用。
///
/// **实测事实（2026-09-14，见 `reverse_engineering/公共查询接口.md` §编码）**：
/// - **正文页**（选课结果 `wsxk.zxjg.jsp`、公共查询报表、`taglib/DataTable.jsp` 列表）
///   是 **GBK**，且响应头**不带 charset**；
/// - 但**会话失效页是 UTF-8**：547 字节的
///   `<script>alert('温馨提示：凭证已失效，请重新登录!');…`。
///
/// 坑：`fast_gbk` 对任意字节都能解出结果（UTF-8 的中文会解成
/// `娓╅Θ鎻愮ず` 这类乱码），所以「先按 GBK 解、再用 `contains('凭证已失效')` 判失效」
/// 的写法**永远判不出失效** —— 页面会静默退化成「空结果」，
/// 界面显示「没有已选课程 / 没有检索到记录」，把会话过期伪装成没数据。
library;

import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

/// 教务会话失效的判据（547 字节 alert 页的文案）。
bool jwSessionExpired(String body) =>
    body.contains('凭证已失效') || body.contains('请重新登录');

/// 按教务真实编码解一页 HTML（先严格试 UTF-8 认失效页，其余一律 GBK）。
///
/// 顺序不能反：GBK 对 UTF-8 字节不报错，先 GBK 就再也认不出失效页。
String decodeJwPage(List<int> bytes) {
  if (bytes.isEmpty) return '';
  try {
    final utf8Text = utf8.decode(bytes);
    if (jwSessionExpired(utf8Text)) return utf8Text;
  } catch (_) {
    // 正常 GBK 正文页在这里抛（字节不是合法 UTF-8）→ 走下面的 GBK。
  }
  try {
    return gbk.decode(bytes);
  } catch (_) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
