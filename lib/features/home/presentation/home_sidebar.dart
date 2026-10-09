/// 左侧导航栏视图（仅电脑端宽窗口；判定见 `domain/home_layout.dart`）。
///
/// 用户 2026-09-15 裁定：
/// - 第 1 条：侧栏按分组列出全部服务；
/// - 第 2 条（同日二轮，**推翻了本文件旧注释里「点它直接 push 功能页」的写法**）：
///   「点击左侧导航栏后，不是跳转页面，而是直接在右侧显示原跳转页面，并取消原
///   页面的返回按钮」→ 侧栏只负责**选中**（[onSelect]/[selectedTitle]），页面由
///   `HomeScreen` 装进右侧的 `HomeDetailPane`（面板自带 Navigator，见该文件）。
///   返回按钮的取消是自动的：内嵌页在面板路由栈里是首页 → `canPop == false`
///   → 各页 AppBar 不再画返回键（`ims_tab_container.dart` / `data_center_screen.dart`
///   两处硬编码返回键已改为按 `canPop` 判定）。
///
/// 顶部固定一行「数据一览」= 未选中任何服务时的右侧概览（[onOverview] 为 null
/// 时不渲染，测试与旧调用点因此不受影响），**紧跟其后**是
/// [HomeServiceEntry.sidebarPinned] 的条目（2026-09-19 起只有「AI 助手」一条，
/// 用户要求它「和"数据一览"下方紧贴」）。这两行同样不画分割线、不插分组标题。
///
/// ⚠ 「数据一览」与它下面第一个分组（`HomeServiceGroup.values[0]` = 「教务系统」）
/// 之间**不画分割线**（用户 2026-09-17：「桌面端主页的侧边导航栏里，顶部"数据
/// 一览"和教务系统之间不要显示分割线」）—— 靠分组标题自身的上内边距（14）留白
/// 即可。分组之间本来就没有分割线，别再加回来（列表里唯一的另一条线在底部
/// 固定区上方，那条不动）。
///
/// 底部固定区（用户 2026-09-16 裁定：「桌面端把标题栏里的头像和设置都应该改到
/// 侧边导航栏，设置在下，头像在上，并且这两个是固定在底部不浮动的」）：由调用方通过
/// [footer] 传入（用 [HomeSidebarFooterRow] 拼行），渲染在滚动区**之外** ——
/// 服务列表再长也压不到它。
///
/// **卡片形态**（用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，然后
/// 都是在设置了可选的」+「要阴影」）：[card] = true 时整条侧栏是一张圆角卡片
/// （圆角 / 描边 / 阴影见 `lib/design/card_frame.dart`），底色换成「卡片色」；
/// 外圈那道缝由调用方（`home_screen.dart`）按边留（见那边的 `_buildSidebarBody`）。
///
/// **可收起**（用户 2026-10-09 七轮：「我希望侧边栏可收起」）：[collapsed] = true 时
/// 只留一条 [collapsedWidth] 的窄轨（**图标与选中胶囊照旧**，十一轮口径）。
/// 收起状态由页面 State 持有、调用方切换；**没有做持久化**（与
/// `_selectedService` 同口径：切走再回来是展开的）。
/// ⚠ **收起后仍然是卡片**（十八轮）：[card] 与 [collapsed] **互不影响**。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 概览行文案（也是它在侧栏里的 Key 后缀）。
const String homeSidebarOverviewTitle = '数据一览';

/// 展开 / 收起侧栏那枚按钮的 Key（展开态在工具栏行尾，收起态在列表下方）。
/// 标题栏里那枚「展开 / 收起侧边栏」的 Key（2026-10-09 从侧栏挪到标题栏）。
const Key homeSidebarTitleBarToggleKey = Key('homeSidebarTitleBarToggle');
const Key homeSidebarToggleKey = Key('homeSidebarToggle');

/// 底部固定区：头像行（进「我的」）的 Key。
const Key homeSidebarProfileKey = Key('homeSidebarProfile');

