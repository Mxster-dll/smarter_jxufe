/// **窗口标题栏（自绘）** —— 隐藏系统标题栏之后的应用级 chrome。
///
/// 分工：**画与量在这里**，**命中测试在原生**（`windows/runner/window_chrome.cpp`）。
/// 完整口径与实测台账见 `docs/agents/43-桌面窗口标题栏（隐藏系统标题栏·自绘三键·贴靠）.md`。
///
/// 2026-10-10 重构：原单文件 1146 行拆成 `lib/design/window_chrome/` 下 7 件
/// （排布模型 / 栏本体 / 三键 / 几何上报 / chrome 外壳 / 路由历史 / 分叉图 painter），
/// **本文件只做再导出**，对外路径与符号零改动（文件地图见 §43.5）。
library;

export 'window_chrome/app_window_chrome.dart';
export 'window_chrome/history_graph_painter.dart';
export 'window_chrome/title_bar_history.dart';
export 'window_chrome/title_bar_model.dart';
export 'window_chrome/title_bar_regions.dart';
export 'window_chrome/window_buttons.dart';
export 'window_chrome/window_title_bar.dart';
