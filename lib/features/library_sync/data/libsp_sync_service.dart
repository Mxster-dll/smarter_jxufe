/// 图书馆订阅词云同步 · 同步状态机（纯逻辑：网络与 Hive 都在端口之外）。
///
/// 三组冗余 + 双代轮转（Q9 / Q10）全在这里落地：
///
/// - **任意时刻云端至少有一份完整快照**：写新的一版时，先删的只是「最旧/空」的那个
///   槽位，另两个槽位（含上一版）原样不动；只有新片全部写完并**逐片读回校验通过**
///   才继续写第二份。任一步失败 → 什么都不删，上一版仍可用。
/// - **稳态形状 = [最新版, 最新版, 上一版]**：写完第一个槽位后立刻把同一份复制到
///   第二个槽位；上一版那一个槽位刻意不动（误操作可回滚）。
/// - **绝不碰用户的词**：只按「结构识别」挑出我们的片，非我们的订阅词一条都不动
///   （服务端不去重，所以清理必须按结构全删，不能靠内容比对）。
/// - **部分缺片自愈**：最新版的完整副本不足 2 份时，用一个空槽 / 最旧槽重写一份。
///   整组缺失（用户删光了）**不自愈** —— 那是用户在表达「不要了」（Q13）。
library;

import 'package:smarter_jxufe/features/library_sync/data/libsp_codec.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_chunk.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

/// 同步失败的原因分类（界面按它给不同文案）。
enum LibspSyncFailure {
  /// 网络 / 服务端错误。
  network,

  /// 载荷连纯偏好都装不下。
  tooLarge,

  /// 写入后校验不过（服务端截断、被中间层改写、权限问题…）。
  verifyFailed,
}

/// 同步结果（成功与失败共用一个形状，界面不必分支解析）。
class LibspSyncOutcome {
  const LibspSyncOutcome({
    required this.ok,
    this.up,
    this.failure,
    this.message,
  });

  final bool ok;
  final LibspUploadResult? up;
  final LibspSyncFailure? failure;
  final String? message;

  /// 给界面用的一句话。
  String get summary {
    if (ok) {
      final u = up;
      if (u == null) return '同步完成';
      final trimmed = u.trim.isEmpty ? '' : '（${u.trim.summary}）';
      return '已同步到图书馆$trimmed';
    }
    return message ?? '同步失败';
  }
}

/// 图书馆订阅词同步服务。
class LibspSyncService {
  LibspSyncService({
    required LibspRemote remote,
    required LibspLocalStore store,
    required String Function() newId,
    this.maxEnvelopeBytes = kLibspDefaultMaxEnvelopeBytes,
  }) : _remote = remote,
       _store = store,
       _newId = newId;

  final LibspRemote _remote;
  final LibspLocalStore _store;
  final String Function() _newId;

  /// 信封字节预算（见 `kLibspDefaultMaxEnvelopeBytes`）。
  final int maxEnvelopeBytes;

  // ───────────────────────────── 只读 ─────────────────────────────

  /// 拉一次云端状态（不改任何东西）。
  Future<LibspCloudState> inspect() async =>
      _stateFrom(await _remote.listWords());

  /// 最新一版快照（云端没有任何完整的一版 → `null`）。
  Future<LibspSnapshot?> latestSnapshot([LibspCloudState? state]) async {
    final s = state ?? await inspect();
    final verified = s.verifiedSlots;
    if (verified.isEmpty) return null;
    return _snapshotOf(verified.first);
  }

  /// 云端最新版的摘要（给恢复弹窗显示，避免「盲盒覆盖本机数据」）。
  Future<LibspCloudSummary?> latestSummary([LibspCloudState? state]) async {
    final current = state ?? await inspect();
    final verified = current.verifiedSlots;
    if (verified.isEmpty) return null;
    final snapshot = _snapshotOf(verified.first);
    if (snapshot == null) return null;
    return LibspCloudSummary(
      generatedAt: snapshot.generatedAt,
      courseCount: snapshot.courseCount,
      prefEntryCount: snapshot.prefEntryCount,
      hasZongce: snapshot.zongce.isNotEmpty,
      trim: snapshot.trim,
      account: snapshot.account,
      wordCount: current.mine.length,
      foreignCount: current.foreign.length,
    );
  }

  // ───────────────────────────── 上传 ─────────────────────────────