/// 底部固定区：设置行的 Key。
const Key homeSidebarSettingsKey = Key('homeSidebarSettings');

/// 侧栏底部固定区的两行（2026-10-09 五轮起它们和目录条目一样**选中后显示在右侧内容区**）。
enum HomeSidebarFooter {
  /// 头像行 =「我的」。
  profile,

  /// 齿轮行 =「设置」。
  settings,
}

/// 侧栏一行的**圆角高亮胶囊**（用户 2026-10-09 十轮：「我希望改成圆角高亮，侧边条
/// 改成短的圆角的」—— 取代原来那条通高的 3px 左侧指示条）。
///
/// 用它的是：目录行 / 顶部「数据一览」/ 底部固定区两行 —— 四类行**共用一套**
/// （[HomeSidebar._rowShell] 与 [HomeSidebarFooterRow] 都调这里）。
///
/// 三个口径：
/// - 胶囊**上下各留 [pillVerticalInset]**（行高 38 → 胶囊高 30）：不缩的话圆角一贴到
///   上下边缘就看不出来，读起来还是"整条色块"；缩完之后左右圆角才是明确的圆角；
/// - **左右各退 [HomeSidebar.pillInset]**（默认 4）：所以圆角不会切到侧栏边缘 ——
///   侧栏是卡片时，那圈留白落在卡片底色上（正确的观感）；侧栏是通栏色块时，就是
///   同色留白（用户 2026-10-09 十轮裁定：**简单退一个固定 4 就够**，不按卡片形态分档）；
/// - **描边很淡**：`AppColors.hairline` 再乘 0.4 —— 深色下不给（10% 白已经够分界）。
///   ⚠ 加上它是为了**浅色下的白卡**：`primary @ 10%` 那种淡红叠在纯白上几乎看不出边界，
///   有一圈同色描边圆角才读得出来（那是本应用的默认形态）——这是本轮唯一超出
///   「只用填充色」的一笔，用户否掉的话删掉这一行即可。
BoxDecoration sidebarPillDecoration(
  BuildContext context,
  Color accent, {
  required bool selected,
}) => BoxDecoration(
  color: selected ? AppColors.tint(context, accent, 0.12) : null,
  borderRadius: BorderRadius.circular(HomeSidebar.pillRadius),
  border: selected ? Border.all(color: _pillBorderColor(context, accent)) : null,
);

Color _pillBorderColor(BuildContext context, Color accent) {
  if (AppColors.isDark(context)) {
    return AppColors.tintBorder(context, accent, 0.0);
  }
  return AppColors.hairline(context, 0.4);
}

