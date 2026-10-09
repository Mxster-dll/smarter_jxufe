#ifndef RUNNER_WINDOW_CHROME_H_
#define RUNNER_WINDOW_CHROME_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <winternl.h>   // RTL_OSVERSIONINFOW（IsWindows11OrGreater 用）

#include <memory>
#include <optional>
#include <string>
#include <vector>

// 自绘窗口标题栏的**原生侧唯一实现**（Windows）。
//
// 目标（用户 2026-10-09 立项，原话：「把系统标题栏隐藏，然后让我们的顶部标题栏支持
// 三键（最小化/最大化/关闭）。然后让我们的顶部标题栏支持系统标题栏的各种特性」）：
// 系统标题栏一条都不画，三键由 Flutter 画在顶部标题栏里，但**命中测试仍交给系统**
// —— 于是拖动、双击最大化/还原、右键系统菜单、边缘缩放、Aero 贴靠、Win11 贴靠布局
// （悬停最大化按钮弹出贴靠面板）全部是原生行为，一个都不自己实现。
//
// 三件事拼起来：
//  ① `WM_NCCALCSIZE` → 客户区铺满整个窗口（= 没有非客户区 = 系统不画标题栏），
//     但**保留 `WS_CAPTION | WS_THICKFRAME`**：贴靠、圆角、阴影、最大化动画都靠它；
//  ② `WM_NCHITTEST` → 标题栏带返回 `HTCAPTION`，三键命中区返回
//     `HTMINBUTTON` / `HTMAXBUTTON` / `HTCLOSE`（`HTMAXBUTTON` 正是 Win11 贴靠
//     布局的官方契约，见 MS Learn《Support snap layouts for desktop apps》）；
//  ③ **子类化 Flutter 视图子窗口**：`FlutterViewController` 的视图是一个铺满客户区
//     的子窗口，而 `WM_NCHITTEST` 是发给**光标下最深的那个窗口**的 —— 子窗口不把
//     消息吐出来，顶层窗口一个都收不到（实测见 `docs/agents/43-…（桌面窗口标题栏）.md`）。子窗口对
//     「标题栏带 + 缩放边框」返回 `HTTRANSPARENT`（同线程内会继续问父窗口），
//     其余照旧交给引擎 = Flutter 正常收鼠标事件。
//
// 几何（标题栏高度、三键矩形、页面动作矩形）由 Dart 侧测量后经
// `smarter_jxufe/window_chrome` 通道上报，单位一律**逻辑像素**（原生侧按当前窗口
// DPI 换算成物理像素再比）。Dart 没上报之前 `enabled_ == false` = 整窗都是客户区
// （安全的默认值：启动瞬间窗口不能拖动，但也不会出现「点哪里都没反应」）。
class WindowChrome {
 public:
  WindowChrome(HWND top_level, flutter::BinaryMessenger* messenger);
  ~WindowChrome();

  WindowChrome(const WindowChrome&) = delete;
  WindowChrome& operator=(const WindowChrome&) = delete;

  // 子类化 Flutter 视图窗口；必须在引擎视图建好之后调用。
  void AttachChild(HWND child);
  void DetachChild();

  // 强制按「自绘标题栏」重算一次非客户区（构造函数里已经调过一次）。
  void ApplyCustomFrame();

  // 顶层窗口的消息钩子。返回 nullopt = 「本类不管，继续走默认处理」
  // （Win32Window / FlutterWindow 自己的分支照旧能跑到）。
  std::optional<LRESULT> HandleMessage(HWND window,
                                       UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam);

 private:
  // 逻辑像素矩形（左上角 = 客户区原点）。
  struct TitleBarRect {
    double left = 0;
    double top = 0;
    double right = 0;
    double bottom = 0;
  };

  static LRESULT CALLBACK ChildSubclassProc(HWND window,
                                            UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam,
                                            UINT_PTR subclass_id,
                                            DWORD_PTR ref_data) noexcept;

  // ---- 通道 ----
  void OnMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                        result);
  void SetLayout(const flutter::EncodableMap& args);
  flutter::EncodableMap StateValue() const;
  void Notify(const char* method, const flutter::EncodableValue& arguments);
  void NotifyState();
  void NotifyPointer();

  // ---- 几何 ----
  double DpiScale() const;
  RECT ClientRect() const;
  double BandHeight() const;
  bool PointInRect(const TitleBarRect& rect, const POINT& point) const;
  bool PointInAnyRect(const std::vector<TitleBarRect>& rects,
                      const POINT& point) const;
  // 边框厚度（物理像素，按窗口 DPI）：左/右/底那圈在 WM_NCCALCSIZE 里收成真非客户区，
  // 顶部那条因为要贴窗口顶边（top += 0）而落在客户区里，由 TopBorderHit 补回来。
  int BorderWidthX() const;
  int BorderWidthY() const;
  LRESULT TopBorderHit(const POINT& point, const RECT& client) const;
  static bool IsWindows11OrGreater();
  int SystemMetricForDpi(int index, UINT dpi) const;
  bool Resizable() const;

  // ---- 命中测试 ----
  void ApplyProbeLayout();
  LRESULT ChildHitTest(HWND child, LPARAM lparam);
  // nullopt = 这个点不归我们判（边框圈）→ 交回 DefWindowProc 给缩放命中码。
  std::optional<LRESULT> TopLevelHitTest(HWND window, LPARAM lparam);
  LRESULT ChildHitTestOrPass(HWND child, UINT message, WPARAM wparam, LPARAM lparam);

  // ---- 三键状态（悬停 / 按下 / 动作）----
  std::string ButtonAt(const POINT& point) const;
  void SetHovered(const std::string& button);
  void SetPressed(const std::string& button);
  void PerformButtonAction(const std::string& button);

  HWND top_level_ = nullptr;
  HWND child_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool enabled_ = false;
  double title_bar_height_ = 0;
  bool has_buttons_ = false;
  TitleBarRect minimize_button_;
  TitleBarRect maximize_button_;
  TitleBarRect close_button_;
  // 页面自己的动作（首页的设置 / 头像等）：留在客户区，原生只负责**不**把它们
  // 当成标题栏（否则点不动）。
  std::vector<TitleBarRect> interactive_;

  std::string hovered_button_;
  std::string pressed_button_;
  bool tracking_leave_ = false;
  bool active_ = true;
  bool maximized_ = false;
  bool minimized_ = false;
  bool child_subclassed_ = false;
};

#endif  // RUNNER_WINDOW_CHROME_H_



