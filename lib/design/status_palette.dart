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
