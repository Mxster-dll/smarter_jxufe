/// 设置页的分节口径。
///
/// 用户 2026-09-16 裁定：「标题栏右上角永远显示一个设置按钮，只不过在主页点进去，
/// 直接进设置页，在不同的页面进入，也是进设置页，但是只显示此部分的设置项」。
///
/// 页面通过 `paneAppBar(context, …, settingsSections: [SettingsSection.calendar])`
/// 声明本页相关的节；**空列表 = 完整设置页**（主页、以及没有对应设置节的页面）。
/// 枚举顺序 = 完整设置页里的分节顺序，`label` 同时用作「只显示本节」时的页面标题。
library;

enum SettingsSection {
  appearance('外观'),

  /// 内置 AI 助手（OpenAI 兼容接口、API Key、悬浮球开关）—— 见 `features/ai/`。
  aiAssistant('AI 助手'),
  campus('校区'),
  scope('生效范围'),
  homeLayout('主页布局'),
  calendar('校历'),
  /// 课表显示（周六 / 周日）——课表页齿轮进本节（用户 2026-09-17 要求）。
  schedule('课表'),
  libraryEdu('入馆教育'),
  platformGuid('平台标识'),
  liveClass('上课实况窗'),
  imsSession('教务会话'),
  cloudSync('云同步'),
  homeWidget('桌面小组件');

  const SettingsSection(this.label);

  /// 该节的标题（与设置页里 `geCardTitle` 的文本一致）。
  final String label;
}
