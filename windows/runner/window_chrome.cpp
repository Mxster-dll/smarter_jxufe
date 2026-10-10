#include "window_chrome.h"

#include <windowsx.h>

#include <commctrl.h>

#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>

#include <flutter/standard_method_codec.h>

// 原生命中测试的临时探针（默认关；排查「鼠标消息到底进了哪个窗口」时改成 1）。
// 打开后每个命中测试都会往 `.probe/window_chrome.log` 追加一行；探针脚本在
// `.probe/win_chrome_probe.ps1`（拖动 / 双击 / 三键 / 边缘缩放四项端到端）。实测台账见
// `docs/agents/43-…（桌面窗口标题栏）.md`。**发布前确认这里是 0。**
#ifndef WINDOW_CHROME_TRACE
#define WINDOW_CHROME_TRACE 0
#endif

#if WINDOW_CHROME_TRACE
namespace {

void Trace(const char* format, ...) {
  FILE* file = nullptr;
  // 相对路径：探针脚本按约定在**仓库根目录**跑（公开仓库不写本机绝对路径）。
  if (fopen_s(&file, ".probe\\window_chrome.log", "a") != 0 ||
      file == nullptr) {
    return;
  }
  va_list args;
  va_start(args, format);
  std::vfprintf(file, format, args);
  va_end(args);
  std::fputc('\n', file);
  std::fclose(file);
}

}  // namespace
#else
#define Trace(...) ((void)0)
#endif

namespace {

// SetWindowSubclass 的子类 id（同一窗口 + 同一 proc 唯一即可）。
constexpr UINT_PTR kChildSubclassId = 1;

// 三键标识（与 Dart 侧 `WindowTitleBarButton.name` 一致）。
constexpr const char* kButtonMinimize = "minimize";
constexpr const char* kButtonMaximize = "maximize";
constexpr const char* kButtonClose = "close";

constexpr const char* kChannelName = "smarter_jxufe/window_chrome";

// 通道方法名（原生 → Dart）。
constexpr const char* kEventState = "windowState";
constexpr const char* kEventPointer = "titleBarPointer";

double ValueAsDouble(const flutter::EncodableValue& value, double fallback) {
  if (const auto* as_double = std::get_if<double>(&value)) {
    return *as_double;
  }
  if (const auto* as_int = std::get_if<int32_t>(&value)) {
    return static_cast<double>(*as_int);
  }
  if (const auto* as_long = std::get_if<int64_t>(&value)) {
    return static_cast<double>(*as_long);
  }
  return fallback;
}

}  // namespace

// Windows 11（build ≥ 22000）判定。
//
// 用 `RtlGetVersion` 而不是 `GetVersionEx` / `IsWindows11OrGreater` 之类：本进程带
// manifest（PerMonitorV2 + supportedOS），`GetVersionEx` 会按 manifest 谎报版本。
// 动态取 ntdll 的导出，拿不到就当 Win10（保守：多留 1px，宁可有条细线也不要顶边空白）。
bool WindowChrome::IsWindows11OrGreater() {
  using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  static const bool is_win11 = []() {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (ntdll == nullptr) {
      return false;
    }
    auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
        GetProcAddress(ntdll, "RtlGetVersion"));
    if (rtl_get_version == nullptr) {
      return false;
    }
    RTL_OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    if (rtl_get_version(&info) != 0) {
      return false;
    }
    return info.dwMajorVersion > 10 ||
           (info.dwMajorVersion == 10 && info.dwBuildNumber >= 22000);
  }();
  return is_win11;
}

WindowChrome::WindowChrome(HWND top_level, flutter::BinaryMessenger* messenger)
    : top_level_(top_level) {
  if (messenger != nullptr) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, kChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) { OnMethodCall(call, std::move(result)); });
  }
  // ⚠ 这里**不要**调 ApplyCustomFrame()：构造函数还在 `chrome_ = make_unique<...>`
  // 的右边，`FlutterWindow::chrome_` 此刻仍是 nullptr → 那条 WM_NCCALCSIZE 又回到
  // 默认处理，白算一次。由 `FlutterWindow::OnCreate` 在赋值**之后**调（实测踩过）。
}

