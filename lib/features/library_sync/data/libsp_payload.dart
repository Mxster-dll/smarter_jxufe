/// 图书馆订阅词云同步 · 载荷白名单与精简降级链（纯函数，不碰 Hive / 网络 / 时钟）。
///
/// 两层职责：
/// 1. **白名单**：哪些本机数据进载荷（见 [kLibspSyncedPrefBoxes] 与 [kLibspExcludedBoxes]）。
///    偏好一律按「box → key → 原样值」整箱搬运，**不解析语义** —— 于是新增一项偏好
///    只要落在这些 box 里就自动跟随同步，不需要改这里（口径见方案 §四载荷白名单）。
/// 2. **精简降级链**（Q15）：撞到容量天花板时按**固定优先级**裁剪，并把裁剪事实写进
///    [LibspTrimReport]，让设置页能如实告诉用户「哪几项没上去」。
///    **绝不静默丢** —— 这是 Q2「明示」的直接推论，也是服务端「超长静默截断」教给我们的。
library;

import 'dart:convert';
import 'dart:io';

/// 载荷编码版本（进载荷，供未来换编码方案时识别）。
const int kLibspPayloadVersion = 1;

/// 偏好白名单：整箱逐键搬运。
///
/// ⚠ `electricityBinding` 是**按 Q7-B 的决定进来的**（含宿舍房间号），而 `wxPlatform`、
/// `homeWidget` 那类设备标识仍被排除 —— 明示文案必须逐项列出「宿舍房间号」。
const List<String> kLibspSyncedPrefBoxes = <String>[
  'themePrefs', // 外观（深色模式）
  'myCampusPrefs', // 我的校区
  'homePrefs', // 主页布局
  'schoolCalendarPrefs', // 校历三个开关
  'tsgxsPrefs', // 入馆教育答题模式
  'electricityBinding', // 电费绑定（校区 + 房间号）
];

/// 明确**不**同步的 box（写下来是为了让守卫测试能守住「没有偷偷加进来」）。
///
/// 三类：会话令牌（换机本就该失效）、设备标识（跨设备共用是错的）、可重取缓存（传了白传）。
const List<String> kLibspExcludedBoxes = <String>[
  'imsAuth', 'auth', 'account', 'sspAuth', 'dzjAuth', 'cxstar', 'readCredit',
  'wxPlatform', 'homeWidget', 'tsgxs', //
  'gradesCache', 'scheduleCache', 'curriculums', 'studentInfo', //
  'colleges', 'majors', 'periodTable', 'scheduleReschedules',
];

/// 订阅词总量预算（保守值）。
///
/// **实测（2026-09-16，真账号 …2513）**：连续写入 120 条订阅词**全部成功**、服务端
/// 一条不拒（写到 120 主动停，未试探更高），故真实上限 **≥120**。这里取 90 ——
/// 留 30 条余量给「用户自己在图书馆里加的订阅词」（探针账号原本就是 0 条，
/// 真实用户可能有自己的词，预算必须让得开）。
const int kLibspDefaultWordBudget = 90;

/// 信封字节预算 = 预算条数 ÷ 槽位 × 每片字节（默认 90÷3×139 = 4170）。
const int kLibspDefaultMaxEnvelopeBytes =
    (kLibspDefaultWordBudget ~/ 3) * 139;

/// 裁剪了哪些内容（进载荷，恢复时能如实告知）。
class LibspTrimReport {
  const LibspTrimReport({
    this.droppedCourseNotes = 0,
    this.droppedDeadlines = 0,
    this.droppedCourses = 0,
    this.droppedZongce = false,
    this.droppedAllCourses = false,
  });

  /// 被清空的课程备注 / 分项备注条数。
  final int droppedCourseNotes;

  /// 被裁掉的截止日期条数。
  final int droppedDeadlines;

  /// 被丢掉的课程门数（按创建时间从旧到新丢）。
  final int droppedCourses;

  /// 是否整块丢了综测数据。
  final bool droppedZongce;

  /// 是否连分数估计整体都没能装下。
  final bool droppedAllCourses;

  /// 是否有任何裁剪。
  bool get isEmpty =>
      droppedCourseNotes == 0 &&
      droppedDeadlines == 0 &&
      droppedCourses == 0 &&
      !droppedZongce &&
      !droppedAllCourses;

