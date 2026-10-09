/// 语义色板（状态 / 等级 / 标签 / 品牌 / 一次性视觉值）——**唯一出处**。
///
/// 架构审查 ⑤ 的结论：`lib/features/**` 里散着 72 处 `Color(0x…)` 字面量，
/// 其中一批与 `lib/design/feature_palette.dart` 的 token **同值**（功能色与状态色
/// 恰好撞色），改一次主题要全仓搜字面量；另有一批是**只在某处用过一次**的视觉值
/// （遮罩、阅读器沉浸底、卡片头条带），散在页面里没人知道全貌。
///
/// 契约：
/// - **功能入口色**（宫格/侧栏/卡片图标）仍走 `lib/design/feature_palette.dart`；
/// - **状态 / 等级 / 标签 / 品牌 / 一次性视觉值**一律登记在本文件；
/// - 页面里**不许再写** `Color(0x…)` 字面量（守卫见 `test/core_conventions_test.dart`
///   「设计色值唯一口径」；唯一白名单 = 课程色板 `schedule_tone.dart`）。
///
/// ⚠ 同名 token 与 `FeaturePalette` 同值是**允许**的（值只有一个地方定义即可）：
/// 例如 `PlatformEntryTone.volunteer` 与 `FeaturePalette.volunteer` 都是 `#E65100`，
/// 但前者是「综合服务平台入口按钮」的语义，后者是「志愿服务」功能色 —— 语义分开，
/// 将来谁要改某个入口不会连坐。
library;

import 'package:flutter/material.dart';

/// 品牌 / 状态 / 一次性视觉值。
abstract final class StatusPalette {
  StatusPalette._();

  /// 微信品牌蓝（授权 / 扫码登录界面）。
  static const wechatBlue = Color(0xFF73A9EC);

  /// 微信成功绿（已扫码 / 授权完成）。
  static const wechatGreen = Color(0xFF14C468);

  /// 通过 / 正确（入馆教育答题判定）。
  static const success = Color(0xFF0F7B0F);

  /// 成绩单「重修」标记（深红）。
  static const retake = Color(0xFF800000);

  /// 弹层遮罩（70% 黑）。
  static const scrim = Color(0xB3000000);

  /// 拖起的宫格卡片投影（用户 2026-09-21「长按拖动合并宫格」——抬起的那张卡要有
  /// 「拿起来了」的实体感；异形卡片走 `Canvas.drawShadow`，所以这里给的是阴影本色）。
  static const liftedShadow = Color(0x99000000);

  /// 畅想之星阅读器沉浸底（与主题无关，阅读器自己的一套深浅）。
  static const readerBackdrop = Color(0xFF2B2B2B);

  /// 阅读器沉浸底上的正文色。
  static const readerInk = Color(0xFF1F1F1F);

  /// 学籍卡头条带（浅色档；深色档走 `AppColors.statusFill`）。
  static const infoBand = Color(0xFFEFA0A0);

  /// 学籍卡头条带文字（浅色档）。
  static const infoBandInk = Color(0xFF000000);

  /// 学科竞赛「团体」标签紫。
  static const competitionTeam = Color(0xFF6A1B9A);

  /// 体测「女」标签玫红（男走 `AppColors.info`）。
  static const ticeFemale = Color(0xFFAD1457);

  /// 开屏流光那道**高光**的本色（2026-10-08 立）。
  ///
  /// 为什么是「本色 + 调用方自己调透明度」而不是直接写 `Colors.white`：
  /// 建筑主体的石材面在白底下本来就接近 `#EDE7DF`，纯 `#FFFFFF` 扫过去差值太小、
  /// 看不出「流动」；这里给一个**略偏冷的白**（比石材冷、比页面底亮），
  /// 在浅色页面与深色页面（`#121212`）上都拉得出可读的对比度。
  /// 深色下不换色 —— 建筑图本身是彩色位图、不随主题反相，换色只会让两边不一致。
  static const splashShine = Color(0xFFEAF4FF);
}