  /// 把本机现状同步到云端：写两遍最新版，保留一份上一版。
  ///
  /// 幂等：同一份数据连传两次，第二次会覆盖「最旧槽位」再复制 —— 形状不变。
  Future<LibspSyncOutcome> upload({
    required String account,
    required int nowMs,
  }) async {
    final LibspCloudState state;
    try {
      state = await inspect();
    } catch (e) {
      return LibspSyncOutcome(
        ok: false,
        failure: LibspSyncFailure.network,
        message: '读取云端失败：$e',
      );
    }

    // 只有一个完整版时，把它保护起来：宁可少写一份，也不能把唯一的好数据删掉。
    final verifiedBefore = state.verifiedSlots;
    final protectedSlots = verifiedBefore.length <= 1
        ? {for (final s in verifiedBefore) s.slot}
        : <int>{};
    var targets = [
      for (final slot in _candidateOrder(state))
        if (!protectedSlots.contains(slot)) slot,
    ];
    if (targets.isEmpty) targets = _candidateOrder(state);

    final LibspBuildResult built;
    try {
      built = buildLibspSnapshot(
        generatedAt: nowMs,
        account: account,
        prefs: await _store.readPrefs(),
        rawCourses: await _store.readCourses(),
        zongce: await _store.readZongceEntries(),
        maxEnvelopeBytes: maxEnvelopeBytes,
      );
    } on StateError catch (e) {
      return LibspSyncOutcome(
        ok: false,
        failure: LibspSyncFailure.tooLarge,
        message: '${e.message}（已停止同步，云端不受影响）',
      );
    }

    final envelope = packLibspEnvelope(built.bytes);
    final List<String> words;
    try {
      words = encodeLibspWords(envelope, slot: targets.first);
    } on ArgumentError catch (e) {
      return LibspSyncOutcome(
        ok: false,
        failure: LibspSyncFailure.tooLarge,
        message: '${e.message}（已停止同步，云端不受影响）',
      );
    }
    final chunkCount = words.length;

    final written = <int>[];
    var healed = 0;
    for (final slot in targets.take(2)) {
      try {
        await _writeSlot(slot, state.slotOf(slot), envelope);
      } catch (e) {
        if (written.isEmpty) {
          return LibspSyncOutcome(
            ok: false,
            failure: LibspSyncFailure.network,
            message: '写入云端失败：$e（上一版未被改动）',
          );
        }
        break; // 第一份已成功 → 保持成功，第二份失败只记账
      }
      // 逐片读回校验：服务端对超长是**静默截断**，不校验就会静默损坏数据。
      final after = _stateFrom(await _remote.listWords());
      final slotState = after.slotOf(slot);
      final ok = slotState != null &&
          slotState.verified &&
          slotState.generatedAt == nowMs;
      if (!ok) {
        if (written.isEmpty) {
          return LibspSyncOutcome(
            ok: false,
            failure: LibspSyncFailure.verifyFailed,
            message: '写入后校验失败：云端这一组不完整（服务端可能截断了订阅词）。'
                '上一版仍完整可用。',
          );
        }
        break;
      }
      written.add(slot);
    }

    // 自愈：最新版完整副本不足 2 份时，补写一份到空槽 / 最旧槽（Q13 部分缺片自愈）。
    if (written.length < 2) {
      final after = _stateFrom(await _remote.listWords());
      final newest = after.verifiedSlots.where((s) => s.generatedAt == nowMs);
      if (newest.length < 2) {
        final spare = _candidateOrder(after).where(
          (s) => !newest.any((n) => n.slot == s),
        );
        if (spare.isNotEmpty) {
          final slot = spare.first;
          try {
            await _writeSlot(slot, after.slotOf(slot), envelope);
            final check = _stateFrom(await _remote.listWords());
            final st = check.slotOf(slot);
            if (st != null && st.verified && st.generatedAt == nowMs) {
              written.add(slot);
              healed++;
            }
          } catch (_) {
            // 自愈失败不影响主流程。
          }
        }
      }
    }

    return LibspSyncOutcome(
      ok: written.isNotEmpty,
      up: LibspUploadResult(
        ok: written.isNotEmpty,
        slotsWritten: written,
        chunkCount: chunkCount,
        envelopeBytes: built.envelopeBytes,
        trim: built.snapshot.trim,
        healed: healed,
        error: written.length < 2 ? '最新版只剩一份（第二份未通过校验）' : null,
      ),
    );
  }

  // ───────────────────────────── 清理 ─────────────────────────────

  /// 按结构删掉**我们写的全部**订阅词，删完对账。
  ///
  /// 服务端不去重（同一条可存在多份），所以必须按结构全删；对账残留不为 0
  /// 时不报成功 —— 否则「一键清除」就是句空话。
  Future<LibspClearResult> clearCloud() async {
    final before = _stateFrom(await _remote.listWords());
    for (final word in before.mine) {
      await _remote.deleteWord(word.subId);
    }
    final after = _stateFrom(await _remote.listWords());
    return LibspClearResult(
      deleted: before.mine.length,
      remaining: after.mine.length,
    );
  }

  // ───────────────────────────── 恢复 ─────────────────────────────

  /// 恢复前留档：把**当前本机状态**先同步上去（于是云端就有「恢复前的一版」）。
  ///
  /// 返回 `false` 表示留档失败 —— 调用方应当据此拦住恢复（Q6：恢复前自动留档，
  /// 留不下档就不该覆盖本机）。
  Future<bool> backupBeforeRestore({
    required String account,
    required int nowMs,
  }) async {
    final outcome = await upload(account: account, nowMs: nowMs);
    return outcome.ok;
  }

  /// 把一份云端快照写回本机（uuid 本地重新生成，见 [adoptGeCourse]）。
  Future<void> restore(LibspSnapshot snapshot, {required int nowMs}) async {
    await _store.writePrefs(snapshot.prefs);
    await _store.writeZongceEntries(snapshot.zongce);
    var t = nowMs;
    final courses = [
      for (final c in snapshot.courses)
        adoptGeCourse(c, newId: _newId, createdAt: t++),
    ];
    await _store.writeCourses(courses);
  }