  /// 给界面用的一句话（空表示没裁剪）。
  String get summary {
    if (isEmpty) return '';
    final parts = <String>[
      if (droppedAllCourses) '分数估计整体',
      if (droppedCourses > 0) '$droppedCourses 门课程',
      if (droppedDeadlines > 0) '$droppedDeadlines 条截止日期',
      if (droppedCourseNotes > 0) '$droppedCourseNotes 条备注',
      if (droppedZongce) '综测填写项',
    ];
    return '已精简：${parts.join('、')} 未同步';
  }

  Map<String, dynamic> toJson() => {
    'notes': droppedCourseNotes,
    'deadlines': droppedDeadlines,
    'courses': droppedCourses,
    'zc': droppedZongce,
    'all': droppedAllCourses,
  };

  static LibspTrimReport fromJson(Object? raw) {
    if (raw is! Map) return const LibspTrimReport();
    int intOf(Object? v) => v is num ? v.toInt() : 0;
    bool boolOf(Object? v) => v == true;
    return LibspTrimReport(
      droppedCourseNotes: intOf(raw['notes']),
      droppedDeadlines: intOf(raw['deadlines']),
      droppedCourses: intOf(raw['courses']),
      droppedZongce: boolOf(raw['zc']),
      droppedAllCourses: boolOf(raw['all']),
    );
  }

  @override
  String toString() => 'LibspTrimReport($summary)';
}

/// 一份待上传的快照（结构化；编码与分片由 codec 负责）。
class LibspSnapshot {
  const LibspSnapshot({
    required this.generatedAt,
    required this.account,
    required this.prefs,
    required this.courses,
    required this.zongce,
    this.trim = const LibspTrimReport(),
    this.version = kLibspPayloadVersion,
  });

  /// 生成时刻（epoch ms）—— 三组之间比新旧就看它。
  final int generatedAt;

  /// 生成者账号（学号）。
  final String account;

  /// 偏好：box → key → 原样值。
  final Map<String, Map<String, String>> prefs;

  /// 分数估计课程（已剥 id / createdAt / memo，见 [sanitizeGeCourse]）。
  final List<Map<String, dynamic>> courses;

  /// 综测：key → 原样 JSON 值（`materials` / `manual-<year>`）。
  final Map<String, String> zongce;

  /// 裁剪事实。
  final LibspTrimReport trim;

  /// 载荷编码版本。
  final int version;

  /// 课程门数（界面摘要用）。
  int get courseCount => courses.length;

  /// 偏好项数（界面摘要用）。
  int get prefEntryCount =>
      prefs.values.fold(0, (sum, box) => sum + box.length);

  Map<String, dynamic> toJson() => {
    'v': version,
    'gen': generatedAt,
    'acc': account,
    'trim': trim.toJson(),
    'prefs': prefs,
    'ge': courses,
    'zc': zongce,
  };

  /// 从载荷 JSON 还原；结构不对 → `null`（绝不抛，损坏的云端数据不能崩 App）。
  static LibspSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final prefs = <String, Map<String, String>>{};
    final rawPrefs = raw['prefs'];
    if (rawPrefs is Map) {
      for (final boxEntry in rawPrefs.entries) {
        final box = boxEntry.key.toString();
        final value = boxEntry.value;
        if (value is! Map) continue;
        final entries = <String, String>{};
        for (final e in value.entries) {
          final v = e.value;
          if (v is String) entries[e.key.toString()] = v;
        }
        prefs[box] = entries;
      }
    }
    final courses = <Map<String, dynamic>>[];
    final rawCourses = raw['ge'];
    if (rawCourses is List) {
      for (final c in rawCourses) {
        if (c is Map) courses.add(Map<String, dynamic>.from(c));
      }
    }
    final zongce = <String, String>{};
    final rawZc = raw['zc'];
    if (rawZc is Map) {
      for (final e in rawZc.entries) {
        final v = e.value;
        if (v is String) zongce[e.key.toString()] = v;
      }
    }
    final gen = raw['gen'];
    final ver = raw['v'];
    return LibspSnapshot(
      generatedAt: gen is num ? gen.toInt() : 0,
      account: raw['acc']?.toString() ?? '',
      prefs: prefs,
      courses: courses,
      zongce: zongce,
      trim: LibspTrimReport.fromJson(raw['trim']),
      version: ver is num ? ver.toInt() : kLibspPayloadVersion,
    );
  }
}

