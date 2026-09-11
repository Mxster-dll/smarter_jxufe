import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 调课记录 Hive box 的**基础**名（实际 box 按账号隔离，见 [RescheduleRepository]）。
///
/// 与课表缓存（`scheduleCache`）**分开存**：教务刷新/换学期只会重建缓存，
/// 不该动到用户手工录的调课记录。
const rescheduleBoxName = 'scheduleReschedules';

/// 调课记录仓储（Hive，按学年学期 + **账号**隔离）。
///
/// 调课是用户手工录入的个人数据，切号必须隔离：box 名 = `scheduleReschedules_<账号>`
/// （见 `core/storage/account_scoped_box.dart`，旧的无账号 box 会在首次使用时
/// 迁移给第一个打开的账号）。
class RescheduleRepository {
  RescheduleRepository({this.account = ''});

  /// 数据归属的账号卡号（空 = 账号未确定，用独立的 `__none` box）。
  final String account;

  Future<Box<String>> _box() =>
      openAccountScopedBox(rescheduleBoxName, account);

  /// 读取某学年学期的全部调课记录（无记录时返回空列表）。
  Future<List<Reschedule>> load({
    required String year,
    required String semester,
  }) async {
    final box = await _box();
    return decode(box.get(storageKey(year: year, semester: semester)));
  }

  /// 整表写入（单 key JSON，与课表缓存同风格）。
  Future<void> save({
    required String year,
    required String semester,
    required List<Reschedule> records,
  }) async {
    final box = await _box();
    await box.put(
      storageKey(year: year, semester: semester),
      jsonEncode({
        'records': records.map((r) => r.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// box key，格式 `reschedules|<year>|<semester>`。
  static String storageKey({required String year, required String semester}) =>
      'reschedules|$year|$semester';

  /// 容错解码：坏数据（非法 JSON、旧字段缺失）逐条丢弃，绝不抛异常。
  static List<Reschedule> decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final list = decoded['records'];
      if (list is! List) return const [];
      final out = <Reschedule>[];
      for (final item in list) {
        final r = Reschedule.fromJson(item);
        if (r != null) out.add(r);
      }
      return out;
    } catch (e) {
      logInfo('调课记录解析失败: $e');
      return const [];
    }
  }
}
