/// 「我的校区」统一校区口径与相关纯函数。
///
/// 学校存在三套互不相同的校区命名（2026-09 实测），本文件以「学校地址」
/// （[campuses]，4 个校区）为**统一口径**，并向下映射到另外两套：
///
/// | 统一口径（本文件） | 电费 `findCampusList` | 校区地图条目 |
/// |---|---|---|
/// | 蛟桥园校区 | `id=1` 蛟桥校区 | 蛟桥园北区 / 蛟桥园南区 |
/// | 青山园校区 | **无对应校区** | 青山园校区 |
/// | 麦庐园校区 | `id=2` 麦庐校区 | 麦庐园北区 / 麦庐园南区 |
/// | 枫林园校区 | `id=3` 枫林校区 | 枫林园校区 |
///
/// 这张映射表是「我的校区」能被电费 / 学校地址 / 校区地图三处同时复用的
/// 唯一依据，改动前先核对：接口真实响应（`findCampusList`）、
/// `campus_address.dart` 的 [campuses]、`campus_map_screen.dart` 的
/// `campusMapEntries`。三处任一改动都会打破映射，
/// `test/my_campus_test.dart` 有对应的漂移守卫测试。
library;

import 'package:smarter_jxufe/features/campus_address/domain/campus_address.dart';

/// 我所在的校区（用户在设置页指定；未指定时为 `null`）。
enum MyCampus {
  jiaoqiao(
    label: '蛟桥园校区',
    shortLabel: '蛟桥园',
    electricityCampusId: 1,
    mapEntryNames: ['蛟桥园北区', '蛟桥园南区'],
  ),
  qingshan(
    label: '青山园校区',
    shortLabel: '青山园',
    electricityCampusId: null,
    mapEntryNames: ['青山园校区'],
  ),
  mailu(
    label: '麦庐园校区',
    shortLabel: '麦庐园',
    electricityCampusId: 2,
    mapEntryNames: ['麦庐园北区', '麦庐园南区'],
  ),
  fenglin(
    label: '枫林园校区',
    shortLabel: '枫林园',
    electricityCampusId: 3,
    mapEntryNames: ['枫林园校区'],
  );

  const MyCampus({
    required this.label,
    required this.shortLabel,
    required this.electricityCampusId,
    required this.mapEntryNames,
  });

  /// 校区全名，与 [CampusInfo.name] 完全同名（学校地址列表即统一口径）。
  final String label;

  /// 短名，供胶囊 / 徽标等窄位使用。
  final String shortLabel;

  /// 电费接口 `findCampusList` 的校区 id。
  ///
  /// [qingshan] 为 `null`：该校区没有宿舍电费服务，绑定页只能手动选校区。
  final int? electricityCampusId;

  /// 校区地图中属于本校区的条目名（对应 `CampusMapEntry.name`）。
  ///
  /// 蛟桥园 / 麦庐园各有北区、南区两条，故为列表。
  final List<String> mapEntryNames;

  /// 电费绑定能否据本校区自动预选。
  bool get supportsElectricity => electricityCampusId != null;

  /// [c] 是否是本校区的学校地址条目。
  bool matchesAddress(CampusInfo c) => c.name == label;

  /// [name] 是否是本校区相关的校区地图条目名。
  bool matchesMapEntry(String name) => mapEntryNames.contains(name);

  /// 对应的学校地址条目；名字对不上（上游数据改名）时返回 `null`。
  CampusInfo? get addressInfo {
    for (final c in campuses) {
      if (c.name == label) return c;
    }
    return null;
  }

  /// 容错解析存档值。
  ///
  /// 优先按枚举名匹配（正常存档格式）；同时接受 [label]，便于手改存档或
  /// 早期版本写入了显示名。`null` / 空串 / 对不上（改名、存档损坏）
  /// 一律返回 `null`，即「未设置」，不抛异常。
  static MyCampus? fromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final c in MyCampus.values) {
      if (c.name == name || c.label == name) return c;
    }
    return null;
  }
}

/// 把「属于我的校区」的条目稳定地提到列表最前，其余保持原有相对顺序。
///
/// 无匹配（未设置 / 名字对不上）或全部匹配时**原样返回入参**（即无需置顶），
/// 调用方可据此免去无谓重建。
List<T> pinMineFirst<T>(List<T> all, bool Function(T item) isMine) {
  if (all.length < 2) return all;
  final mine = <T>[];
  final rest = <T>[];
  for (final item in all) {
    if (isMine(item)) {
      mine.add(item);
    } else {
      rest.add(item);
    }
  }
  if (mine.isEmpty || rest.isEmpty) return all;
  return <T>[...mine, ...rest];
}

/// 电费绑定页「展开更换面板时预选哪个校区」。
///
/// 优先级：本会话已选 > 已绑定宿舍所在校区（快速换房）> 我的校区 > 不预选。
/// 入参为纯 int（而非领域对象），便于单测且不引入跨 feature 依赖；
/// `0` 与负数视为无效（绑定记录里 `campusId` 缺省即写成 0）。
int? resolveElectricityCampusId({
  int? currentId,
  int? boundCampusId,
  MyCampus? mine,
}) {
  if (currentId != null && currentId > 0) return currentId;
  if (boundCampusId != null && boundCampusId > 0) return boundCampusId;
  return mine?.electricityCampusId;
}
