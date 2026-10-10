/// 侧栏（左侧导航栏）视图下的**页面 chrome 口径**。
///
/// 用户 2026-09-16 裁定：**侧栏模式下每个服务页自己的导航栏一律不画**——侧栏已经
/// 高亮当前服务，再写一遍服务名是重复信息，还白占 56px。原先放在导航栏里的按钮
/// **下沉到页面内容顶部**（右对齐一行），面板顶部不留任何横向 chrome。
///
/// 两个判定（`build` 期求值，不要缓存）：
/// - [paneEmbedded]：本页是否被内嵌在侧栏右侧面板里（`HomeDetailPane` 注入 [PaneScope]）；
/// - [paneIsRoot]：且是**面板的首路由**（= 真正的服务主页）。
///
/// 面板内压栈的二级页（成绩 → 课程详情、材料库 → 编辑…）**保持原样**：它们要标题、
/// 要返回键，而且整块盖住面板，不会与任何东西叠成两条栏。这条同时兜住了
/// 「服务页被当作二级页再打开一次」的情形（那时 `canPop() == true`，导航栏照旧在，
/// 不会出现回不去的页面）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/breakpoints.dart';

import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/design/settings_entry.dart';

/// 标记「本子树位于侧栏右侧面板内」。由 `HomeDetailPane` 在面板 Navigator **之上**注入，
/// 因此面板内所有路由（含二级页）都能查到。
class PaneScope extends InheritedWidget {
  /// 是否内嵌在面板里。宫格视图（整页 push）恒为 false。
  final bool embedded;

  /// **本面板就是侧栏视图右栏的那一个**（`home_screen._paneSwitcher` 建的那个）。
  ///
  /// ⚠ 为什么要单独标出来（用户 2026-10-10 二十六轮：「点击主页卡片后的效果还是不对，
  /// 顶部不应该显示标题栏」）：
  ///
  /// 右栏那一格「数据一览」概览现在是**面板的首路由**（§44.1.18），从它点卡片是往同一个
  /// Navigator 上**压第二层**。而 [paneIsRoot] 的判据原本是「`canPop() == false`」，
  /// 压了第二层之后就不再成立 → [paneAppBar] 照常画出一条完整导航栏 + 返回键。
  ///
  /// 但**右栏这一格**和"在内嵌服务页里再进二级页"（成绩 → 课程详情，那时候有返回键是对的）
  /// 不是一回事：右栏本身就是"在侧栏视图里看某一格"，用户要的是**内容铺满、没有顶部条**。
  /// 所以这一格上的**任何**路由都算"面板首路由"（都不画导航栏）。
  ///
  /// 其余调用点（单独的 `HomeDetailPane`、内嵌服务页里的二级页）**不传**，保持原判据。
  final bool sidebarPane;

  /// **侧栏右栏这一格的"宿主回调"**（只有 [sidebarPane] 为 true 时给）。
  ///
  /// 收到「要把某一页开在右栏」的请求时调它（参数 = 侧栏目录里的条目名）。
  /// ⚠ 为什么不让页面自己 `Navigator.push`（用户 2026-10-10 二十七轮：
  /// 「点击数据一览的卡片后，顶部路由不记录」）：面板内部那个 Navigator 的压栈
  /// **绕不过宿主的记账** —— 顶部的全局路由历史是在 `home_screen._select` /
  /// `_recordPaneHistory` 里记的，直接 push 只是"栈里多一层"，历史里什么都不留，
  /// 于是前进/后退按钮对这一段完全瞎。所以改成回调宿主，由它走**和点侧栏同一套**通道。
  final void Function(String entryTitle)? sidebarHost;

