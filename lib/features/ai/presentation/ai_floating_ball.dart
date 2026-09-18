/// 全局悬浮球：挂在 `MaterialApp.builder` 上，任何页面都能随时叫出 AI。
///
/// 用户拍板的入口之一（另一个是首页宫格/侧栏条目）。
///
/// 四个实现要点：
/// - **必须包在 `builder` 里**（`lib/main.dart`），这样它浮在 `Navigator` 之上，
///   页面切换不会把它一起销毁；
/// - **只在手机 / 平板上出现** —— 桌面端（Windows / macOS / Linux）不出悬浮球，
///   入口交给侧栏「数据一览」正下方那一格（用户 2026-09-19 裁定：「我希望电脑端
///   不显示悬浮球」，见 [aiDesktopPlatformOn]）；
/// - 移动端上还要「设置 → AI 助手 → 全局悬浮球」开着、且对话页没开着；
/// - ⚠ `builder` 的 context 是根 Navigator 的**祖先**（见 [_openChat] 注释），
///   所以**绝对不能**用 `Navigator.of(context)`，得走全局 `navigatorKey`。
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';

/// 当前有几层 AI 对话页开着（>0 时悬浮球隐藏）。
final aiChatScreenOpenProvider = StateProvider<int>((ref) => 0);

/// 这条平台算不算「电脑端」（吃 `TargetPlatform.name` 的小写形式）。
///
/// **电脑端不出悬浮球**（用户 2026-09-19 裁定：「我希望电脑端不显示悬浮球」）：
/// 桌面端的入口 = 左侧导航栏「数据一览」正下方的「AI 助手」那一格
/// （`home_sidebar.dart` 的 `HomeServiceEntry.sidebarPinned`），再压一个圆球纯属
/// 重复，还会挡住正文；设置页「全局悬浮球」开关因此只管手机 / 平板。
///
/// 抽成**公开顶层纯函数**是为了能单测，与 `geMemoMobilePlatformOn` /
/// `avatarMobilePlatformOn` 同一口径（都吃 `TargetPlatform.name`）。
/// ⚠ 测试环境下 `defaultTargetPlatform` **恒为 `android`**
/// （`package:flutter/src/foundation/platform.dart:25`）→ 要测「桌面端隐藏」
/// 必须用 `debugDefaultTargetPlatformOverride` 显式覆盖。
bool aiDesktopPlatformOn(String platform) =>
    platform == 'windows' || platform == 'macos' || platform == 'linux';

/// 悬浮球宿主：包住整个 App。
class AiFloatingBallHost extends ConsumerStatefulWidget {
  final Widget child;

  const AiFloatingBallHost({super.key, required this.child});

  @override
  ConsumerState<AiFloatingBallHost> createState() => _AiFloatingBallHostState();
}

class _AiFloatingBallHostState extends ConsumerState<AiFloatingBallHost> {
  /// 距右下角的偏移（松手后吸附到最近的左右边）。
  ///
  /// 初值是**相对**值（负数 = 从右/下往内数）；拖动之后就变成绝对坐标了，
  /// [build] 两种都认。
  double _dx = -18;
  double _dy = -108;
  bool _dragging = false;

  /// 本次手势的**按下点**（全局坐标）+ 按下时的绝对位置。
  ///
  /// 用来把「几乎没动的点击」和「真拖拽」分开（见 [_tapSlop]），并在判定为
  /// 点击时把球**放回原位** —— 否则每点一次就漂 1~2px，多点几次球会自己走掉。
  ///
  /// ⚠ 位移必须由**全局坐标差**算，不能靠累加 `onPanUpdate` 的 delta：
  /// `gestures/monodrag.dart:805-811` 在默认的 `DragStartBehavior.start` 下把
  /// 首帧的 `localUpdateDelta` 置为 `Offset.zero` → **单次大幅移动根本不派发
  /// `onPanUpdate`**（`tester.moveBy` / 快速一甩都是这种），累加值恒为 0
  /// → 真拖拽会被误判成点击。（同时把 [GestureDetector.dragStartBehavior] 设成
  /// `down`，这样首帧那条被吞掉的位移会以完整 delta 补发，球才会跟手。）
  Offset _dragOrigin = Offset.zero;
  double _startLeft = 0;
  double _startTop = 0;

  static const double _size = 52;
  static const double _margin = 10;

  /// 「几乎没动」的阈值：累计位移不超过它就当成一次点击（打开对话页）。
  ///
  /// ⚠ 不能用 Flutter 自己的 tap/pan 竞技场裁决：**鼠标的拖拽 slop 只有 1 逻辑
  /// 像素**（`kPrecisePointerPanSlop = 1.0`，触屏才是 `kPanSlop = 36`）——
  /// 电脑端一次「点击」只要抖了 2px，外层 pan 就赢下竞技场、内层
  /// `InkWell.onTap` **永不触发**（用户 2026-09-19 报的「点击后概率无反应」）。
  /// 所以位移小的 pan 也要当点击补上（两条路互斥：竞技场只会判给一方，不会双开）。
  static const double _tapSlop = 8;

