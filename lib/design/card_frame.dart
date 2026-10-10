/// **卡片化的界面 chrome**：把一块区域框成「浮起的圆角卡片」。
///
/// 用户 2026-10-09 立项（侧栏视图下的内容卡片 / 侧栏卡片），参考实现 = 用户另一个项目
/// vshell（`.vsc-video-card` / `.vshell-sidebar`：圆角 + 1px 描边 + `surface` 底 +
/// `shadow-lg`，卡片四周留 `--vshell-card-gap`，见其 `styles/base.css:18`
/// `--vscode-shadow-lg: 0 0 12px rgba(0, 0, 0, 0.14)`）。
///
/// ⚠ **与 `app_card.dart` 的分工**（别把两者合并）：
/// - `app_card.dart` = **页面内的卡片语言** —— 全仓调用点最多，**明确不画阴影**，圆角 12。
///   它管的是「页面里的一张卡」。
/// - 本文件 = **界面 chrome 的卡片化** —— 只用于「把一块**区域**（侧栏 / 内容面板）
///   框成卡片」，带阴影（用户明确要求），并配有「卡片与窗口边缘之间那道缝」的口径。
///   页面内**不要**用它包内容：那是 `app_card.dart` 的活。
///
/// 两处的圆角与描边取值刻意同源（[kCardFrameRadius] = `kAppCardRadius`、
/// 描边走 `appCardBorderSide`），这样「区域卡」与「内容卡」是同一套语言。
///
/// **卡片底色由调用方自己铺**（本组件只画圆角 / 描边 / 阴影，不设底色）：
/// 侧栏本来就有底色（`surfaceContainerLow` → 卡片形态换成卡片色），内嵌页的
/// `Scaffold` 也自带底色 —— 再叠一层只会让「哪一层在画」变得难查。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';

import 'app_card.dart';

/// 卡片圆角（= 页面内卡片口径 `kAppCardRadius`）—— **只是默认值**。
///
/// 用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」→ 实际取值由调用方传进
/// [CardFrame.radius]（来自 `features/home/domain/home_card_radius.dart`，
/// 落盘在 `homePrefs` 的 `homeCardRadius`）。这里保留常量是为了：
/// ① 默认档 = 它与页面小卡同值（"同源"从"两处常量相等"变成"默认值相等"）；
/// ② 旧调用点 / 守卫仍可引用一个具名的"标准圆角"。
const double kCardFrameRadius = kAppCardRadius;

/// 卡片与**窗口边缘**之间那道缝（= vshell 的 `--vshell-card-gap`，默认 6）；
/// 同时也是两块之间那道缝的宽度（见 `home_screen.dart` 的 `_buildSidebarBody`）。
///
/// ⚠ **本常量已不是唯一出处**（2026-10-09 三轮）：用户要求「卡片与卡片之间的距离为
/// **a**、卡片与窗口之间的距离也是 **a**（十七轮修订），`a` 存在
/// `homePrefs` 的 `homeCardGap`，派生量由
/// `features/home/domain/home_card_gap.dart` 的 `cardGapMetricsOf` 算
/// （默认 `a = 6` → 卡片间距 12 / 窗口边距 6），页面侧走
/// `homeLayoutStoreProvider` 的 `cardGap`。
///
/// 这里保留的是**回退值**：`CardFrame` 不依赖 store（单测 / 别处单独用它时按这个）。
const double kCardFrameGap = kCardGapDefault;

