import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/period_table_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/period_table_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 作息时间表 Hive box 名。
const periodTableBoxName = 'periodTable';

/// 作息时间表仓库：实时拉取 + 按学期缓存 + 兜底回退。
///
/// 回退链（保证**永远有表可用**，因为倒计时缺了它就是错的）：
/// ① 本学期实时拉取成功 → 写入缓存并返回；
/// ② 拉取失败或该学期无数据 → 用缓存中**最近一个学期**的表；
/// ③ 缓存也为空 → [PeriodTable.builtin]（主流版内置表）。
///
/// 实测该接口随学期变化（2020–2026 出现 3 种表），故缓存按学期分键；
/// 但接口**免登录**，不受教务会话过期影响，可随时刷新。
class PeriodTableRepository {
  final PeriodTableRemoteDataSource _remote;
  final PeriodTableHtmlParser _parser;

  PeriodTableRepository({
    required PeriodTableRemoteDataSource remote,
    required PeriodTableHtmlParser parser,
  }) : _remote = remote,
       _parser = parser;

  /// 取作息表。
  ///
  /// [xn] 学年起始年（如 2026），[xq] 学段（0 第一学期 / 1 第二学期）。
  /// [refresh] 为 false 时优先命中缓存；缓存未命中或 [refresh] 为 true 才走网络。
  Future<PeriodTable> getTable({
    required int xn,
    required int xq,
    bool refresh = false,
  }) async {
    final box = await Hive.openBox<String>(periodTableBoxName);
    final key = _key(xn, xq);

    if (!refresh) {
      final cached = _decode(box.get(key));
      if (cached != null && cached.isUsable) return cached;
    }

    try {
      final html = await _remote.fetchTimetableHtml(xn: xn, xq: xq);
      final table = _parser.parse(html, termCode: '$xn-$xq');
      if (table != null && table.isUsable) {
        await box.put(key, jsonEncode(table.toJson()));
        return table;
      }
      logInfo('作息表 $xn-$xq 无数据（可能尚未发布），走回退');
    } catch (e) {
      logInfo('作息表 $xn-$xq 拉取失败: $e，走回退');
    }

    return _fallback(box);
  }

  /// 同步读取缓存中最近一个学期的作息表；没有则返回内置表。
  ///
  /// 用于界面首帧先渲染已知内容，避免空白等待。
  Future<PeriodTable> cachedOrBuiltin() async {
    final box = await Hive.openBox<String>(periodTableBoxName);
    return _fallback(box);
  }

  /// 回退：缓存中 termCode 最大（最近学期）的可用表 → 内置表。
  PeriodTable _fallback(Box<String> box) {
    PeriodTable? newest;
    for (final key in box.keys) {
      final table = _decode(box.get(key));
      if (table == null || !table.isUsable) continue;
      if (newest == null || _isNewer(table, newest)) newest = table;
    }
    return newest ?? PeriodTable.builtin;
  }

  /// termCode 形如 `2026-0`，按 (学年, 学段) 比较。
  bool _isNewer(PeriodTable a, PeriodTable b) {
    final ka = _parseKey(a.termCode);
    final kb = _parseKey(b.termCode);
    if (ka == null) return false;
    if (kb == null) return true;
    if (ka.$1 != kb.$1) return ka.$1 > kb.$1;
    return ka.$2 > kb.$2;
  }

  (int, int)? _parseKey(String? termCode) {
    if (termCode == null) return null;
    final parts = termCode.split('-');
    if (parts.length != 2) return null;
    final xn = int.tryParse(parts[0]);
    final xq = int.tryParse(parts[1]);
    if (xn == null || xq == null) return null;
    return (xn, xq);
  }

  PeriodTable? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return PeriodTable.fromJson(jsonDecode(raw));
    } catch (e) {
      logInfo('作息表缓存解析失败: $e');
      return null;
    }
  }

  String _key(int xn, int xq) => 'periodTable|$xn-$xq';
}
