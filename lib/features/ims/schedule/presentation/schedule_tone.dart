/// 课表用色的深浅两档（**唯一实现**，竖版 / 横版共用）。
///
/// 背景：用户 2026-09-17 报「课表的颜色没有做深色适配」。课表的「课程底板 12 色」
/// 原先是两份**硬编码的浅色 pastel**（`schedule_grid_view.dart` 与
/// `schedule_horizontal_view.dart` 各一份），深色主题下仍是浅底 + 深字 ——
/// 在深色页面上既刺眼，又与 §22 的 A 阶梯（低阶 `#1A1A1A`）完全不搭。
///
/// 口径（**浅色逐值冻结，只修深色**，与 §22「浅色侧一个色值都不许动」一致）：
/// - 浅色 = 原样返回 pastel 底 + 原深色文字；
/// - 深色 = 底色改用「同色相实底」= 把提亮后的同色相按 [darkFillAlpha] 叠到卡片底
///   （[Color.alphaBlend] 出**实色**，不受下层影响）；文字见下面两条。
///
/// ## 深色下格内文字的两个角色（2026-09-17 第三轮立，别合并）
/// 用户三轮口径：① 「深色模式的课表，每个课程内部的文字用白色，但是浅色模式的
/// 显示不变」→ ② 「深色模式课程字体颜色不要用纯白，太亮」→ ③ 「感觉课程名的
/// 颜色还是太亮」。第 ② 轮只从 `#FFFFFF` 降到 `#EBEBEB`（亮度 −8%），肉眼几乎
/// 没差别，所以第 ③ 轮落到真正的一档：
/// - **课程名**（格内加粗那行）走 [name] = [darkCourseName]（`#C8C8C8`，
///   比正文色再暗 27% 相对亮度）；
/// - **次级行**（教师 / 教室 / 周次）走 [meta] 再 `.withAlpha(130~190)` 淡化，
///   基准色**不动**（`#EBEBEB`）—— 它们本来就比课名暗得多（实测 α140 那档压在
///   最亮的课格底 `#265458` 上只有 3.34:1，已经低于 AA），跟着一起降会掉到
///   3.2:1、把元信息读没了。降课名不会造成层级倒挂：α190 的教师行合成色
///   ≈ `#B9C5C6`，仍明显暗于课名的 `#C8C8C8`。
///
/// 为什么不用半透明色直接画：课程格底下可能是页面底、卡片底或空格子填充，
/// 同一门课在不同位置会得到不同观感；叠成实色后 14 色恒定。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';

abstract final class ScheduleTone {
  /// 星期表头（工作日）底色 —— 校徽红，与改动前逐值相同。
  static const Color headerRed = Color(0xFFC62828);

  /// 星期表头（周末）底色 —— `Colors.blueGrey.shade700` 的同值常量。
  static const Color weekendHeader = Color(0xFF455A64);

  /// 补课格底板（无源课程时的固定浅绿）。
  static const Color extraFill = Color(0xFFE8F5E9);

  /// 课程底板 **14 色**（浅色档）。前 12 色 = 改动前的 `_coursePalette`（**逐值未动**），
  /// 末尾 2 色是 2026-09-17 扩表新增（用户原话：「感觉课表中课程卡片的颜色不够丰富，
  /// 可以稍微再添加一两种」）。
  ///
  /// ⚠ **取模扩表会重新分配已有课程的颜色**：[`_index`] 是 `seed % n`（seed =
  /// `entry.courseCode.hashCode.abs()`），n 从 12 变 14 后多数课程的落点都会平移。
  /// 这是用户主动要求加色的必然结果（色值本身仍是原值），不是缺陷。
  ///
  /// 新色的挑法 = **填色相空档**，不是凭感觉加（实测表见 [courseTexts]）：
  /// 原 12 色在深色下的色相是 0/0/10/22/38/95/125/185/212/234/254/276（°），
  /// 两处最大的空档 = 276°→360°（84°）与 125°→185°（60°），新色正好落进去。
  static const List<Color> courseFills = <Color>[
    Color(0xFFE3F2FD), // 浅蓝
    Color(0xFFFFF3E0), // 浅橙
    Color(0xFFE8F5E9), // 浅绿
    Color(0xFFFCE4EC), // 浅粉
    Color(0xFFF3E5F5), // 浅紫
    Color(0xFFE0F7FA), // 浅青
    Color(0xFFFFF8E1), // 浅黄
    Color(0xFFEFEBE9), // 浅棕
    Color(0xFFE8EAF6), // 靛蓝
    Color(0xFFF1F8E9), // 浅黄绿
    Color(0xFFFFEBEE), // 浅红
    Color(0xFFEDE7F6), // 深紫
    Color(0xFFF8BBD0), // 玫红（新增，pink 100 —— 比浅粉更饱和，一眼分得出）
    Color(0xFFE0F2F1), // 青绿（新增，teal 50）
  ];

