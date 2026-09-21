/// 宫格**编辑模式**的开关（跨页面共享的一次性状态）。
///
/// 用户 2026-09-21 十三轮原话：「我希望标题栏不显示编辑模式按钮和重置按钮，这两个都放到
/// 设置里」—— 开关因此不能只活在 `_HomeScreenState` 里：**设置页要能拨它、主页宫格要能听它**
/// （宫格靠 `HomeServiceGrid.editMode` 这个入参工作，值一变它就在 `didUpdateWidget` 里
/// 进入 / 结算，见 `home_service_grid.dart`）。
///
/// **刻意不持久化**：它不是偏好，是一次编辑会话 —— 重启回到普通模式；编辑期间那些「断开」
/// 本来也只活到退出那一刻（退出时只有真的把卡片分成两块的缝才落盘，见 §17.10）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` = 宫格处于编辑模式（画分割线、按下即拖、点击拿起再点放下）。
final homeEditModeProvider = StateProvider<bool>((ref) => false);
