/// 填表助手 · **zc 层**（顶层函数，2026-10-09 架构审计第四轮）。
///
/// 拆分自 `fill_form_data.dart`（1061 行 = 1 个模型 + 39 个顶层函数）：
/// 依赖实测为**有向无环** —— `values`(编排) → `prose`(行文) → `zc`(取数) → `ffNum`(叶子)。
/// 桶文件 `fill_form_data.dart` 既 import（自己用）又 export 本文件，**调用点零改动**。
library;

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'fill_form_data.dart';

String ffDimName(String dim) => ffDimNames[dim] ?? '';

/// 从「德育民主评议分 / 德育基础分 / 班级评议德育等次」里认出是哪一育。
String? ffDimOf(String t) {
  if (t.isEmpty) return null;
  for (final e in ffDimNames.entries) {
    if (t.startsWith(e.value)) return e.key;
  }
  // 「班级评议德育等次」这类中间带育名的写法。
  for (final e in ffDimNames.entries) {
    if (t.contains(e.value)) return e.key;
  }
  return null;
}

double ffDetailSum(ZcCalcResult r, String prefix) {
  var s = 0.0;
  for (final d in r.details) {
    if (d.label.startsWith(prefix)) s += d.value;
  }
  return s;
}

double ffDimTotal(ZcCalcResult r, String dim) {
  switch (dim) {
    case 'd':
      return r.deyu;
    case 'z':
      return r.zhiyu;
    case 't':
      return r.tiyu;
    case 'm':
      return r.meiyu;
    default:
      return r.laoyu;
  }
}

ZcGrade ffDimGrade(ZcCalcResult r, String dim) {
  switch (dim) {
    case 'd':
      return r.gD;
    case 'z':
      return r.gZ;
    case 't':
      return r.gT;
    case 'm':
      return r.gM;
    default:
      return r.gL;
  }
}

/// 该育**实际计入**的附加分（= 总分 − 基础分 − 民主评议 + 扣分）。
///
/// ⚠ 不能把 details 里那几行直接相加：父级还有封顶（附加合计 20 / 荣誉合计 10 /
/// 思想教育参与度 2，见 `zc_engine.dart` 的注释），相加会偏大。
double ffAddedScore(ZcCalcResult r, ZcManual m, String dim) {
  final kou = -ffDetailSum(r, '${ffDimName(dim)} · 扣分'); // 扣分在 details 里是负值
  switch (dim) {
    case 'd':
      return r.deyu - 60 - ffDetailSum(r, '德育 · 民主评议') + kou;
    case 'm':
      return r.meiyu - 60 - ffDetailSum(r, '美育 · 民主评议') + kou;
    case 'l':
      return r.laoyu - 60 - ffDetailSum(r, '劳育 · 民主评议') + kou;
    case 'z':
      return r.zhiyu - r.weightUsed + kou;
    case 't':
      final base = m.tMian ? 60.0 : m.tScore;
      return r.tiyu - base + kou;
  }
  return 0;
}

/// 「加、减分项目」那一格的文字：逐条列出该育的加减分。
String? ffAddSubtractText(ZcCalcResult r, String dim) {
  final skip = {
    '基础分',
    '民主评议',
    '加权成绩',
    '体测',
    '加权缺失（需填/需登录）',
  };
  final out = <String>[];
  for (final d in r.details) {
    final prefix = '${ffDimName(dim)} · ';
    if (!d.label.startsWith(prefix)) continue;
    final short = d.label.substring(prefix.length);
    if (skip.contains(short)) continue;
    if (d.value == 0) continue;
    final sign = d.value > 0 ? '+' : '−';
    out.add('$short $sign${ffNum(d.value.abs())}');
  }
  return out.isEmpty ? '无' : out.join('；');
}

// ---------------------------------------------------------------------------
// 材料
// ---------------------------------------------------------------------------

double? ffMaterialTotal(List<ZcMaterial> mats) {
  var s = 0.0;
  var any = false;
  for (final m in mats) {
    final v = zcMaterialValue(m);
    if (v == null) continue;
    s += v;
    any = true;
  }
  return any ? s : null;
}

List<ZcMaterial> ffByType(FillFormData d, Iterable<ZcTypeId> ids, {bool all = false}) {
  final src = all ? d.allMaterials : d.materials;
  return [
    for (final m in src)
      if (ids.contains(m.typeId)) m,
  ];
}

/// 「国一」「省二」这种级别+奖次的短文案（也用于统计「国家级一等奖 N 项」）。
String ffAwardText(ZcMaterial m) {
  final spec = m.spec;
  final level = m.level >= 0 && m.level < spec.levels.length
      ? spec.levels[m.level]
      : '';
  final opt = m.opt >= 0 && m.opt < spec.opts.length ? spec.opts[m.opt] : '';
  return '$level$opt';
}

/// 把材料按「级别 → 条目」归拢成计数，用于「国家级一等奖 1 项」这类概述。
String ffAwardSummary(List<ZcMaterial> mats, {int keep = 3}) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final m in mats) {
    final key = ffAwardText(m);
    if (key.trim().isEmpty) continue;
    if (!counts.containsKey(key)) order.add(key);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (order.isEmpty) return '';
  // 级别高的排前面（国家级 > 省级 > 校级）。
  order.sort((a, b) {
    int rank(String s) {
      if (s.startsWith('国家')) return 0;
      if (s.startsWith('省')) return 1;
      if (s.startsWith('市')) return 2;
      if (s.startsWith('校')) return 3;
      if (s.startsWith('院')) return 4;
      return 5;
    }

    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.compareTo(b);
  });
  return order
      .take(keep)
      .map((k) => counts[k]! > 1 ? '$k ${counts[k]} 项' : '$k 1 项')
      .join('、');
}

/// 材料名 + 年份（「国家奖学金（2025年）」）。
String ffNamedWithYear(ZcMaterial m) {
  final year = m.date?.year;
  final name = m.displayName;
  return year == null ? name : '$name（$year年）';
}
