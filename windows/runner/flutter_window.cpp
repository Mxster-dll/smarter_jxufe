#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 自绘标题栏：隐藏系统标题栏（WM_NCCALCSIZE）+ 三键 / 拖动 / 缩放的命中测试，
  // 并给 Flutter 视图子窗口装 WM_NCHITTEST 子类化（子窗口会把命中测试吃掉）。
  chrome_ = std::make_unique<WindowChrome>(GetHandle(),
                                           flutter_controller_->engine()
                                               ->messenger());
  chrome_->AttachChild(flutter_controller_->view()->GetNativeWindow());
  // ⚠ 必须在 `chrome_` **赋值之后**调：它内部那条 SetWindowPos(SWP_FRAMECHANGED)
  // 会立刻派发 WM_NCCALCSIZE，而本类的消息入口是 `if (chrome_)` —— 早一步（哪怕是
  // 在 WindowChrome 的构造函数里）都会落回默认处理，系统标题栏就一直摘不掉
  // （实测：客户区比窗口小 22×56）。
  chrome_->ApplyCustomFrame();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 先摘子窗口子类化，再销毁引擎（子窗口销毁后 RemoveWindowSubclass 就没意义了）。
  chrome_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 自绘标题栏优先：非客户区消息（命中测试 / 三键 / 拖动）引擎不关心，
  // 拦在引擎前面才能保证三键的按下-抬起由我们自己收尾（否则会被默认处理再发一次
  // SC_*）。本类只 **消费**它真正处理的那几条，其余一律返回 nullopt 继续往下走。
  if (chrome_) {
    std::optional<LRESULT> chrome_result =
        chrome_->HandleMessage(hwnd, message, wparam, lparam);
    if (chrome_result) {
      return *chrome_result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
