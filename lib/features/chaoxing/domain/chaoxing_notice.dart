/// 学习通（超星）通知 —— 收件箱里的一条。
///
/// 来源（**JSON，最干净的一条**）：
/// ```
/// GET https://notice.chaoxing.com/pc/notice/getNoticeList?s=<32 位 hex token>
/// → {"status":true,"notices":{"lastPage":0,"lastGetId":"…","list":[ {…} × 20 ]}}
/// ```
/// `s` token 从学习空间首页 `https://i.chaoxing.com/base` 页内正则取
/// （`notice.chaoxing.com/pc/notice/myNotice?s=…`）—— 登录链最后一跳正好落在这个页面，
/// 因此**不需要额外请求**。
///
/// ⚠ 字段名实测口径（别照抄 App 端的猜测名）：
/// 发件人是 **`createrName`**（没有 `senderName`），已读是 **`isread`**（小写 r）。
library;

/// 一条通知。
class ChaoxingNotice {
  const ChaoxingNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.sender,
    this.sentAt,
    this.read = false,
    this.top = false,
    this.sourceTag = '',
    this.courseId = '',
  });

  /// 稳定键：`uuid`（形如 `$CACG$d12d509b-…`），缺失时回落 `idCode`。
  final String id;

  /// 标题（如 `261学前测通知及注意事项`）。
  final String title;

  /// 正文纯文本（含 `\r`，显示前自行收拢空白）。
  final String content;

  /// 发件人显示名（`createrName`）。
  final String sender;

  /// 发送时刻（优先 `sendTime`，回落 `completeTime`）。
  final DateTime? sentAt;

  /// 已读（`isread == 1`）。
  final bool read;

  /// 置顶（`top == 1`）。
  final bool top;

  /// 归属标签（`tag`，课程通知形如 `courseId266659194`）。
  final String sourceTag;

  /// 从 [sourceTag] 解析出的课程 id；认不出为空串（非课程类通知很多）。
  final String courseId;

  /// 详情路径（收件箱里点击跳转的那个）；[id] 为空时返回空串。
  ///
  /// ⚠ App 侧**不直接可用**：它依赖学习通会话 Cookie，只能作为「在网页端查看」的
  /// 提示文本，不要当成可点链接。
  String get detailPath => id.isEmpty ? '' : '/pc/notice/$id/detail';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'sender': sender,
    'sentAt': sentAt?.toIso8601String(),
    'read': read,
    'top': top,
    'sourceTag': sourceTag,
    'courseId': courseId,
  };

  /// 容错解析。⚠ 不要写 `as bool?` / `as String?`：脏数据会抛类型异常。
  factory ChaoxingNotice.fromJson(Map<String, dynamic> json) => ChaoxingNotice(
    id: _str(json['id']),
    title: _str(json['title']),
    content: _str(json['content']),
    sender: _str(json['sender']),
    sentAt: _date(json['sentAt']),
    read: json['read'] == true,
    top: json['top'] == true,
    sourceTag: _str(json['sourceTag']),
    courseId: _str(json['courseId']),
  );

  static String _str(Object? value) => value == null ? '' : value.toString().trim();

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  String toString() => 'ChaoxingNotice($id, $title, read=$read, at=$sentAt)';
}

/// 从 `tag`（`courseId266659194`）里抠课程 id；认不出返回空串。
String chaoxingCourseIdFromTag(String tag) {
  final m = RegExp(r'courseId\s*(\d{4,})').firstMatch(tag);
  return m?.group(1) ?? '';
}