  /// 打开对话页。
  ///
  /// ⚠ **不能用 `Navigator.of(context)`**：本宿主挂在 `MaterialApp.builder` 上，
  /// 而 `D:\Program\flutter\packages\flutter\lib\src\widgets\app.dart:1707-1717` 里
  /// `routing`（根 `Navigator`）是**以参数塞进 builder 返回值内部**的 →
  /// 本 widget 的 context 是根 Navigator 的**祖先**、和它是**兄弟**关系，
  /// 祖先链上根本没有 `NavigatorState` → 每次点击都抛
  /// `Navigator operation requested with a context that does not include a Navigator`
  /// （被 `main.dart` 的 `FlutterError.onError` 吞成一行日志，用户只看到「点了没反应」）。
  /// 走 `main.dart:90` 挂在 `MaterialApp.navigatorKey` 上的全局 key 才拿得到它。
  void _openChat(BuildContext context) {
    // 兜底那条只在「宿主被放在 Navigator **下方**」的场合才成立
    // （`test/ai_floating_ball_test.dart` 之外的旧挂法 / 内嵌预览），
    // 真实 App 一定走前者。
    final navigator =
        navigatorKey.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);
    navigator?.push(
      MaterialPageRoute<void>(builder: (_) => const AiChatScreen()),
    );
  }

  /// `value.clamp(lower, upper)` 在 `upper < lower` 时会抛 `ArgumentError`：
  /// 窗口比球还窄/矮时（首帧、被拖到极小）真的会发生 → 先把上界抬到下界。
  static double _clampIn(double value, double lower, double upper) =>
      value.clamp(lower, upper < lower ? lower : upper);

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(aiFloatingBallProvider);
    final chatOpen = ref.watch(aiChatScreenOpenProvider) > 0;
    // ⚠ **隐藏时也必须返回同一个 `Stack` 形状**，不能图省事
    // `if (!enabled || chatOpen) return widget.child;`：
    // 形状一变（`Stack` ↔ `FocusScope`），`widget.child`（根 Navigator 整棵子树）
    // 会被卸载再用 GlobalKey 重新挂载，**宿主自己的 Riverpod 订阅会一并失效**
    // → 计数器从 1 落回 0 时宿主**不再重建**、悬浮球再也不出现。
    // 用户 2026-09-19 报的「电脑端不显示悬浮球」正是这条：在侧栏点开 AI 助手
    // （或点悬浮球进对话页）→ 球按设计隐藏 → 退出后球再也回不来。
    // 守卫 = `test/ai_floating_ball_test.dart` 的「关掉后回来」。
    return Stack(
      children: [
        widget.child,
        // 电脑端不出悬浮球（用户 2026-09-19 裁定，见 [aiDesktopPlatformOn]）。
        if (enabled &&
            !chatOpen &&
            !aiDesktopPlatformOn(defaultTargetPlatform.name))
          _ball(context),
      ],
    );
  }

  /// 悬浮球本体（含拖拽手势）。仅在显示时调用。
  Widget _ball(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxX = media.size.width - _size - _margin;
    final minY = media.padding.top + _margin;
    final maxY = media.size.height - _size - media.padding.bottom - _margin;

    final left = _clampIn(_dx < 0 ? media.size.width + _dx : _dx, _margin, maxX);
    final top = _clampIn(_dy < 0 ? media.size.height + _dy : _dy, minY, maxY);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        // 让「按下→越过 slop」那一段位移以完整 delta 补发（见 [_dragOrigin]）。
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => setState(() {
          _dragging = true;
          _dragOrigin = d.globalPosition;
          _startLeft = left;
          _startTop = top;
        }),
        // ⚠ 位移一律由「按下点 + 当前全局坐标」算，**不累加 d.delta、也不读
        // build 闭包里的 left/top**：同一帧内可能连续来好几个 move 而不重 build，
        // 那时闭包里的 left 还是旧的 → 球会滞后甚至被吸附算到错误的一侧。
        onPanUpdate: (d) => setState(() {
          _dx = _clampIn(
            _startLeft + (d.globalPosition.dx - _dragOrigin.dx),
            _margin,
            maxX,
          );
          _dy = _clampIn(
            _startTop + (d.globalPosition.dy - _dragOrigin.dy),
            minY,
            maxY,
          );
        }),
        onPanCancel: () => setState(() => _dragging = false),
        onPanEnd: (d) => setState(() {
          _dragging = false;
          final moved = d.globalPosition - _dragOrigin;
          if (moved.distance <= _tapSlop) {
            // 一次带抖动的点击：位置放回按下那一刻（不贴边、不漂移），
            // 并补上 InkWell 因竞技场判负而没拿到的那次「打开」。
            _dx = _startLeft;
            _dy = _startTop;
            _openChat(context);
            return;
          }
          // 真拖拽：吸附到更近的一侧，避免挡住正文。
          final finalLeft = _clampIn(_startLeft + moved.dx, _margin, maxX);
          final finalTop = _clampIn(_startTop + moved.dy, minY, maxY);
          final center = finalLeft + _size / 2;
          _dx = center < media.size.width / 2 ? _margin : maxX;
          _dy = finalTop;
        }),
        child: _Ball(
          size: _size,
          dragging: _dragging,
          onTap: () => _openChat(context),
        ),
      ),
    );
  }
}

class _Ball extends StatelessWidget {
  final double size;
  final bool dragging;
  final VoidCallback onTap;

  const _Ball({
    required this.size,
    required this.dragging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: dragging ? 1.08 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: scheme.primary,
        elevation: dragging ? 8 : 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.auto_awesome,
              size: 24,
              color: scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
