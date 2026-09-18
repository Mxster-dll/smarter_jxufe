/// 材料库列表的**分组口径 = 按二级分类（材料类型）**（用户 2026-09-18 九轮）。
///
/// 用户原话：「我希望材料库条目显示不要按综测分类，而是直接按二级分类分类，
/// 比如学科竞赛这样的」——分组键从「五育」（`ZcTypeSpec.dim`：德育 / 智育 /
/// 体育 / 美育 / 劳育，综测口径）换成**材料类型**（`ZcTypeSpec.label`：
/// 学科竞赛获奖 / 论文 · 专利 / 外语水平 …），也就是录入时「材料类型」那一项。
///
/// 口径（改动前先读）：
/// - **组顺序 = [zcTypeSpecs] 的注册顺序**（即「新增材料」下拉顺序，按综测规则表号排：
///   智育 → 德育 → 体育 → 美育 → 劳育），**不按数量排** —— 顺序恒定，新录一条材料
///   不会让整页分组跳动；
/// - **空组不占位**：没有材料的类型不出现在列表里；
/// - 组内按 [ZcMaterial.dateIso] 倒序（新的在前），同日再按 [ZcMaterial.id] 定序
///   （`List.sort` 不稳定，不给兜底键时同日的相对顺序在两次渲染之间可能不同）；
/// - **每条材料恰好落进一个组**：`typeId` 必来自 [zcTypeSpecs]（见 [ZcMaterial.spec]），
///   所以这里只按类型名匹配、不需要「未归类」兜底组 —— 但这条不变式有守卫
///   （`test/materials_grouping_test.dart`：输出条数之和 == 输入条数），别静默丢行。
///
/// 页面侧唯一调用点 = `lib/features/materials/presentation/materials_screen.dart`
/// 的 `_buildBody`；**不要再在页面里按 `dim` 分一遍**。
library;

import 'package:flutter/foundation.dart';

import '../../zongce/domain/zc_catalog.dart';
import '../../zongce/domain/zc_models.dart';

/// 一个二级分类分组：类型规格 + 该类型下的材料（已按时间倒序）。
@immutable
class MaterialGroup {
  const MaterialGroup({required this.spec, required this.materials});

  final ZcTypeSpec spec;
  final List<ZcMaterial> materials;

  ZcTypeId get typeId => spec.id;

  /// 分组标题文案 = 二级分类名（如「学科竞赛获奖」）。
  String get label => spec.label;

  int get count => materials.length;

  /// 分组标题的 Key（`materialsGroup-<typeId.name>`）——挂在标题行的根 widget 上，
  /// 供守卫测试定位（列表是 lazy 的，屏外分组取不到，测试请先滚到可见）。
  Key get groupKey => Key('materialsGroup-${spec.id.name}');
}

/// 按二级分类分组（唯一实现）。
List<MaterialGroup> groupMaterialsByType(List<ZcMaterial> materials) {
  final groups = <MaterialGroup>[];
  for (final spec in zcTypeSpecs) {
    final list = <ZcMaterial>[
      for (final m in materials)
        if (m.typeId == spec.id) m,
    ];
    if (list.isEmpty) continue;
    list.sort((a, b) {
      final byDate = b.dateIso.compareTo(a.dateIso);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    groups.add(MaterialGroup(spec: spec, materials: List.unmodifiable(list)));
  }
  return groups;
}
