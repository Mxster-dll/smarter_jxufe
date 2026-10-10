// 本文件是 `lib/design/window_chrome/` 拆分件之一 —— 文件地图见 docs/agents/43 的 §43.5。
// 公开入口仍是 `package:smarter_jxufe/design/window_title_bar.dart`（桶文件，对外零改动）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:smarter_jxufe/core/web/browser_nav.dart';
import 'package:smarter_jxufe/design/window_chrome/history_graph_painter.dart';

/// 顶部那条栏里的**全局路由历史**控件（`←` `→` `🕘`）。
///
/// - `←` / `→`：不可用时 `onPressed: null`（**禁用而不是藏起来** —— 藏起来会让按钮左右
///   横跳，禁用还能当「这里能回退」的提示）。
/// - `🕘`：历史面板（git 图），鼠标停上去 260ms 自动展开，点一下也能开关；面板里有 📌
///   可固定（固定后移开鼠标、点外面都不收）。
/// - ⚠ **不能用 `PopupMenuButton`**（用户实测「点击路由历史按钮无反应」）：它靠
///   `Navigator.push` 弹菜单，而标题栏挂在 `MaterialApp.builder` 上、是 Navigator 的
///   **兄弟** → 找不到 Navigator，菜单永远弹不出来。这里用 `OverlayPortal`（插进最近的
///   Overlay = `AppWindowChrome` 那个罩住整块 chrome 的 Overlay），既不需要 Navigator，
///   又能画到栏外、还能被点到。
/// - ⚠ 悬浮展开后**关闭要延迟**（用户实测「从历史按钮上移开就会让面板消失，不能移动到
///   面板上」）：按钮与面板是两棵子树（面板在 Overlay 里、中间还隔着一道缝），移出按钮
///   的那一瞬间就 `hide()` 的话鼠标根本来不及挪进面板。给 [_hoverCloseDelay] 宽限，
///   鼠标一进面板就取消它。
class WindowTitleBarHistory extends ConsumerStatefulWidget {
  const WindowTitleBarHistory({super.key});

  @override
  ConsumerState<WindowTitleBarHistory> createState() =>
      _WindowTitleBarHistoryState();
}

class _WindowTitleBarHistoryState extends ConsumerState<WindowTitleBarHistory> {
  final OverlayPortalController _panel = OverlayPortalController();

  /// 面板挂在按钮下方（`CompositedTransformFollower`）。
  final LayerLink _link = LayerLink();

  /// 钉住（用户 2026-10-09：「点击固定按钮固定不再消失」）。
  ///
  /// ⚠ 用 `ValueNotifier` 而不是 `setState`（用户同日三轮：「点击固定按钮后页面闪动」）：
  /// `setState` 会重建整条标题栏 → `OverlayPortal` 的 overlay 子件被拆挂一次 → 遮罩与
  /// 面板肉眼可见地闪一下。`ValueListenableBuilder` 只重建它自己那几行。
  final ValueNotifier<bool> _pinned = ValueNotifier<bool>(false);

  Timer? _hoverOpenTimer;
  Timer? _hoverCloseTimer;

  /// 悬浮 260ms 才展开 —— 鼠标只是扫过标题栏时不弹（不然很吵）。
  static const Duration _hoverOpenDelay = Duration(milliseconds: 260);

  /// 移出后的宽限：够鼠标从按钮挪到面板上。
  static const Duration _hoverCloseDelay = Duration(milliseconds: 320);