// 强制按「自绘标题栏」重算一次非客户区。
//
// ⚠ 必须显式做一次，不能只靠 `WM_NCCALCSIZE` 分支：**窗口创建时的第一条
// `WM_NCCALCSIZE` 早于本对象存在**（那时 `FlutterWindow::chrome_` 还是 nullptr），
// 系统按「有标题栏」算了一次客户区；不重算的话窗口会一直顶着系统标题栏 ——
// 实测客户区比窗口小 **22×56**（系统标题栏还在，应用又在它下面画了一条自绘栏）。
// `SWP_FRAMECHANGED` 会强制重算，这一次就走到我们的处理里（重算后差值 = 0×0）。
void WindowChrome::ApplyCustomFrame() {
  if (top_level_ == nullptr) {
    return;
  }
  SetWindowPos(top_level_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

WindowChrome::~WindowChrome() {
  DetachChild();
}

void WindowChrome::AttachChild(HWND child) {
  if (child == nullptr || child == child_) {
    return;
  }
  DetachChild();
  child_ = child;
  child_subclassed_ =
      SetWindowSubclass(child, &WindowChrome::ChildSubclassProc,
                        kChildSubclassId, reinterpret_cast<DWORD_PTR>(this)) !=
      FALSE;
  Trace("[chrome] attach child=%p subclassed=%d", static_cast<void*>(child),
        child_subclassed_ ? 1 : 0);
}

void WindowChrome::DetachChild() {
  if (child_ != nullptr && child_subclassed_) {
    RemoveWindowSubclass(child_, &WindowChrome::ChildSubclassProc,
                         kChildSubclassId);
  }
  child_ = nullptr;
  child_subclassed_ = false;
}

// ---------------------------------------------------------------- 通道

void WindowChrome::OnMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "setTitleBarLayout") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "setTitleBarLayout 需要一个 map");
      return;
    }
    SetLayout(*args);
    result->Success(flutter::EncodableValue(StateValue()));
    return;
  }
  if (call.method_name() == "getWindowState") {
    result->Success(flutter::EncodableValue(StateValue()));
    return;
  }
  // 还原上次的窗口大小（用户 2026-10-10：「我希望应用记住上次启动时的窗口大小」）。
  // 传进来的是**逻辑像素**的客户区尺寸：这里按窗口 DPI 换成物理，再把「外框 − 客户区」
  // 那圈加回去 —— 本工程保留了原生边框（只是被 WM_NCCALCSIZE 收进窗口内），不补就会越缩越小。
  if (call.method_name() == "setClientSize") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr || top_level_ == nullptr) {
      result->Error("bad_args", "setClientSize 需要一个 map 且窗口已就绪");
      return;
    }
    auto read_num = [&args](const char* key) -> double {
      const auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end()) return 0;
      const auto* real = std::get_if<double>(&it->second);
      if (real != nullptr) return *real;
      const auto* integer = std::get_if<int32_t>(&it->second);
      return integer == nullptr ? 0 : static_cast<double>(*integer);
    };
    const double logical_width = read_num("width");
    const double logical_height = read_num("height");
    // 防呆：太小 / 非法值直接忽略（宁可保持系统默认，也不要缩成一个点）。
    // ⚠ 这条线与 Dart 侧 `window_size_keeper.dart` 的 `windowSizeMinimum` 同值 ——
    // 一开始写的是 480×360，把用户「真心想拖得很窄」的窗口挡在门外（拖窄了重启又变宽 ✗），
    // 现在只挡 0 / 负数 / 离谱值。改一处要一起改。
    if (logical_width < 200 || logical_height < 140) {
      result->Success(flutter::EncodableValue(StateValue()));
      return;
    }
    const UINT dpi = GetDpiForWindow(top_level_);
    const double scale = (dpi == 0) ? 1.0 : dpi / 96.0;
    RECT client{};
    RECT outer{};
    if (GetClientRect(top_level_, &client) && GetWindowRect(top_level_, &outer)) {
      const LONG frame_width =
          (outer.right - outer.left) - (client.right - client.left);
      const LONG frame_height =
          (outer.bottom - outer.top) - (client.bottom - client.top);
      const int target_width =
          static_cast<int>(logical_width * scale + 0.5) + frame_width;
      const int target_height =
          static_cast<int>(logical_height * scale + 0.5) + frame_height;
      Trace("[chrome] setClientSize %.0fx%.0f 逻辑 -> 外框 %dx%d (dpi=%u)",
            logical_width, logical_height, target_width, target_height, dpi);
      SetWindowPos(top_level_, nullptr, 0, 0, target_width, target_height,
                   SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    result->Success(flutter::EncodableValue(StateValue()));
    return;
  }
  result->NotImplemented();
}