/// 卡片阴影（浅色）——**两层**，值取自 Material 的 elevation 阴影那套规模
/// （`kElevationToShadow[6]` ≈ `alpha .14 blur 8` + `alpha .12 blur 3` / offset 3）。
///
/// ⚠ **不要把 vshell 的 CSS 值直接搬过来**（2026-10-09 实测）：vshell 是
/// `shadow-lg: 0 0 12px rgba(0,0,0,0.14)`，而在 Flutter 里 `alpha 0.14 + blur 12`
/// 渲染出来**逐像素测不到** —— 沿卡片外沿逐行采样全是 `#FFFFFF`（与无阴影完全一样），
/// 只在贴边 1~2 行蹭到 `#DBDBDB`。原因是高斯模糊把这点 alpha 摊到了约 19px 半径上：
/// 0.14 ÷ 19 ≈ **0.7% 的峰值强度**，比 1/255 大不了多少。
/// 所以这里给**两层**：一层小 blur + 低 offset 勾出边缘，一层大 blur 撑起扩散，
/// 峰值强度才够人眼（和 vshell 的 Flutter 侧重做同一个取舍）。
const List<BoxShadow> kCardFrameShadowsLight = <BoxShadow>[
  BoxShadow(color: Color(0x24000000), blurRadius: 3, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
];

/// 深色下的卡片阴影。
///
/// ⚠ 深色**不能照抄浅色的 alpha**：`#121212` 页面底上 14% 黑只掉 1 个亮度级
/// （深底吞阴影，与 `AppLadder` 注释里「深底吞淡色」同源）。这里抬到 **34%**，
/// 让缝里真的看得见一圈比页面底更暗的晕（实测 `#121212` → `#0D0D0D`）。
const List<BoxShadow> kCardFrameShadowsDark = <BoxShadow>[
  BoxShadow(color: Color(0x57000000), blurRadius: 4, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x3D000000), blurRadius: 14, offset: Offset(0, 4)),
];

/// 卡片描边（圆角 12 + 1px）——与页面内卡片**逐值同源**。
///
/// ⚠ 走 [appCardBorderSide] 而不是自己写一个中性灰：浅色是 `outlineVariant` 60%
/// （**暖灰**，§3「主题纯白」裁定只改白色系、文字与描边保持暖灰），深色是
/// `outlineVariant` 原值（10% 白）。自己写会在浅色下与全应用的卡片描边不是同一个颜色。
BoxBorder cardFrameBorder(BuildContext context) =>
    Border.all(color: appCardBorderSide(Theme.of(context).colorScheme).color);

/// 卡片阴影（按亮度取）。两层那套见 [kCardFrameShadowsLight] 的说明。
List<BoxShadow> cardFrameShadows(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? kCardFrameShadowsDark
    : kCardFrameShadowsLight;

/// 卡片背后那层**露出来的窗口背景**（= 标题栏色）。
///
/// 用户 2026-10-09 八轮原话：「我希望卡片后露出来的窗口背景色要与标题栏一致」。
///
/// 之前露的是**页面底**（`AppColors.page` = `scheme.surface`）：深色下页面底 `#121212`
/// 而标题栏 `#1A1A1A`，于是卡片四周能看到一圈**比标题栏更深**的带子（逐像素实测：
/// 暗色下缝里是 `#121212`、标题栏是 `#1A1A1A`），顶栏与侧栏的「视觉连续」被这圈带子
/// 打断。取标题栏色之后，卡片就是浮在「与顶栏同一片底」上。
///
/// ⚠ 浅色下标题栏本来就是 `#FFFFFF`，与卡片同色 —— 这一档**没有视觉变化**
/// （卡片仍只靠 1px 描边与阴影与背景分界）。这是浅色主题「纯白」口径的必然结果
/// （§3：`surface` 与 `surfaceContainerLowest` 都是纯白），不是这里实现漏了。
Color cardFrameBackdropColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
}

/// 卡片背后那层背景的容器（**恒返回同一个 `ColoredBox`**，没有卡片时透明）。
///
/// 由 `home_screen.dart` 的 `_buildSidebarBody` 包住整条 `Row`：侧栏左边、两块之间、
/// 内容区右边与底部那些缝全部落在这层上；卡片与内嵌页各自不透明，盖住中间部分。
///
/// ⚠ **不要在 `visible == false` 时直通 `child`、也不要换 key**
/// （2026-10-09 九轮 · 用户报的「改卡片样式后设置页跳回顶部」的第二个根因）：
/// `visible` 一变就**换组件类型**，内嵌页的视口跟着重建，`ListView` 的滚动位置归零
/// （逐帧实测 `pixels 1200 → 0`；把这一层去掉就不跳 —— 对照 D/E 钉死了这一点）。
/// 恒返回同一个 `ColoredBox` 之后，`color` 从透明到标题栏色只是一次普通 setState，
/// 元素原地复用。
class CardFrameBackdrop extends StatelessWidget {
  const CardFrameBackdrop({
    super.key,
    required this.visible,
    required this.child,
  });

  /// 是否有卡片（false = 透明，等于没铺）。
  final bool visible;

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: visible
        ? cardFrameBackdropColor(context)
        : const Color(0x00000000),
    child: child,
  );
}