// ─────────────────────────── 分数估计的剥离与认领 ───────────────────────────

/// 把 `GeCourse.toJson()` 的形态剥成**可跨设备**的载荷形态：
///
/// - `id` / `createdAt` / `memo` 一律剔除：uuid 只在本地用（跨设备同课必然不同 id，
///   见 Q6），备忘录文字按 Q7-B 不上云、图片文件名换机后是坏引用；
/// - `parts[].id` / `deadlines[].id` 同理剔除（它们只用于本地编辑与通知排期）；
/// - [dropNotes] 为真时连 `note` 一起清空（降级链第 1 档）。
Map<String, dynamic> sanitizeGeCourse(
  Map<String, dynamic> raw, {
  bool dropNotes = false,
  int? maxDeadlines,
}) {
  final out = <String, dynamic>{
    'name': raw['name'],
    'courseCode': raw['courseCode'] ?? '',
    'dailyPercent': raw['dailyPercent'],
    'credits': raw['credits'] ?? 1,
    'finalScore': raw['finalScore'],
    'note': dropNotes ? '' : (raw['note'] ?? ''),
  };
  final parts = <Map<String, dynamic>>[];
  for (final p in (raw['parts'] as List?) ?? const []) {
    if (p is! Map) continue;
    parts.add({
      'name': p['name'],
      'mode': p['mode'],
      'target': p['target'],
      'current': p['current'] ?? 0,
      'score': p['score'] ?? 0,
      'cap': p['cap'] ?? 0,
      'note': dropNotes ? '' : (p['note'] ?? ''),
    });
  }
  out['parts'] = parts;

  var deadlines = <Map<String, dynamic>>[];
  for (final d in (raw['deadlines'] as List?) ?? const []) {
    if (d is! Map) continue;
    deadlines.add({
      'title': d['title'],
      'kind': d['kind'],
      'dueAt': d['dueAt'],
      'repeat': d['repeat'],
      'note': dropNotes ? '' : (d['note'] ?? ''),
      'doneAt': d['doneAt'],
      'remind': d['remind'],
    });
  }
  if (maxDeadlines != null && deadlines.length > maxDeadlines) {
    deadlines.sort((a, b) {
      final x = (a['dueAt'] as num?)?.toInt() ?? 0;
      final y = (b['dueAt'] as num?)?.toInt() ?? 0;
      return x.compareTo(y);
    });
    deadlines = deadlines.sublist(0, maxDeadlines);
  }
  out['deadlines'] = deadlines;
  return out;
}

/// 把载荷里的课程「认领」回本机：补上新的 id / createdAt / 空备忘录。
///
/// [newId] 注入是为了可测（生产传 `const Uuid().v4`）。
Map<String, dynamic> adoptGeCourse(
  Map<String, dynamic> payload, {
  required String Function() newId,
  required int createdAt,
}) {
  final out = <String, dynamic>{
    'id': newId(),
    'name': payload['name'] ?? '',
    'courseCode': payload['courseCode'] ?? '',
    'dailyPercent': payload['dailyPercent'] ?? 30,
    'credits': payload['credits'] ?? 1,
    'finalScore': payload['finalScore'],
    'note': payload['note'] ?? '',
  };
  out['parts'] = [
    for (final p in (payload['parts'] as List?) ?? const [])
      if (p is Map)
        {
          'id': newId(),
          'name': p['name'] ?? '',
          'mode': p['mode'] ?? 'up',
          'target': p['target'] ?? 1,
          'current': p['current'] ?? 0,
          'score': p['score'] ?? 0,
          'cap': p['cap'] ?? 0,
          'note': p['note'] ?? '',
        },
  ];
  out['deadlines'] = [
    for (final d in (payload['deadlines'] as List?) ?? const [])
      if (d is Map)
        {
          'id': newId(),
          'title': d['title'] ?? '',
          'kind': d['kind'] ?? 'other',
          'dueAt': d['dueAt'] ?? 0,
          'repeat': d['repeat'] ?? 'none',
          'note': d['note'] ?? '',
          'doneAt': d['doneAt'],
          'remind': d['remind'] ?? true,
        },
  ];
  // 备忘录不进载荷（Q7-B）：恢复出空备忘录，避免留下指向不存在图片的坏引用。
  out['memo'] = {'text': '', 'images': <dynamic>[]};
  out['createdAt'] = createdAt;
  return out;
}

