/// 侧栏视图的**卡片圆角口径**（用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」；
/// 十六轮：「卡片圆角样式我希望与毕业学分页的卡片圆角样式相同」）。
///
/// 管的是**区域级卡片**（`lib/design/card_frame.dart` 框住的侧栏 / 内容面板）的圆角，
/// 与页面内小卡的全局契约 `kAppCardRadius`（`lib/design/app_card.dart`，恒 12）**分工不同**：
/// 那个是全应用每一张卡的形状语言，这里是「区域卡片」这一档可调的外观参数。
/// **默认值跟的是毕业学分页那套 Fluent 卡片**（见 [kCardRadiusDefault]）。
///
/// 纯逻辑、无 Flutter 依赖：阈值、解析、夹取都只在这里算
/// （与 `home_card_gap.dart` / `home_card_style.dart` 同一套路）。
library;

import 'package:smarter_jxufe/design/fluent/fluent_tokens.dart';

/// 圆角默认值 = **毕业学分页那套 Fluent 卡片的圆角**（`FluentRadius.overlay` = 8）。
///
/// 用户 2026-10-09 十六轮：「卡片圆角样式我希望与毕业学分页的卡片圆角样式相同」。
/// 毕业学分页的卡片全部是 `FluentCard`，它的默认圆角就是 `FluentRadius.overlay`（8）
/// —— 所以这里**直接引用那个常量**（而不是抄一个 8）：
/// 以后 Fluent 那档圆角若改，这里跟着走，两边不会再漂（`test/home_card_style_test.dart`
/// 有一条断言把这件事钉住）。
///
/// ⚠ 历史：十五轮时默认值取的是 `kAppCardRadius`（12，页面内小卡口径）。
/// 十六轮按用户口径改成 Fluent 卡片那一档 —— 于是**已经落盘过 12 的用户不会自动变**
/// （他们显式调过/或存过默认值），要回到新默认按一下「恢复默认」即可。
const double kCardRadiusDefault = FluentRadius.overlay;

/// 圆角下限：**0**（允许直角）。
///
/// 允许 0 是有意的：用户要的是"可控"，而 0 恰好给出「纯色块 + 阴影」那种现代观感
/// （与 `kCardFrameShadows*` 搭配仍然成立 —— 阴影不吃圆角）。
const double kCardRadiusMin = 0;

/// 圆角上限：28（再大两块区域的角就开始"吃掉"侧栏顶部那枚按钮的留白）。
const double kCardRadiusMax = 28;

/// 圆角的可选档位：**0..28 每个整数**（步长 1，与间距同口径）。
///
/// ⚠ 与 [kCardGapStops] 同一条教训（2026-10-09 十四轮）：**滑杆的 `divisions` 是段数、
/// 这张表是刻度数**，两者必须一致 —— 滑杆每格 1、档位表却稀疏的话，用户会看到
/// 「步长不是 1」（间距那一轮就是这么来的）。所以这里直接铺满。
const List<double> kCardRadiusStops = <double>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
];

/// 把任意输入夹进 [kCardRadiusMin] ~ [kCardRadiusMax]（NaN / 无穷 → 默认值）。
double clampCardRadius(double value) {
  if (value.isNaN || value.isInfinite) return kCardRadiusDefault;
  return value.clamp(kCardRadiusMin, kCardRadiusMax).toDouble();
}

/// 把圆角吸附到最近的 [kCardRadiusStops]（设置页滑杆用；越界先夹取）。
///
/// 现行档位表 = 每个整数，滑杆也是每格 1 → 本函数实际上只是**夹取**（恒等映射）。
/// 保留它当"落盘值一定在允许集合里"的保险，与 [snapCardGap] 同一口径。
double snapCardRadius(double value) {
  final clamped = clampCardRadius(value);
  var best = kCardRadiusStops.first;
  var bestDelta = (clamped - best).abs();
  for (final stop in kCardRadiusStops.skip(1)) {
    final delta = (clamped - stop).abs();
    if (delta < bestDelta) {
      best = stop;
      bestDelta = delta;
    }
  }
  return best;
}

/// 落盘文本（十进制整数 —— 档位都是整数，写成 `12` 而不是 `12.0`）。
String formatCardRadius(double value) => clampCardRadius(value).round().toString();

/// 从落盘文本还原（缺省 / 脏值 / 越界一律回落 [kCardRadiusDefault] 或夹回范围内）。
double parseCardRadius(String? raw) {
  if (raw == null) return kCardRadiusDefault;
  final parsed = double.tryParse(raw.trim());
  if (parsed == null) return kCardRadiusDefault;
  return clampCardRadius(parsed);
}
