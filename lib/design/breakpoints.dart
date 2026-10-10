/// 响应式断点 —— **唯一出处**（2026-09-20 · 架构审查 ⑤-B）。
///
/// 审计前的写法是各页各写数字（`constraints.maxWidth < 600` / `< 400` / `>= 720` /
/// `>= 1000`），看代码时无法判断「600 是同一个约定还是碰巧」。
///
/// ⚠ 断点是**布局约定**不是设计 token：新增之前先看这里有没有能用的档位，
/// 不要为了一处布局新开一个数字。
library;

abstract final class Breakpoints {
  Breakpoints._();

  /// 窄屏：约束宽 < 它 → 单列 / 紧凑布局（成绩、培养方案、学籍、登录判移动端）。
  static const double narrow = 600;

  /// 极窄：卡片内两列再切一列（成绩页统计卡）。
  static const double tight = 400;

  /// 宽屏：左右分栏（毕业学分要求）。
  static const double wide = 720;

  /// 超宽：目录 + 正文两栏（规章制度阅读器）。
  static const double extraWide = 1000;

  /// 宫格 ⇄ 侧栏的分界（宽 ≥ 它才是「桌面侧栏布局」，窄于它就是手机那种形态）。
  ///
  /// ⚠ 与 `features/home/domain/home_layout.dart` 里决定侧栏布局的那个 900 **同值** ——
  /// 那边是页面布局、这里是 chrome（见 `pane_chrome.dart` 的顶栏动作簇排布），
  /// 用户看到的必须是同一个「宽 / 窄」：拖窄到手机上那种形态时，顶栏也要跟着换成
  /// 手机端那套排布（用户 2026-10-10：「电脑端窄屏显示时，也要使用和移动端一样的策略，
  /// 而不是把这个显示逻辑只影响移动端」）。改一处要一起改。
  static const double sidebarLayout = 900;
}
