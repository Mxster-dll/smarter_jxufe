import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

/// 桌面小组件数据同步：App 侧算好 → 原生只负责渲染。
///
/// 口径与首页「数据一览」完全一致（电费走 [dashboardElectricityProvider]、
/// 成绩走 [weightedGradeRankingProvider]、网费 / 志愿 / 今日课程与面板同源），
/// 避免 App 与桌面两处数字打架。
///
/// 触发时机：登录成功、进入首页、回到前台、点击小组件唤起；
/// 后台定时/解锁刷新由原生 headless 引擎走
/// `home_widget_background.dart` 的入口，不复用本类（那里没有 Hive）。
class HomeWidgetSync {
  HomeWidgetSync(this._ref);

  final Ref _ref;

  /// 同一内容在 [maxAge] 内不重复推送（避免每次重建都打一次通道）。
  static const Duration maxAge = Duration(minutes: 10);
  static final Map<HomeWidgetMetric, String> _lastKey = {};
  static final Map<HomeWidgetMetric, DateTime> _lastPushAt = {};

  static String _contentKey(HomeWidgetSnapshot s) =>
      '${s.state.key}|${s.label}|${s.value}|${s.unit}|${s.sub1}|${s.message}'
      '|${s.cells.join(',')}';

  bool _shouldPush(
    HomeWidgetMetric metric,
    HomeWidgetSnapshot snapshot,
    bool force,
  ) {
    if (force) return true;
    final key = _contentKey(snapshot);
    final prevKey = _lastKey[metric];
    final prevAt = _lastPushAt[metric];
    if (prevKey == null || prevAt == null) return true;
    if (prevKey != key) return true;
    return DateTime.now().difference(prevAt) > maxAge;
  }

  Future<bool> _push(HomeWidgetSnapshot snapshot, {required bool force}) async {
    if (!_shouldPush(snapshot.metric, snapshot, force)) return false;
    final ok = await HomeWidgetBridge.updateSnapshot(snapshot);
    if (ok) {
      _lastKey[snapshot.metric] = _contentKey(snapshot);
      _lastPushAt[snapshot.metric] = DateTime.now();
    }
    return ok;
  }

  /// 电费快照：口径 = 首页「数据一览 · 电费余额」。
  Future<bool> syncElectricity({bool force = false}) async {
    // 未登录不推送：避免在桌面留下「未绑定宿舍」这类误导性空态。
    if (_ref.read(currentAccountProvider).isEmpty) return false;
    HomeWidgetSnapshot snapshot;
    try {
      final balance = await _ref.read(dashboardElectricityProvider.future);
      if (balance == null) {
        snapshot = _empty(
          HomeWidgetMetric.electricity,
          '未绑定宿舍',
          accent: _accentElectricity,
        );
      } else {
        snapshot = HomeWidgetSnapshot(
          metric: HomeWidgetMetric.electricity,
          label: HomeWidgetMetric.electricity.defaultLabel,
          value: balance.balance,
          valueShort: _shortValue(balance.balance, decimals: 1),
          unit: balance.unit,
          sub1: balance.roomNo.isEmpty ? '' : '房间 ${balance.roomNo}',
          sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
          state: HomeWidgetState.ok,
          message: '',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          accent: _accentElectricity,
        );
      }
    } catch (e) {
      debugPrint('[home_widget] 电费快照失败: $e');
      snapshot = _error(
        HomeWidgetMetric.electricity,
        '电费获取失败',
        accent: _accentElectricity,
      );
    }
    return _push(snapshot, force: force);
  }

  /// 成绩快照：口径 = 首页「数据一览 · 课程加权 + 专业排名」。
  Future<bool> syncGrades({bool force = false}) async {
    // 未登录不推送（同上）。
    if (_ref.read(currentAccountProvider).isEmpty) return false;
    HomeWidgetSnapshot snapshot;
    try {
      final grade = await _ref.read(weightedGradeRankingProvider(1).future);
      if (grade == null) {
        snapshot = _empty(
          HomeWidgetMetric.grades,
          '暂无成绩',
          accent: _accentGrades,
        );
      } else {
        snapshot = HomeWidgetSnapshot(
          metric: HomeWidgetMetric.grades,
          label: HomeWidgetMetric.grades.defaultLabel,
          value: grade.grade,
          valueShort: _shortValue(grade.grade),
          unit: '分',
          sub1: grade.majorRank > 0 ? '专业排名 第 ${grade.majorRank} 名' : '未上榜',
          sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
          state: HomeWidgetState.ok,
          message: '',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          accent: _accentGrades,
        );
      }
    } catch (e) {
      debugPrint('[home_widget] 成绩快照失败: $e');
      snapshot = _error(
        HomeWidgetMetric.grades,
        '成绩获取失败',
        accent: _accentGrades,
      );
    }
    return _push(snapshot, force: force);
  }

