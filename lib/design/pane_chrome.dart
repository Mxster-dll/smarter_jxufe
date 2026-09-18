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

import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_entry.dart';

/// 标记「本子树位于侧栏右侧面板内」。由 `HomeDetailPane` 在面板 Navigator **之上**注入，
/// 因此面板内所有路由（含二级页）都能查到。
class PaneScope extends InheritedWidget {
  /// 是否内嵌在面板里。宫格视图（整页 push）恒为 false。
  final bool embedded;

  const PaneScope({super.key, required this.embedded, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneScope>()?.embedded ??
      false;

  @override
  bool updateShouldNotify(PaneScope oldWidget) =>
      oldWidget.embedded != embedded;
}

/// 本页是否被内嵌在侧栏右侧面板里。
bool paneEmbedded(BuildContext context) => PaneScope.of(context);

/// 本页是不是面板的**首路由**（内嵌的服务主页）。
///
/// false = 整页模式（宫格 push / 独立页面），或面板内的二级页 —— 两种情况都照旧画
/// 完整导航栏。
bool paneIsRoot(BuildContext context) =>
    paneEmbedded(context) && !Navigator.of(context).canPop();

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
  return AppBar(
    title: title,
    actions: [
      ...actions,
      SettingsActionButton(sections: settingsSections),
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
