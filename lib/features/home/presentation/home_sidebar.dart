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
        // ⚠ `AnimatedContainer`（与目录行的 `_rowShell` 同口径，见那边的注释）：
        // 底部固定区这两行的选中胶囊也要淡入淡出，不然"目录行会动、这两行瞬切"。
        child: AnimatedContainer(
          duration: HomeSidebar.pillDuration,
          curve: Curves.easeOutCubic,
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
class HomeSidebar extends StatefulWidget {
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

  /// **高亮切换的动画时长**（用户 2026-10-10 三十/三十一轮：先要"切换动画"，
  /// 再明确要"**高亮框有移动和颜色大小改变动画**"）。
  ///
  /// 口径（决定了观感，改之前先读）：
  /// - 侧栏里**只有一个**高亮框，它**会飞**：换选中项时从旧行的矩形**平移到**新行的矩形
  ///   （所以"位置"与"尺寸"一起补间 —— 行高一致、宽度在收起态会变，两者都由矩形插值覆盖）；
  /// - **颜色也一起补间**：不同条目各有 accent，飞行途中从旧色渐变到新色；
  /// - 时长与 [CardFrame.duration]（220ms）同档，切换侧栏 / 内容卡片时观感一致。
  static const Duration pillDuration = Duration(milliseconds: 200);

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
  State<HomeSidebar> createState() => _HomeSidebarState();
}

/// [HomeSidebar] 的状态：**只为一件事存在 —— 那个会飞的高亮框**。
///
/// 用户 2026-10-10 三十一轮：「我希望是高亮框有移动和颜色大小改变动画」。
/// 做法：侧栏里**只有一个**高亮框，换选中项时它在**旧行的矩形 → 新行的矩形**之间补间
/// （于是位置与尺寸一起动 —— 行高 / 栏宽（收起态）变化都被矩形插值覆盖），
/// 颜色同时从旧条目的 accent 渐变到新条目的 accent。
///
/// ⚠ 为什么不用 `AnimatedPositioned` + `AnimatedContainer`：那只能补间**目标值**，
/// 表达不了"从旧矩形飞过来"（旧矩形的来源是**上一帧量出来的**，不是某个常量）；
/// 所以这里自己拿一个 `AnimationController`，两端都是量出来的 `Rect`。
class _HomeSidebarState extends State<HomeSidebar>
    with SingleTickerProviderStateMixin {
  /// 选中项的高亮矩形（**本栏坐标系**，见 [_measure]）；null = 还没有目标。
  Rect? _target;

  /// 补间起点（= 上一次画出来的矩形）。
  Rect? _from;

  /// 目标条目的 accent（飞行途中 `Color.lerp(_fromAccent → _accent, t)`）。
  Color? _accent;
  Color? _fromAccent;

  /// ⚠ **必须在 `initState` 里就建出来**，不能写成 `late final … = AnimationController(…)`
  /// 的惰性初始化：若这一帧没有任何人碰过它（例如首帧 `_rect` 还是 null），`dispose()` 里
  /// 的 `_anim.dispose()` 才是**第一次**读它 → 那一刻 element 已经 deactivated →
  /// `createTicker` 去查 `TickerMode` 会抛
  /// 「Looking up a deactivated widget's ancestor is unsafe」（实测踩过）。
  late final AnimationController _anim;

  /// 侧栏的测量锚点。
  static const Key _measureBarKey = Key('homeSidebar_pillAnchor');

  /// 选中行的 key（直接复用既有的行 key，不必另挂一套）。
  Key? _selectedRowKey() {
    final overview = widget.overviewSelected ?? widget.selectedTitle == null;
    if (overview) return const Key('homeSidebarOverview');
    final title = widget.selectedTitle;
    if (title == null) return null;
    return Key('homeSidebarItem-$title');
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: HomeSidebar.pillDuration,
    )..addListener(_onTick);
    // 首帧之后才量得到（那时锚点都挂上了）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _retarget());
  }

  @override
  void didUpdateWidget(HomeSidebar old) {
    super.didUpdateWidget(old);
    if (old.selectedTitle != widget.selectedTitle ||
        old.overviewSelected != widget.overviewSelected ||
        old.collapsed != widget.collapsed) {
      // 换行 / 收起态变化都要重新量：目标可能变了，也可能只是宽度变了。
      WidgetsBinding.instance.addPostFrameCallback((_) => _retarget());
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  /// 量一次「选中行」在**本栏坐标系**里的胶囊矩形。
  ///
  /// ⚠ 用 `globalToLocal` 相减而不是累加行高：滚动、分组标题、收起态宽度全都自动跟上。
  /// ⚠ 外面那圈留白在这里让掉（[HomeSidebar.pillInset] / [HomeSidebar.pillVerticalInset]），
  /// 所以量出来的就是**胶囊**的矩形（与从前每行自己画的那个一致）。
  Rect? _measure() {
    final rowKey = _selectedRowKey();
    if (rowKey == null) return null;
    final rowBox = _ctxOfKey(rowKey)?.findRenderObject();
    final barBox = _ctxOfKey(_measureBarKey)?.findRenderObject();
    if (rowBox is! RenderBox || barBox is! RenderBox) return null;
    if (!rowBox.hasSize || !barBox.hasSize) return null;
    final topLeft = barBox.globalToLocal(rowBox.localToGlobal(Offset.zero));
    final rowRect = topLeft & rowBox.size;
    return Rect.fromLTWH(
      rowRect.left + HomeSidebar.pillInset,
      rowRect.top + HomeSidebar.pillVerticalInset,
      rowRect.width - HomeSidebar.pillInset * 2,
      rowRect.height - HomeSidebar.pillVerticalInset * 2,
    );
  }

  /// 按 key 找 element（用来取 RenderBox）。
  ///
  /// ⚠ 不引入 `GlobalKey` 表：行 key 已经存在（`homeSidebarItem-<标题>` / 概览行），
  /// 用 `WidgetsBinding.instance.rootElement` 自上而下找一次即可 —— 只发生在
  /// "选中项变了 / 收起态变了"这两种时刻，不在每帧热路径上。
  Element? _ctxOfKey(Key key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  /// 把高亮框挪到当前选中行；从**此刻画着的矩形**开始补间（颜色同理）。
  void _retarget() {
    if (!mounted) return;
    final next = _measure();
    final nextAccent = next == null ? null : _accentOfCurrent();
    if (next == null) {
      if (_target == null) return;
      setState(() {
        _from = _target;
        _target = null;
        _fromAccent = _accent;
      });
      _anim.forward(from: 0);
      return;
    }
    if (_target == next) return; // 没变，别打断正在跑的补间
    setState(() {
      // ⚠ 补间途中目标变了（收起动画每帧都在改宽度）：**保留起点**，只换终点 ——
      // 若把 `_from` 也改成新量到的值，框会"粘"在当前位置不再飞。
      _from ??= next;
      _target = next;
      // 颜色只在**真的换了条目**时才重设起点（宽度变化不该让颜色重跑一遍）。
      if (nextAccent != _accent) {
        _fromAccent = _currentAccent ?? nextAccent;
        _accent = nextAccent;
        _anim.forward(from: 0);
      }
    });
  }

  /// 当前选中项该用的 accent（概览 = 主题色；条目 = 自己的 accent）。
  Color? _accentOfCurrent() {
    final overview = widget.overviewSelected ?? widget.selectedTitle == null;
    if (overview) return Theme.of(context).colorScheme.primary;
    final title = widget.selectedTitle;
    for (final e in widget.entries) {
      if (e.title == title) return e.accent;
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// 此刻该画出来的**胶囊纵向位置与高度**（把 t 缓动后在 `_from` 与 `_target`
  /// 之间插值）。
  ///
  /// ⚠ **只取纵向**：横向（左右退让 / 宽度）一律由 `LayoutBuilder` 现拿栏的宽度算
  /// —— 收起侧栏时栏宽自己也在补间，而"量"出来的宽度永远是**上一帧**的
  /// （实测：`_measure()` 在收起动画里一路读到 232，框纹丝不动地停在展开态宽度）。
  /// 布局阶段拿到的宽度才是这一帧真正在用的那个。
  ({double top, double height})? get _pillVertical {
    final from = _from;
    final target = _target;
    if (target == null) return null;
    final rect = from == null
        ? target
        : Rect.lerp(from, target, Curves.easeOutCubic.transform(_anim.value))!;
    return (top: rect.top, height: rect.height);
  }

  /// 此刻该画出来的 accent（旧色 → 新色）。
  Color? get _currentAccent {
    final base = _accent ?? _fromAccent;
    if (base == null) return null;
    final from = _fromAccent ?? base;
    return Color.lerp(from, base, Curves.easeOutCubic.transform(_anim.value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 通栏 = `surfaceContainerLow`（原口径，逐像素不变）；
    // 卡片 = 「卡片色」（浅色纯白 / 深色 `#1A1A1A`，见 [card] 的说明）。
    final background = widget.card
        ? appCardColorOf(scheme)
        : scheme.surfaceContainerLow;
    // ⚠ **收起态不是另一棵子树**（2026-10-09 十一轮 · 用户：「侧边栏折叠也要显示图标，
    // 只是不显示每一项的文本了，高亮什么的照旧」）：原来是「窄轨 = 只有一枚按钮」，
    // 现在收起只是**宽度变窄 + 所有文本不画**，列表 / 分组 / 底部固定区 / 选中胶囊
    // 全部照旧 —— 也从根上避免了"换子树 → 滚动位置归零"那类问题（见 §44.4 ②）。
    // ⚠ 宽度是**补间**的（用户 2026-10-09 十二轮：「展开收起侧边栏要有动画」）：
    // `AnimatedContainer` 在 `width` 与 `HomeSidebar.collapsedWidth` 之间跑 [collapseDuration]，
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
      // ⚠ `homeSidebar` 这个 key **测试在用**（量宽度 / 量矩形），不许换成测量用的那个。
      key: const Key('homeSidebar'),
      duration: HomeSidebar.collapseDuration,
      curve: Curves.easeOutCubic,
      width: widget.collapsed ? HomeSidebar.collapsedWidth : widget.width,
      color: background,
      // ⚠ `Stack` 是为了那个**会飞的高亮框**（三十一轮）：它画在整栏之上、内容之下，
      // 位置由 `_rect` 给（本栏坐标系 → 滚动也跟着动，因为它量的是行的全局位置）。
      // ⚠ **不能**给这个 Stack 挂 `clipBehavior`：栏宽是补间的，收起那一下内容照旧
      // 由各行的 `ClipRect` 兜着（见上面那段），这里再裁一层会连带把高亮框裁掉。
      child: Stack(
        // 测量锚点与 `homeSidebar` 是**同一个盒子**（Stack 铺满 AnimatedContainer），
        // 所以行矩形减出来的就是本栏坐标系里的位置。
        key: _measureBarKey,
        children: [
          Column(
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
                  if (widget.onOverview != null) _overviewRow(context, scheme),
                  // 顶部固定项：紧贴「数据一览」下方**不分节**（用户 2026-09-19：
                  // 「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴」）——
                  // 中间不插分组标题、不加分割线，两行同高（HomeSidebar.rowHeight）直接相接。
                  for (final item in homePinnedSidebarEntries(widget.entries))
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
          if (widget.footer != null) ...[
            // ⚠ 那两行（[HomeSidebarFooterRow]）**不自带左右外边距** —— 缩进由这里给，
            // 这样它们的圆角胶囊与目录行的胶囊**左右对齐**（十轮口径）。
            // ⚠ 外面这层 `ClipRect` 是给**收起动画**用的：那 200ms 里文本还在画、
            // 轨道已经收窄 → 不裁就是 `RenderFlex overflowed`（见 [body] 的注释）。
            ClipRect(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: HomeSidebar.pillInset),
                child: widget.footer!,
              ),
            ),
          ],
        ],
          ),
          // 会飞的高亮框：**唯一一个**，画在内容之上（`Stack` 里排在后面）。
          // ⚠ `IgnorePointer`：它只是观感，不许吃点击（行自己的 `InkWell` 照旧收事件）。
          // ⚠ `LayoutBuilder` 拿的是**这一帧真正在用的栏宽**（见 [_pillVertical] 的说明）：
          // 收起动画的每一帧都能跟上，不必等"量"出来的下一帧。
          if (_pillVertical != null)
            Align(
              alignment: Alignment.topLeft,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final v = _pillVertical!;
                  return Padding(
                    padding: EdgeInsets.only(top: v.top),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const Key('homeSidebarFlyingPill'),
                        decoration: sidebarPillDecoration(
                          context,
                          _currentAccent ?? scheme.primary,
                          selected: true,
                        ),
                        child: SizedBox(
                          width: (constraints.maxWidth -
                                  HomeSidebar.pillInset * 2)
                              .clamp(0.0, double.infinity),
                          height: v.height,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
    // 卡片形态：圆角 + 描边 + 阴影，内容按圆角裁掉（见 `lib/design/card_frame.dart`）。
    // ⚠ **不挂 key**（2026-10-09 九轮）：`CardFrame` 两种形态返回的是同一个
    // `AnimatedContainer`，就地补间即可；挂一个「随 card 变」的 Key 会让整棵子树
    // 重新挂载（侧栏不内含设置页，但同一份口径要一致）。
    return CardFrame(card: widget.card, radius: widget.radius, child: body);
  }

  /// 顶部「数据一览」：右侧面板的默认内容，也是唯一的「返回概览」入口。
  ///
  /// ⚠ 高亮判据是 [overviewSelected] 而不是 `selectedTitle == null`（2026-10-09 五轮
  /// 用户报的 bug：「点底部设置或我的，会导致设置/我的高亮，然后此时上方功能区的高亮
  /// 不消失」）——底部固定区的两行**不是目录条目**，选中它们时 `selectedTitle` 也是
  /// null，于是「数据一览」被误判成选中，侧栏上下一同高亮 ✗。
  Widget _overviewRow(BuildContext context, ColorScheme scheme) {
    final selected = widget._overviewSelected;
    final accent = scheme.primary;
    return InkWell(
      key: const Key('homeSidebarOverview'),
      onTap: widget.onOverview,
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
      for (final e in homeServiceEntriesInGroup(widget.entries, group))
        if (!e.sidebarPinned) e,
    ];
    if (items.isEmpty) return const [];
    return [
      // 分组标题：**收起时不画文字**，改成一条与图标同宽的分隔线 ——
      // 既保住「这里换了一组」这个信息，又不会在 40 宽的轨道里换行 / 溢出。
      if (widget.collapsed)
        Padding(
          padding: EdgeInsets.fromLTRB(
            HomeSidebar.rowPadding + HomeSidebar.pillInset,
            10,
            HomeSidebar.rowPadding,
            10,
          ),
          child: Divider(height: 1, thickness: 1, color: AppColors.hairline(context)),
        )
      else
        Padding(
          // 分组标题与行内容左对齐（缩进跟着行的外边距走，见 [_rowShell]）。
          padding: EdgeInsets.fromLTRB(
            HomeSidebar.rowPadding + HomeSidebar.pillInset,
            14,
            HomeSidebar.rowPadding,
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
    final selected = item.title == widget.selectedTitle;
    return InkWell(
      key: Key('homeSidebarItem-${item.title}'),
      onTap: () {
        final select = widget.onSelect;
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
  /// 两层缩进的账：外层 [HomeSidebar.pillInset]（胶囊与侧栏左右边缘之间）＋ 内层
  /// [HomeSidebar.pillHorizontalPadding]（胶囊内部留白）＝ [HomeSidebar.rowPadding] —— 于是**图标 / 文字仍在
  /// 原来的 x 上**，只有高亮块自己缩了进来。
  Widget _rowShell(
    BuildContext context, {
    required bool selected,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      height: HomeSidebar.rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: HomeSidebar.pillInset,
        vertical: HomeSidebar.pillVerticalInset,
      ),
      // ⚠ **这里只留几何，不再画高亮**（用户 2026-10-10 三十一轮：
      // 「我希望是高亮框有移动和颜色大小改变动画」）。
      //
      // 高亮本身由侧栏那一层**唯一一个会飞的框**负责（见 [_flyingHighlight] /
      // `TweenAnimationBuilder<Rect?>`）：换选中项时它从旧行**平移**到新行，
      // 同时把颜色与尺寸一起补间过去。所以本行只用一个**透明**的占位盒把矩形与内边距占住
      // （图标 / 文案的 x 不变），填充与描边都交给那个飞行的框。
      //
      // ⚠ 于是"本行选不选中"不再影响这里的观感 —— 但仍要把 [selected] / [accent] 留在签名里：
      // 旧调用点与测试都在用，而且飞行框的目标矩形就是按这些行算出来的。
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: HomeSidebar.pillHorizontalPadding,
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