/// 五育（综合素质测评）语义色 + 综测等级色。
///
/// 五育色沿用传统对应：德玫红 / 智蓝 / 体青绿 / 美紫 / 劳琥珀金。
///
/// **2026-09-21 二次定色（用户原话：「我觉得我现在调的五育不好看，你改改」）**：
/// 提亮那一版（`0xFFE23A2E`/`0xFF1E88E5`/`0xFF2A8F3C`/`0xFF8E5FD4`/`0xFF0F8C81`）的毛病
/// 不在「亮」而在**不齐**：五者白底对比度散在 3.68–4.43，智育蓝明显更亮，一行一个重量；
/// 且德育红与「不合格」红、体育绿与「优秀」绿几乎同色（ΔE 15 / 19），同一行里
/// 「育名 + 等次」会糊成一片。
///
/// 现在这五个色由两条硬指标一起定出来（不是挑好看的手感色）：
/// ① **同明度**：白底对比度一律 **4.75:1**（WCAG AA 对小字要 4.5）→ 五行等重、谁也不跳；
/// ② **互相离得开**：育与育之间最小 ΔE(CIE76) **55.9**，育与最近等次色最小 **ΔE 20.2**
///    （德育玫红 vs 不合格红、体育青绿 vs 优秀绿都拉开了）。
/// 它们同时是「育名 / 占比胶囊」的文字色，所以**要再亮就得先改形态**
/// （深色文字 + 淡底 / 加粗 / 改胶囊实底），别直接往 400/300 档走 —— 那会退回上面那个毛病。
/// 守卫 = `test/core_conventions_test.dart`「五育色 = 2026-09-21 定色后的取值」。
abstract final class ZongceTone {
  ZongceTone._();

  static const deyu = Color(0xFFD03860);
  static const zhiyu = Color(0xFF2B77B8);
  static const tiyu = Color(0xFF1E8261);
  static const meiyu = Color(0xFFBA31CF);
  static const laoyu = Color(0xFF926D22);

  /// 单项达标档位色（`ZcGrade`）。
  static const gradeOk = Color(0xFF00A870);
  static const gradeGood = Color(0xFF2F7BFF);
  static const gradePass = Color(0xFFED7B2F);
  static const gradeFail = Color(0xFFE5484D);
}

/// 体测等级色（优秀绿 / 良好蓝 / 及格橙 / 不及格红 / 未识别灰）。
abstract final class TiceTone {
  TiceTone._();

  static const excellent = Color(0xFF2E7D32);
  static const good = Color(0xFF0288D1);
  static const pass = Color(0xFFEF6C00);
  static const fail = Color(0xFFC62828);
  static const unknown = Color(0xFF9E9E9E);
}

/// 材料库标签色（类型 / Ⅰ~Ⅳ 类 / 级别 / 奖项）。
abstract final class MaterialsTone {
  MaterialsTone._();

  /// 类型标签的中性墨蓝（也是所有未命中判词时的兜底色）。
  static const typeNeutral = Color(0xFF455A64);

  /// Ⅰ~Ⅳ 类（同时也是国家级 / 省级 / 市校 / 院级的级别色）。
  static const category1 = Color(0xFFB3261E);
  static const category2 = Color(0xFFE65100);
  static const category3 = Color(0xFF1565C0);
  static const category4 = Color(0xFF00695C);

  /// 班级级别（级别里唯一不与类别撞色的那一档）。
  static const levelClass = Color(0xFF6A1B9A);

  /// 奖项档位：特等/一等/金奖 → 银奖 → 铜奖 → 优胜/优秀 → 未获奖/合格。
  static const awardGold = Color(0xFFB8860B);
  static const awardSilver = Color(0xFF607D8B);
  static const awardBronze = Color(0xFF8D6E63);
  static const awardHonor = Color(0xFF00838F);
  static const awardNone = Color(0xFF757575);
}

/// 阅读学分五部分的点缀色（圆环分段与图例，四部分各不相同便于辨认）。
abstract final class ReadCreditTone {
  ReadCreditTone._();

  static const classic = Color(0xFF2E7D32);
  static const ordinary = Color(0xFF1565C0);
  static const libraryEdu = Color(0xFF00B8D4);
  static const infoLiteracy = Color(0xFFEF6C00);
  static const culture = Color(0xFF795548);
}

/// 综合管理服务平台首页三个入口按钮的强调色。
///
/// ⚠ 与 `FeaturePalette` 里的同名功能色**值不同**（第二课堂：这里 `#6A1B9A`、
/// 色板 `#3949AB`；蛟湖阅读：这里 `#1565C0`、色板 `#6D4C41`）—— 历史遗留。
/// 本次只做「值搬家」，**没有改任何一个像素**；要统一得用户先拍板换哪个值。
abstract final class PlatformEntryTone {
  PlatformEntryTone._();