void WindowChrome::SetLayout(const flutter::EncodableMap& args) {
  auto read_rect = [&args](const char* key, TitleBarRect* out) -> bool {
    const auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
      return false;
    }
    const auto* list = std::get_if<flutter::EncodableList>(&it->second);
    if (list == nullptr || list->size() != 4) {
      return false;
    }
    out->left = ValueAsDouble((*list)[0], 0);
    out->top = ValueAsDouble((*list)[1], 0);
    out->right = ValueAsDouble((*list)[2], 0);
    out->bottom = ValueAsDouble((*list)[3], 0);
    return true;
  };

  const auto enabled_it = args.find(flutter::EncodableValue("enabled"));
  enabled_ = false;
  if (enabled_it != args.end()) {
    if (const auto* flag = std::get_if<bool>(&enabled_it->second)) {
      enabled_ = *flag;
    }
  }

  const auto height_it = args.find(flutter::EncodableValue("height"));
  title_bar_height_ =
      height_it == args.end() ? 0 : ValueAsDouble(height_it->second, 0);

  has_buttons_ = read_rect("minimize", &minimize_button_) &&
                 read_rect("maximize", &maximize_button_) &&
                 read_rect("close", &close_button_);
  if (!has_buttons_) {
    // 三键缺失（比如某个平台画了标题栏却报不出按钮）→ 整条带子都不当标题栏，
    // 宁可少一个拖动区，也不要让三键点不动。
    enabled_ = false;
  }

  interactive_.clear();
  const auto interactive_it = args.find(flutter::EncodableValue("interactive"));
  if (interactive_it != args.end()) {
    if (const auto* list =
            std::get_if<flutter::EncodableList>(&interactive_it->second)) {
      for (const auto& item : *list) {
        const auto* rect = std::get_if<flutter::EncodableList>(&item);
        if (rect == nullptr || rect->size() != 4) {
          continue;
        }
        TitleBarRect value;
        value.left = ValueAsDouble((*rect)[0], 0);
        value.top = ValueAsDouble((*rect)[1], 0);
        value.right = ValueAsDouble((*rect)[2], 0);
        value.bottom = ValueAsDouble((*rect)[3], 0);
        interactive_.push_back(value);
      }
    }
  }

  Trace("[chrome] layout enabled=%d height=%.1f buttons=%d interactive=%u",
        enabled_ ? 1 : 0, title_bar_height_, has_buttons_ ? 1 : 0,
        static_cast<unsigned>(interactive_.size()));
}

flutter::EncodableMap WindowChrome::StateValue() const {
  flutter::EncodableMap value;
  value[flutter::EncodableValue("maximized")] =
      flutter::EncodableValue(maximized_);
  value[flutter::EncodableValue("minimized")] =
      flutter::EncodableValue(minimized_);
  value[flutter::EncodableValue("active")] = flutter::EncodableValue(active_);
  return value;
}

void WindowChrome::Notify(const char* method,
                          const flutter::EncodableValue& arguments) {
  if (channel_ == nullptr) {
    return;
  }
  channel_->InvokeMethod(method,
                         std::make_unique<flutter::EncodableValue>(arguments));
}