  /// 课程文字 **14 色**（浅色档 = 原 `_textPalette` 12 色 + 末尾 2 个新增；深色档由它
  /// 提亮得到）。
  ///
  /// 新增两色的实测（`design_preview/schedule_palette_candidates.png` 是选色对照板）：
  /// | 新增 | 浅色字/底对比 | 深色底 | 深色底色相 | 课名(`#C8C8C8`)对比 | 与既有 12 色的最小 ΔE76 |
  /// |---|---|---|---|---|---|
  /// | 玫红 `#880E4F` | 5.85:1 | `#532B40` | 329° | 7.02:1 | **13.2**（最像浅粉，一眼可辨） |
  /// | 青绿 `#00695C` | 5.71:1 | `#265852` | 173° | 4.83:1 | 6.9（最像浅青，仍可辨） |
  ///
  /// 候选里另外两个（**橄榄 `#827717`/`#F9FBE7`、蓝灰 `#37474F`/`#ECEFF1`**）实测
  /// 分别只到 ΔE 7.5 / 8.0，且橄榄又是一张暖褐卡（深色下与浅黄 `#564527` 撞调）、
  /// 蓝灰是中性灰（用户要的是「更丰富」，不是更灰）→ 均未采用，对照板里留着备查。
  static const List<Color> courseTexts = <Color>[
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFF9A825),
    Color(0xFF4E342E),
    Color(0xFF283593),
    Color(0xFF558B2F),
    Color(0xFFB71C1C),
    Color(0xFF4527A0),
    Color(0xFF880E4F), // 玫红（pink 900）
    Color(0xFF00695C), // 青绿（teal 800）
  ];

  /// 深色课格底的「同色相实底」透明度 —— **唯一取值点**（[darkTint] 的默认值）。
  ///
  /// 演进：初版 `0.20` → **本值**。用户 2026-09-17 第四轮原话：「课表深色模式下，
  /// 课程卡片颜色较暗，稍微提亮一点」。
  ///
  /// 取值依据（实测，非估计）：叠出来的 12 色底亮度整体 +35%~56%（如青格
  /// `#234346`→`#265458`、橙格 `#462F23`→`#583826`），与卡片底 `#1A1A1A` 的
  /// 分离度 1.26:1 → **1.40:1**（一眼能看出「这是一格课」）。
  ///
  /// ⚠ **上限就是这里了，别再往上加**：
  /// - `0.30` 课程名 `#C8C8C8` 最差只剩 4.76:1（还够，但余量 0.26）；
  /// - `0.32` 掉到 **4.49:1**（已破 AA），`0.36` 4.02:1、`0.40` 3.60:1；
  /// - 次级行（教师/教室/周次，α140~190）也会跟着掉：α190 5.78→4.76、
  ///   α140 3.91→3.34（后者本就低于 AA，不是本轮引入，但别再加剧）。
  ///
  /// 想更亮必须**同时**抬课程名（如回到 `#D8D8D8`），那是另一档改动、要重新测。
  static const double darkFillAlpha = 0.28;

  /// 深色下的「同色相实底」：accent 低透明度叠在卡片底上。
  static Color darkTint(
    BuildContext context,
    Color accent, {
    double alpha = darkFillAlpha,
  }) => Color.alphaBlend(
    accent.withValues(alpha: alpha),
    AppColors.card(context),
  );

  /// 课程底板色；[seed] 是课程配色下标（任意整数，内部取模）。
  ///
  /// 深色下 = [darkTint]（[darkFillAlpha] 的同色相实底），14 色实测落在
  /// `#265458`（青，最亮）~ `#37304E`（深紫，最暗），与卡片底 `#1A1A1A`
  /// 的分离度 ≥ 1.40:1。
  static Color fill(BuildContext context, int seed) {
    final i = _index(seed);
    if (!AppColors.isDark(context)) return courseFills[i];
    return darkTint(context, featureTone(courseTexts[i]));
  }

  /// 课程格内**次级文字**（教师 / 教室 / 周次）的基准色 —— 调用方再按 α 淡化
  /// （`metaColor.withAlpha(140~190)`）。
  ///
  /// 深色下 = **全应用正文色** [AppLadder.darkOnSurface]（`#EBEBEB`）；浅色侧仍
  /// 逐值返回原 14 色深字（pastel 底必须配深字）—— **一个色值都不动**。
  ///
  /// ⚠ 它**不是**课程名的颜色（课名走 [name]，深色下比它更柔）。
  /// ⚠ 「本次停课 / 已调走」这类**语义降级**态由两个视图把颜色覆盖成
  /// `AppColors.textMuted`，不走这里。
  static Color meta(BuildContext context, int seed) =>
      AppColors.isDark(context) ? AppLadder.darkOnSurface : courseTexts[_index(seed)];

  /// 深色下**课程名**的柔光灰。
  ///
  /// 演进（用户 2026-09-17 三轮）：`#FFFFFF`（第一轮「文字用白色」）→
  /// `#EBEBEB`（第二轮「不要用纯白，太亮」，只降 8% ≈ 看不出）→ **本值**
  /// （第三轮「感觉课程名的颜色还是太亮」）。
  ///
  /// 取值依据：相对亮度比 [AppLadder.darkOnSurface] 低 **27%**、CIELAB 明度
  /// 93.4 → **80.7**（肉眼明确的一档）；压在 14 个课格实底上仍 ≥ **4.83:1**
  /// （最紧的是新增青绿格底 `#265852` 4.83:1；原 12 色里最亮的青格底
  /// `#265458` 5.04:1、最暗的深紫格底 `#37304E` 7.40:1，见 [darkFillAlpha]），
  /// 加粗 11–12px 完全够读。**别再往纯白回退**，
  /// 也别跟着 [meta] 一起降级（那会把次级行拖到 3.2:1）。
  static const Color darkCourseName = Color(0xFFC8C8C8);

  /// **课程名**色（格内加粗那一行）；深色下用 [darkCourseName]。
  ///
  /// ⚠ 「本次停课 / 已调走」这类**语义降级**态不走这里：两个视图会把颜色覆盖成
  /// `AppColors.textMuted`（改成亮字会毁掉「灰掉」的信号），照旧。
  static Color name(BuildContext context, int seed) =>
      AppColors.isDark(context) ? darkCourseName : courseTexts[_index(seed)];

  /// 固定底板（补课格这类）的深浅两档：浅色 = [light] 原值，深色 = 同色相实底
  /// （与 [fill] 同一个 [darkFillAlpha]，两处观感一致）。
  static Color tintFill(BuildContext context, Color light, Color accent) =>
      AppColors.isDark(context)
      ? darkTint(context, featureTone(accent))
      : light;

  /// **图形/文字**用的表头强调色（红 / 蓝灰）→ 深色下提亮。
  ///
  /// ⚠ 只给**线稿**用（左上角横竖版切换图标）。表头**实心底**不许走这里：
  /// 实心件按 §22 用「深、饱和、实」的档，深色下仍是原深红 [#headerRed]
  /// —— 提亮成 `#D96363` 后白字只有 3.55:1，`AppColors.onAccent` 会把「周一」
  /// 翻成近黑字（用户 2026-09-17：「顶部周几的文本不要用深灰，太暗」）。
  /// 见 [headerFill]。
  static Color header(BuildContext context, Color light) =>
      AppColors.tone(context, light);

  /// 星期表头 / 节次表头的**实心底**：深浅两档都返回原深色值。
  ///
  /// 理由：它是**实心件**（不是压在页面底上的文字色），白字压 `#C62828` 有
  /// 5.62:1、压周末的 `#455A64` 有 7.25:1 —— 两档都够 AA，`AppColors.onAccent`
  /// 两侧自动择白。浅色侧本来就返回原值 → **逐像素不变**。
  static Color headerFill(BuildContext context, Color light) => light;

  static int _index(int seed) {
    final n = courseFills.length;
    final i = seed % n;
    return i < 0 ? i + n : i;
  }
}