// ─────────────────────────── 压缩与信封 ───────────────────────────

/// gzip（level 9）。与 `libsp_codec.dart` 的分层关系：本函数只出「gzip 字节」，
/// 信封（长度前缀）与分片在 codec 里。
List<int> libspGzip(List<int> data) => GZipCodec(level: 9).encode(data);

/// gunzip；损坏 / 非 gzip → `null`。
List<int>? libspGunzip(List<int> data) {
  try {
    return GZipCodec().decode(data);
  } catch (_) {
    return null;
  }
}

/// 载荷 JSON → gzip 字节（UTF-8）。
List<int> encodeLibspSnapshotBytes(LibspSnapshot snapshot) =>
    libspGzip(utf8.encode(jsonEncode(snapshot.toJson())));

/// gzip 字节 → 快照；任何一步失败 → `null`。
LibspSnapshot? decodeLibspSnapshotBytes(List<int> gzipBytes) {
  final plain = libspGunzip(gzipBytes);
  if (plain == null) return null;
  try {
    return LibspSnapshot.fromJson(jsonDecode(utf8.decode(plain)));
  } catch (_) {
    return null;
  }
}

// ─────────────────────────── 降级链 ───────────────────────────

/// 一次构建的结果：够不够装、装了什么、丢过什么。
class LibspBuildResult {
  const LibspBuildResult({
    required this.snapshot,
    required this.envelopeBytes,
    required this.bytes,
  });

  final LibspSnapshot snapshot;

  /// 信封字节数（= 4 + gzip 长度），不含分片填充。
  final int envelopeBytes;

  /// gzip 字节。
  final List<int> bytes;
}

