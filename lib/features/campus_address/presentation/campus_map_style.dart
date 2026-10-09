import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_painter.dart';

/// 校区地图的两种风格。
///
/// 用户 2026-10 原话：「可以手动切换两种风格的地图」。定案 =
/// **浅色（日间）/ 深色（夜间）**，默认跟随 App 主题，页内再给一个手动开关
/// 覆盖它（手动选过之后以手动为准，直到用户再切回「跟随」）。
enum CampusMapStyleKind {
  /// 浅色：米白底图 + 白路面 + 暖灰建筑。
  light('浅色', Icons.light_mode_outlined, '日间'),

  /// 深色：炭灰底图 + 中灰路面 + 深灰建筑，夜间不刺眼。
  dark('深色', Icons.dark_mode_outlined, '夜间');

  const CampusMapStyleKind(this.label, this.icon, this.hint);

  /// 开关上显示的名字。
  final String label;

  final IconData icon;

  /// 副标题（说明这是什么场景用的）。
  final String hint;

  /// 另一个风格（切换按钮用）。
  CampusMapStyleKind get other =>
      this == CampusMapStyleKind.light ? CampusMapStyleKind.dark : light;

  /// 把配色组装成渲染端要的 [CampusMapStyle]。
  ///
  /// 色值全部来自 [CampusMapTone] —— 这里不做任何取色计算，
  /// 只做「浅色取哪一组、深色取哪一组」的搬运，
  /// 保证两套风格各自可被单独调整而不互相牵连。
  CampusMapStyle resolve() => switch (this) {
        CampusMapStyleKind.light => const CampusMapStyle(
            ground: CampusMapTone.lightGround,
            water: CampusMapTone.lightWater,
            waterEdge: CampusMapTone.lightWaterEdge,
            green: CampusMapTone.lightGreen,
            sport: CampusMapTone.lightSport,
            sportEdge: CampusMapTone.lightSportEdge,
            road: CampusMapTone.lightRoad,
            roadCasing: CampusMapTone.lightRoadCasing,
            building: CampusMapTone.lightBuilding,
            buildingEdge: CampusMapTone.lightBuildingEdge,
            buildingNamed: CampusMapTone.lightBuildingNamed,
            label: CampusMapTone.lightLabel,
            labelHalo: CampusMapTone.lightLabelHalo,
            accent: CampusMapTone.accent,
          ),
        CampusMapStyleKind.dark => const CampusMapStyle(
            ground: CampusMapTone.darkGround,
            water: CampusMapTone.darkWater,
            waterEdge: CampusMapTone.darkWaterEdge,
            green: CampusMapTone.darkGreen,
            sport: CampusMapTone.darkSport,
            sportEdge: CampusMapTone.darkSportEdge,
            road: CampusMapTone.darkRoad,
            roadCasing: CampusMapTone.darkRoadCasing,
            building: CampusMapTone.darkBuilding,
            buildingEdge: CampusMapTone.darkBuildingEdge,
            buildingNamed: CampusMapTone.darkBuildingNamed,
            label: CampusMapTone.darkLabel,
            labelHalo: CampusMapTone.darkLabelHalo,
            accent: CampusMapTone.accentSoft,
          ),
      };

  /// 从持久化值还原（认不出就返回 null = 跟随主题）。
  static CampusMapStyleKind? fromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final k in CampusMapStyleKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// 当前该用哪套风格：**手动优先，没手动过就跟主题**。
///
/// 单独抽成纯函数是为了能直接单测（不需要 pump 页面）。
CampusMapStyleKind resolveCampusMapStyle({
  required CampusMapStyleKind? manual,
  required Brightness platformBrightness,
}) {
  if (manual != null) return manual;
  return platformBrightness == Brightness.dark
      ? CampusMapStyleKind.dark
      : CampusMapStyleKind.light;
}