void WindowChrome::NotifyState() {
  Notify(kEventState, flutter::EncodableValue(StateValue()));
}

void WindowChrome::NotifyPointer() {
  flutter::EncodableMap value;
  value[flutter::EncodableValue("hovered")] =
      hovered_button_.empty() ? flutter::EncodableValue()
                              : flutter::EncodableValue(hovered_button_);
  value[flutter::EncodableValue("pressed")] =
      pressed_button_.empty() ? flutter::EncodableValue()
                              : flutter::EncodableValue(pressed_button_);
  value[flutter::EncodableValue("active")] = flutter::EncodableValue(active_);
  value[flutter::EncodableValue("maximized")] =
      flutter::EncodableValue(maximized_);
  Notify(kEventPointer, flutter::EncodableValue(value));
}

// ---------------------------------------------------------------- 几何

// 按窗口 DPI 取系统度量（物理像素）。dpi == 0（窗口还没建好）时退回未缩放的度量。
int WindowChrome::SystemMetricForDpi(int index, UINT dpi) const {
  if (dpi == 0) {
    return GetSystemMetrics(index);
  }
  return GetSystemMetricsForDpi(static_cast<UINT>(index), dpi);
}

double WindowChrome::DpiScale() const {
  const UINT dpi =
      top_level_ == nullptr ? 0 : GetDpiForWindow(top_level_);
  return dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
}

RECT WindowChrome::ClientRect() const {
  RECT rect{};
  if (top_level_ != nullptr) {
    GetClientRect(top_level_, &rect);
  }
  return rect;
}

double WindowChrome::BandHeight() const {
  return enabled_ ? title_bar_height_ * DpiScale() : 0;
}

bool WindowChrome::PointInRect(const TitleBarRect& rect,
                               const POINT& point) const {
  const double scale = DpiScale();
  const double x = static_cast<double>(point.x);
  const double y = static_cast<double>(point.y);
  return x >= rect.left * scale && x < rect.right * scale &&
         y >= rect.top * scale && y < rect.bottom * scale;
}

bool WindowChrome::PointInAnyRect(const std::vector<TitleBarRect>& rects,
                                  const POINT& point) const {
  for (const auto& rect : rects) {
    if (PointInRect(rect, point)) {
      return true;
    }
  }
  return false;
}

bool WindowChrome::Resizable() const {
  if (top_level_ == nullptr) {
    return false;
  }
  const LONG_PTR style = GetWindowLongPtr(top_level_, GWL_STYLE);
  return (style & WS_THICKFRAME) != 0;
}

// 边框厚度（物理像素，按该窗口 DPI）。
//
// ⚠ 用 GetSystemMetricsForDpi，不要再乘 DpiScale()：本进程是 PerMonitorV2，
// `GetSystemMetrics` 返回的**已经**是按（系统）DPI 缩放过、再乘一次就得到 1.5 倍的
// 边框（150% 缩放下实测 24px），标题栏带的下半截会被判成缩放区 → 「三键点不动、
// 点标题栏变成拉高度」。
int WindowChrome::BorderWidthX() const {
  const UINT dpi = top_level_ == nullptr ? 0 : GetDpiForWindow(top_level_);
  return SystemMetricForDpi(SM_CXSIZEFRAME, dpi) +
         SystemMetricForDpi(SM_CXPADDEDBORDER, dpi);
}

int WindowChrome::BorderWidthY() const {
  const UINT dpi = top_level_ == nullptr ? 0 : GetDpiForWindow(top_level_);
  return SystemMetricForDpi(SM_CYSIZEFRAME, dpi) +
         SystemMetricForDpi(SM_CXPADDEDBORDER, dpi);
}