/// 按「先用完整的、装不下就按固定优先级裁」构建载荷。
///
/// 降级顺序（**固定，不随机、不静默**）：
/// 1. 课程/分项/截止日期的备注文字
/// 2. 截止日期只留最近的 [deadlineKeep]
/// 3. 丢掉最旧的课程，只留 [courseKeepRatio] 比例
/// 4. 整块丢掉综测
/// 5. 再砍课程比例
/// 6. 连分数估计整体丢掉（至少把纯偏好送上去）
///
/// **课程顺序 = 本机原序**（2026-09-17 实测修正）：早先实现按 `createdAt` 新在前
/// 重排后再输出，恢复时用户的课程列表被**整体倒过来**（真机端到端跑出 10 门全反序）。
/// 现在「新在前」只用来决定**装不下时先丢谁**，输出仍按 [rawCourses] 的原序 ——
/// 跨设备搬运不该顺手改用户看到的排列。
///
/// 抛 [StateError] 当连纯偏好都装不下（此时应由调用方按「同步失败」处理，
/// 而不是把一份空快照传上去覆盖云端）。
LibspBuildResult buildLibspSnapshot({
  required int generatedAt,
  required String account,
  required Map<String, Map<String, String>> prefs,
  required List<Map<String, dynamic>> rawCourses,
  required Map<String, String> zongce,
  int maxEnvelopeBytes = kLibspDefaultMaxEnvelopeBytes,
  int deadlineKeep = 20,
  double courseKeepRatio = 0.7,
}) {
  // 「新的在前」的**下标**次序：只用于裁剪决策（丢尾部 = 丢最旧的）。
  final byNewest = List<int>.generate(rawCourses.length, (i) => i)
    ..sort((a, b) {
      final x = (rawCourses[a]['createdAt'] as num?)?.toInt() ?? 0;
      final y = (rawCourses[b]['createdAt'] as num?)?.toInt() ?? 0;
      return y.compareTo(x);
    });
  final total = rawCourses.length;

  var droppedNotes = 0;
  var droppedDeadlines = 0;
  var droppedCourses = 0;
  var droppedZongce = false;

  LibspBuildResult attempt({
    required bool dropNotes,
    required int? maxDeadlines,
    required double ratio,
    required bool dropZongce,
    required bool dropAllCourses,
  }) {
    final keep = dropAllCourses
        ? 0
        : (total * ratio).floor().clamp(1.clamp(0, total), total);
    final keptIndices = {for (final i in byNewest.take(keep)) i};
    // 输出按本机原序（见方法文档）。
    final courses = [
      for (var i = 0; i < total; i++)
        if (keptIndices.contains(i))
          sanitizeGeCourse(rawCourses[i], dropNotes: dropNotes, maxDeadlines: maxDeadlines),
    ];
    final snapshot = LibspSnapshot(
      generatedAt: generatedAt,
      account: account,
      prefs: prefs,
      courses: courses,
      zongce: dropZongce ? const {} : zongce,
      trim: LibspTrimReport(
        droppedCourseNotes: droppedNotes,
        droppedDeadlines: droppedDeadlines,
        droppedCourses: droppedCourses,
        droppedZongce: droppedZongce,
        droppedAllCourses: dropAllCourses,
      ),
    );
    final bytes = encodeLibspSnapshotBytes(snapshot);
    return LibspBuildResult(
      snapshot: snapshot,
      envelopeBytes: bytes.length + 4,
      bytes: bytes,
    );
  }

  // 0) 完整形态
  var result = attempt(
    dropNotes: false,
    maxDeadlines: null,
    ratio: 1,
    dropZongce: false,
    dropAllCourses: false,
  );
  if (result.envelopeBytes <= maxEnvelopeBytes) return result;

  // 1) 备注文字
  for (final c in rawCourses) {
    if ((c['note'] as String? ?? '').isNotEmpty) droppedNotes++;
    for (final p in (c['parts'] as List?) ?? const []) {
      if (p is Map && (p['note'] as String? ?? '').isNotEmpty) droppedNotes++;
    }
    for (final d in (c['deadlines'] as List?) ?? const []) {
      if (d is Map && (d['note'] as String? ?? '').isNotEmpty) droppedNotes++;
    }
  }
  result = attempt(
    dropNotes: true,
    maxDeadlines: null,
    ratio: 1,
    dropZongce: false,
    dropAllCourses: false,
  );
  if (result.envelopeBytes <= maxEnvelopeBytes) return result;

  // 2) 截止日期只留最近的
  var deadlineTotal = 0;
  for (final c in rawCourses) {
    deadlineTotal += ((c['deadlines'] as List?) ?? const []).length;
  }
  droppedDeadlines = deadlineTotal > deadlineKeep
      ? deadlineTotal - deadlineKeep
      : 0;
  result = attempt(
    dropNotes: true,
    maxDeadlines: deadlineKeep,
    ratio: 1,
    dropZongce: false,
    dropAllCourses: false,
  );
  if (result.envelopeBytes <= maxEnvelopeBytes) return result;

  // 3) ~ 5) 逐级砍课程，中间插一档「整块丢综测」
  final ladder = <({double ratio, bool dropZc})>[
    (ratio: courseKeepRatio, dropZc: false),
    (ratio: courseKeepRatio, dropZc: true),
    (ratio: 0.4, dropZc: true),
    (ratio: 0.2, dropZc: true),
  ];
  for (final step in ladder) {
    final keep = (total * step.ratio).floor().clamp(0, total);
    droppedCourses = total - keep;
    droppedZongce = step.dropZc;
    result = attempt(
      dropNotes: true,
      maxDeadlines: deadlineKeep,
      ratio: step.ratio,
      dropZongce: step.dropZc,
      dropAllCourses: false,
    );
    if (result.envelopeBytes <= maxEnvelopeBytes) return result;
  }

  // 6) 分数估计整体丢掉，至少把纯偏好送上去
  droppedCourses = total;
  droppedZongce = true;
  result = attempt(
    dropNotes: true,
    maxDeadlines: deadlineKeep,
    ratio: 0,
    dropZongce: true,
    dropAllCourses: true,
  );
  if (result.envelopeBytes <= maxEnvelopeBytes) return result;

  throw StateError(
    '连纯偏好都装不下：${result.envelopeBytes} 字节 > 预算 $maxEnvelopeBytes 字节',
  );
}
