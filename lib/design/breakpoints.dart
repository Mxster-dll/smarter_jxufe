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
}
