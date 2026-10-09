/// 侧栏视图的**卡片间距口径**（卡片↔卡片 = a、卡片↔窗口边 = a）。
///
/// 用户 2026-10-09 三轮原话：「我希望卡片与卡片之间的距离为 2a、卡片与窗口之间
/// （卡片与标题栏之间的距离不受此限制）的距离为 a；然后 a 可以通过设置调」；
/// **十七轮修订**：「我希望现在的卡片与卡片之间的间距不再是 2a，而是 a」——
/// 于是 `a` 一值管两处（见 [cardGapMetricsOf]）。
///
/// 纯逻辑、无 Flutter 依赖：`a` 的**阈值、解析、夹取、派生量**都只在这里算，
/// 页面与 `lib/design/card_frame.dart` 只做渲染（与 `home_layout.dart` /
/// `home_card_style.dart` 同一套路）。
///
/// ⚠ **标题栏那条不受限**：主体顶边与标题栏的距离恒为 0（`top: 0`）——
/// 留一条横幅空白比「卡片挨着标题栏」难看。所以 [CardGapMetrics.edge] 只作用于
/// 左 / 右 / 底三边。
library;

/// `a` 的默认值：**8**。
///
/// 历史：三轮时口径是「卡片间距 = 2a、窗口边距 = a」，为让卡片间距仍是改造前的 12
/// 而把默认取成 **6**；**十七轮**用户把口径改成「卡片间距**也是** a」（见
/// [cardGapMetricsOf]），于是 `a` 一值管两处，默认取 **6** 就显得太挤
/// （实心圆角卡片之间只剩 6px）→ 改成 **8**：
/// 既与十六轮的圆角默认（`FluentRadius.overlay` = 8）同值，读起来是「8 的栅格」，
/// 也正好等于 Fluent 那套里常用的 8px 间距档。
const double kCardGapDefault = 8;

/// `a` 的下限：2。再小卡片之间就只剩描边对描边（阴影没有落点，圆角也会重新黏成
/// 一张卡 —— 见 §44.2③ 那条实测）。
const double kCardGapMin = 2;

/// `a` 的上限：24。再大两块区域就被缝吃掉了。
const double kCardGapMax = 24;

/// `a` 的可选档位（设置页滑杆按它吸附）。
///
/// ⚠ **2026-10-09 十四轮改成「每个整数一格」**（用户：「我希望卡片间距可以调整的最小
/// 步长应该是 1，现在是 2」）：旧表是 `[2,3,4,6,8,10,12,16,20,24]`，滑杆却按
/// 「22 等分」画刻度 —— 于是拖到刻度 5 时被 [snapCardGap] 吸附到 **4 或 6**，
/// 用户看到的就是「步长 2」。现在表 = **2..24 的全部整数**，吸附是恒等映射。
///
/// ⚠ 别为了"整齐"再删中间档：那样滑杆的刻度与落盘值又会不一致（这正是上一版的 bug）。
const List<double> kCardGapStops = <double>[
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
];

/// 一套间距派生量（逻辑像素）。
typedef CardGapMetrics = ({double edge, double between, double gutter});

/// 由 `a` 算三处间距。
///
/// - [CardGapMetrics.edge] = **a** —— 卡片与窗口左 / 右 / 底边的距离；
/// - [CardGapMetrics.between] = **a** —— 卡片与卡片之间的距离（**十七轮起与 edge 同值**）；
/// - [CardGapMetrics.gutter] = 主体外围补的那一圈 = `edge + 阴影呼吸位`。
///
/// ⚠ **十七轮改口径**（用户：「我希望现在的卡片与卡片之间的间距不再是 2a，而是 a」）：
/// 三轮那一版是「卡片间距 = 2a」，为让间距仍是改造前的 12 而把默认取成 6；
/// 现在**一个 `a` 管两处**，读起来就是"卡片离窗口和离邻居一样远"。
/// 于是默认值也跟着从 6 抬到 8（见 [kCardGapDefault]）——6 在实心圆角卡之间太挤。
/// `between` 这个字段**保留**（不删）：它是页面的取值点，删了要改三处调用；
/// 而且以后若再要"间距 ≠ 边距"的档位，改回 `edge * k` 一处即可。
///
/// ⚠ **`gutter` 为什么比 `edge` 大**：卡片阴影的模糊半径约 9px（两层里的
/// `.12 / blur 12`），若外圈留白正好等于 `edge`，阴影在**窗口边被裁掉**是一回事，
/// 更糟的是当 `edge` 小到 2~6 时缝里会既没有边距也没有影子落点 —— 卡片看着像
/// 直接贴在窗口边上。补到至少 [shadowRoom] 之后再留 `edge`，`a` 才有「调小也好看」
/// 的自由度；卡片与窗口的**可见**距离仍然是 `edge`。
CardGapMetrics cardGapMetricsOf(double a) {
  final edge = clampCardGap(a);
  return (
    edge: edge,
    between: edge,
    gutter: edge + _shadowRoom,
  );
}

/// 阴影呼吸位（逻辑像素）：`gutter` 至少要留出这么多，阴影才落得下。
const double _shadowRoom = 8;

/// 把任意输入夹进 [kCardGapMin] ~ [kCardGapMax]（NaN / 无穷 → 默认值）。
double clampCardGap(double value) {
  if (value.isNaN || value.isInfinite) return kCardGapDefault;
  return value.clamp(kCardGapMin, kCardGapMax).toDouble();
}

/// 把 `a` 吸附到最近的 [kCardGapStops]（设置页滑杆用；越界先夹取）。
///
/// ⚠ 十四轮起档位表 = **2..24 全部整数（23 格）**，而滑杆的 `divisions` = 22 **段**
/// → 23 个刻度、每段 1 → 本函数在现行口径下是**恒等映射**（夹取之外不改值）。
/// 保留它是因为：① 它是"落盘值一定落在允许集合里"的那道保险；② 以后若要重新引入
/// 稀疏档位，改这里一处即可。**别把 `divisions` 与本表拆成两套口径** —— 那正是
/// 「步长看起来是 2」那个 bug 的成因（见 [kCardGapStops] 的注释）。
///
/// 正好落在两档中点时取**较小**那档（`<` 而不是 `<=`）——「x.5 → x」比「x.5 → x+1」
/// 更符合「往小调」的直觉，也让结果可预测（不依赖档位表里的先后顺序）。
double snapCardGap(double value) {
  final clamped = clampCardGap(value);
  var best = kCardGapStops.first;
  var bestDelta = (clamped - best).abs();
  for (final stop in kCardGapStops.skip(1)) {
    final delta = (clamped - stop).abs();
    if (delta < bestDelta) {
      best = stop;
      bestDelta = delta;
    }
  }
  return best;
}

/// 落盘文本（十进制整数——档位都是整数，写成 `6` 而不是 `6.0`）。
String formatCardGap(double a) => clampCardGap(a).round().toString();

/// 从落盘文本还原（缺省 / 脏值 / 越界一律回落 [kCardGapDefault] 或夹回范围内）。
double parseCardGap(String? raw) {
  if (raw == null) return kCardGapDefault;
  final parsed = double.tryParse(raw.trim());
  if (parsed == null) return kCardGapDefault;
  return clampCardGap(parsed);
}
