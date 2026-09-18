/// 图书馆订阅词云同步 · 领域模型与端口（让同步逻辑可单测：网络与 Hive 都在端口之外）。
library;

import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_chunk.dart';

/// 服务端的一条订阅词。
class LibspRemoteWord {
  const LibspRemoteWord({required this.subId, required this.subName});

  /// 服务端主键（删除要用）。
  final int subId;

  /// 订阅词原文（实测：服务端零规范化，原样往返）。
  final String subName;

  @override
  String toString() => 'LibspRemoteWord($subId)';
}

/// 订阅词远端端口（真实实现见 `data/datasources/libsp_subscribe_remote_datasource.dart`）。
abstract class LibspRemote {
  /// 拉全部订阅词（含用户自己的，调用方负责筛）。
  Future<List<LibspRemoteWord>> listWords();

  /// 新增一条订阅词（服务端不去重，同一串可重复写入）。
  Future<void> addWord(String name);

  /// 按 subId 删除。
  Future<void> deleteWord(int subId);
}

/// 本机数据端口（偏好 / 分数估计 / 综测的读与写）。
///
/// 读出来的是**原始 JSON 形态**（`GeCourse.toJson()` 那种），因为载荷层要在
/// 剥离 uuid 之前先看到它们。
abstract class LibspLocalStore {
  /// 偏好：box → key → 原样值。
  Future<Map<String, Map<String, String>>> readPrefs();

  /// 分数估计课程（`GeCourse.toJson()` 形态）。
  Future<List<Map<String, dynamic>>> readCourses();

  /// 综测：key → 原样 JSON 值。
  Future<Map<String, String>> readZongceEntries();

  /// 写回偏好（只覆盖载荷里出现的 box/key，不动其它偏好）。
  Future<void> writePrefs(Map<String, Map<String, String>> prefs);

  /// 写回课程（调用方已补好 id / createdAt / 空备忘录）。
  Future<void> writeCourses(List<Map<String, dynamic>> courses);

  /// 写回综测条目。
  Future<void> writeZongceEntries(Map<String, String> entries);
}

/// 一个槽位（组）的云端状态。
class LibspSlotState {
  const LibspSlotState({
    required this.slot,
    required this.chunks,
    required this.words,
    required this.total,
    required this.verified,
    this.generatedAt,
  });

  final int slot;

  /// 该槽位解析出的片（按序号排序）。
  final List<LibspChunk> chunks;

  /// 该槽位的词（带 subId —— 删除与重写要用）。
  final List<LibspRemoteWord> words;

  /// 该槽位自称的总片数（取自第一片）。
  final int total;

  /// 片齐 + 全部 CRC 通过。
  final bool verified;

  /// 快照生成时刻（仅在 [verified] 时解得出）。
  final int? generatedAt;

  /// 片是否齐（不保证 CRC）。
  bool get complete => chunks.length == total;

  @override
  String toString() =>
      'LibspSlotState(slot=$slot, ${chunks.length}/$total, verified=$verified)';
}

/// 云端的整体状态（一次 `list` 的快照）。
class LibspCloudState {
  const LibspCloudState({
    required this.words,
    required this.slots,
    required this.mine,
  });

  /// 服务端返回的全部订阅词。
  final List<LibspRemoteWord> words;

  /// 我们的槽位（可能少于 [kLibspSlots] 个）。
  final List<LibspSlotState> slots;

  /// 属于我们的词（结构识别通过），按槽位分组前的平铺列表。
  final List<LibspRemoteWord> mine;

  /// 用户自己的（非我们的）订阅词 —— **绝不触碰**。
  List<LibspRemoteWord> get foreign =>
      [for (final w in words) if (!mine.any((m) => m.subId == w.subId)) w];

  LibspSlotState? slotOf(int slot) {
    for (final s in slots) {
      if (s.slot == slot) return s;
    }
    return null;
  }

  /// 通过校验的槽位，按生成时刻从新到旧。
  List<LibspSlotState> get verifiedSlots {
    final list = [
      for (final s in slots)
        if (s.verified) s,
    ];
    list.sort((a, b) => (b.generatedAt ?? 0).compareTo(a.generatedAt ?? 0));
    return list;
  }
}

/// 上传结果。
class LibspUploadResult {
  const LibspUploadResult({
    required this.ok,
    required this.slotsWritten,
    required this.chunkCount,
    required this.envelopeBytes,
    required this.trim,
    this.healed = 0,
    this.error,
  });

  final bool ok;

  /// 本次写入了哪些槽位（Q10：正常是 2 个 —— 最新版两份）。
  final List<int> slotsWritten;

  /// 每份的片数。
  final int chunkCount;

  /// 信封字节数。
  final int envelopeBytes;

  /// 精简报告（空 = 没丢东西）。
  final LibspTrimReport trim;

  /// 自愈补写的片数。
  final int healed;

  /// 失败原因（ok=false 时非空）。
  final String? error;
}

/// 清理结果。
class LibspClearResult {
  const LibspClearResult({required this.deleted, required this.remaining});

  final int deleted;

  /// 删完对账后仍残留的我们的词（必须为 0 才算干净；服务端不去重，所以要按前缀全删）。
  final int remaining;

  bool get clean => remaining == 0;
}