  @override
  void dispose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _pinned.dispose();
    super.dispose();
  }

  void _onEnter() {
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = null;
    if (_panel.isShowing) return;
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(_hoverOpenDelay, () {
      if (!mounted) return;
      if (ref.read(routeHistoryProvider).isEmpty) return;
      _panel.show();
    });
  }

  void _onExit() {
    _hoverOpenTimer?.cancel();
    if (_pinned.value) return;
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(_hoverCloseDelay, () {
      if (!mounted || _pinned.value) return;
      _panel.hide();
    });
  }

  /// 点面板外面：收起（钉住了就不收）。
  void _closeByOutsideTap() {
    if (_pinned.value) return;
    _panel.hide();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(routeHistoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurfaceVariant;

    // ⚠ 顶部这两枚「后退 / 前进」= **应用位置回退 + 内嵌网页的原生回退**，一个键一种读法
    // （用户 2026-10-10 二十九轮：「我不希望你手动记录，我只希望把浏览器原生的前进回退
    // 融合进来」）：
    //   - 当前有内嵌网页、且它还能往回走 → **回网页**（不碰 route_history）；
    //   - 回不了了 → 才回应用的上一个位置。
    // 用 `ListenableBuilder` 听那个单例，是为了让按钮的灰/亮跟着网页的历史变
    // （网页里点一层，这里就亮起来）。
    return ListenableBuilder(
      listenable: browserNavService,
      builder: (context, _) {
        final browser = browserNavService.state;
        final canBack = browser.canGoBack || history.canGoBack;
        final canForward = browser.canGoForward || history.canGoForward;

        Widget button({
          required Key key,
          required IconData icon,
          VoidCallback? onTap,
        }) =>
            IconButton(
              key: key,
              // ⚠ 历史这三枚**一律不挂 tooltip**（用户 2026-10-09 二十五轮：
              // 「把历史的悬浮提示文本关了」）。`tooltip` 为 null 时 `IconButton`
              // 不会建 `Tooltip`，鼠标停上去既不弹文字、也不会多出一层 hover 区域
              // （后者正是「从按钮挪到面板上就消失」那条 bug 的同族隐患）。
              icon: Icon(icon, size: 17),
              color: iconColor,
              disabledColor: iconColor.withValues(alpha: 0.35),
              onPressed: onTap,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 14,
            );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              key: const Key('windowTitleBarBack'),
              icon: Icons.arrow_back_rounded,
              onTap: !canBack
                  ? null
                  : () {
                      // 先在网页里退（`browserNavService.goBack` 返回 true = 它处理了）。
                      if (browserNavService.goBack()) return;
                      history.goBack();
                    },
            ),
        button(
          key: const Key('windowTitleBarForward'),
          icon: Icons.arrow_forward_rounded,
          onTap: !canForward
              ? null
              : () {
                  // 先在网页里进（同上）。
                  if (browserNavService.goForward()) return;
                  history.goForward();
                },
        ),
        if (!history.isEmpty)
          CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              onEnter: (_) => _onEnter(),
              onExit: (_) => _onExit(),
              child: OverlayPortal(
                controller: _panel,
                overlayChildBuilder: (context) => CompositedTransformFollower(
                  link: _link,
                  // 面板左上角贴在按钮左下角，只留 2px —— 用户两次说「太远」，
                  // 所以这里刻意紧贴（改动前是 4）。
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 2),
                  child: Align(
                    alignment: Alignment.topLeft,
                    // ⚠ 两块：全屏透明屏障（点外面收起）+ 面板本体。
                    // 面板外面再垫一层 `ColoredBox(transparent)`：它**参与命中测试**，
                    // 于是「按钮 → 那道 2px 缝 → 面板」连成一整块悬停区，鼠标挪下来
                    // 不会在中途被判成「移出」（配 `_hoverCloseDelay` 双保险）。
                    child: Stack(
                      children: [
                        // 遮罩常驻，钉住时只是不响应（拆掉再装上也会闪）。
                        Positioned.fill(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _pinned,
                            builder: (_, pinned, _) => IgnorePointer(
                              ignoring: pinned,
                              child: GestureDetector(
                                key: const Key('windowTitleBarHistoryBarrier'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeByOutsideTap,
                              ),
                            ),
                          ),
                        ),
                        MouseRegion(
                          onEnter: (_) => _onEnter(),
                          onExit: (_) => _onExit(),
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: _panelBody(context, history, scheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: button(
                  key: const Key('windowTitleBarHistoryMenu'),
                  icon: Icons.history_rounded,
                  onTap: _panel.isShowing ? _panel.hide : _panel.show,
                ),
              ),
            ),
          ),
      ],
    );
      },
    );
  }
  /// 历史面板本体：**一张 git 提交图**（用户 2026-10-09：「我希望这个历史直接显示一个
  /// git 图」）—— 左侧一条竖线 + 节点，右边是那一格的名字；顶上一行是标题 + 固定按钮。
  ///
  /// 三条着色口径（照着 git 图的读法）：
  /// - **游标所在那一笔**：实心大点 + 外圈；
  /// - **祖先链上的路**（`activePathIndices()`）：实心小点 + 主色线；
  /// - **其余**（另一条分支 / 还没前进回去的尾巴）：空心点 + 灰线；其中「前进会去的那一笔」
  ///   额外套一圈主色，分叉之后一眼看出前进走哪支。
  Widget _panelBody(
    BuildContext context,
    RouteHistory history,
    ColorScheme scheme,
  ) {
    final total = history.entries.length;
    final activePath = history.activePathIndices();
    final forwardTarget = history.forwardTargetIndex;
    return Material(
      key: const Key('windowTitleBarHistoryPanel'),
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minWidth: 200, maxWidth: 320, maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行 + 固定按钮。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                      '路由历史',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<bool>(
                    valueListenable: _pinned,
                    builder: (_, pinned, _) => IconButton(
                    key: const Key('windowTitleBarHistoryPin'),
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 15,
                    ),
                    color: pinned ? scheme.primary : scheme.onSurfaceVariant,
                    // 不 setState（见 _pinned 的注释）：只让这一枚和遮罩自己重建。
                    onPressed: () => _pinned.value = !_pinned.value,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                    splashRadius: 12,
                  ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < total; i++)
                      InkWell(
                        key: Key('windowTitleBarHistoryItem$i'),
                        onTap: history.entries[i].canRestore
                            ? () {
                                history.goTo(i);
                                if (!_pinned.value) _panel.hide();
                              }
                            : null,
                        child: SizedBox(
                          height: 30,
                          child: Row(
                            // ⚠ 必须 stretch：Row 默认给子件**松约束**，裸 `CustomPaint`
                            // 于是高度算成 0 —— 节点画得出来、竖线长度 0（实测就是
                            // 「有红点没线」）。拉满之后沟槽才是 30 高，线才有得画。
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                // 每条泳道 14 宽，再加左右各 8 的边距。
                                width: 16.0 + history.laneCount * 14,
                                child: CustomPaint(
                                  painter: HistoryGraphPainter(
                                    index: i,
                                    current: history.index,
                                    total: total,
                                    lane: history.laneOf(i),
                                    active: activePath.contains(i),
                                    isForwardTarget: i == forwardTarget,
                                    activePath: activePath,
                                    parentIndex: history.parentIndexOf(i),
                                    parentLane: history.parentIndexOf(i) >= 0
                                        ? history.laneOf(history.parentIndexOf(i))
                                        : 0,
                                    activeColor: scheme.primary,
                                    idleColor: scheme.outlineVariant,
                                    dimColor: scheme.outline,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  history.entries[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: history.entries[i].canRestore
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    fontWeight: i == history.index
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