/// 把 [child] 框成一张卡片：圆角 + 描边 + 阴影，内容按圆角裁掉。
///
/// - [card] = false 时**零包裹、零影响**（直接返回 [child]）——「都不显示为卡片」
///   那一档要求与改造前逐像素一致，所以关闭时必须不留下任何一层。
/// - **描边不会盖住内容**：`BoxDecoration` 与子件同为圆角 12，子件的圆角像素正好落在
///   描边带下方，不会出现「内容压住框线」的白边。
/// - 形态变化（设置页拨开关）是**补间**的（[duration]）：圆角 / 描边 / 阴影一起长出来，
///   外圈那道缝由调用方的 `AnimatedPadding` 负责（见 `home_screen.dart`）。
class CardFrame extends StatelessWidget {
  const CardFrame({
    super.key,
    required this.card,
    required this.child,
    this.radius = kCardFrameRadius,
    this.shadow = false,
  });

  /// 是否画成卡片；false = 原样返回 [child]。
  final bool card;

  /// 圆角大小（逻辑像素）。默认 [kCardFrameRadius]（= 页面小卡口径）；
  /// 设置页可调，取值见 `features/home/domain/home_card_radius.dart`。
  ///
  /// ⚠ 它**只影响圆角**：描边不随它变（圆角 0 时就是"直角卡片"）。
  final double radius;

  /// **要不要阴影**（用户 2026-10-10 三十六轮：「我希望侧边栏内容卡片的阴影是可选的」）。
  ///
  /// ⚠ **默认 `false`**（用户当面选定「默认没有阴影」）：卡片只靠 1px 描边与底色分界。
  /// 侧栏 / 内容区**各自一个开关**，取值见
  /// `features/home/domain/home_card_shadow.dart` 与 `HomeLayoutStore`。
  ///
  /// ⚠ 拨这个开关**只改 decoration**（元素原地复用）——不许换组件类型 / 换 key，
  /// 否则整棵子树重挂、内嵌页滚动归零（见 [build] 的教训）。
  final bool shadow;

  final Widget child;

  /// 卡片形态切换的时长（比页面转场略长一点，读起来才是「浮起来」）。
  static const Duration duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    // ⚠ **两种形态返回同一个组件类型、且调用方不许换 key**
    // （2026-10-09 九轮 · 用户报的「改卡片样式后设置页跳回顶部」的根因）：
    // 之前这里是 `if (!card) return child;`，调用方又挂了
    // `ValueKey(card ? 'Card…' : 'Plain…')` —— 换 key + 换组件类型 = **整棵子树重新
    // 挂载**，内嵌的设置页（以及它的 `ListView`）一起重建 → 滚动位置归零
    // （实测 `pixels 1386 → 0`）。现在只补间 decoration，元素原地复用。
    return _cardTween(
      context,
      card: card,
      radius: radius,
      shadow: shadow,
      child: child,
    );
  }
}

/// `CardFrame` 里那个画形状的 `Container` 的 Key（守卫按它取 decoration / clipBehavior）。
///
/// ⚠ 有这个 Key 才好断言：`CardFrame` 的子树里**不止一个 `Container`**
/// （补间层 `_CardTween` 自己也是 `StatefulWidget` → `Container` 链），
/// 用 `find.byType(Container)` 会 `Bad state: Too many elements`（实测踩过）。
const Key cardFrameContainerKey = Key('cardFrameContainer');

/// 卡片形态的 decoration（t = 1 的终态）：圆角 + 描边 +（可选）阴影。
///
/// [radius] 由 [CardFrame.radius] 传下来（设置页可调）；描边不随圆角变。
/// [shadow] 决定这一圈投影画不画（默认不画，见 [CardFrame.shadow]）。
BoxDecoration _cardDecoration(
  BuildContext context,
  double radius, {
  required bool shadow,
}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  border: cardFrameBorder(context),
  boxShadow: shadow ? cardFrameShadows(context) : null,
);

/// 「不是卡片」的占位 decoration：形状与终态一致，但圆角 0、无描边无阴影。
///
/// ⚠ 必须是**非 null** 的 decoration —— `Container` 在 `clipBehavior != none` 时要求
/// decoration 非 null（见 [CardFrame.build] 的注释）。
BoxDecoration _plainDecoration() =>
    BoxDecoration(borderRadius: BorderRadius.circular(0));

