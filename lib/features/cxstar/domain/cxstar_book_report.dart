/// 单本书的阅读报告（`GET /api/books/{bookId}/readreport`）。
///
/// 逆向实测（2026-09-15，个人会话，见 reverse_engineering/畅想之星接口.md §11）：
/// 该接口返回**逐书**统计，是阅读记录里唯一能给出「读完时间」的地方：
/// ```json
/// {"code":"0","text":"","data":{
///   "userId":"…","userName":"…","pinstRuid":"1cdceffd0000020bce",
///   "bookRuid":"…","title":"…","cover":"…",
///   "startReadTime":"2026年09月14日","endReadTime":"2026年09月15日",
///   "readMinutes":"53","readDays":"2","readNo":"14",
///   "finishReadTime":null,"finishReadNo":null,
///   "longestTime":"52","longestDate":"2026年09月14日",
///   "noteCount":"0","noteDate":null,"isFinish":false}}
/// ```
///
/// ⚠ 精度口径：平台只给**分钟**（`readMinutes`），**没有秒级字段**
/// （`/api/books/{id}/readtime`、`/api/user/readtime/{id}` 均 404）。学分平台
/// （jhread）明细里的「总阅读时长(秒)」是另一套数据，此处取不到。
/// ⚠ `finishReadTime` 仅**已读完**的书有值（`readings` 的 `ifReadFinish`
/// 实测恒为 null/false，不能用来判断读完 —— 本报告才是权威）。
library;

/// 单本书阅读报告。
class CxstarBookReport {
  final String bookId;
  final String title;

  /// 首次阅读日期，服务端原文形如 `2026年09月14日`。
  final String startReadTime;

  /// 最近一次阅读日期。
  final String endReadTime;

  /// 读完日期；未读完为空串。
  final String finishReadTime;

  /// 累计阅读时长（分钟）。
  final int readMinutes;

  /// 累计阅读天数。
  final int readDays;

  /// 累计阅读次数。
  final int readNo;

  /// 读完时是第几次阅读（未读完为 0）。
  final int finishReadNo;

  /// 单次最长阅读时长（分钟）与其日期。
  final int longestMinutes;
  final String longestDate;

  final int noteCount;

  /// 服务端标记的「已读完」。
  final bool isFinish;

  const CxstarBookReport({
    this.bookId = '',
    this.title = '',
    this.startReadTime = '',
    this.endReadTime = '',
    this.finishReadTime = '',
    this.readMinutes = 0,
    this.readDays = 0,
    this.readNo = 0,
    this.finishReadNo = 0,
    this.longestMinutes = 0,
    this.longestDate = '',
    this.noteCount = 0,
    this.isFinish = false,
  });

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  factory CxstarBookReport.fromJson(Map<String, dynamic> json) =>
      CxstarBookReport(
        bookId: _str(json['bookRuid'] ?? json['bookId']),
        title: _str(json['title']),
        startReadTime: _str(json['startReadTime']),
        endReadTime: _str(json['endReadTime']),
        finishReadTime: _str(json['finishReadTime']),
        readMinutes: _int(json['readMinutes']),
        readDays: _int(json['readDays']),
        readNo: _int(json['readNo']),
        finishReadNo: _int(json['finishReadNo']),
        longestMinutes: _int(json['longestTime']),
        longestDate: _str(json['longestDate']),
        noteCount: _int(json['noteCount']),
        isFinish: json['isFinish'] == true,
      );

  /// 是否已读完（`isFinish` 或存在读完日期）。
  bool get finished => isFinish || finishReadTime.isNotEmpty;

  /// 「完成于 2026年09月09日」；未读完为 null。
  String? get finishText =>
      finishReadTime.isEmpty ? null : '完成于 $finishReadTime';

  /// 「阅读 2 天 · 14 次」（阅读天数为 0 时省略）。
  String get activityText {
    final parts = <String>[
      if (readDays > 0) '阅读 $readDays 天',
      if (readNo > 0) '$readNo 次',
    ];
    return parts.join(' · ');
  }
}