  const PaneScope({
    super.key,
    required this.embedded,
    this.sidebarPane = false,
    this.sidebarHost,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>()?.embedded ??
      false;

  /// 最近的这一层是不是"侧栏右栏那个面板"。
  static bool isSidebarPaneOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>()?.sidebarPane ??
      false;

  /// 最近的"侧栏右栏宿主回调"（宫格视图 / 独立面板：null）。
  static void Function(String entryTitle)? sidebarHostOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>()?.sidebarHost;

  @override
  bool updateShouldNotify(PaneScope oldWidget) =>
      oldWidget.embedded != embedded ||
      oldWidget.sidebarPane != sidebarPane ||
      oldWidget.sidebarHost != sidebarHost;
}

/// 本页是否被内嵌在侧栏右侧面板里。
bool paneEmbedded(BuildContext context) => PaneScope.of(context);

/// 本页是不是面板的**首路由**（内嵌的服务主页）。
///
/// false = 整页模式（宫格 push / 独立页面），或面板内的二级页 —— 两种情况都照旧画
/// 完整导航栏。
///
/// ⚠ **侧栏右栏那一格是特例**：它是 `home_screen` 建的 [PaneScope.sidebarPane]，
/// **不管栈里有几层都算"首路由"**（见那个字段的注释：从概览点卡片会压第二层，
/// 但用户要的是内容铺满、没有顶部条）。
bool paneIsRoot(BuildContext context) {
  if (!paneEmbedded(context)) return false;
  if (PaneScope.isSidebarPaneOf(context)) return true;
  return !Navigator.of(context).canPop();
}

/// 服务页导航栏的**唯一入口**：整页模式照旧返回真 [AppBar]，内嵌服务主页返回 `null`
/// （`Scaffold.appBar` 接受 null → 整条栏不画）。
///
/// 参数与 [AppBar] 同名同义，**一律原样透传**：可空参数保持可空（不要给
/// `centerTitle` 之类填默认值），否则会盖掉主题里的 AppBar 配置、整页模式的观感就变了。
/// 页面里所有原本写 `AppBar(...)` 的地方都改成 `paneAppBar(context, ...)`。
///
/// **`actions` 末尾会被追加一个全局设置按钮**（用户 2026-09-16：「标题栏右上角永远
/// 显示一个设置按钮」）——页面不必自己加；`settingsSections` 声明本页相关的设置节，
/// 点进去的设置页只显示该节（空 = 完整设置页）。
PreferredSizeWidget? paneAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget> actions = const <Widget>[],
  List<SettingsSection> settingsSections = const <SettingsSection>[],
  bool? centerTitle,
  Widget? leading,
  PreferredSizeWidget? bottom,
  double? toolbarHeight,
  double? titleSpacing,
  Color? backgroundColor,
  Color? surfaceTintColor,
}) {
  if (paneIsRoot(context)) return null;
  // 全局设置按钮**只在这里造一次**（两种排布共用同一个实例）—— 守卫按源码里
  // 「设置按钮构造」的出现次数记账（恰好两处：本文件 + 内嵌行），复制一份就会打红。
  // ⚠ 连注释里也别写出那个「类名 + 左括号」的字样：守卫数的是文本，写进注释同样算命中。
  final settingsButton = SettingsActionButton(sections: settingsSections);
  // 窄屏（手机 / 电脑拖窄）：整条动作簇（各页自己的按钮 + 全局设置按钮 + 头像）
  // **搬到左侧**（用户 2026-10-10：「不要在手机端顶栏左侧显示图标，然后把设置什么的
  // 都放到左侧，其中头像要在最左侧」+「电脑端窄屏显示时也要使用和移动端一样的策略」）。
  // 桌面宽屏维持原样（动作仍在右上角；桌面的设置入口另有侧栏底部固定区）。
  final isDesktop = switch (Theme.of(context).platform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux =>
      true,
    _ => false,
  };
  // ⚠ **能被 pop 的页面不许动 `leading`**（那是返回键的位置）：顶掉它等于把「返回」
  // 弄没了（守卫实测「面板内二级页：保留完整导航栏与返回键」当场变红）。所以这条
  // 只在「根页面 / 不能返回的页面」上生效 —— 也正是用户看的那种顶栏。
  final canPop = ModalRoute.of(context)?.canPop ?? false;
  // 「窄」= 拖到手机上那种形态。判据取**宽度**而不是平台（用户 2026-10-10：
  // 「电脑端窄屏显示时，也要使用和移动端一样的策略，而不是把这个显示逻辑只影响
  // 移动端」）—— 桌面窗口拖窄到 `Breakpoints.sidebarLayout` 以下时，页面本身就已经
  // 换成手机那套布局了，顶栏没理由还留着桌面排布。
  final isNarrow =
      MediaQuery.sizeOf(context).width < Breakpoints.sidebarLayout;
  if ((!isDesktop || isNarrow) && !canPop) {
    // ⚠ 顺序**原样**（不反转）：调用方给的就是「头像在前、设置在后」——
    // 顺序的唯一出处 = `home_screen.dart` 的 `_buildTitleBarActions`。
    final cluster = <Widget>[...actions, settingsButton];
    return AppBar(
      title: title,
      // 移动端右侧不再放动作（都去了左边）。
      actions: const <Widget>[],
      // `leading` 默认只给 56 宽，塞不下「头像 + 设置」→ 按枚数放宽（每枚 40）。
      leadingWidth: leading == null ? 40.0 + 40.0 * cluster.length : null,
      leading: leading ??
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: cluster),
          ),
      centerTitle: centerTitle,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      backgroundColor: backgroundColor,
      surfaceTintColor: surfaceTintColor,
    );
  }
  return AppBar(
    title: title,
    actions: [
      ...actions,
      settingsButton,
    ],
    centerTitle: centerTitle,
    leading: leading,
    bottom: bottom,
    toolbarHeight: toolbarHeight,
    titleSpacing: titleSpacing,
    backgroundColor: backgroundColor,
    surfaceTintColor: surfaceTintColor,
  );
}