  /// 仪表盘快照：口径 = 首页「数据一览」的 5 项（电费 / 网费 / 课程加权 /
  /// 志愿时长 / 今日课程）。
  ///
  /// 每一项独立容错：单项失败只让该格显示 `—`，不牵连整卡；网格容量小的档位
  /// （2×1 / 2×2 / 3×1 …）由原生按尺寸取前 N 格。
  Future<bool> syncDashboard({bool force = false}) async {
    if (_ref.read(currentAccountProvider).isEmpty) return false;

    final cells = <HomeWidgetCell>[];
    var resolved = 0;

    Future<void> add(String label, Future<String?> Function() read) async {
      String? value;
      try {
        value = await read();
      } catch (e) {
        debugPrint('[home_widget] 仪表盘「$label」获取失败: $e');
      }
      if (value != null && value.isNotEmpty) resolved++;
      cells.add(HomeWidgetCell(label: label, value: value ?? '—'));
    }

    await add('电费', () async {
      final balance = await _ref.read(dashboardElectricityProvider.future);
      return balance == null ? null : _shortValue(balance.balance, decimals: 1);
    });
    await add('网费', () async {
      final summary = await _ref.read(netFeeSummaryProvider.future);
      final balance = summary.balance;
      return balance == null ? null : fmtYuan(balance);
    });
    await add('加权', () async {
      final grade = await _ref.read(weightedGradeRankingProvider(1).future);
      return grade == null ? null : _shortValue(grade.grade);
    });
    await add('志愿', () async {
      final hours = await _ref.read(dashboardVolunteerHoursProvider.future);
      return '${_trimHours(hours)}h';
    });
    await add('今日', () async {
      final courses = await _ref.read(dashboardTodayCoursesProvider.future);
      return courses.isEmpty ? '无课' : '${courses.length} 节';
    });

    final now = DateTime.now();
    final snapshot = HomeWidgetSnapshot(
      metric: HomeWidgetMetric.dashboard,
      label: HomeWidgetMetric.dashboard.defaultLabel,
      value: '',
      unit: '',
      sub1: '',
      sub2: HomeWidgetSnapshot.updatedLabel(now),
      state: resolved == 0 ? HomeWidgetState.error : HomeWidgetState.ok,
      message: resolved == 0 ? '暂无数据，打开 App 刷新' : '',
      updatedAt: now.millisecondsSinceEpoch,
      accent: _accentDashboard,
      cells: cells,
    );
    return _push(snapshot, force: force);
  }

  /// 三路一起推。
  Future<void> syncAll({bool force = false}) async {
    await syncElectricity(force: force);
    await syncGrades(force: force);
    await syncDashboard(force: force);
  }

  /// 把后台刷新所需的最小认证快照写给原生。
  ///
  /// 后台 isolate 不能碰 Hive（与主 isolate 争用 box），
  /// 因此学号 / 密码 / TGC / JSESSIONID / 房间号都走这里落盘；
  /// 这份快照同时也是后台静默续期的凭据来源。
  Future<void> pushAuthSnapshot() async {
    try {
      final account = _ref.read(currentAccountProvider);
      if (account.isEmpty) return;

      final accountDs = await _ref.read(accountLocalDataSourceProvider.future);
      final authDs = await _ref.read(authLocalDataSourceProvider.future);
      final imsDs = await _ref.read(imsAuthLocalDataSourceProvider.future);

      final current = accountDs.getCurrentAccount();
      var password = current?.cardNumber == account
          ? (current?.password ?? '')
          : '';
      if (password.isEmpty) {
        for (final a in accountDs.getAccounts()) {
          if (a.cardNumber == account) {
            password = a.password;
            break;
          }
        }
      }

      var roomId = 0;
      var roomName = '';
      try {
        final box = await _ref.read(electricityBindingBoxProvider.future);
        final raw = box.get(account);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final record = RoomBindingRecord.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)),
            );
            roomId = record.roomId;
            roomName = record.roomName;
          }
        }
      } catch (e) {
        debugPrint('[home_widget] 读取宿舍绑定失败: $e');
      }

      await HomeWidgetBridge.setAuthSnapshot({
        'username': account,
        'password': password,
        'tgc': authDs.getTgc(account) ?? '',
        'jsessionid': await imsDs.read(account) ?? '',
        'trustDevice': authDs.isTrustDevice(account),
        'roomId': roomId,
        'roomName': roomName,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[home_widget] 认证快照失败: $e');
    }
  }

  /// 退出登录：清掉桌面残留（快照 + 认证信息）。
  Future<void> clearAll() => HomeWidgetBridge.clearSnapshots();

  /// 点缀色唯一来源 = `lib/design/feature_palette.dart`，转为 `#RRGGBB`。
  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// 窄尺寸（2×1）用的短数值：成绩 `91.85965` → `91.86`，电费 `12.5` → `12.5`。
  static String _shortValue(String raw, {int decimals = 2}) =>
      double.tryParse(raw.trim())?.toStringAsFixed(decimals) ?? raw;

  /// 志愿时长：整数不带小数（24h 而不是 24.0h）。
  static String _trimHours(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static final String _accentElectricity = _hex(FeaturePalette.electricity);
  static final String _accentGrades = _hex(FeaturePalette.grade);
  static final String _accentDashboard = _hex(FeaturePalette.dashboard);

  HomeWidgetSnapshot _empty(
    HomeWidgetMetric metric,
    String message, {
    required String accent,
  }) => HomeWidgetSnapshot(
    metric: metric,
    label: metric.defaultLabel,
    value: '',
    unit: '',
    sub1: '',
    sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
    state: HomeWidgetState.empty,
    message: message,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    accent: accent,
  );

  HomeWidgetSnapshot _error(
    HomeWidgetMetric metric,
    String message, {
    required String accent,
  }) => HomeWidgetSnapshot(
    metric: metric,
    label: metric.defaultLabel,
    value: '',
    unit: '',
    sub1: '',
    sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
    state: HomeWidgetState.error,
    message: message,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    accent: accent,
  );
}

/// 小组件同步服务（界面层用 `ref.read(homeWidgetSyncProvider)`）。
final homeWidgetSyncProvider = Provider<HomeWidgetSync>(
  (ref) => HomeWidgetSync(ref),
);
