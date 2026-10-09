/// 侧栏视图下的**卡片形态**口径（侧栏 / 内容区各自可以是一张圆角卡片）。
///
/// 用户 2026-10-09 二轮原话：「我希望 内容区一个卡片、侧栏一个卡片，然后都是在设置了
/// 可选的。可以都不显示为卡片样式」+「要阴影」。
///
/// 参考实现 = 用户另一个项目 vshell 的侧栏/内容卡片（`vshell/src/styles/components.css`
/// 的 `.vshell-sidebar`：`cornerRadius-large` + 1px 描边 + `surface` 底 + `shadow-lg`，
/// 四周留 `--vshell-card-gap`）。形状与留白口径落在 `lib/design/card_frame.dart`。
///
/// 纯逻辑、无 Flutter 依赖：**什么组合画成卡片**只在这里判定，页面只做渲染
/// （与 `home_layout.dart` 同一套路）。
library;

/// 侧栏视图的卡片形态（四个取值 = 两块区域选或不选的四种组合）。
///
/// **默认 [none]**：不开卡片时与从前几乎逐像素一致（侧栏 `surfaceContainerLow` 通栏 +
/// 右栏直接铺满），老用户升级后观感不变。
///
/// ⚠ 2026-10-09 十三轮起，两块之间那道 1px 分割线**已撤掉**（用户：「侧边栏不要有
/// 边框线」）—— 现在靠**底色差**分界（侧栏是另一档底色）。这一档与改造前的差异
/// **只有这一条线**，别再按"逐像素一致"去写断言。
enum HomeCardStyle {
  /// 两块都不是卡片（默认，= 改造前的观感）。
  none('都不显示', '侧栏与内容区都通栏平铺（默认，与旧版一致）'),

  /// 只有左侧导航栏是卡片。
  sidebar('仅侧栏', '左侧导航栏浮起成一张圆角卡片，内容区仍平铺'),

  /// 只有内容区是卡片。
  content('仅内容区', '右侧内容区浮起成一张圆角卡片，侧栏仍通栏'),

  /// 两块各自一张卡片（用户给的参考形态）。
  both('侧栏 + 内容区', '两块各浮起一张卡片，中间留一道缝（推荐）');

  const HomeCardStyle(this.label, this.description);

  /// 设置页里的选项名。
  final String label;

  /// 设置页里的说明文案。
  final String description;

  /// 从落盘字符串还原（未知值 / null → [none]，旧数据不会导致崩溃）。
  static HomeCardStyle fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return HomeCardStyle.none;
  }

  /// 左侧导航栏是否画成卡片。
  bool get sidebarIsCard =>
      this == HomeCardStyle.sidebar || this == HomeCardStyle.both;

  /// 右侧内容区是否画成卡片。
  bool get contentIsCard =>
      this == HomeCardStyle.content || this == HomeCardStyle.both;

  /// 是否有任何一块是卡片（决定要不要在主体外围留出「卡片间距」）。
  bool get anyCard => sidebarIsCard || contentIsCard;
}
