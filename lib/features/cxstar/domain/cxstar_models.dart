/// 畅想之星「经典阅读」平台域模型（m.cxstar.com）。
///
/// 数据口径（逆向实测，见 reverse_engineering/畅想之星接口.md）：
/// - `GET /api/user/readsummary` → 阅读本数 readCount、读完 finishCount、
///   总阅读时长 readMinutes（分钟）、今日 todayReadMinutes（分钟）。
/// - `GET /api/user/readings?page=N` / `GET /api/user/GetReadTJ` → 逐书阅读记录。
/// - 会话：`POST /api/auth/ip_login` 免密（校园网 IP → 全校公用号 `IP用户`），
///   或个人 JWT（学校统一身份认证换取，`Authorization: Bearer <JWT>`）。
library;

/// 畅想之星接口异常（message 直接可展示）。
class CxstarApiException implements Exception {
  final String message;

  const CxstarApiException(this.message);

  @override
  String toString() => message;
}

/// 当前畅想之星会话。
class CxstarSession {
  final String token;

  /// true = 由校园网 IP 免密登录（全校公用账号，非个人）。
  final bool fromIpLogin;

  const CxstarSession({required this.token, this.fromIpLogin = false});
}

/// 页面数据的会话来源（三档，界面必须据此标注）。
enum CxstarSessionSource {
  /// 学校统一身份认证换来的个人会话（按账号持久化，24h）。
  unifiedAuth('统一身份认证', '个人账号 · 你的阅读数据'),

  /// 用户手工粘贴的个人令牌（高级回退）。
  manualToken('手工令牌', '个人账号 · 手工配置的令牌'),

  /// 校园网 IP 免密登录的公用账号（全校聚合）。
  ipShared('校园网公用账号', '校园网公用账号 · 全校聚合数据');

  const CxstarSessionSource(this.label, this.description);

  final String label;
  final String description;

  /// 是否为个人数据（仅 [ipShared] 不是）。
  bool get isPersonal => this != CxstarSessionSource.ipShared;
}

/// 账号信息（`GET /api/user`）。
class CxstarUser {
  final String userId;
  final String userName;
  final String realName;
  final String schoolName;

  /// 机构号（= 阅读器接口的 `pinst`，如江西财经大学 `1cdceffd0000020bce`）。
  final String schoolId;

  const CxstarUser({
    this.userId = '',
    this.userName = '',
    this.realName = '',
    this.schoolName = '',
    this.schoolId = '',
  });

  /// 校园网 IP 免密登录得到的公用账号（数据为全校聚合）。
  bool get isSharedIpAccount =>
      userName.toUpperCase().startsWith('IPUSER') || realName == 'IP用户';

  String get displayName {
    if (realName.isNotEmpty) return realName;
    if (userName.isNotEmpty) return userName;
    return '未知账号';
  }

  factory CxstarUser.fromJson(Map<String, dynamic> json) => CxstarUser(
        userId: '${json['userId'] ?? ''}',
        userName: '${json['userName'] ?? ''}',
        realName: '${json['realName'] ?? ''}',
        schoolName: '${json['schoolName'] ?? ''}',
        schoolId: '${json['schoolId'] ?? ''}',
      );
}

/// 阅读统计（`GET /api/user/readsummary`）。
class CxstarReadSummary {
  /// 阅读本数。
  final int readCount;

  /// 读完本数。
  final int finishCount;
  final int noteCount;
  final int commentCount;

  /// 累计阅读时长（分钟）。
  final int readMinutes;

  /// 今日阅读时长（分钟）。
  final int todayReadMinutes;
  final int level;

  const CxstarReadSummary({
    this.readCount = 0,
    this.finishCount = 0,
    this.noteCount = 0,
    this.commentCount = 0,
    this.readMinutes = 0,
    this.todayReadMinutes = 0,
    this.level = 0,
  });

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  factory CxstarReadSummary.fromJson(Map<String, dynamic> json) =>
      CxstarReadSummary(
        readCount: _int(json['readCount']),
        finishCount: _int(json['finishCount']),
        noteCount: _int(json['noteCount']),
        commentCount: _int(json['commentCount']),
        readMinutes: _int(json['readMinutes']),
        todayReadMinutes: _int(json['todayReadMinutes']),
        level: _int(json['level']),
      );
}

/// 阅读记录条目（`readings` / `GetReadTJ` 的 readData 元素）。
class CxstarReadRecord {
  final String id;
  final String bookId;
  final String title;
  final String author;
  final String cover;
  final String publisher;

  /// 服务端原文，形如 `2026/9/11 20:47:51`。
  final String readingTime;
  final bool ifReadFinish;

  const CxstarReadRecord({
    this.id = '',
    this.bookId = '',
    this.title = '',
    this.author = '',
    this.cover = '',
    this.publisher = '',
    this.readingTime = '',
    this.ifReadFinish = false,
  });

  factory CxstarReadRecord.fromJson(Map<String, dynamic> json) =>
      CxstarReadRecord(
        id: '${json['id'] ?? ''}',
        bookId: '${json['bookId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        author: '${json['author'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        publisher: '${json['publisher'] ?? ''}',
        readingTime: '${json['readingTime'] ?? ''}',
        ifReadFinish: json['ifReadFinish'] == true,
      );
}

/// 页面聚合数据：账号 + 统计 + 记录。
class CxstarOverview {
  final CxstarUser user;
  final CxstarReadSummary summary;
  final List<CxstarReadRecord> records;

  /// 本次数据来自哪一档会话。
  final CxstarSessionSource source;

  /// 降级说明（个人会话不可用时为何回退），非空时界面展示。
  final String? fallbackNote;

  const CxstarOverview({
    required this.user,
    required this.summary,
    required this.records,
    required this.source,
    this.fallbackNote,
  });

  /// true = 个人数据（统一认证或手工令牌）；false = 校园网公用账号。
  bool get personal => source.isPersonal;
}

/// 分钟 → 「X 小时 Y 分」/「Y 分」。
String cxstarDurationText(int minutes) {
  if (minutes <= 0) return '0 分';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h <= 0) return '$m 分';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分';
}

/// 分钟 → 小时（一位小数，用于紧凑展示）。
String cxstarHoursText(int minutes) {
  if (minutes <= 0) return '0';
  final hours = minutes / 60;
  if (hours >= 100) return hours.toStringAsFixed(0);
  return hours.toStringAsFixed(1);
}
