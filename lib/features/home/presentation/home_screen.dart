import 'dart:async';

import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/core/window/window_title_bar_actions.dart';
import 'package:smarter_jxufe/design/app_page_transitions.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/design/settings_entry.dart';
import 'package:smarter_jxufe/features/home/data/home_edit_mode.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_grid.dart';
import 'package:smarter_jxufe/features/home/presentation/overview_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_sync_scope.dart';
import 'package:smarter_jxufe/shared/widgets/account_avatar.dart';

/// 单页功能主页 —— 登录后的统一落地页。
///
/// 两种布局（用户 2026-09-15 裁定第 1 条，**切换入口只在设置页**、选择记住）：
/// - **宫格视图**（默认，手机端唯一形态）：图标磁贴铺满页面，点磁贴 push 整页；
/// - **左侧导航栏视图**（仅电脑端且宽度 ≥ [homeSidebarMinWidth]）：左侧按分组
///   列出全部服务，点击**把功能页内嵌在右侧面板**（`HomeDetailPane`，用户同日
///   第 2 条），右侧默认内容是「数据一览」概览。
///
/// 侧栏视图下**两块区域各自可以是圆角卡片**（用户 2026-10-09 二轮：「我希望 内容区
/// 一个卡片、侧栏一个卡片，然后都是在设置了可选的。可以都不显示为卡片样式」+
/// 「要阴影」）：口径 = `home_card_style.dart` 的 `HomeCardStyle`（四档，设置页可拨），
/// 形状 / 缝 / 阴影落在 `lib/design/card_frame.dart`。默认「都不显示」，与改造前一致。
///
/// 服务条目表在 `home_service_catalog.dart`（宫格与侧栏共用一份，强调色随条目走）。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// 侧栏当前选中的服务标题；`null` = 右侧显示「数据一览」概览。
  ///
  /// 只活在页面 State 里（不进 Hive）：切走再回来仍是概览，符合「主页 = 概览」
  /// 的直觉；窄窗口 / 宫格视图下这个字段被忽略。
  String? _selectedService;

  /// 侧栏底部固定区选中的那一行（设置 / 我的）；与 [_selectedService] **互斥**。
  ///
  /// 2026-10-09 五轮（用户原话：「我们目前『侧边栏』模式下，设置和我的页都不是在
  /// 右侧内容区显示，而是进入一个子页面，我希望与其他功能页统一」）：这两行不再
  /// `push` 子页面，而是和目录条目一样**在右侧内容区**显示（走同一个
  /// `HomeDetailPane` 内嵌通道）。宫格视图下这两个入口仍走整页跳转（那里没有右栏）。
  HomeSidebarFooter? _selectedFooter;

  /// 侧栏是否收起（用户 2026-10-09 七轮：「我希望侧边栏可收起」）。
  ///
  /// 与 [_selectedService] 同口径：**只活在页面 State 里、不进 Hive** —— 切走再
  /// 回来是展开的。收起时侧栏只剩一条 [HomeSidebar.collapsedWidth] 的窄轨 +
  /// 一枚展开按钮，右栏自动占满腾出来的宽度（`Row` + `Expanded` 天然如此）。
  /// **手动意愿**（三态）：`null` = 没表态（跟随自动那半）、`true` = 手动收起、
  /// `false` = 手动展开。
  ///
  /// ⚠ 为什么必须是三态而不是「手动收起」一个布尔（用户 2026-10-10：
  /// 「我希望自动折叠时，点击展开按钮是可以直接展开的」）：只有 `收起 = 手动 || 自动`
  /// 时，窄窗口里自动收起之后**点展开也展不开** ✗（自动那半立刻又把它按住）。
  /// 现在 `false` 表示「用户明确要展开」，**压过自动** ✓；用户再点一下就是 `true`（手动收起，
  /// 宽度变宽也不弹开 ✓）。
  bool? _sidebarManual;

  /// 「窄窗口自动收起」本次跨线是否已处理过（见 build 里的注释）。
  /// 「窄窗口自动收起」的**派生**结果（每次 build 重新算，不锁存；见 build 里的注释）。
  bool _autoCollapsedNow = false;

  /// 标题栏那枚侧栏开关现在发不发布（避免每帧 notify 祖先）。
  bool? _sidebarToggleShown;

  /// 全局标题栏的「页面动作」插槽（2026-10-09：首页品牌栏并入标题栏后，
  /// 宫格视图的设置 / 头像要画到标题栏右侧去）。
  WindowTitleBarActions? _titleBarActions;

  /// 上一次发布的可见性（null = 还没发布过）。值没变就什么都不做。
  bool? _actionsVisible;

  @override
  void initState() {
    super.initState();
    _titleBarActions = ref.read(windowTitleBarActionsProvider);
  }

  @override
  void dispose() {
    // 标题栏是全局的：本页走了必须把动作收回，否则别的页面上会一直挂着首页的
    // 设置 / 头像（标题栏本身不认识路由）。
    _titleBarActions?.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layoutStore = ref.watch(homeLayoutStoreProvider);
    final layout = layoutStore.layout;
    final cardStyle = layoutStore.cardStyle;
    final cardGap = layoutStore.cardGap;
    final cardRadius = layoutStore.cardRadius;
    final gridStore = ref.watch(homeGridStoreProvider);
    final desktop = homeDesktopPlatform(Theme.of(context).platform.name);

    return Scaffold(
      // 底部**不**留 SafeArea 内边距：Android 已铺满整屏（edge-to-edge），
      // 若在这里避开导航栏，导航栏那一条只会露出 Scaffold 的白底（用户
      // 2026-09-16：「主页宫格底部只显示白色而不是内容」）。不避开后磁贴
      // 会一直画到屏幕底边；列表底部 48 的内边距保证最后一行仍在导航栏之上。
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 强调色随亮度解析（宫格磁贴与侧栏共用这一份目录）：
            // 深色下 `FeatureColors.forBrightness` 会把每条 accent 提到可读档。
            final entries = homeServiceEntries(
              brightness: Theme.of(context).brightness,
              push: (screen) => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => screen)),
            );
            final useSidebar = homeUsesSidebarLayout(
              layout: layout,
              desktop: desktop,
              width: constraints.maxWidth,
            );
            // 顶栏（品牌 + 设置 / 头像）已于 2026-10-09 并入**全局窗口标题栏**：
            // 品牌（logo + 应用名）由 `WindowTitleBar` 画；宫格视图的设置 / 头像
            // 通过动作插槽交给它。侧栏视图下这两个入口仍在侧栏底部固定区（§3 口径），
            // 所以那条不发布动作。二级页盖上来时（本路由不再是当前路由）也收回 ——
            // 那些页面自己的 AppBar 里有齿轮，标题栏再挂一个会同时出现两个。
            _queueTitleBarActions(
              visible:
                  !useSidebar && (ModalRoute.of(context)?.isCurrent ?? true),
            );
      // 侧栏视图才发布「展开 / 收起」（宫格视图没有侧栏）。
      // 侧栏「收起」的两半**互相独立**（用户 2026-10-10：「自动折叠与手动折叠独立，自动
      // 折叠等窗口宽度足够会自动展开，而手动折叠则不会」）：
      // - **自动**：由宽度**派生**（不锁存）—— 窄于 900 就收、回到 900 以上**自己展开**；
      // - **手动**：三态 `_sidebarManual`（null 跟随自动 / true 收起 / false 展开）——
      //   点一下就是「表态」，`false`（要展开）**压过自动**，所以窄窗口里点展开能真的展开 ✓；
      //   而 `true`（要收起）宽度再宽也不会自己弹开 ✓。
      // 实际是否收起 = 两者取或。
      //
      // ⚠ 这里把派生结果记在 `_autoCollapsedNow` 上，由两个 `_build*Body` 读取 ——
      // 它们内部再各自 `MediaQuery.sizeOf` 派生一遍的话，「宽度」这条依赖就散成三处了
      // （2026-10-10 试过：宽窗口下也判成窄，几条既有用例当场变红）。
      final autoCollapsePref = layoutStore.autoCollapseSidebar;
      _autoCollapsedNow = autoCollapsePref &&
          constraints.maxWidth < homeSidebarAutoCollapseWidth;
      _publishSidebarToggle(show: useSidebar);
            return useSidebar
                ? _buildSidebarBody(
                      context,
                      entries,
                      cardStyle,
                      cardGap,
                      cardRadius,
                    )
                : _buildGridBody(context, entries, gridStore);
          },
        ),
      ),
    );
  }

  /// 宫格视图：仪表盘（左：指标卡；右：今日课程 12 格）+ 服务宫格。
  ///
  /// 两个小标题（原「数据一览」「全部服务」）已按用户 2026-09-18 裁定撤掉。
  /// **下拉刷新整页卡片**（用户 2026-09-19：「主页视图下拉刷新所有卡片」）——
  /// 面板里的刷新按钮已撤，这里是唯一刷新入口。
  ///
  /// [gridStore] 提供宫格聚合布局（长按拖动 / 合并的结果，用户 2026-09-21 需求）：
  /// 布局由本页 watch、由宫格回写，宫格组件本身不碰 Riverpod（见 `home_service_grid.dart`）。
  ///
  /// 宫格编辑模式（原名「拆解模式」）的开关在**设置页** —— 用户 2026-09-21 十三轮原话：
  /// 「我希望标题栏不显示编辑模式按钮和重置按钮，这两个都放到设置里」。状态由
  /// [homeEditModeProvider] 持有：设置页拨、这里听，不再是本 State 的字段。
  Widget _buildGridBody(
    BuildContext context,
    List<HomeServiceEntry> entries,
    HomeGridStore gridStore,
  ) {
    final editMode = ref.watch(homeEditModeProvider);
    return RefreshIndicator(
      onRefresh: () => refreshDashboard(ref),
      child: ListView(
        // 恒可下拉（内容不足一屏时也要能触发刷新）。
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部内边距只留 12：Android 已铺满整屏（edge-to-edge），导航栏那一栏
        // 归 App 绘制；留 48 会让列表末尾空出一条通屏宽白带（用户 2026-09-16
        // 两次追问「主页宫格底部为什么只显示白色」，并裁定「铺到最底」）。
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        children: [
          // 桌面小组件同步触发点（首帧推送 + 回前台重推 + 冷启动路由）
          const HomeWidgetSyncScope(child: DashboardPanel()),
          const SizedBox(height: 26),
          HomeServiceGrid(
            entries: entries,
            layout: gridStore.layout,
            editMode: editMode,
            onLayoutChanged: (next) => unawaited(gridStore.save(next)),
          ),
        ],
      ),
    );
  }

  /// 左侧导航栏视图：侧栏（全部服务，按分组）+ 右侧「概览 / 内嵌功能页」。
  ///
  /// **卡片形态**（用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，然后
  /// 都是在设置了可选的。可以都不显示为卡片样式」+「要阴影」）：两块**各自**可以是
  /// 一张圆角卡片（[HomeCardStyle] 四档，设置页可拨）。
  ///
  /// **间距逐边按卡片给**（用户 2026-10-09 七轮：「是不是只要内容和侧边栏不都处于
  /// 非卡片状态，就会有一个整体相对于窗口的边距，我希望取消」—— 是的，原来那一版是
  /// **整块主体**统一 `Padding`，于是顶部（卡片↔标题栏）也白留了一条带子）：
  ///
  /// | 边 | 留多少 | 谁来留 |
  /// |---|---|---|
  /// | 侧栏左 | **a**，只要侧栏是卡片（**收起也留**） | 侧栏外面那层 `AnimatedPadding` |
  /// | 侧栏底 | **a**，同上（**和内容卡同值**，否则两张卡下边不齐） | 同一个 `AnimatedPadding` |
  /// | 两块之间 | **a**（十七轮起与边距同值），只要**两块都是卡片**（**收起也留**，否则是 1px 空隙） | 中间的间隔件 |
  /// | 内容区右 / 底 | **a**，仅当内容区是卡片 | 右栏那层 `AnimatedPadding` |
  /// | 顶（贴标题栏） | **恒 0**（两块都是） | —— |
  ///
  /// 三条推论（都是有意为之）：
  /// 1. **不是卡片的那一侧不缩边** —— 侧栏不是卡片时它左边缘就是窗口边缘（通栏），
  ///    内容区不是卡片时它的右侧 / 底部一直铺到窗口边；
  /// 2. 只有一侧是卡片时中间**不留那道缝**（留了也只是一条白带子：另一侧没有
  ///    「卡片边」要跟它分开）；
  /// 3. **收起来不改任何一道缝**（十八 / 十九轮）：侧栏是卡片时，收起后的窄轨仍然是卡片
  ///    （圆角 / 描边 / 阴影都在），左边照样留 `a`、与内容卡之间照样是 `a`。
  ///    十八轮前这里是「收起就不算卡片」、十九轮前是「收起就不留块间缝」——
  ///    用户 2026-10-09 十八轮：「我希望卡片模式的侧边栏收起后仍然是卡片」、
  ///    十九轮：「我希望收起之后与右侧卡片的间距不要变」；
  /// 4. **左右两张卡的"下边"必须同值**（二十三轮）：侧栏卡片的下边一度漏了 `a`
  ///    （只留了左缝），于是它一路铺到窗口底、和内容卡不齐 —— 用户读作
  ///    「没有应用设置里的卡片间距设置」。
  ///
  /// ⚠ **右栏的卡片层包在 `AnimatedSwitcher` 外面**（二十一轮）：包在里面会让整张卡片
  /// 跟着换页动画横移 + 被 `Stack` 裁掉一截（用户报的「切换页面时卡片水平闪动」与
  /// 「圆角处框线断开」是同一个 bug，见 §44.1.15）。
  Widget _buildSidebarBody(
    BuildContext context,
    List<HomeServiceEntry> entries,
    HomeCardStyle cardStyle,
    double cardGap,
    double cardRadius,
  ) {
    final footer = _selectedFooter;
    final selected = footer == null ? _selectedEntry(entries) : null;
    // 右栏当前内容的面板 id（也当切换动画的 key）：底部固定区两行不是目录条目，
    // 用它们自己的名字当 id（与目录标题天然不会撞）。
    final paneKey =
        footer?.name ?? selected?.title ?? homeSidebarOverviewTitle;
    final collapsed = _sidebarManual ?? _autoCollapsedNow;
    final sidebarCard = cardStyle.sidebarIsCard;
    final contentCard = cardStyle.contentIsCard;
    // 间距口径：卡片↔卡片 = a、卡片↔窗口左/右/底边 = a（十七轮起同值；顶边贴标题栏不受限）。
    final gap = cardGapMetricsOf(cardGap);
    return CardFrameBackdrop(
      // 卡片背后露出来的那层窗口背景 = **标题栏色**（用户 2026-10-09 八轮：
      // 「我希望卡片后露出来的窗口背景色要与标题栏一致」）—— 之前露的是页面底，
      // 深色下它就是 #121212、比标题栏 #1A1A1A 更深，卡片四周会有一圈突兀的深带子。
      visible: sidebarCard || contentCard,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 侧栏那一侧：**左边 + 下边**（贴窗口）由这里留；右边（贴内容卡）由下面那个
          // 间隔件留；**顶边不留**（贴标题栏，见下面那条口径）。
          // ⚠ 判据只看「**侧栏是不是卡片**」——收起与否**都要留**（用户 2026-10-09 十八轮：
          // 「我希望卡片模式的侧边栏收起后仍然是卡片」→ 窄轨也是卡片，自然也要离窗口 `a`）。
          // 不是卡片时才去掉 —— 否则会白留一条缝（用户 2026-10-09 七轮：
          // 「只要内容和侧边栏不都处于非卡片状态，就会有一个整体相对于窗口的边距，我
          // 希望取消」说的就是这种「不是卡片却仍有边距」）。
          //
          // ⚠⚠ **下边必须有**（用户 2026-10-09 二十三轮：「侧边栏以卡片形式显示时，距离
          // 页面底部太近，似乎没有应用设置里的卡片间距设置」）：二十二轮之前这里只有
          // `left`，于是侧栏卡片一路铺到窗口底边、和右边那张内容卡**不齐**（右卡有
          // `bottom: a`）—— 用户读到的就是"没应用间距设置"。左右两张卡的下边必须同值。
          AnimatedPadding(
            duration: CardFrame.duration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              left: sidebarCard ? gap.edge : 0,
              bottom: sidebarCard ? gap.edge : 0,
            ),
            child: HomeSidebar(
              entries: entries,
              // ⚠ **卡片形态与"收没收起"无关**（十八轮改）：收起后那条窄轨**仍然是卡片**
              // （圆角 / 描边 / 阴影都在），只是变窄了。所以这里不再带 `&& !collapsed`。
              card: sidebarCard,
              radius: cardRadius,
              collapsed: collapsed,
              onToggleCollapsed: () =>
                  // 翻转的是**当前实际状态**，并记为手动意愿（点击即表态，压过自动）。
          setState(() => _sidebarManual = !collapsed),
              width: homeSidebarWidth,
              selectedTitle: selected?.title,
              // 底部固定区选中时「数据一览」不许跟着高亮（它不是 null 就等于概览）。
              overviewSelected: footer == null && selected == null,
              // 高亮框要能飞到「我的 / 设置」那两行上去（2026-10-10：
              // 认不出它们时框会直接消失，点这两行就是"啪"地一闪）。
              footerSelected: footer != null,
              settingsSelected: footer == HomeSidebarFooter.settings,
              onOverview: () => _select(null),
              onSelect: (entry) => _select(entry.title),
              // 底部固定区：头像在上、设置在下（用户 2026-09-16 裁定 —— 桌面端这两个
              // 入口从顶栏搬到这里，恒贴侧栏底部、不随服务列表滚动）。
              // 2026-10-09 五轮：点击改成**在右栏显示**（不再是 push 子页面），
              // 所以这两行也要能显示选中态。
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeSidebarFooterRow(
                    key: homeSidebarProfileKey,
                    leading: const AccountAvatar(radius: 15),
                    label: '我的',
                    selected: footer == HomeSidebarFooter.profile,
                    onTap: () => _selectFooter(HomeSidebarFooter.profile),
                  ),
                  HomeSidebarFooterRow(
                    key: homeSidebarSettingsKey,
                    leading: Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    label: '设置',
                    selected: footer == HomeSidebarFooter.settings,
                    onTap: () => _selectFooter(HomeSidebarFooter.settings),
                  ),
                ],
              ),
            ),
          ),
          // 两块之间：**两块都是卡片** → 一道 **a** 宽的透明缝；否则是 1px 的空隙
          // （**不画分割线** —— 十三轮撤掉了那道 `VerticalDivider`：侧栏本来就是另一档
          // 底色（通栏 = `surfaceContainerLow` / 卡片 = 卡片色），分界靠色差就够）。
          // ⚠ 判据只看「**两块是不是卡片**」——**侧栏收起与否都不改这道缝**
          // （用户 2026-10-09 十九轮：「我希望收起之后与右侧卡片的间距不要变」）：
          // 收起后窄轨仍然是卡片（十八轮），它和内容卡之间当然还是同一个 `a`。
          // ⚠ 只有一侧是卡片时才不留缝：留了也只会白出一条带子（另一侧没有「卡片边」
          // 要跟它分开）。
          // 宽度仍是 1（不能直接删掉这个间隔件）：`AnimatedContainer` 的补间要有落点。
          AnimatedContainer(
            duration: CardFrame.duration,
            curve: Curves.easeOutCubic,
            width: sidebarCard && contentCard ? gap.between : 1,
          ),
          // 右栏：右边 / 底边的 `a` 由下面那层 `AnimatedPadding` 留。
          Expanded(
            // ⚠⚠ **卡片层必须在 `AnimatedSwitcher` 外面**（用户 2026-10-09 二十一轮：
            // 「为什么现在点击切换页面，会导致整个右侧内容卡片出现位置的水平闪动」）。
            //
            // 原来 `CardFrame` 在 `AnimatedSwitcher` 的 child 里面 → 换页时**整张卡片**
            // （圆角 / 描边 / 阴影）跟着 `SlideTransition` 一起横移：
            //   ① 看着就是"右侧内容卡片整体在水平闪动"；
            //   ② 卡片被 `Stack` 的边界裁掉一截 → 被裁的那一边**描边整段消失** ——
            //      这正是用户二十轮报的「圆角处框线断开」（当时我按对比度解释，**错了**，
            //      真正的原因在这里：切换动画期间卡片自己在动、边被裁掉了）。
            // 移出来之后：**框不动，只有页内容滑入 + 淡入**。
            child: Padding(
              padding: EdgeInsets.only(
                right: contentCard ? gap.edge : 0,
                bottom: contentCard ? gap.edge : 0,
              ),
              child: CardFrame(
                card: contentCard,
                radius: cardRadius,
                // 滑入的内容按卡片的圆角裁掉（内嵌页的 Scaffold 会自己铺满整块）。
                child: _paneSwitcher(
                  paneKey: paneKey,
                  footer: footer,
                  selected: selected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 右栏内容：概览 / 目录条目 / 底部固定区那两页 —— 三者都走**同一套内嵌通道**
  /// （`HomeDetailPane`：面板内独立 Navigator + `PaneScope(embedded: true)`）。
  ///
  /// ⚠ 设置页 / 我的页的 builder 一律经**跳转缝**取（`serviceScreenBuilder`，
  /// 组装根 `lib/main.dart` 注册）：`home` 不许直接 import 别家 presentation 页面
  /// —— 那条边早在 2026-09-20 就收口了，守卫会拦（见 §33.6.1.1）。
  ///
  /// ⚠ 三者都带 `sidebarPane: true`：右栏这一格上**任何**路由都不画导航栏
  /// （见 `_overviewPane()` 的注释）。
  Widget _buildPaneContent({
    required HomeSidebarFooter? footer,
    required HomeServiceEntry? selected,
  }) {
    final seamId = switch (footer) {
      HomeSidebarFooter.settings => kServiceSettings,
      HomeSidebarFooter.profile => kServiceStudentInfo,
      null => null,
    };
    if (seamId != null) {
      final builder = serviceScreenBuilder(seamId);
      // 未注册（单测只 pump 一个页面、不走组装根）→ 静默回落概览，与跳转缝同口径。
      if (builder == null) return _overviewPane();
      return HomeDetailPane(
        paneKey: footer!.name,
        sidebarPane: true,
        sidebarHost: _openEntryInPane,
        builder: builder,
      );
    }
    if (selected == null) return _overviewPane();
    return HomeDetailPane(
      paneKey: selected.title,
      sidebarPane: true,
      sidebarHost: _openEntryInPane,
      builder: selected.builder,
    );
  }

  /// 把右栏切到目录里的某一个条目 —— **概览卡片点开也走这里**。
  ///
  /// 用户 2026-10-10 二十七轮：「点击数据一览的卡片后，顶部路由不记录」。
  /// 根因是那段从前直接 `Navigator.of(context).push(...)` —— 只往面板内部的 Navigator
  /// 压了一层，**绕过了宿主的记账**（全局路由历史记在 [_select] / [_recordPaneHistory] 里）。
  ///
  /// 所以由宿主把它收回来：走和点侧栏条目**同一套**通道（记账 + 侧栏高亮 + 换页动画），
  /// 「往前退回到概览」也就自然由历史里那条 `restore` 负责（它本来就是切回那一格）。
  void _openEntryInPane(String entryTitle) {
    if (!mounted) return;
    _select(entryTitle);
  }

  /// 右栏默认那一格「数据一览」。
  ///
  /// ⚠⚠ **必须走 `HomeDetailPane`（= 面板的一条路由）**，不能再像从前那样直接
  /// `return _buildOverviewPane()` 把 `ListView` 裸渲染在右栏里（用户 2026-10-09
  /// 二十四轮的真因）：裸渲染时概览**不是面板路由**，它里面的卡片上查不到
  /// `PaneScope` → `dashboardPush` 退回整页 push → **页面占满整个窗口**。
  ///
  /// 所以这里和别的服务一视同仁：`HomeDetailPane(paneKey: kServiceOverview, builder: 概览)`。
  /// 页面本体在 `presentation/overview_pane.dart`（能在跳转缝里注册，必须独立成文件）。
  /// 未注册（单测不走组装根）→ 就地建一个，行为等价。
  ///
  /// ⚠ 这里取的 id 是 **`kServiceOverview`**（不是 `kServiceHome`！）：缝里那一个是
  /// "整页打开主页"，用它当键会让**注册表永远查不中** → 每次都走就地兜底，
  /// 于是"注册了却没用上"（本轮真踩过：两者不一致时表现完全一样，光跑测试看不出来）。
  ///
  /// ⚠ `sidebarPane: true` 一并交给 [HomeDetailPane]：右栏这一格上**任何**路由都不画
  /// 导航栏（用户 2026-10-10 二十六轮：「点击主页卡片后的效果还是不对，顶部不应该显示
  /// 标题栏」）—— 从概览点卡片是往同一个 Navigator 压第二层，若仍按"只有首路由才不画"
  /// 的判据，那一层就会凭空多出一条导航栏 + 返回键。
  Widget _overviewPane() {
    final builder = serviceScreenBuilder(kServiceOverview);
    return HomeDetailPane(
      paneKey: kServiceOverview,
      sidebarPane: true,
      sidebarHost: _openEntryInPane,
      builder: builder ?? () => const HomeOverviewPane(),
    );
  }

  /// 右栏的**换页动画**（内容滑入 + 淡入；与页面转场同一语言，见
  /// `lib/design/app_page_transitions.dart`）—— 从概览/上一个服务**硬切**改成滑动。
  ///
  /// ⚠⚠ **它只包"页内容"，卡片框不在这里**（用户 2026-10-09 二十一轮：
  /// 「点击切换页面，会导致整个右侧内容卡片出现位置的水平闪动」）。
  /// 卡片层由调用方（`_buildSidebarBody` 的 `Expanded`）包在**外面**，
  /// 于是切换时**框不动、只有页内容动**。
  ///
  /// ⚠ 必须自备 layoutBuilder：`AnimatedSwitcher` 默认那个用
  /// `Stack(alignment: center)` 且不撑满 → 右栏内容（`ListView` / 内嵌 `Navigator`）
  /// 会缩成内容大小、贴着中间，看起来像「页面变小了」。
  Widget _paneSwitcher({
    required String paneKey,
    required HomeSidebarFooter? footer,
    required HomeServiceEntry? selected,
  }) => AnimatedSwitcher(
    duration: appPaneSwitchDuration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      fit: StackFit.expand,
      children: <Widget>[...previous, ?current],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(appPaneSwitchOffsetX, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: KeyedSubtree(
      key: ValueKey<String>(paneKey),
      child: _buildPaneContent(footer: footer, selected: selected),
    ),
  );

  /// 按标题找回当前条目；目录里已不存在该标题（改版残留）→ 回落概览。
  HomeServiceEntry? _selectedEntry(List<HomeServiceEntry> entries) {
    final title = _selectedService;
    if (title == null) return null;
    for (final entry in entries) {
      if (entry.title == title) return entry;
    }
    return null;
  }

  void _select(String? title) {
    if (_selectedService == title && _selectedFooter == null) return;
    // 先把「离开的位置」记进历史，再切 —— 于是从任何一格都能按「后退」回到上一格。
    _recordPaneHistory(_selectedFooter, _selectedService);
    setState(() {
      _selectedService = title;
      _selectedFooter = null; // 目录条目与底部固定区互斥
    });
    _recordPaneHistory(null, title);
  }

  /// 把「右栏此刻显示哪一格」记进全局路由历史（顶部的前进 / 后退要用它）。
  ///
  /// `restore` 直接改选中项、**不走 `_select`**：历史回放时游标已经停在那一格上，
  /// 再记一笔会把历史顶歪。同 key 连续记两次只留一条（`RouteHistory.record` 去重）。
  void _recordPaneHistory(HomeSidebarFooter? footer, String? serviceTitle) {
    final label = footer == null
        ? (serviceTitle ?? homeSidebarOverviewTitle)
        : (footer == HomeSidebarFooter.settings ? '设置' : '我的');
    ref.read(routeHistoryProvider).record(
          RouteHistoryEntry(
            label: label,
            key: 'pane:$label',
            restore: () {
              if (!mounted) return;
              setState(() {
                _selectedFooter = footer;
                _selectedService = serviceTitle;
              });
            },
          ),
        );
  }

  /// 选中底部固定区的某一行（设置 / 我的）→ 右栏显示它（不再 push 子页面）。
  ///
  /// 「再点当前那行**不**回概览」—— 与目录行 [ _select ] 同口径（点已选中的服务是空操作，
  /// 回概览一律走顶部「数据一览」行）：两条路径行为一致才叫「与其他功能页统一」。
  void _selectFooter(HomeSidebarFooter footer) {
    if (_selectedFooter == footer && _selectedService == null) return;
    _recordPaneHistory(_selectedFooter, _selectedService);
    setState(() {
      _selectedFooter = footer;
      _selectedService = null;
    });
    _recordPaneHistory(footer, null);
  }

  /// push 一个整页（顶栏品牌区与侧栏底部共用同一种转场）。
  void _pushPage(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  // ---------- 标题栏的「页面动作」（宫格视图：设置 + 头像） ----------
  //
  // 顶栏不再显示账号名/卡号，也不再有「切换账号」按钮：姓名与卡号在「我的」页里看，
  // 账号管理（添加/切换/删除账户）走「我的」页右上角的退出图标 → AccountScreen。
  //
  // **侧栏视图下这两个入口不在这里**（用户 2026-09-16 裁定）：它们在左侧导航栏
  // 底部的固定区（头像在上、设置在下，见 `home_sidebar.dart`），标题栏那条
  // 只留品牌 + 三键。
  //
  // ⚠ 发布必须**排在构建之后**（post-frame）：标题栏是首页的**祖先**（挂在
  // `MaterialApp.builder` 上，在 Navigator 之上），在 build 里 notify 祖先 =
  // 「build 期间 markNeedsBuild」直接报错。
  /// 侧栏视图下：把「展开 / 收起侧边栏」那一枚发布到标题栏（品牌组最前面）。
  ///
  /// 用户 2026-10-09：「我希望展开/收起侧边栏的按钮放在标题栏」—— 从前它是侧栏工具栏
  /// 行尾那枚 chevron（收起后还会落到列表下方），现在**只**在标题栏，侧栏里不再画。
  /// 与 `_queueTitleBarActions` 一样必须 post-frame（标题栏是本页的祖先，build 里
  /// notify 祖先 = build 期间 markNeedsBuild）。
  void _publishSidebarToggle({required bool show}) {
    if (_sidebarToggleShown == show) return;
    _sidebarToggleShown = show;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final actions = _titleBarActions;
      if (actions == null) return;
      actions.update(
        // ⚠ 别动右侧那组（宫格视图的设置 / 头像由 `_queueTitleBarActions` 管）。
        visible: actions.visible,
        builder: actions.builder,
        leadingVisible: show,
        leadingBuilder: show ? _buildSidebarToggle : null,
      );
    });
  }

  /// 标题栏里那枚「展开 / 收起侧边栏」。
  ///
  /// ⚠ `context` 是标题栏的（在 Navigator 之上）—— 状态一律改本 State，先判 `mounted`。
  Widget _buildSidebarToggle(BuildContext context) {
    final collapsed = _sidebarManual ?? _autoCollapsedNow;
    return IconButton(
      key: homeSidebarTitleBarToggleKey,
      tooltip: collapsed ? '展开侧边栏' : '收起侧边栏',
      // 用户 2026-10-10 自绘的两个图标：源文件 `design/icons/侧边栏展开|收起.svg`，
      // Inkscape 导出到 `assets/images/icons/`（见 design/icons/README 的归置规矩）。
      // 图标表达**这个按钮会做什么**：收起态显示「展开」、展开态显示「收起」——
      // 与 tooltip 的措辞一致。
      // ⚠ `Image.asset` 不跟 IconButton 的 color 走，用 `color` + `BlendMode.srcIn`
      // 染色（按 alpha 当遮罩），深浅色主题都跟着前景色。
      icon: Image.asset(
        collapsed
            ? 'assets/images/icons/sidebar_expand.png'
            : 'assets/images/icons/sidebar_collapse.png',
        width: 18,
        height: 18,
        filterQuality: FilterQuality.medium,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        colorBlendMode: BlendMode.srcIn,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      onPressed: () {
        if (!mounted) return;
        // ⚠ 取**当下**的实际状态（闭包捕获的 `collapsed` 是外层旧值 → 「点展开后再也收不起来」）。
        setState(() => _sidebarManual = !(_sidebarManual ?? _autoCollapsedNow));
      },
    );
  }

  void _queueTitleBarActions({required bool visible}) {
    if (_actionsVisible == visible) return;
    _actionsVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final actions = _titleBarActions;
      if (actions == null) return;
      if (visible) {
        actions.update(visible: true, builder: _buildTitleBarActions);
      } else {
        actions.clear();
      }
    });
  }

  /// 标题栏右侧那两颗（设置 + 头像）。
  ///
  /// ⚠ 传进来的 `context` 是**标题栏**的（在 Navigator 之上）→ `Navigator.of(context)`
  /// 找不到路由。导航一律走本 State 自己的 `context`（在 Navigator 之内），
  /// 并先判 `mounted`（动作已收回后仍可能有一帧的旧 widget 被点到）。
  Widget _buildTitleBarActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠ **头像在前、设置在后**（用户 2026-10-10：窄屏顶栏要「头像在最左侧」）。
        // 消费方（标题栏的窄屏排布 / `paneAppBar` 的窄屏排布）都是**原样**摆这串，
        // 不再自己反转 —— 顺序的唯一出处就是这里。
        // 个人入口：本地头像（未设置则姓名首字，再退通用图标）。
        AccountAvatar(
          radius: 13,
          tooltip: '我的',
          onTap: () {
            if (!mounted) return;
            // 页面经跳转缝取（`home` 不直接 import 别家 presentation 页面）。
            final build = serviceScreenBuilder(kServiceStudentInfo);
            if (build == null) return;
            _pushPage(this.context, build());
          },
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            if (!mounted) return;
            openSettings(this.context);
          },
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}