/// 内嵌服务主页的**内容顶部按钮行**：把原导航栏的 `actions` 搬到这里（右对齐，
/// 贴合原来的位置），行首可放该页自己的控件（如选课的 `TabBar`、课表的学期选择器）。
///
/// 非内嵌 / 面板内二级页 / 什么都没传 → `SizedBox.shrink()`，所以调用方可以直接把它
/// 摆在 body 最前面，不必自己判断。
///
/// ⚠ **本行默认只放页面自己的按钮**：全局设置按钮**不在这里**（用户 2026-09-16 二轮
/// 「你的设置添加导致不少页面凭空多了一个标题栏，我希望下沉到内容里」——内嵌页
/// 本来没有横向 chrome，塞一个齿轮进来就会多出一条只有齿轮的 44px 行）。桌面端
/// 的设置入口 = 左侧导航栏底部固定区（见 `home_sidebar.dart`），整页模式仍在
/// [paneAppBar] 的 `actions` 末尾。
///
/// **例外（用户 2026-09-17：「课表页的设置按钮不见了」）**：页面**本来就有工具条**
/// （有 [leading] 或 [actions]）时，只要它声明了 [settingsSections]，就在行尾补一个
/// 齿轮 —— 不新增任何横条，因此不违反上面那条红线（红线是「**空**行不许塞齿轮」，
/// 见下面第 132 行的早退）。课表页的内嵌工具栏（学期选择器 + 切换视图 / 调课管理 /
/// 刷新）正是这种情形：导航栏不画之后，它的设置入口就整个消失了（齿轮只由
/// [paneAppBar] 注入，而内嵌模式根本没有 AppBar）。
class PaneActionRow extends StatelessWidget {
  /// 行尾的按钮（与整页模式 `AppBar.actions` 的同一批 widget 实例）。
  final List<Widget> actions;

  /// 行首控件（占满剩余宽度）。给了就不再需要 `Spacer`。
  final Widget? leading;

  /// 本页相关的设置节；**非空且本行已有内容**时，行尾追加一个设置按钮。
  ///
  /// 空 = 不注入（默认，绝大多数内嵌页走这条 —— 它们的设置入口是侧栏底部固定区）。
  final List<SettingsSection> settingsSections;

