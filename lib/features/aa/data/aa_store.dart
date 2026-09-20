/// AA 算账 · 本地存储（Hive `Box<String>` **单键整表**读写，按账号隔离）。
///
/// 两张表：成员名单 + 开销清单；一次读全、一次写全——数据量是人手录的几十条，
/// 整表读写比增量维护简单得多，也不会出现「删了一半」的中间态。
library;

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/aa_models.dart';

/// 成员名单的键。
const String aaMembersKey = 'members';

/// 开销清单的键。
const String aaExpensesKey = 'expenses';

class AaStore {
  final Box<String> box;

  const AaStore(this.box);

  /// 成员（坏数据 → 空表，页面按「还没有成员」处理）。
  Future<List<AaMember>> loadMembers() async {
    final raw = box.get(aaMembersKey);
    if (raw == null || raw.isEmpty) return const <AaMember>[];
    return aaMembersFromJson(raw);
  }

  Future<void> saveMembers(List<AaMember> list) =>
      box.put(aaMembersKey, aaMembersJson(list));

  /// 开销（坏数据 → 空表）。
  Future<List<AaExpense>> loadExpenses() async {
    final raw = box.get(aaExpensesKey);
    if (raw == null || raw.isEmpty) return const <AaExpense>[];
    return aaExpensesFromJson(raw);
  }

  Future<void> saveExpenses(List<AaExpense> list) =>
      box.put(aaExpensesKey, aaExpensesJson(list));
}
