/// 全局设置入口 —— 标题栏右上角的「设置」按钮。
///
/// 用户 2026-09-16 裁定：「标题栏右上角永远显示一个设置按钮，只不过在主页点进去，
/// 直接进设置页，在不同的页面进入，也是进设置页，但是只显示此部分的设置项」。
///
/// 落地口径：
/// - **按钮自动注入**：`lib/design/pane_chrome.dart` 的 `paneAppBar` 会把它追加到
///   `actions` 末尾 —— 所有走 `paneAppBar` 的服务页（宫格 / 侧栏能直达的那 20 多个）
///   自动都有，**新页面也不用记得加**。侧栏内嵌模式（不画导航栏、也就没有 AppBar）
///   由页面自己给 `PaneBody` / `PaneActionRow` 传 `settingsSections`，齿轮补在
///   **既有**工具条的行尾 —— 用户 2026-09-17「课表页的设置按钮不见了」：课表页是
///   目前唯一这样做的页面（`scheduleSettingsSections`）；**没有工具条的空行不注入**
///   （那会凭空多出一条只有齿轮的 44px 横条，用户 2026-09-16 二轮否掉过）。
/// - **只显示本节**：页面用 `paneAppBar(context, …, settingsSections: [SettingsSection.calendar])`
///   声明自己相关的节；不声明 = 空 = 完整设置页（用户拍板：没有对应设置节的页面
///   —— 综测 / 材料库 / 体测 / 邮箱 / 规章制度 —— 当主页一样进完整设置页）。
/// - 二级页（畅想之星阅读器、入馆教育答题页、课程详情、编辑弹层…）用裸 `AppBar`，
///   不走 `paneAppBar`，因此**不会**出现设置按钮（用户拍板「所有服务主页、二级页不加」）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 设置按钮的尺寸契约：`iconSize 18` + `visualDensity: compact` + `constraints 30×30`
/// → **实测点击区宽 40**，与课表页 `scheduleBarAction` / `ScheduleTitleBar.actionWidth`
/// 同口径（课表标题栏的行宽计算按 40 记账，改这里要同步那处常量）。
const double settingsActionWidth = 40.0;

/// 打开设置页；[sections] 为空 = 完整设置页。
Future<void> openSettings(
  BuildContext context, {
  List<SettingsSection> sections = const <SettingsSection>[],
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => SettingsScreen(sections: sections)),
);

/// 可直接放进 `AppBar.actions` / `PaneActionRow.actions` 的设置按钮。
///
/// 由 `pane_chrome.dart` 统一注入，页面通常不必自己使用它。
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({super.key, this.sections = const []});

  /// 只显示这些节；空 = 完整设置页。
  final List<SettingsSection> sections;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '设置',
    icon: const Icon(Icons.settings_outlined),
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    onPressed: () => openSettings(context, sections: sections),
  );
}