/// 在「不是卡片」与「是卡片」之间插值。
///
/// ⚠ 阴影那一段也走 `BoxDecoration.lerp` —— 开关拨过去是**淡入 / 淡出**的，
/// 不是"啪"地出现（与圆角 / 描边同一套观感）。
BoxDecoration _lerpCardDecoration(
  BuildContext context,
  double t,
  double radius, {
  required bool shadow,
}) => BoxDecoration.lerp(
  _plainDecoration(),
  _cardDecoration(context, radius, shadow: shadow),
  t,
)!;

/// [CardFrame] 的补间体：把 `card` 的有无补成 0→1。
///
/// 首帧取终值（不做动画）：`_CardTween` 是新建元素，`initState` 里
/// `value: card ? 1 : 0`，所以「一进来就是卡片」不会先闪一下再长出来；之后同一元素上
/// `card` 翻转才走动画（**元素复用 = 子树不重挂**，这正是修「设置页跳回顶部」的关键）。
///
/// ⚠ 为什么不用 `AnimatedContainer`：它**不许**「`clipBehavior != none` 且
/// `decoration == null`」（`container.dart` 的断言 `decoration != null ||
/// clipBehavior == none`，实测踩过）。所以自己驱动 controller，把 decoration 在
/// **透明占位**与**真实卡片**之间插值 —— 非 null 的占位 decoration 让裁剪合法，
/// 而 t = 0 时圆角 0 / 边与影全透明 = 与「没画卡片」逐像素等价。
///
/// ⚠ **改 `radius` 不走这个 tween**（拉滑杆时圆角是**立刻**变的，没有 220ms 补间）：
/// 这里只补间"是不是卡片"，圆角直接取当前值 —— 拖滑杆要的是即时反馈，
/// 每个刻度都补一次 220ms 反而糊。
Widget _cardTween(
  BuildContext context, {
  required bool card,
  required double radius,
  required bool shadow,
  required Widget child,
}) => _CardTween(
  card: card,
  child: child,
  builder: (context, t, child) {
    final effective = radius * t;
    return Container(
      key: cardFrameContainerKey,
      decoration: t >= 1
          ? _cardDecoration(context, radius, shadow: shadow)
          : _lerpCardDecoration(context, t, radius, shadow: shadow),
      // 不是卡片时圆角为 0，裁剪是空操作。
      clipBehavior: Clip.antiAlias,
      // ⚠⚠ **孩子要按「比外框小 1px」的圆角再裁一层**（用户 2026-10-09 二十轮：
      // 「在别的页面，右侧内容卡片圆角处框线断开，但是在"数据一览"页就不会」）。
      //
      // 成因：外框那层 `Clip` 与**孩子自己的不透明底**在圆角处**同一条抗锯齿边界**上
      // 各自混一次色 —— 内嵌服务页（`Scaffold` 自带不透明背景，四边铺满）的底色会把
      // 外框那 1px 弧线的**外侧一半**盖掉，弧线于是看着"断开"；而「数据一览」的内容
      // 自带 24px 左右内边距、铺不到边上，所以那边看着是好的。
      //
      // 治法：孩子**内缩 1px 半径**（即 `radius - 1`）—— 弧线内侧让出描边那一带的宽度，
      // 孩子的边再也压不到描边上。半径 ≤ 1 时退化成直角裁剪（那一档本来就看不出来）。
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          effective <= 1 ? 0 : effective - 1,
        ),
        child: child,
      ),
    );
  },
);

class _CardTween extends StatefulWidget {
  const _CardTween({
    required this.card,
    required this.builder,
    required this.child,
  });

  final bool card;
  final Widget child;
  final Widget Function(BuildContext context, double t, Widget? child) builder;

  @override
  State<_CardTween> createState() => _CardTweenState();
}

class _CardTweenState extends State<_CardTween>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: CardFrame.duration,
    value: widget.card ? 1 : 0,
  );
  late final Animation<double> _t = _c.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  @override
  void didUpdateWidget(_CardTween old) {
    super.didUpdateWidget(old);
    if (widget.card != old.card) {
      if (widget.card) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _t, builder: (context, child) {
        return widget.builder(context, _t.value, child);
      }, child: widget.child);
}