  static const volunteer = Color(0xFFE65100);
  static const secondClass = Color(0xFF6A1B9A);
  static const jhRead = Color(0xFF1565C0);
}

/// 校区矢量地图的**两套配色**（浅色 / 深色）。
///
/// 用户 2026-10 要求「可以手动切换两种风格的地图」。这里只放色值，
/// 语义与挑选理由见 `docs/agents/41-校区矢量地图.md`：
/// - `light` 为默认，底图米白、道路白、建筑暖灰，与全站浅色主题一致；
/// - `dark` 为夜间款，底图炭灰、道路中灰、建筑深灰，**不自发光**，
///   深色模式下长时间看也不刺眼；
/// - 两套的 `accent` 都是校红 `#C3282E` 系（校色），用于水体描边与
///   「我的校区」高亮，保证换风格时品牌色不丢。
///
/// ⚠ 页面里**不许**再写 `Color(0x…)`（守卫见 `test/core_conventions_test.dart`
/// 「设计色值唯一口径」）—— 地图配色只能从这里取。
abstract final class CampusMapTone {
  CampusMapTone._();

  // ---------- 浅色（日间）----------
  static const lightGround = Color(0xFFF7F5F0);
  static const lightWater = Color(0xFFA9CCE3);
  static const lightWaterEdge = Color(0xFF7FA8C4);
  static const lightGreen = Color(0xFFCFE0BF);
  static const lightSport = Color(0xFFE9D9A6);
  static const lightSportEdge = Color(0xFFC9B47C);
  static const lightRoad = Color(0xFFFFFFFF);
  static const lightRoadCasing = Color(0xFFDCD7CD);
  static const lightBuilding = Color(0xFFE0D9CD);
  static const lightBuildingEdge = Color(0xFFBFB6A6);
  static const lightBuildingNamed = Color(0xFFCEC3B0);
  static const lightLabel = Color(0xFF3A3630);
  static const lightLabelHalo = Color(0xF2FFFFFF);

  // ---------- 深色（夜间）----------
  static const darkGround = Color(0xFF1E1F22);
  static const darkWater = Color(0xFF24455C);
  static const darkWaterEdge = Color(0xFF3D6C8C);
  static const darkGreen = Color(0xFF2A3A2A);
  static const darkSport = Color(0xFF4A4029);
  static const darkSportEdge = Color(0xFF6B5C36);
  static const darkRoad = Color(0xFF4A4B4F);
  static const darkRoadCasing = Color(0xFF2C2D30);
  static const darkBuilding = Color(0xFF34363A);
  static const darkBuildingEdge = Color(0xFF4E5156);
  static const darkBuildingNamed = Color(0xFF42454A);
  static const darkLabel = Color(0xFFE6E2DA);
  static const darkLabelHalo = Color(0xE61E1F22);

  // ---------- 两套共用：校色 ----------
  static const accent = Color(0xFFC3282E);
  static const accentSoft = Color(0xFFE57373);
}

/// 窗口标题栏（自绘三键）的语义色 —— Win 风格与 mac 风格各一套。
///
/// 取值不是挑出来的：**Windows 风格**的关闭键悬停底色就是 Win11 原生 caption
/// 按钮的 `#C42B1C`（Windows 11 默认浅色主题下实测取样），其余按钮的悬停 / 按下
/// 底色由主题的 `onSurface` 调透明度得到（不登记在这里 —— 它跟着深浅色走）。
/// **mac 风格**三个指示灯用 macOS 的固定色（红 / 黄 / 绿），窗口失焦时整组转灰
/// 也是 macOS 的规矩。守卫 = `test/window_title_bar_test.dart`。
abstract final class WindowChromeTone {
  WindowChromeTone._();

  /// Windows 风格：关闭键悬停 / 按下时的底色（Win11 原生）。
  static const windowsCloseHighlight = Color(0xFFC42B1C);

  /// macOS 风格：关闭（红）。
  static const macClose = Color(0xFFFF5F57);

  /// macOS 风格：最小化（黄）。
  static const macMinimize = Color(0xFFFEBC2E);

  /// macOS 风格：最大化 / 全屏（绿）。
  static const macZoom = Color(0xFF28C840);

  /// macOS 风格：窗口失焦时三个指示灯一律转灰。
  static const macInactive = Color(0xFFC6C6C6);
}