  /// 行高。默认 44（图标按钮自身点击区 40 + 上下各 2）。
  ///
  /// 选课页传 `kTextTabBarHeight`，这样内嵌与整页两种模式的顶部高度一致、切换视图时
  /// 内容不会跳。**null = 由行内内容撑高**：课表页的学期选择器要按真实行宽自己决定
  /// 单行/两行（见 `schedule_title_bar.dart` 的 `fitsOneRow`），外部算不准它的高度，
  /// 写死就会出现「行高按单行给、内容却是两行」的溢出。
  final double? height;

  /// [height] 的默认值（`PaneBody` 也用它）。
  static const double defaultHeight = 44;

  /// 外层内边距。作为 `ListView` 首项时传 `EdgeInsets.zero`，避免与列表自身的
  /// 24px 边距叠加成 36。
  final EdgeInsetsGeometry padding;

  const PaneActionRow({
    super.key,
    this.actions = const <Widget>[],
    this.leading,
    this.height = defaultHeight,
    this.padding = const EdgeInsets.fromLTRB(12, 2, 12, 2),
    this.settingsSections = const <SettingsSection>[],
  });

  @override
  Widget build(BuildContext context) {
    if (!paneIsRoot(context)) return const SizedBox.shrink();
    // 本行没有任何内容 → 整行不画（否则会凭空多出一条 44px 空白「标题栏」——
    // 用户 2026-09-16：「不少页面凭空多了一个标题栏」）。**设置按钮也在这道闸门
    // 之后**：空行 + 齿轮 = 用户否掉过的那种「只有齿轮的横条」。
    if (actions.isEmpty && leading == null) return const SizedBox.shrink();
    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) Expanded(child: leading!) else const Spacer(),
          ...actions,
          if (settingsSections.isNotEmpty)
            SettingsActionButton(sections: settingsSections),
        ],
      ),
    );
    final fixed = height;
    return fixed == null ? row : SizedBox(height: fixed, child: row);
  }
}

/// 服务页的 `Scaffold.body`，**自带内嵌模式的按钮下沉**。
///
/// 非内嵌 / 面板内二级页 → 原样返回 [child]（零包裹、零影响）；内嵌服务主页 →
/// `Column[PaneActionRow, Expanded(child)]`。用它就不必在每个页面里写一遍
/// `if (paneIsRoot(context)) ...` 与 `Column` / `Expanded` 的配对括号。
class PaneBody extends StatelessWidget {
  final Widget child;

  /// 见 [PaneActionRow.actions]。
  final List<Widget> actions;

  /// 见 [PaneActionRow.leading]。
  final Widget? leading;

  /// 见 [PaneActionRow.height]。
  final double? height;

  /// 见 [PaneActionRow.padding]。列表页传与列表自身一致的水平边距（如 24），
  /// 按钮才会和内容左右对齐。
  final EdgeInsetsGeometry padding;

  /// 见 [PaneActionRow.settingsSections]：**本页相关**的设置节。
  ///
  /// ⚠ 只有**本来就有工具条**的页面才该传（课表页）；传了但本页没有 [actions] /
  /// [leading] 时不会有任何效果（不会新增横条）。
  final List<SettingsSection> settingsSections;

  const PaneBody({
    super.key,
    required this.child,
    this.actions = const <Widget>[],
    this.leading,
    this.height = PaneActionRow.defaultHeight,
    this.padding = const EdgeInsets.fromLTRB(12, 2, 12, 2),
    this.settingsSections = const <SettingsSection>[],
  });

  @override
  Widget build(BuildContext context) {
    if (!paneIsRoot(context)) return child;
    return Column(
      children: [
        PaneActionRow(
          actions: actions,
          leading: leading,
          height: height,
          padding: padding,
          settingsSections: settingsSections,
        ),
        Expanded(child: child),
      ],
    );
  }
}
