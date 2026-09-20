<!-- 本册 = AGENTS.md §25 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

## 25. 浮层定位（RuleTip）（2026-09-17 立）

用户原话：「综测页的悬浮提示位置不对，我希望显示在悬浮按钮周围，并且不能超出屏幕外」。
唯一实现 = `lib/features/zongce/presentation/widgets/rule_tip.dart`（`RuleTip`）：

- 定位用 **`OverlayEntry` → `Positioned.fill` → `CustomSingleChildLayout` + `_TipPositionDelegate`**：
  只有 delegate 的 `getPositionForChild(size, child)` 同时拿得到屏幕尺寸与**卡片真实尺寸**
  （旧实现按 `maxHeight`（≤400）估高 → 翻到上方时卡片离按钮很远）。规则：下方放得下
  （`anchor.bottom + gap + child.height ≤ size.height - margin`）→ 紧贴下沿；否则若
  `anchor.top - gap - child.height ≥ margin` → 贴上沿；两者都放不下 → 夹在屏幕内。
  横向 `anchor.center.dx - child.width/2` 夹在 `[margin, size.width - margin - child.width]`。
  `gap = 6`、`margin = 8`；卡片最大宽 420 / 最大高 460。卡片有 `Key`：`ruleTipCardKey`。
- **⚠ 两条硬约束（都实测踩到）**：
  1. **不能在 delegate 的布局回调里 `localToGlobal`** —— 布局期读祖先 `RenderBox.size` 被禁，
     报 `RenderBox.size accessed beyond the scope of resize, layout, or permitted parent access`
     （栈里可见 `RenderFractionalTranslation.applyPaintTransform` → `getTransformTo`），卡片会被
     扔到屏幕外。按钮矩形必须**在 build 时算好**传给 delegate。
  2. **`ScrollPosition` 的通知在新偏移应用之前同步发出** → 收到通知立刻重建，`localToGlobal`
     仍是旧位置，卡片原地不动。必须 `WidgetsBinding.instance.addPostFrameCallback` **帧后再
     `markNeedsBuild()`**（`_repositionScheduled` 去重）。滚动跟随 = `Scrollable.maybeOf(context)`
     的 position listener + 帧后重排；窗口变化 = `WidgetsBindingObserver.didChangeMetrics` 走同一路径。
- **不许遮盖悬停处（2026-09-18 追加 · 用户原话「综测的悬浮显示不能遮盖悬停的地方」）**：
  卡片高度上限改为 **较大一侧的实际可用空间**（`availBelow = size.height - margin - (anchor.bottom + gap)`、
  `availAbove = (anchor.top - gap) - margin`，取 `max` 后 clamp 到 ≤460）→「放不下就翻面」这条**永远成立**，
  卡片不可能压在按钮上；定位一律按**原始锚点** + `gap`（6 > 安全外扩 `_tipAnchorPadding = 4`，天然留 4px）。
  ⚠ 旧版高度固定 `clamp(120,460)`，矮窗口靠 `(size.height - margin - child.height).clamp(margin, belowTop)`
  兜底 —— 那一夹就把卡片夹到按钮上（实测 760×220 窗口：按钮 `[100,118]`，卡片 `[42,212]` **压住了**）。
- 守卫 = `test/rule_tip_position_test.dart`（**8 例**：下方紧贴 / 贴底翻到上方 / 靠右夹取 /
  矮窗口不越界 / **矮窗口卡片收缩且与按钮不相交** / **中部按钮不压按钮** / 滚动跟随（用 `ScrollPosition.jumpTo`，**不能用 `tester.drag`** —— 浮层卡片在
  列表之上会吃掉拖拽）/ 再点收起）。**测试必须真改窗口尺寸**（`tester.view.physicalSize`），
  只塞一个 `MediaQuery(data: MediaQueryData(size: …))` 不改变 Overlay 的实际大小 → 会得出
  「越界」的假结论。
