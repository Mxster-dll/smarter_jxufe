/// 本机数据被「整体改写」（云同步恢复 / 以后的导入）时的版本号。
///
/// 为什么需要它：两类消费者的刷新方式不同 ——
/// - **偏好 store** 自己订阅了 Hive box（`lib/core/storage/box_reload_watcher.dart`），
///   写盘即跟上，不需要这个版本号；
/// - 而**把数据读进自己 State 的页面**（分数估计列表、综测条目）不会自己知道
///   云端恢复改过盘。恢复方 [LocalDataRevision.bump] 一次，这些页面 `ref.listen`
///   到变化就重读自己的内存副本。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 版本号 provider（值只增不减；页面只关心「变过没有」）。
final localDataRevisionProvider = NotifierProvider<LocalDataRevision, int>(
  LocalDataRevision.new,
);

/// 见文件头注释。
class LocalDataRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// 记一次「本机数据被整体改写」。
  void bump() => state = state + 1;
}
