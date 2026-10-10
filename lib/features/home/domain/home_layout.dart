/// 主页布局口径（宫格视图 / 左侧导航栏视图）。
///
/// 用户 2026-09-15 裁定：「电脑端主页可选宫格视图与左侧导航栏视图」，
/// 切换入口**只在设置页**、选择**记住**（落 Hive，见 `data/home_layout_prefs.dart`）。
///
/// 纯逻辑、无 Flutter 依赖 —— 判定集中在这里，页面只做渲染，
/// 免得「什么宽度、什么平台用侧栏」散在 build 里各写一遍。
library;

/// 主页布局形态。
enum HomeLayout {
  /// 图标磁贴铺满页面（手机端与窄窗口的唯一形态）。
  grid('宫格视图', '图标磁贴铺满页面，适合一览全部功能'),

  /// 左侧固定导航栏 + 右侧数据区（仅电脑端宽窗口生效）。
  sidebar('左侧导航栏', '左侧按分组列出全部服务，右侧显示数据一览');

  const HomeLayout(this.label, this.description);

  /// 设置页里的选项名。
  final String label;

  /// 设置页里的说明文案。
  final String description;

  /// 从落盘字符串还原（未知值 / null → 宫格，旧数据不会导致崩溃）。
  static HomeLayout fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return HomeLayout.grid;
  }
}

/// 侧栏布局的最小可用宽度：窄于它（或非桌面平台）一律回落到宫格。
///
/// **2026-10-10 由 900 降到 600**（用户裁定「B」：把「页面宫格⇄侧栏」与「顶栏宽⇄窄」
/// 两条线合成一条 ✓，此前 900/600 两段各变一次、用户看到的是两次形态切换 ✗）。
/// 判据仍是「侧栏 232 + 内容区」够不够用：600 时内容区 368，卡片退成单列但可用；
/// **挤的问题由 [homeSidebarAutoCollapseWidth] 那条线解决** —— 600~900 之间侧栏在、
/// 但自动收成 40 宽的窄轨，把地方让给内容。
const double homeSidebarMinWidth = 600;

/// 侧栏**自动收起**的宽度线：可用宽度窄于它时，侧栏自动收成窄轨（40 宽）。
///
/// 用户 2026-10-10：「加一个在 900 时，侧边栏自动收起的设置项，默认开启」——
/// 开关落在设置页「主页布局」卡里（`autoCollapseSidebar`，默认 true）。
/// **只在「跨过这条线」的那一刻收一次**：用户随后手动展开仍然算数（不会被反复按住），
/// 否则窄窗口里想看一眼完整侧栏都做不到 ✗。
const double homeSidebarAutoCollapseWidth = 900;

/// 侧栏宽度（内容区 = 窗口宽 − 232 − 1px 分隔线）。
const double homeSidebarWidth = 232;

/// 是否采用左侧导航栏布局。
///
/// 三个条件同时满足才用侧栏：用户在设置页选了侧栏、当前是桌面平台、
/// 可用宽度 ≥ [homeSidebarMinWidth]。任一不满足 → 宫格（手机端永远宫格）。
bool homeUsesSidebarLayout({
  required HomeLayout layout,
  required bool desktop,
  required double width,
}) =>
    layout == HomeLayout.sidebar && desktop && width >= homeSidebarMinWidth;

/// 平台名 → 是否桌面（windows / macOS / linux）。
bool homeDesktopPlatform(String platformName) {
  switch (platformName.toLowerCase()) {
    case 'windows':
    case 'macos':
    case 'linux':
      return true;
    default:
      return false;
  }
}


