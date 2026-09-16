import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/reschedule_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';

/// 调课记录的作用域：一个学年学期一份。
@immutable
class RescheduleTerm {
  /// 学年，如 `2025`。
  final String year;

  /// 学期，`0` / `1` / `2`（与课表页的下拉一致）。
  final String semester;

  const RescheduleTerm(this.year, this.semester);

  /// 内存缓存的 key。
  String get key => '$year|$semester';

  /// 展示文本，如 `2025 · 第一学期`。
  String get label {
    final name = switch (semester) {
      '0' => '第一学期',
      '1' => '第二学期',
      '2' => '第二阶段',
      _ => '第 $semester 学期',
    };
    return '$year · $name';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RescheduleTerm &&
          other.year == year &&
          other.semester == semester;

  @override
  int get hashCode => Object.hash(year, semester);

  @override
  String toString() => 'RescheduleTerm($key)';
}

/// 调课记录的进程内共享仓库。
///
/// 课表页、实况窗、调课管理页三处都要**即时**看到彼此的修改（改完立刻
/// 影响实况窗/通知内容），因此用 ChangeNotifier 共享一份内存缓存 +
/// 立即落盘，而不是各自 `FutureProvider` 拿一份快照。
///
/// ⚠️ 内存缓存按 `学期` 索引，因此**切换账号必须清掉**（[bindAccount]）：
/// 否则 A 账号的调课记录会留在内存里被 B 账号读到。
class RescheduleStore extends ChangeNotifier {
  RescheduleStore({RescheduleRepository? repository})
    : _repository = repository ?? RescheduleRepository();

  /// 全 App 共享实例。
  static final RescheduleStore instance = RescheduleStore();

  RescheduleRepository _repository;
  String _account = '';
  final Map<String, List<Reschedule>> _cache = {};

  /// 当前绑定账号（空 = 尚未登录）。
  String get account => _account;

  /// 绑定账号；账号变化时换仓储并**清空内存缓存**（个人数据按账号隔离）。
  ///
  /// 由 `rescheduleStoreProvider` 在 `currentAccountProvider` 变化时调用。
  void bindAccount(String account) {
    if (_account == account) return;
    _account = account;
    _repository = RescheduleRepository(account: account);
    _cache.clear();
    notifyListeners();
  }

  /// 该学期是否已从磁盘读过（未读时 [recordsOf] 返回空列表）。
  bool isLoaded(RescheduleTerm term) => _cache.containsKey(term.key);

  /// 当前内存中的记录（只读视图）。
  List<Reschedule> recordsOf(RescheduleTerm term) =>
      List.unmodifiable(_cache[term.key] ?? const <Reschedule>[]);

  /// 从磁盘载入（幂等：已载入则直接返回内存值）。
  Future<List<Reschedule>> ensureLoaded(RescheduleTerm term) async {
    final cached = _cache[term.key];
    if (cached != null) return List.unmodifiable(cached);
    final loaded = await _repository.load(
      year: term.year,
      semester: term.semester,
    );
    _cache[term.key] = loaded;
    notifyListeners();
    return List.unmodifiable(loaded);
  }

  /// 新增或按 [Reschedule.id] 替换一条记录。
  Future<void> upsert(RescheduleTerm term, Reschedule record) async {
    final list = [..._cache[term.key] ?? const <Reschedule>[]];
    final i = list.indexWhere((r) => r.id == record.id);
    if (i >= 0) {
      list[i] = record;
    } else {
      list.add(record);
    }
    await _commit(term, list);
  }

  /// 删除一条记录。
  Future<void> remove(RescheduleTerm term, String id) async {
    final list = [..._cache[term.key] ?? const <Reschedule>[]]
      ..removeWhere((r) => r.id == id);
    await _commit(term, list);
  }

  /// 清空该学期全部调课记录。
  Future<void> clear(RescheduleTerm term) => _commit(term, const []);

  Future<void> _commit(RescheduleTerm term, List<Reschedule> list) async {
    _cache[term.key] = list;
    notifyListeners();
    await _repository.save(
      year: term.year,
      semester: term.semester,
      records: list,
    );
  }
}

/// 调课仓储（按账号）。
final rescheduleRepositoryProvider = Provider<RescheduleRepository>(
  (ref) => RescheduleRepository(account: ref.watch(currentAccountProvider)),
);

/// 调课记录 store（跨页面共享）。
///
/// watch 账号：切号时 [RescheduleStore.bindAccount] 会换仓储并清内存缓存。
final rescheduleStoreProvider = Provider<RescheduleStore>((ref) {
  final account = ref.watch(currentAccountProvider);
  return RescheduleStore.instance..bindAccount(account);
});
