/// 全局路由历史（2026-10-09 立 · 用户原话：「我希望在顶部增加一个全局路由记录前进/后退，
/// 就是记录一下页面跳转，然后我希望可以点击顶部的按钮，实现页面之间的切换」）。
///
/// **模型 = 浏览器式「访问过的位置」**：一条线性列表 + 一个游标，**不是** Flutter 的
/// Navigator 栈（那玩意儿只支持 pop，「前进」根本无从谈起）。
///
/// - 每个位置 [RouteHistoryEntry] 自带一个 [RouteHistoryEntry.restore]：把应用**放回那个
///   位置** —— 侧栏视图里就是「换回那一格」（改 `_selectedService` / `_selectedFooter`），
///   整页 push 出去的页面就是「重新打开它」。
/// - [RouteHistory.record] 追加新位置并**截断前进尾巴**（浏览器语义）。
/// - [RouteHistory.goBack] / [RouteHistory.goForward] 只移动游标 + 调 `restore()`，
///   **不碰 Navigator 栈** —— 于是「用户自己按返回键 pop 掉了一页」这种旁路也不会让历史
///   失效：那一条照样点得回去。
/// - `restore == null` 的位置（页面没法重建：有些页面只拿得到一个一次性状态）→ 对应的
///   前进/后退按钮**禁用**，不画死按钮（与 `AppErrorState` 的 retry 同一条纪律）。
///
/// 记录点（v1，就两处，别到处塞）：
/// 1. 跳转缝 `lib/core/navigation/service_nav.dart` 的三个动作（带 `label` 注册的页面）；
/// 2. 侧栏视图的面板切换（`home_screen.dart` 的 `_select` / `_selectFooter`）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一个「去过的地方」。
@immutable
class RouteHistoryEntry {
  const RouteHistoryEntry({
    required this.label,
    this.restore,
    this.key,
    this.id,
    this.parentId,
  });

  /// 这一笔的编号（图里连线的端点用；`record` 时自动分配，调用方不用管）。
  final int? id;

  /// 父节点编号 —— **分叉就是这么来的**（用户 2026-10-09：「如果从 a 页面之前访问了 b，
  /// 现在回退到 a 再访问 c，就要出现分叉」）：c 的父是 a，于是 b 和 c 成了兄弟，
  /// 图上从 a 分出去两条。
  final int? parentId;

  /// 显示名（顶部下拉里那一行字），如「设置」「我的」「课程表」。
  final String label;

  /// 回到这个位置的动作；`null` = 回不去（按钮禁用）。
  final VoidCallback? restore;

  /// 去重键：连续记录同一个 key 只留一条（面板来回点不刷屏）。
  final String? key;

  bool get canRestore => restore != null;

  @override
  String toString() => 'RouteHistoryEntry($label${key == null ? '' : ' #$key'})';
}

/// 全局单例（`routeHistoryProvider` 不用 autoDispose：历史必须跨页面活着）。
class RouteHistory extends ChangeNotifier {
  final List<RouteHistoryEntry> _entries = <RouteHistoryEntry>[];
  int _index = -1;

  /// 已访问的位置（只读快照）。
  List<RouteHistoryEntry> get entries => List<RouteHistoryEntry>.unmodifiable(_entries);

  /// 当前游标（-1 = 还没有任何记录）。
  int get index => _index;

  RouteHistoryEntry? get current =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;

  bool get isEmpty => _entries.isEmpty;

  /// 能不能后退 / 前进（目标那一条必须**可重建**，否则等于死按钮）。
  bool get canGoBack {
    if (_index < 0) return false;
    final p = parentIndexOf(_index);
    return p >= 0 && _entries[p].canRestore;
  }

  bool get canGoForward {
    if (_index < 0) return false;
    final c = lastChildIndexOf(_index);
    return c >= 0 && _entries[c].canRestore;
  }

  /// 记一笔。
  ///
  /// - `key` 与当前这条相同 → **什么都不做**（同一个页面里点了两下不产生两条历史）；
  /// - 否则截断 `index` 之后的「前进尾巴」，再追加。
  void record(RouteHistoryEntry entry) {
    if (entry.key != null && current?.key == entry.key) return;
    final parent = _index >= 0 ? _entries[_index].id : null;
    _nextId += 1;
    _entries.add(RouteHistoryEntry(
      label: entry.label,
      restore: entry.restore,
      key: entry.key,
      id: _nextId,
      parentId: parent,
    ));
    _index = _entries.length - 1;
    notifyListeners();
  }