// 命中测试里「顶部那条边框」的判定。
//
// 左 / 右 / 底三面**不在这里**：它们是真正的非客户区（见 WM_NCCALCSIZE 的收边），
// 系统自己会给 HTLEFT/HTRIGHT/HTBOTTOM 与四角，光标下最深的 Flutter 子窗口根本
// 覆盖不到那圈，所以这里也收不到那些点。只有**顶边**因为要贴着窗口顶边画标题栏
// （`rgrc[0].top += 0`，window_manager 同款）而落在客户区里，得由这里补回来 ——
// 少了它顶边就完全不能拖拽缩放（window_manager 0.4.3 就是这个行为）。
LRESULT WindowChrome::TopBorderHit(const POINT& point,
                                   const RECT& client) const {
  if (!Resizable() || IsZoomed(top_level_) || IsIconic(top_level_)) {
    return 0;
  }
  const int border_y = BorderWidthY();
  if (point.y >= border_y) {
    return 0;
  }
  const int border_x = BorderWidthX();
  if (point.x < border_x) return HTTOPLEFT;
  if (point.x >= client.right - border_x) return HTTOPRIGHT;
  return HTTOP;
}

// 命中测试前的探针几何：`WINDOW_CHROME_TRACE=1` 时，即使 Dart 还没上报布局也
// 给一套默认值（高 40、右侧三键各 46 宽），这样**只改原生**就能先把拖动 / 三键 /
// 缩放 / 贴靠全部跑通再做 Dart 侧。发布构建里整块被编译掉。
void WindowChrome::ApplyProbeLayout() {
#if WINDOW_CHROME_TRACE
  if (enabled_ && has_buttons_) {
    return;
  }
  const RECT client = ClientRect();
  const double scale = DpiScale();
  const double width = static_cast<double>(client.right) / scale;
  const double height = 40;
  const double button_width = 46;
  enabled_ = true;
  title_bar_height_ = height;
  has_buttons_ = true;
  close_button_ = TitleBarRect{width - button_width, 0, width, height};
  maximize_button_ =
      TitleBarRect{width - 2 * button_width, 0, width - button_width, height};
  minimize_button_ =
      TitleBarRect{width - 3 * button_width, 0, width - 2 * button_width, height};
  interactive_.clear();
#endif
}

// ---------------------------------------------------------------- 命中测试

