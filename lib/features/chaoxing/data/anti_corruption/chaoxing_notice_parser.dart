/// 学习通 · 通知解析（收件箱 JSON 与未读数）。
///
/// 实测（2026-09-19）：
/// ```
/// GET https://notice.chaoxing.com/pc/notice/getNoticeList?s=<32 位 hex>
/// → {"status":true,
///    "notices":{"lastPage":0,"lastGetId":"…","list":[{…} × 20]}}
/// GET https://i.chaoxing.com/base/getNoticeCount
/// → {"status":true,"msg":false}          // msg 是**布尔**（有没有新通知）
/// ```
///
/// ⚠ 字段名实测口径：发件人 **`createrName`**（没有 `senderName`）、已读 **`isread`**
/// （小写 r，值为 `1`/`0` 或 `true`/`false`，两种都要认）。
library;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';

/// 从学习空间首页抠收件箱 token（`notice.chaoxing.com/pc/notice/myNotice?s=…`）。
///
/// 登录链最后一跳正好落在这个页面上，所以**不需要额外请求**。
/// 认不出返回 null（调用方据此告知「通知暂不可用」，而不是拿空 token 硬打）。
String? chaoxingNoticeToken(String html) {
  if (html.trim().isEmpty) return null;
  final m = RegExp(
    r'notice\.chaoxing\.com/pc/notice/myNotice\?s=([0-9a-zA-Z]{8,})',
  ).firstMatch(html);
  if (m != null) return m.group(1);
  // 兜底：页内 JS 里的相对写法 `/pc/notice/myNotice?s=…`。
  final m2 = RegExp(r'/pc/notice/myNotice\?s=([0-9a-zA-Z]{8,})').firstMatch(html);
  return m2?.group(1);
}

/// 解析 `getNoticeList` 的响应（已解码的 JSON 对象）→ 通知列表。
///
/// 容错：非 Map / 缺 `notices.list` / 单条不是 Map → 一律跳过，不抛。
/// 顺序 = 服务端给的顺序（实测为倒序，最新在前）。
List<ChaoxingNotice> parseChaoxingNotices(Object? json) {
  final list = _noticeList(json);
  if (list == null) return const [];
  final out = <ChaoxingNotice>[];
  for (final raw in list) {
    if (raw is! Map) continue;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final notice = chaoxingNoticeFromItem(map);
    if (notice.title.isEmpty && notice.content.isEmpty) continue;
    out.add(notice);
  }
  return out;
}

/// 单条通知（`getNoticeList` 里的一项）。
ChaoxingNotice chaoxingNoticeFromItem(Map<String, dynamic> item) {
  final tag = _str(item['tag']);
  final sendTime = _str(item['sendTime']);
  final completeTime = _str(item['completeTime']);
  return ChaoxingNotice(
    id: _str(item['uuid']).isEmpty ? _str(item['idCode']) : _str(item['uuid']),
    title: _str(item['title']),
    content: _str(item['content']),
    sender: _str(item['createrName']),
    sentAt: _date(sendTime) ?? _date(completeTime),
    read: _bool(item['isread']) || item['read'] == true,
    top: _bool(item['top']),
    sourceTag: tag,
    courseId: chaoxingCourseIdFromTag(tag),
  );
}

/// 未读数接口（`/base/getNoticeCount`）的语义：`msg` 为 `true` = 有新通知。
///
/// ⚠ `msg` 是布尔不是数字 —— 实测本账号（有 20 条通知）也是 `false`，
/// 所以它表达的是**红点**（有未看过的新通知），不是「未读条数」。
/// 别把它当计数显示。
bool chaoxingNoticeHasNew(Object? json) {
  if (json is! Map) return false;
  return _bool(json['msg']);
}

/// 通知数组的位置（`{"notices":{"list":[…]}}`）；认不出返回 null。
List<dynamic>? _noticeList(Object? json) {
  if (json is! Map) return null;
  final notices = json['notices'] ?? json['data'] ?? json;
  if (notices is List) return notices;
  if (notices is Map) {
    final list = notices['list'] ?? notices['rows'] ?? notices['records'];
    if (list is List) return list;
  }
  return null;
}

String _str(Object? value) => value == null ? '' : value.toString().trim();

/// `1`/`"1"`/`true`/`"true"` 都算真；判不出算假（宁少报不多报）。
bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final t = value?.toString().trim().toLowerCase() ?? '';
  return t == '1' || t == 'true' || t == 'yes';
}

DateTime? _date(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t) ??
      DateTime.tryParse(t.replaceAll('/', '-')) ??
      DateTime.tryParse(t.split('.').first);
}
