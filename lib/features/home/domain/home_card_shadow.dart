/// 侧栏视图里两张**区域卡片**的**阴影开关**口径（侧栏一个、内容区一个）。
///
/// 用户 2026-10-10 三十六轮：「我希望侧边栏内容卡片的阴影是可选的」；
/// 当面选定：**两块各自一个开关**、**默认没有阴影**。
///
/// 历史：2026-10-09 二轮用户要求卡片「要阴影」，于是 `CardFrame` 一直无条件画那两层
/// 投影（`kCardFrameShadowsLight` / `Dark`）；本轮把它变成可选，默认关。
///
/// 纯逻辑、无 Flutter 依赖：**阴影的取值与默认值只在这里判定**，渲染侧只读开关
/// （与 `home_card_style.dart` / `home_card_gap.dart` 同一套路）。
library;

/// 区域卡片阴影的**默认值** —— 用户 2026-10-10 当面选定「默认没有阴影」。
///
/// ⚠ 改这个常量 = 老用户升级后观感立刻变（卡片从"浮起"变成只靠 1px 描边分界）。
/// 这是一次**有意**的默认值变更，不是漏迁移（本仓纪律：改默认值只改常量、不许写迁移，
/// 见 `home_layout_prefs.dart` 的说明）。
const bool kCardShadowDefault = false;

/// 侧栏那张卡的阴影开关（落盘 key 见 `home_layout_prefs.dart`）。
///
/// 这些是**读取侧**的语义封装：开关为 off 时 `CardFrame` 的 `boxShadow` 为 null，
/// 圆角与描边照旧（阴影只是那一圈投影，关掉不影响卡片的形状）。
enum HomeCardShadowTarget {
  /// 左侧导航栏那张卡。
  sidebar('侧栏卡片', '左侧导航栏那张卡的投影'),

  /// 右侧内容区那张卡。
  content('内容卡片', '右侧内容区的投影');

  const HomeCardShadowTarget(this.label, this.description);

  /// 设置页里的选项名。
  final String label;

  /// 设置页里的说明文案。
  final String description;
}