LRESULT CALLBACK WindowChrome::ChildSubclassProc(HWND window,
                                                 UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam,
                                                 UINT_PTR subclass_id,
                                                 DWORD_PTR ref_data) noexcept {
  auto* self = reinterpret_cast<WindowChrome*>(ref_data);
  if (self != nullptr && message == WM_NCHITTEST) {
    return self->ChildHitTestOrPass(window, message, wparam, lparam);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

LRESULT WindowChrome::ChildHitTestOrPass(HWND child,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) {
  const LRESULT result = ChildHitTest(child, lparam);
  if (result != HTCLIENT) {
    Trace("[chrome] child hit (%d,%d) -> %ld", GET_X_LPARAM(lparam),
          GET_Y_LPARAM(lparam), static_cast<long>(result));
  }
  return result;
}

// Flutter 视图子窗口的命中测试：只吐「标题栏带」（含顶边那条缩放区），其余原样交给引擎。
//
// ⚠ 左 / 右 / 底**不在这里**：它们是真正的非客户区（`WM_NCCALCSIZE` 里收掉了一圈），
// 子窗口的矩形本来就不覆盖它们 → 系统直接按边框处理，用不着这里让路
// （旧版「客户区 = 整个窗口」才需要子窗口把边框吐出来；那是模拟，不是原生边框）。
LRESULT WindowChrome::ChildHitTest(HWND child, LPARAM lparam) {
  ApplyProbeLayout();
  if (!enabled_ || BandHeight() <= 0) {
    return DefSubclassProc(child, WM_NCHITTEST, 0, lparam);
  }
  POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  const HWND reference = top_level_ != nullptr ? top_level_ : child;
  if (!ScreenToClient(reference, &point)) {
    return DefSubclassProc(child, WM_NCHITTEST, 0, lparam);
  }
  if (static_cast<double>(point.y) < BandHeight()) {
    // 页面自己的动作（首页的设置 / 头像）留在客户区 —— 它们要能点、要能出 tooltip。
    if (PointInAnyRect(interactive_, point)) {
      return DefSubclassProc(child, WM_NCHITTEST, 0, lparam);
    }
    return HTTRANSPARENT;
  }
  return DefSubclassProc(child, WM_NCHITTEST, 0, lparam);
}

// 顶层窗口的命中测试：只会被子窗口「吐」出来的点问到（见 ChildHitTest）。
//
// ⚠ 返回 `std::nullopt` = 「这个点不归我判」→ 交给 `DefWindowProc`。**边框那圈必须
// 走这条路**：左/右/底是真非客户区（WM_NCCALCSIZE 收掉的一圈），系统靠默认处理才能
// 给出 HTLEFT/HTRIGHT/HTBOTTOM 与四角。旧版对所有客户区外的点一律回 HTCLIENT，
// 结果**整个边框拖不动**（2026-10-09 探针实测：右边缘拖拽 1600 → 1600 毫无反应）。
std::optional<LRESULT> WindowChrome::TopLevelHitTest(HWND window, LPARAM lparam) {
  ApplyProbeLayout();
  POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  if (!ScreenToClient(window, &point)) {
    return std::nullopt;
  }
  if (!enabled_ || BandHeight() <= 0) {
    return std::nullopt;
  }
  const RECT client = ClientRect();
  if (point.x < 0 || point.y < 0 || point.x >= client.right ||
      point.y >= client.bottom) {
    return std::nullopt;  // 边框圈 → 默认处理（缩放就靠它）
  }
  if (static_cast<double>(point.y) < BandHeight()) {
    // 顶边那条缩放区优先（原生 Windows 也是边框压住标题栏的最外圈）。
    const LRESULT top_border = TopBorderHit(point, client);
    if (top_border != 0) {
      Trace("[chrome] top hit client(%ld,%ld) top border -> %ld",
            static_cast<long>(point.x), static_cast<long>(point.y),
            static_cast<long>(top_border));
      return top_border;
    }
    // 三键一律回**非客户区命中码**：HTMAXBUTTON 是 Win11 贴靠布局的官方契约
    // （悬停最大化按钮弹贴靠面板），三个码同时决定鼠标消息进哪条路（WM_NC*）。
    if (has_buttons_) {
      if (PointInRect(close_button_, point)) {
        Trace("[chrome] top hit client(%ld,%ld) -> HTCLOSE",
              static_cast<long>(point.x), static_cast<long>(point.y));
        return HTCLOSE;
      }
      if (PointInRect(maximize_button_, point)) {
        Trace("[chrome] top hit client(%ld,%ld) -> HTMAXBUTTON",
              static_cast<long>(point.x), static_cast<long>(point.y));
        return HTMAXBUTTON;
      }
      if (PointInRect(minimize_button_, point)) {
        Trace("[chrome] top hit client(%ld,%ld) -> HTMINBUTTON",
              static_cast<long>(point.x), static_cast<long>(point.y));
        return HTMINBUTTON;
      }
    }
    if (PointInAnyRect(interactive_, point)) {
      return HTCLIENT;
    }
    Trace("[chrome] top hit client(%ld,%ld) -> HTCAPTION",
          static_cast<long>(point.x), static_cast<long>(point.y));
    return HTCAPTION;
  }
  // 标题栏带以下、客户区里的点：交回默认处理（否则 Flutter 会收不到鼠标）。
  return std::nullopt;
}

// ---------------------------------------------------------------- 三键

std::string WindowChrome::ButtonAt(const POINT& point) const {
  if (!has_buttons_) {
    return std::string();
  }
  if (PointInRect(close_button_, point)) return kButtonClose;
  if (PointInRect(maximize_button_, point)) return kButtonMaximize;
  if (PointInRect(minimize_button_, point)) return kButtonMinimize;
  return std::string();
}

void WindowChrome::SetHovered(const std::string& button) {
  if (hovered_button_ == button) {
    return;
  }
  hovered_button_ = button;
  NotifyPointer();
}

void WindowChrome::SetPressed(const std::string& button) {
  if (pressed_button_ == button) {
    return;
  }
  pressed_button_ = button;
  NotifyPointer();
}

void WindowChrome::PerformButtonAction(const std::string& button) {
  if (top_level_ == nullptr) {
    return;
  }
  Trace("[chrome] action %s zoomed=%d", button.c_str(),
        IsZoomed(top_level_) ? 1 : 0);
  if (button == kButtonMinimize) {
    PostMessage(top_level_, WM_SYSCOMMAND, SC_MINIMIZE, 0);
    return;
  }
  if (button == kButtonMaximize) {
    PostMessage(top_level_, WM_SYSCOMMAND,
                IsZoomed(top_level_) ? SC_RESTORE : SC_MAXIMIZE, 0);
    return;
  }
  if (button == kButtonClose) {
    PostMessage(top_level_, WM_SYSCOMMAND, SC_CLOSE, 0);
  }
}

// ---------------------------------------------------------------- 消息

std::optional<LRESULT> WindowChrome::HandleMessage(HWND window,
                                                   UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (wparam == FALSE) {
        return std::nullopt;  // 罕见分支：交给默认处理
      }
      // 非客户区怎么算 —— 口径照 `window_manager` 0.4.3 的 `TitleBarStyle.hidden`
      // （vshell 用的那套，用户 2026-10-09 指定「要用系统原生边框」）：
      //
      //   ① **顶部不留**（`top += IsWindows11 ? 0 : 1`）—— 自绘标题栏贴住窗口顶边，
      //      与原生 caption 的位置一致（Win10 那 +1 是他们踩出来的「顶边一条白线」）；
      //   ② **左 / 右 / 底各留一圈非客户区**（`SM_CXSIZEFRAME + SM_CXPADDEDBORDER`）
      //      —— 那圈是**真边框**：DWM 画边框 / 圆角 / 阴影，缩放热区由系统自己提供，
      //      我们一个 HTLEFT/HTRIGHT/HTBOTTOM 都不用模拟；
      //   ③ 最大化时用**显示器工作区**把客户区扩回来（`adjustNCCALCSIZE` 同款公式），
      //      否则内容会被挤出屏幕 / 压到任务栏下面。
      //
      // ⚠ 旧版这里是「客户区 = 整个窗口 + 自己模拟缩放边框」，观感上是「没有系统边框」
      // （用户原话：「我怎么觉得你没用系统原生边框呢」）—— 已按上面重做。
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      if (params == nullptr) {
        return std::nullopt;
      }
      if (IsZoomed(window)) {
        // 最大化：rgrc[0]（提议的窗口矩形）比工作区大一圈，按工作区把它扩回去。
        HMONITOR monitor = MonitorFromRect(&params->rgrc[0],
                                           MONITOR_DEFAULTTONEAREST);
        LONG inset_x = BorderWidthX();
        LONG inset_y = BorderWidthY();
        MONITORINFO info{};
        info.cbSize = sizeof(MONITORINFO);
        if (monitor != nullptr && GetMonitorInfo(monitor, &info) == TRUE) {
          inset_x = params->rgrc[0].left - info.rcWork.left;
          inset_y = params->rgrc[0].top - info.rcWork.top;
        }
        params->rgrc[0].left -= inset_x;
        params->rgrc[0].top -= inset_y;
        params->rgrc[0].right += inset_x;
        params->rgrc[0].bottom += inset_y;
      } else {
        params->rgrc[0].top += IsWindows11OrGreater() ? 0 : 1;
        params->rgrc[0].left += BorderWidthX();
        params->rgrc[0].right -= BorderWidthX();
        params->rgrc[0].bottom -= BorderWidthY();
      }
      return 0;
    }

    case WM_NCACTIVATE: {
      // 自绘标题栏时不让系统重画非客户区（window_manager 同款 return 1）—— 否则
      // 激活 / 失活那一下会把我们那条栏的背景擦成系统 caption 的颜色。
      const bool active = wparam != FALSE;
      if (active != active_) {
        active_ = active;
        if (!active_) {
          SetHovered(std::string());
          SetPressed(std::string());
        }
        NotifyState();
        NotifyPointer();
      }
      return 1;
    }

    case WM_NCHITTEST: {
      const std::optional<LRESULT> hit = TopLevelHitTest(window, lparam);
      if (hit.has_value()) {
        return *hit;
      }
      return std::nullopt;  // 边框圈 / 客户区其余部分 → 默认处理
    }

    case WM_NCMOUSEMOVE: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      SetHovered(ButtonAt(point));
      if (!tracking_leave_) {
        TRACKMOUSEEVENT track{};
        track.cbSize = sizeof(track);
        track.dwFlags = TME_LEAVE | TME_NONCLIENT;
        track.hwndTrack = window;
        tracking_leave_ = TrackMouseEvent(&track) != FALSE;
      }
      return std::nullopt;  // 不拦：系统还要照常走非客户区的默认处理
    }

    case WM_NCMOUSELEAVE:
      tracking_leave_ = false;
      SetHovered(std::string());
      return std::nullopt;

    case WM_NCLBUTTONDOWN: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      const std::string button = ButtonAt(point);
      Trace("[chrome] NCLBUTTONDOWN client(%ld,%ld) button=%s active=%d",
            static_cast<long>(point.x), static_cast<long>(point.y),
            button.empty() ? "-" : button.c_str(), active_ ? 1 : 0);
      if (button.empty()) {
        // 标题栏空白处 / 缩放边框：交给默认处理（拖动、双击最大化、贴靠全在这里）。
        return std::nullopt;
      }
      if (GetActiveWindow() != window) {
        SetForegroundWindow(window);
      }
      SetPressed(button);
      return 0;  // 自己处理动作，别让系统再发一次 SC_*
    }

    case WM_NCLBUTTONUP: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      const std::string button = ButtonAt(point);
      const std::string pressed = pressed_button_;
      Trace("[chrome] NCLBUTTONUP client(%ld,%ld) button=%s pressed=%s "
            "zoomed=%d",
            static_cast<long>(point.x), static_cast<long>(point.y),
            button.empty() ? "-" : button.c_str(),
            pressed.empty() ? "-" : pressed.c_str(), IsZoomed(window) ? 1 : 0);
      SetPressed(std::string());
      if (pressed.empty()) {
        if (button.empty()) {
          return std::nullopt;
        }
        return 0;
      }
      // 按下后滑出去再松手 = 取消（原生三键就是这个手感）。
      if (button == pressed) {
        PerformButtonAction(pressed);
      }
      return 0;
    }

    case WM_NCLBUTTONDBLCLK: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      Trace("[chrome] NCLBUTTONDBLCLK client(%ld,%ld)",
            static_cast<long>(point.x), static_cast<long>(point.y));
      // 双击三键本身不做事（原生同理）；双击标题栏空白处 = 最大化/还原，走默认处理。
      if (ButtonAt(point).empty()) {
        return std::nullopt;
      }
      return 0;
    }

    case WM_SIZE: {
      const bool maximized = IsZoomed(window) != FALSE;
      const bool minimized = IsIconic(window) != FALSE;
      if (maximized != maximized_ || minimized != minimized_) {
        maximized_ = maximized;
        minimized_ = minimized;
        NotifyState();
      }
      return std::nullopt;
    }

    case WM_ACTIVATE: {
      const bool active = LOWORD(wparam) != WA_INACTIVE;
      if (active != active_) {
        active_ = active;
        if (!active_) {
          SetHovered(std::string());
          SetPressed(std::string());
        }
        NotifyState();
        NotifyPointer();
      }
      return std::nullopt;
    }

    case WM_DESTROY:
      DetachChild();
      return std::nullopt;

    default:
      return std::nullopt;
  }
}






