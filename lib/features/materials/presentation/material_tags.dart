import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 材料卡上的属性胶囊（用户 2026-09-18 裁定）。
///
/// 原话：「底部的国家级/省级、一二三等奖 I/II/III/IV 类赛的颜色也不用那么浅，
/// 并且按不同类别属性，要显示为不同色的胶囊」→ 原来那一行是 `scheme.outline`
/// 的**浅灰纯文本**，现在按属性分色做成胶囊：
/// - **类别**（Ⅰ/Ⅱ/Ⅲ/Ⅳ 类赛）= [materialCategoryColor]（红 / 橙 / 蓝 / 青）；
/// - **级别**（国家级 / 省级 / 市（校）级 / 院级 / 班级）= [materialAttributeColor]；
/// - **奖项**（一等 / 二等 / 三等 / 优胜 / 优秀…）= [materialAttributeColor]；
/// - **类型**（学科竞赛 / 论文…）= [materialTypeColor]（中性墨蓝）。
///
/// 颜色只给**浅色值**，深色由 [AppColors.tone] 提亮、底色由
/// [AppColors.statusFill] 出（与全站深色口径一致，见 AGENTS §22）。
const Color materialTypeColor = Color(0xFF455A64);

/// Ⅰ~Ⅳ 类赛配色（key = `ZcMaterial.cat`，即 `zcCatNames` 的 c1~c4）。
const Map<String, Color> materialCategoryColors = <String, Color>{
  'c1': Color(0xFFB3261E), // Ⅰ类：深红
  'c2': Color(0xFFE65100), // Ⅱ类：橙
  'c3': Color(0xFF1565C0), // Ⅲ类：蓝
  'c4': Color(0xFF00695C), // Ⅳ类：青
};

/// 属性文字 → 颜色（级别优先，其次奖项；都不中 = 中性）。
///
/// ⚠ 判词顺序有意义：`国家级` 含「国」、`一等奖` 含「一」，两边关键词不重叠，
/// 但「省级一等奖」这类合并串会先命中「省」→ 归级别色（级别更粗粒度，合理）。
Color materialAttributeColor(String text) {
  final t = text.trim();
  if (t.isEmpty) return materialTypeColor;
  // 级别
  if (t.contains('国家') || t.contains('全国')) return const Color(0xFFB3261E);
  if (t.contains('省') || t.contains('部')) return const Color(0xFFE65100);
  if (t.contains('市') || t.contains('校')) return const Color(0xFF1565C0);
  if (t.contains('院')) return const Color(0xFF00695C);
  if (t.contains('班')) return const Color(0xFF6A1B9A);
  // 奖项
  if (t.contains('特等') || t.contains('一等') || t.contains('金奖')) {
    return const Color(0xFFB8860B);
  }
  if (t.contains('二等') || t.contains('银奖')) return const Color(0xFF607D8B);
  if (t.contains('三等') || t.contains('铜奖')) return const Color(0xFF8D6E63);
  if (t.contains('优胜') || t.contains('优秀')) return const Color(0xFF00838F);
  if (t.contains('未获奖') || t.contains('合格')) return const Color(0xFF757575);
  return materialTypeColor;
}

/// `cat` → 类别色。
Color materialCategoryColor(String cat) =>
    materialCategoryColors[cat] ?? materialTypeColor;

/// 档位/级别文案去掉「（x 分）」之类的后缀 → 胶囊里只留短名。
String materialLevelShort(String raw) {
  var t = raw.trim();
  for (final sep in const ['（', '(']) {
    final i = t.indexOf(sep);
    if (i > 0) t = t.substring(0, i);
  }
  return t.trim();
}

/// 级别 / 奖项两枚胶囊（外语这类「级别列 = 证书档位」的类型只出一枚档位胶囊）。
List<Widget> materialLevelTags(BuildContext context, ZcMaterial m) {
  final spec = m.spec;
  final out = <Widget>[];
  if (spec.id == ZcTypeId.foreign) {
    // 材料库只登记事实：外语出**原始成绩**一枚胶囊（`489`），不出
    // `大学英语四级 489 → 1 分` 这种综测口径的换算文案（用户 2026-09-18：
    // 「材料库不是综测的材料库……直接显示『489』就可以了」）。
    // 等级类证书 / 没填分 → 没有可显示的成绩，这一枚不出现（标题已写证书名）。
    final raw = zcForeignRawScoreText(m.manualScore);
    if (raw.isNotEmpty) {
      out.add(MaterialTag(text: raw, color: const Color(0xFF00838F)));
    }
    return out;
  }
  final lvl = spec.levels.isNotEmpty && m.level >= 0 && m.level < spec.levels.length
      ? materialLevelShort(spec.levels[m.level])
      : '';
  if (lvl.isNotEmpty) {
    out.add(MaterialTag(text: lvl, color: materialAttributeColor(lvl)));
  }
  final opt = spec.opts.isNotEmpty && m.opt >= 0 && m.opt < spec.opts.length
      ? spec.opts[m.opt].trim()
      : '';
  if (opt.isNotEmpty) {
    out.add(MaterialTag(text: opt, color: materialAttributeColor(opt)));
  }
  return out;
}

/// 属性胶囊：深色文字 + 同色底 + 同色描边（浅色下也不再是浅灰）。
class MaterialTag extends StatelessWidget {
  const MaterialTag({
    super.key,
    required this.text,
    required this.color,
    this.dense = true,
  });

  final String text;

  /// **浅色值**（深色模式内部自行提亮）。
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.tone(context, color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusFill(context, color),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.38), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