  // ───────────────────────────── 内部 ─────────────────────────────

  /// 槽位覆盖顺序：**空槽优先**（删都不用删），然后按「未验证 → 生成时刻最旧」排。
  List<int> _candidateOrder(LibspCloudState state) {
    final entries = <({int slot, int rank, int gen})>[];
    for (var slot = 0; slot < kLibspSlots; slot++) {
      final st = state.slotOf(slot);
      if (st == null) {
        entries.add((slot: slot, rank: 0, gen: -1));
      } else {
        entries.add((
          slot: slot,
          rank: 1,
          gen: st.verified ? (st.generatedAt ?? -1) : -1,
        ));
      }
    }
    entries.sort((a, b) {
      if (a.rank != b.rank) return a.rank.compareTo(b.rank);
      if (a.gen != b.gen) return a.gen.compareTo(b.gen);
      return a.slot.compareTo(b.slot);
    });
    return [for (final e in entries) e.slot];
  }

  /// 把一个槽位整体重写成给定信封：**先清空该槽位，再写全部新片**。
  ///
  /// 先清空是安全的：另两个槽位仍在（Q10），且清理只针对**这一个槽位的片**。
  Future<void> _writeSlot(
    int slot,
    LibspSlotState? existing,
    List<int> envelope,
  ) async {
    if (existing != null) {
      for (final word in existing.words) {
        await _remote.deleteWord(word.subId);
      }
    }
    final words = encodeLibspWords(envelope, slot: slot);
    for (final word in words) {
      await _remote.addWord(word);
    }
  }

  LibspCloudState _stateFrom(List<LibspRemoteWord> words) {
    final mine = <LibspRemoteWord>[];
    final bySlot = <int, List<({LibspRemoteWord word, LibspChunk chunk})>>{};
    for (final word in words) {
      final chunk = decodeLibspWord(word.subName);
      if (chunk == null) continue;
      mine.add(word);
      (bySlot[chunk.slot] ??= []).add((word: word, chunk: chunk));
    }
    final slots = <LibspSlotState>[];
    for (final entry in bySlot.entries) {
      final items = [...entry.value]
        ..sort((a, b) => a.chunk.index.compareTo(b.chunk.index));
      final chunks = [for (final i in items) i.chunk];
      final total = chunks.first.total;
      final joined = joinLibspChunks(chunks);
      int? generatedAt;
      if (joined != null) {
        final payload = unpackLibspEnvelope(joined);
        final snapshot =
            payload == null ? null : decodeLibspSnapshotBytes(payload);
        generatedAt = snapshot?.generatedAt;
      }
      slots.add(
        LibspSlotState(
          slot: entry.key,
          chunks: chunks,
          words: [for (final i in items) i.word],
          total: total,
          verified: generatedAt != null,
          generatedAt: generatedAt,
        ),
      );
    }
    slots.sort((a, b) => a.slot.compareTo(b.slot));
    return LibspCloudState(words: words, slots: slots, mine: mine);
  }

  LibspSnapshot? _snapshotOf(LibspSlotState slot) {
    final joined = joinLibspChunks(slot.chunks);
    if (joined == null) return null;
    final payload = unpackLibspEnvelope(joined);
    if (payload == null) return null;
    return decodeLibspSnapshotBytes(payload);
  }
}

/// 云端快照摘要（恢复弹窗展示；**不展示原文**，只报「有多少、什么时候」）。
class LibspCloudSummary {
  const LibspCloudSummary({
    required this.generatedAt,
    required this.courseCount,
    required this.prefEntryCount,
    required this.hasZongce,
    required this.trim,
    required this.account,
    this.wordCount = 0,
    this.foreignCount = 0,
  });

  final int generatedAt;
  final int courseCount;
  final int prefEntryCount;
  final bool hasZongce;
  final LibspTrimReport trim;
  final String account;

  /// 云端属于我们的订阅词条数（明示：用户能在图书馆界面看到它们）。
  final int wordCount;

  /// 用户自己的订阅词条数（我们绝不触碰 —— 明示里要说清占比）。
  final int foreignCount;

  /// 一行摘要，如「2026-09-17 14:22 的快照 · 10 门课 · 5 项偏好」。
  String get label {
    final at = DateTime.fromMillisecondsSinceEpoch(generatedAt);
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
    final parts = <String>[
      if (courseCount > 0) '$courseCount 门课',
      if (prefEntryCount > 0) '$prefEntryCount 项偏好',
      if (hasZongce) '综测填写项',
    ];
    final body = parts.isEmpty ? '仅偏好' : parts.join(' · ');
    final note = trim.isEmpty ? '' : '（原快照${trim.summary}）';
    final words = wordCount == 0
        ? ''
        : ' · 云端 $wordCount 条同步词'
              '${foreignCount > 0 ? '（另有你自己的 $foreignCount 条订阅词，不会被改动）' : ''}';
    return '$when 的快照 · $body$note$words';
  }
}