  int _nextId = 0;

  /// 某一笔的父节点在列表里的下标（没有父 = -1；给图连线用）。
  int parentIndexOf(int i) {
    if (i < 0) return -1;
    final parentId = _entries[i].parentId;
    if (parentId == null) return -1;
    for (var j = i - 1; j >= 0; j--) {
      if (_entries[j].id == parentId) return j;
    }
    return -1;
  }

  /// 某一笔的「泳道」下标（0 = 主干；分叉出去的新支依次 +1）。
  ///
  /// 规则照 git 的观感：**父节点的第一个孩子留在父的泳道**（主线直着往下走），
  /// 之后的孩子（= 回退后再去的新页）另开一条泳道。
  int laneOf(int i) {
    final lanes = List<int>.filled(_entries.length, 0);
    final childCount = List<int>.filled(_entries.length, 0);
    var maxLane = 0;
    for (var k = 0; k < _entries.length; k++) {
      final p = parentIndexOf(k);
      if (p < 0) {
        lanes[k] = 0;
      } else if (childCount[p] == 0) {
        lanes[k] = lanes[p];
      } else {
        maxLane += 1;
        lanes[k] = maxLane;
      }
      if (p >= 0) childCount[p] += 1;
      if (lanes[k] > maxLane) maxLane = lanes[k];
    }
    return lanes[i];
  }

  /// 从根一路到**游标**的那条祖先链（下标集合）。
  ///
  /// ⚠ 图上「走过 / 亮起」的判据必须是**这条链**，不能是「列表里排在游标前面」——
  /// 用户 2026-10-09 报的「分叉时所有子节点都亮起」就是后者：另一条分支排在游标
  /// 之前，于是被当成走过 ✗。分叉之后只有链上的那一支才算「走过去的路」。
  Set<int> activePathIndices() {
    final path = <int>{};
    var i = _index;
    while (i >= 0 && !path.contains(i)) {
      path.add(i);
      i = parentIndexOf(i);
    }
    return path;
  }

  /// 「前进」会去的那一笔（= 游标最近的那个孩子；没有则 -1）。
  ///
  /// 用户 2026-10-09：「当产生了分叉时，此时点击前进，那就应该往最新的分支上前进」——
  /// 所以是**最后记录的那个孩子**（最新分支），界面要把这一笔标出来。
  int get forwardTargetIndex => _index < 0 ? -1 : lastChildIndexOf(_index);
  /// 图上最多用到几条泳道（面板要按它留左边距）。
  int get laneCount {
    var maxLane = 0;
    for (var i = 0; i < _entries.length; i++) {
      final l = laneOf(i);
      if (l > maxLane) maxLane = l;
    }
    return maxLane + 1;
  }

  /// 后退一格（不可用时静默返回，调用方先用 [canGoBack] 判）。
  bool goBack() {
    if (!canGoBack) return false;
    _index = parentIndexOf(_index);
    final entry = _entries[_index];
    notifyListeners();
    entry.restore?.call();
    return true;
  }

  /// 前进一格。
  bool goForward() {
    if (_index < 0) return false;
    final child = lastChildIndexOf(_index);
    if (child < 0 || !_entries[child].canRestore) return false;
    _index = child;
    final entry = _entries[_index];
    notifyListeners();
    entry.restore?.call();
    return true;
  }

  /// 某一笔**最近的那个孩子**（分叉之后「前进」走这条：等于撤销上一次后退）。
  int lastChildIndexOf(int i) {
    if (i < 0) return -1;
    final id = _entries[i].id;
    var found = -1;
    for (var k = i + 1; k < _entries.length; k++) {
      if (_entries[k].parentId == id) found = k;
    }
    return found;
  }

  /// 直接跳到历史上第 [target] 条（顶部下拉里点某一行）。
  bool goTo(int target) {
    if (target < 0 || target >= _entries.length || target == _index) return false;
    final entry = _entries[target];
    if (!entry.canRestore) return false;
    final backwards = target < _index;
    _index = target;
    notifyListeners();
    entry.restore?.call();
    // backwards 只是给调用方读日志用的语义，不影响行为。
    assert(backwards || true);
    return true;
  }

  /// 清空（换账号 / 回到根这类场景；也给测试用）。
  void clear() {
    _entries.clear();
    _index = -1;
    notifyListeners();
  }
}

/// 全局历史单例。
final routeHistoryProvider = ChangeNotifierProvider<RouteHistory>(
  (ref) => RouteHistory(),
);