/// 侧栏底部固定区的一行：左内边距 / 行高与上方服务行同口径（图标或头像 + 标签）。
///
/// [selected] 与目录行同一套选中观感（**圆角胶囊高亮** + 字重）——侧栏底部这两行
/// 也是右栏的内容来源之一，选中态不能只有目录行有（用户 2026-10-09 五轮；
/// 十轮把高亮从"左侧通高指示条"改成圆角胶囊，见 [sidebarPillDecoration]）。
///
/// ⚠ **不自带左右外边距**：内嵌在侧栏里时由 [HomeSidebar] 那层给（连同缩进），
/// 这样胶囊与目录行**左右对齐**；单独用（旧调用点 / 测试）时就是通栏一行。
class HomeSidebarFooterRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  /// 本行是不是右栏当前显示的内容。
  final bool selected;

  /// 选中胶囊的强调色（默认主题色，与「目录行 / 数据一览」同口径）。
  final Color? accent;

  const HomeSidebarFooterRow({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? scheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: HomeSidebar.footerRowHeight,
        padding: const EdgeInsets.symmetric(
          vertical: HomeSidebar.pillVerticalInset,
        ),
        child: Container(
          decoration: sidebarPillDecoration(
            context,
            accentColor,
            selected: selected,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HomeSidebar.pillHorizontalPadding,
          ),
          alignment: Alignment.centerLeft,
          // ⚠ 与 [HomeSidebar._iconAndLabel] 同一口径（十二轮）：**判据是"本行此刻多宽"
          // 而不是"侧栏收没收起"** —— 宽度补间期间会出现放不下「头像 30 + 缝 10」的帧，
          // 那时只画头像，连缝一起收掉，任何宽度都不会溢出。
          child: LayoutBuilder(
            builder: (context, constraints) {
              final room = constraints.maxWidth;
              if (!room.isFinite || room < 30 + 10 + 24) return leading;
              final labelWidth = (room - 30 - 10).clamp(0.0, double.infinity);
              return Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: labelWidth,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: scheme.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 左侧导航栏。
class HomeSidebar extends StatelessWidget {
  final List<HomeServiceEntry> entries;

  /// 栏宽（默认 [homeSidebarWidth]）。
  final double width;

  /// 当前选中的服务标题；`null` = 没选中目录条目（可能是概览，也可能是底部固定区
  /// 那两行之一 —— 概览高亮另看 [overviewSelected]，别再拿 null 当判据）。
  final String? selectedTitle;

  /// 顶部「数据一览」是不是当前选中项。
  ///
  /// 默认 = `selectedTitle == null`（旧调用点原样）。**底部固定区那两行选中时必须传
  /// false** —— 它们不是目录条目，`selectedTitle` 同样为 null，不区分就会「上下一同
  /// 高亮」（用户 2026-10-09 五轮报的那个 bug）。
  final bool? overviewSelected;

  /// 点击服务条目。为 null 时回落到条目自带的 [HomeServiceEntry.onTap]。
  final ValueChanged<HomeServiceEntry>? onSelect;

  /// 点击顶部「数据一览」；为 null 时不渲染该行。
  final VoidCallback? onOverview;

  /// 底部固定区（不随列表滚动）；为 null 时整块不画。
  final Widget? footer;

  /// 是否画成**圆角卡片**（带阴影）。
  ///
  /// 用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，然后都是在设置了
  /// 可选的。可以都不显示为卡片样式」+「要阴影」。口径 = `HomeCardStyle.sidebarIsCard`
  /// （设置页可拨），形状与阴影落在 `lib/design/card_frame.dart`。
  ///
  /// **默认 `false`**：旧调用点（测试、别的装配）零改动 —— 不开卡片时这块区域与从前
  /// 逐像素一致（通栏 `surfaceContainerLow` 底 + 无圆角无描边无阴影）。
  ///
  /// 开卡片时**底色跟着换成「卡片色」**（浅色纯白 / 深色 `#1A1A1A`）：原来那档
  /// `surfaceContainerLow` 是为「通栏分区」挑的，浮起来之后要和页面内的卡片同色。
  final bool card;

  /// 区域卡片的圆角（逻辑像素，默认 [kCardFrameRadius]）。
  ///
  /// 用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」—— 由设置页调、
  /// 落盘在 `homePrefs` 的 `homeCardRadius`（见 `domain/home_card_radius.dart`），
  /// 这里只负责透传给 [CardFrame]。
  final double radius;

  /// 是否**收起**（用户 2026-10-09 七轮：「我希望侧边栏可收起」）。
  ///
  /// 收起 = **同一条侧栏变窄到 [collapsedWidth]**、文本不画、**图标与选中胶囊照旧**
  /// （十一轮口径），切换由调用方（`home_screen.dart` 的 `_sidebarCollapsed`）持有，
  /// `onToggleCollapsed` 回传。
  ///
  /// ⚠ **与 [card] 互不影响**（用户 2026-10-09 十八轮：「我希望卡片模式的侧边栏收起后
  /// 仍然是卡片」）：收起后的窄轨**仍然是卡片**（圆角 / 描边 / 阴影都在），
  /// 所以调用方传的是 `card: sidebarCard`（不再 `&& !collapsed`）。
  final bool collapsed;

  /// 点展开 / 收起按钮；为 null 时不画那枚按钮（旧调用点零改动）。
  final VoidCallback? onToggleCollapsed;

  const HomeSidebar({
    super.key,
    required this.entries,
    this.width = homeSidebarWidth,
    this.selectedTitle,
    this.overviewSelected,
    this.onSelect,
    this.onOverview,
    this.footer,
    this.card = false,
    this.radius = kCardFrameRadius,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  /// 概览行是否高亮（[overviewSelected] 未传时的旧口径）。
  bool get _overviewSelected => overviewSelected ?? selectedTitle == null;

  /// 单个条目行高。
  static const double rowHeight = 38;

  /// 行内容（图标 / 文字）距侧栏左右边的留白。
  static const double rowPadding = 18;

  /// 圆角高亮胶囊的圆角（比行高的一半小一点，读起来是"圆角块"而不是药丸）。
  static const double pillRadius = 8;

  /// 胶囊左右各退多少（见 [sidebarPillDecoration] 的注释）。
  static const double pillInset = 4;

  /// 胶囊内部再缩进的量（让图标 / 文字仍在原来的 x 上，不因圆角而右移）。
  static const double pillHorizontalPadding = 6;

  /// 胶囊上下各留多少（行高 38 → 胶囊高 30）。
  static const double pillVerticalInset = 4;

  /// 底部固定区单行行高（比服务行略高：头像外径 30）。
  static const double footerRowHeight = 46;

  /// 收起态的宽度 = **刚好装下一个图标 + 高亮胶囊的左右留白**
  /// （`pillInset 4` + `pillHorizontalPadding 6` + 图标 18 + 6 + 4 = 38 → 取 40）。
  ///
  /// 「折叠也要显示图标，只是不显示文本」（见 [HomeSidebar.collapsed]）。40 宽
  /// 刚好让图标列居中、胶囊铺满可用宽度。
  static const double collapsedWidth = 40;

  /// 收起 / 展开的时长（与卡片形态的同款补间，读起来是「让开 / 收回来」）。
  static const Duration collapseDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 通栏 = `surfaceContainerLow`（原口径，逐像素不变）；
    // 卡片 = 「卡片色」（浅色纯白 / 深色 `#1A1A1A`，见 [card] 的说明）。
    final background = card ? appCardColorOf(scheme) : scheme.surfaceContainerLow;
    // ⚠ **收起态不是另一棵子树**（2026-10-09 十一轮 · 用户：「侧边栏折叠也要显示图标，
    // 只是不显示每一项的文本了，高亮什么的照旧」）：原来是「窄轨 = 只有一枚按钮」，
    // 现在收起只是**宽度变窄 + 所有文本不画**，列表 / 分组 / 底部固定区 / 选中胶囊
    // 全部照旧 —— 也从根上避免了"换子树 → 滚动位置归零"那类问题（见 §44.4 ②）。
    // ⚠ 宽度是**补间**的（用户 2026-10-09 十二轮：「展开收起侧边栏要有动画」）：
    // `AnimatedContainer` 在 `width` 与 `collapsedWidth` 之间跑 [collapseDuration]，
    // 与 `home_screen` 那两层 `AnimatedPadding`（左缝 / 块间缝）**同时启动、同一时长**
    // → 收起来是「文字先消失、整块缩回去」，右栏同时让开。
    // ⚠ **两种形态返回的是同一个组件类型**（九轮那次的教训，见 §44.4 ②）：`collapsed`
    // 只改 `width` 与「文本画不画」，绝不换 key / 换类型，否则子树重挂（内嵌页滚动归零）。
    //
    // ⚠ **行的内容按「本行此刻有多宽」决定画不画文字**（十二轮 · 见 [_iconAndLabel]）：
    // 宽度是补间的，动画中途会出现「图标 18 + 缝 10 = 28 就已经超过可用宽 20」的帧 ——
    // 那种帧里连文字都不该有，`Row` 才不会 `RenderFlex overflowed by 8.0 pixels`
    // （实测：光把文字夹成 0 宽度**不管用**，那 8px 是图标 + 缝本身撑出去的）。
    // 工具行与底部固定区外面那两层 `ClipRect` 只是第二道保险（视觉上"切掉"而不是溢出）。
    final body = AnimatedContainer(
      key: const Key('homeSidebar'),
      duration: collapseDuration,
      curve: Curves.easeOutCubic,
      width: collapsed ? collapsedWidth : width,
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⚠ 展开 / 收起那枚按钮 2026-10-09 起**只在标题栏**（用户：「我希望展开 / 收起
          // 侧边栏的按钮放在标题栏」）：首页把它发布到 `WindowTitleBarActions.leading`，
          // 侧栏这里整行撤掉 —— 不再需要那 36 高的工具行（它的唯一作用是给按钮占位、
          // 免得收起 / 展开那一下整列跳动；按钮搬走后没有跳动可言）。
          // `onToggleCollapsed` 参数保留：旧调用点 / 既有测试还在传（侧栏已经不用它了）。
          // 服务列表：**只有它滚动**。
          // ⚠ **不画滚动条**（用户 2026-10-09 十三轮：「我希望侧边栏滚动不显示滚动条」）：
          // 桌面端的默认 `MaterialScrollBehavior` 会替每个滚动区套一层 `Scrollbar`
          // （滚动时才显形），侧栏只有 232 宽、又贴着胶囊与卡片边，那条细线很扎眼。
          // `ScrollConfiguration` 改的是**滚动区自己的行为**（鼠标滚轮 / 拖拽照旧），
          // 不是全局开关。
          Expanded(
            child: ScrollConfiguration(
              behavior: const _NoScrollbarBehavior(),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  if (onOverview != null) _overviewRow(context, scheme),
                  // 顶部固定项：紧贴「数据一览」下方**不分节**（用户 2026-09-19：
                  // 「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴」）——
                  // 中间不插分组标题、不加分割线，两行同高（rowHeight）直接相接。
                  for (final item in homePinnedSidebarEntries(entries))
                    _row(context, item),
                  for (final group in HomeServiceGroup.values)
                    ..._group(context, scheme, group),
                ],
              ),
            ),
          ),
          // 底部固定区：不随列表滚动（超长服务列表也压不到它）。
          // ⚠ **上面那条分割线已去掉**（用户 2026-10-09 十三轮：「侧边栏不要有边框线」）：
          // 侧栏本来就靠底色与内容分界（宫格页那一侧也一样），再压一根线只是噪点。
          // 历史：2026-09-17 用户曾报「底部固定项最顶部的分割线太亮」→ 当时把
          // `outlineVariant.withValues(alpha: 0.6)` 换成 `hairline`；现在整条撤掉。
          if (footer != null) ...[
            // ⚠ 那两行（[HomeSidebarFooterRow]）**不自带左右外边距** —— 缩进由这里给，
            // 这样它们的圆角胶囊与目录行的胶囊**左右对齐**（十轮口径）。
            // ⚠ 外面这层 `ClipRect` 是给**收起动画**用的：那 200ms 里文本还在画、
            // 轨道已经收窄 → 不裁就是 `RenderFlex overflowed`（见 [body] 的注释）。
            ClipRect(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: pillInset),
                child: footer!,
              ),
            ),
          ],
        ],
      ),
    );
    // 卡片形态：圆角 + 描边 + 阴影，内容按圆角裁掉（见 `lib/design/card_frame.dart`）。
    // ⚠ **不挂 key**（2026-10-09 九轮）：`CardFrame` 两种形态返回的是同一个
    // `AnimatedContainer`，就地补间即可；挂一个「随 card 变」的 Key 会让整棵子树
    // 重新挂载（侧栏不内含设置页，但同一份口径要一致）。
    return CardFrame(card: card, radius: radius, child: body);
  }

  /// 顶部「数据一览」：右侧面板的默认内容，也是唯一的「返回概览」入口。
  ///
  /// ⚠ 高亮判据是 [overviewSelected] 而不是 `selectedTitle == null`（2026-10-09 五轮
  /// 用户报的 bug：「点底部设置或我的，会导致设置/我的高亮，然后此时上方功能区的高亮
  /// 不消失」）——底部固定区的两行**不是目录条目**，选中它们时 `selectedTitle` 也是
  /// null，于是「数据一览」被误判成选中，侧栏上下一同高亮 ✗。
  Widget _overviewRow(BuildContext context, ColorScheme scheme) {
    final selected = _overviewSelected;
    final accent = scheme.primary;
    return InkWell(
      key: const Key('homeSidebarOverview'),
      onTap: onOverview,
      hoverColor: accent.withValues(alpha: 0.06),
      child: _rowShell(
        context,
        selected: selected,
        accent: accent,
        child: _iconAndLabel(
          icon: Icon(Icons.dashboard_outlined, size: 18, color: accent),
          label: homeSidebarOverviewTitle,
          scheme: scheme,
          selected: selected,
        ),
      ),
    );
  }

  List<Widget> _group(
    BuildContext context,
    ColorScheme scheme,
    HomeServiceGroup group,
  ) {
    // 固定项已经在「数据一览」下方单独渲染过 → 从分组里摘掉，别出现两次。
    final items = [
      for (final e in homeServiceEntriesInGroup(entries, group))
        if (!e.sidebarPinned) e,
    ];
    if (items.isEmpty) return const [];
    return [
      // 分组标题：**收起时不画文字**，改成一条与图标同宽的分隔线 ——
      // 既保住「这里换了一组」这个信息，又不会在 40 宽的轨道里换行 / 溢出。
      if (collapsed)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            rowPadding + pillInset,
            10,
            rowPadding,
            10,
          ),
          child: Divider(height: 1, thickness: 1, color: AppColors.hairline(context)),
        )
      else
        Padding(
          // 分组标题与行内容左对齐（缩进跟着行的外边距走，见 [_rowShell]）。
          padding: const EdgeInsets.fromLTRB(
            rowPadding + pillInset,
            14,
            rowPadding,
            6,
          ),
          child: Text(
            group.title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final item in items) _row(context, item),
    ];
  }

  Widget _row(BuildContext context, HomeServiceEntry item) {
    final scheme = Theme.of(context).colorScheme;
    final selected = item.title == selectedTitle;
    return InkWell(
      key: Key('homeSidebarItem-${item.title}'),
      onTap: () {
        final select = onSelect;
        if (select != null) {
          select(item);
        } else {
          item.onTap();
        }
      },
      hoverColor: item.accent.withValues(alpha: 0.06),
      child: _rowShell(
        context,
        selected: selected,
        accent: item.accent,
        child: _iconAndLabel(
          icon: Icon(item.icon, size: 18, color: item.accent),
          label: item.title,
          scheme: scheme,
          selected: selected,
        ),
      ),
    );
  }

  /// 「图标 +（有地方放时才画的）文本」—— 侧栏每一行的内容都是这一对。
  ///
  /// 用户 2026-10-09 十一轮：「侧边栏折叠也要显示图标，只是不显示每一项的文本了，
  /// 高亮什么的照旧」。
  ///
  /// ⚠ **判据是「本行此刻有多宽」而不是「侧栏收没收起」**（十二轮 · 逐帧实测把这里
  /// 定死了）：宽度是**补间**的，收起动画中途会出现 `room = 20` 这种帧 —— 此时
  /// **图标 18 + 缝 10 = 28 就已经超过 20**，光把文字夹成 0 照样 `RenderFlex
  /// overflowed by 8.0 pixels`（那 8px 就是被撑出去的图标 + 缝）。
  /// 所以：**放不下就只画图标**（连那道 10 的缝一起收掉），这样任何宽度都不会溢出。
  ///
  /// 宽度阈值怎么来的：`iconSize + gap + minLabelWidth`。给文字留不到
  /// [minLabelWidth] 就干脆不画 —— 比画一两个字的省略号干净。
  Widget _iconAndLabel({
    required Widget icon,
    required String label,
    required ColorScheme scheme,
    required bool selected,
  }) {
    const iconSize = 18.0;
    const gap = 10.0;
    const minLabelWidth = 24.0;
    final iconBox = SizedBox(
      width: iconSize,
      height: iconSize,
      child: FittedBox(fit: BoxFit.contain, child: icon),
    );
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13.5,
        color: scheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        if (!room.isFinite || room < iconSize + gap + minLabelWidth) {
          return iconBox;
        }
        final labelWidth = (room - iconSize - gap).clamp(0.0, double.infinity);
        return Row(
          children: [
            iconBox,
            const SizedBox(width: gap),
            // ⚠ 文字外面那层 `Stack` 是「裁剪型布局、不报溢出」的保险：宽度补间期间
            // 万一还被量到比 `labelWidth` 窄的框，也不会冒出 `RenderFlex overflowed`
            // （真正的裁剪由侧栏那层 `ClipRect` 做）。
            SizedBox(
              width: labelWidth,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                alignment: AlignmentDirectional.centerStart,
                children: [
                  SizedBox(width: labelWidth, child: text),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 行外壳：恒定的定高 + **圆角高亮胶囊**（选中才着色）。
  ///
  /// 用户 2026-10-09 十轮：「我希望改成圆角高亮，侧边条改成短的圆角的」——
  /// 取代原来那条**通高 3px 左侧指示条**（胶囊的样式与三个口径见
  /// [sidebarPillDecoration]）。
  ///
  /// 两层缩进的账：外层 [pillInset]（胶囊与侧栏左右边缘之间）＋ 内层
  /// [pillHorizontalPadding]（胶囊内部留白）＝ [rowPadding] —— 于是**图标 / 文字仍在
  /// 原来的 x 上**，只有高亮块自己缩了进来。
  Widget _rowShell(
    BuildContext context, {
    required bool selected,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: pillInset,
        vertical: pillVerticalInset,
      ),
      child: Container(
        decoration: sidebarPillDecoration(context, accent, selected: selected),
        padding: const EdgeInsets.symmetric(
          horizontal: pillHorizontalPadding,
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

/// 侧栏滚动区用的 `ScrollBehavior`：**不画滚动条**。
///
/// 用户 2026-10-09 十三轮：「我希望侧边栏滚动不显示滚动条」。
/// 只覆盖 `buildScrollbar`（把子件原样返回 = 不套那层 `Scrollbar`），
/// 滚动本身（滚轮 / 拖拽 / 物理效果）走父类，行为不变。
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// 展开 / 收起侧栏的那枚小按钮（用户 2026-10-09 七轮：「我希望侧边栏可收起」）。
///
/// 两种位置同一个组件（所以 Key 只有一个）：
/// - **展开态**：侧栏顶部的工具行右端，图标 = 「收起」（chevron 朝左）；
/// - **收起态**：窄轨里，图标 = 「展开」（chevron 朝右）。
///
/// 尺寸 / 视觉与 `lib/design/settings_entry.dart` 的 `SettingsActionButton` 同口径
/// （`iconSize 18` + `visualDensity compact` + 30×30 命中区 → 实测点击区 40）。
class SidebarToggleButton extends StatelessWidget {
  const SidebarToggleButton({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  /// 当前是否收起（决定图标朝向与 tooltip 文案）。
  final bool collapsed;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    key: homeSidebarToggleKey,
    tooltip: collapsed ? '展开侧边栏' : '收起侧边栏',
    icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left, size: 18),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    onPressed: onTap,
  );
}


