/// 主页布局偏好的持久化（Hive `homePrefs` 单 key）。
///
/// 与 `my_campus_prefs.dart` / `calendar_prefs.dart` 同款：`ChangeNotifier`
/// 而非 `AsyncNotifier` —— 设置页改完要**立刻**反映到主页（切换布局不该等
/// 一次异步读盘，否则会先闪一帧旧布局）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_radius.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

/// 存储 box 名（与 `myCampusPrefs`、`schoolCalendarPrefs` 等分开）。
const homePrefsBoxName = 'homePrefs';

/// 布局 key（值为 [HomeLayout.name]；缺省 = 宫格）。
///
/// 公开（不是私有）：云同步恢复 / 测试都要按 key 直接读写同一个 box。
const homeLayoutPrefsKey = 'homeLayout';

/// 卡片形态 key（值为 [HomeCardStyle.name]；缺省 = 都不显示）。
///
/// 与 [homeLayoutPrefsKey] **同 box、不同 key**：两项偏好都只管主页，且都在设置页
/// 「主页布局」那一张卡里改，分成两个 box 只会多一份打开失败的处理。
const homeCardStyleKey = 'homeCardStyle';

/// 卡片间距系数 key（值为十进制整数文本，单位逻辑像素；缺省 [kCardGapDefault]）。
///
/// 用户 2026-10-09 三轮口径：「卡片与卡片之间的距离为 **2a**、卡片与窗口之间`r`n/// （**十七轮改成 `a`**：卡片间距与窗口边距同值，见 `cardGapMetricsOf`）
/// （卡片与标题栏之间的距离不受此限制）的距离为 **a**，然后 a 可以通过设置调」。
/// 阈值与派生量（边距 / 卡片间距 / 外围补白）见
/// `features/home/domain/home_card_gap.dart` 的 [cardGapMetricsOf]。
const homeCardGapKey = 'homeCardGap';

/// 卡片圆角 key（值为十进制整数文本，单位逻辑像素；缺省 [kCardRadiusDefault]）。
///
/// 用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」。
/// 阈值与夹取见 `features/home/domain/home_card_radius.dart`。
const homeCardRadiusKey = 'homeCardRadius';

/// 主页布局偏好存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打开失败时仅本次会话生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面。
class HomeLayoutStore extends ChangeNotifier with BoxReloadWatcher {
  HomeLayout _layout = HomeLayout.grid;
  HomeCardStyle _cardStyle = HomeCardStyle.none;
  double _cardGap = kCardGapDefault;
  double _cardRadius = kCardRadiusDefault;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前布局（默认宫格）。
  HomeLayout get layout => _layout;

  /// 当前卡片形态（默认 `HomeCardStyle.none` = 两块都通栏平铺）。
  HomeCardStyle get cardStyle => _cardStyle;

  /// 卡片间距系数 `a`（逻辑像素，默认 [kCardGapDefault]，夹在 [kCardGapMin] ~ [kCardGapMax]）。
  double get cardGap => _cardGap;

  /// 区域卡片的圆角（逻辑像素，默认 [kCardRadiusDefault]，夹在
  /// [kCardRadiusMin] ~ [kCardRadiusMax]）。
  double get cardRadius => _cardRadius;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(homePrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持默认（宫格 + 无卡片）。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；四个值都没变就不通知。
  ///
  /// ⚠ **这里不许写盘**（只读）：它同时是 box 监听器的回调，写盘会再把监听器叫起来。
  ///
  /// ⚠ **也别在 `_load` 里加"改默认值"的一次性迁移写盘**（2026-10-09 十六轮试过并撤回）：
  /// 只要 `_load()` 里出现一次 `box.put`/`box.delete`，本仓的 Hive + 假异步测试环境就会
  /// **把每个建 store 的用例挂到超时**（实测整份 `test/home_card_style_test.dart` 从 1 秒
  /// 变成逐例 12~30 秒超时；换成不 await 的 `box.put` 也一样）。
  /// 结论：**改默认值就只改常量，别迁移**；用户要新默认按一下「恢复默认」。
  void _readFromBox(Box<String> box) {
    final parsed = HomeLayout.fromName(box.get(homeLayoutPrefsKey));
    final parsedCard = HomeCardStyle.fromName(box.get(homeCardStyleKey));
    final parsedGap = parseCardGap(box.get(homeCardGapKey));
    final parsedRadius = parseCardRadius(box.get(homeCardRadiusKey));

    if (parsed == _layout &&
        parsedCard == _cardStyle &&
        parsedGap == _cardGap &&
        parsedRadius == _cardRadius) {
      return;
    }
    _layout = parsed;
    _cardStyle = parsedCard;
    _cardGap = parsedGap;
    _cardRadius = parsedRadius;
    notifyListeners();
  }

  /// 写入新布局。绝不抛异常。
  Future<void> save(HomeLayout next) async {
    await ensureLoaded();
    if (next == _layout) return;
    _layout = next;
    notifyListeners();
    await _write(homeLayoutPrefsKey, next.name);
  }

  /// 写入新的卡片形态。绝不抛异常。
  Future<void> saveCardStyle(HomeCardStyle next) async {
    await ensureLoaded();
    if (next == _cardStyle) return;
    _cardStyle = next;
    notifyListeners();
    await _write(homeCardStyleKey, next.name);
  }

  /// 写入新的卡片间距系数 `a`（超范围一律夹回，绝不抛异常）。
  Future<void> saveCardGap(double next) async {
    await ensureLoaded();
    final clamped = clampCardGap(next);
    if (clamped == _cardGap) return;
    _cardGap = clamped;
    notifyListeners();
    await _write(homeCardGapKey, formatCardGap(clamped));
  }

  /// 写入新的卡片圆角（超范围一律夹回，绝不抛异常）。
  Future<void> saveCardRadius(double next) async {
    await ensureLoaded();
    final clamped = clampCardRadius(next);
    if (clamped == _cardRadius) return;
    _cardRadius = clamped;
    notifyListeners();
    await _write(homeCardRadiusKey, formatCardRadius(clamped));
  }

  /// 落盘一个 key（存储不可用 / 写失败 → 仅本次会话生效，不影响界面）。
  Future<void> _write(String key, String value) async {
    final box = _box;
    if (box == null) return;
    try {
      await box.put(key, value);
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }

}

/// 主页布局偏好（改动即时通知）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [HomeLayoutStore] 不做全局单例）。
final homeLayoutStoreProvider = ChangeNotifierProvider<HomeLayoutStore>((ref) {
  final store = HomeLayoutStore();
  unawaited(store.ensureLoaded());
  return store;
});
