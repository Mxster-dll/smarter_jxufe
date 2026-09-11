import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

/// 入馆教育本地题库:题目 id → 正确答案(逐题提交时服务端下发的那份)。
///
/// 题目与答案全校共用(不随账号变化),因此存单个 key、**跨账号共享**:
/// 一次作答/探底积累后,任何账号再遇同题都能直接答对。
/// 存放于 Hive box `tsgxs`,key `tsgxs_answer_bank`。
class TsgxsAnswerBank {
  final Box<String> _box;

  TsgxsAnswerBank(this._box);

  static const String storageKey = 'tsgxs_answer_bank';

  /// 全部条目(题目 id → 条目);损坏数据一律容错为空。
  Map<String, TsgxsBankEntry> load() {
    final raw = _box.get(storageKey);
    if (raw == null || raw.isEmpty) return <String, TsgxsBankEntry>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, TsgxsBankEntry>{};
      final out = <String, TsgxsBankEntry>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        final entry = TsgxsBankEntry.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
        final qid = entry.questionId.isEmpty
            ? key.toString()
            : entry.questionId;
        if (qid.isNotEmpty) out[qid] = entry;
      });
      return out;
    } catch (_) {
      return <String, TsgxsBankEntry>{};
    }
  }

  TsgxsBankEntry? entryFor(String questionId) => load()[questionId];

  int get count => load().length;

  /// 记录一条正确答案(空答案忽略)。
  Future<void> record(TsgxsBankEntry entry) async {
    if (entry.questionId.isEmpty || entry.answer.trim().isEmpty) return;
    final all = load()..[entry.questionId] = entry;
    await _box.put(
      storageKey,
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }

  Future<void> clear() => _box.delete(storageKey);
}
