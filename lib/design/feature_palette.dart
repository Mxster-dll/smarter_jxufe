import 'dart:math' as math;

import 'app_ladder.dart';

import 'package:flutter/material.dart';

/// 首页功能宫格 / 仪表盘指标卡的功能分色板。
///
/// 全局主题为红主框架（seed #C3282E，见 `lib/design/app_theme.dart`），此处为各功能
/// 入口的点缀色（Material 深色调，**白底可读**）。
/// 深色下不能直接用这些值（深底上对比度只有 3:1 上下），一律走 [FeatureColors] /
/// [fp]：那里会按 [featureTone] 口径自动提亮。这里保留的 `static const` 只给
/// 「拿不到 `BuildContext` 的静态场景」用（如桌面小组件的后台 isolate 绘制）。
class FeaturePalette {
  FeaturePalette._();

  /// **全应用卡片强调色**（2026-09-15 用户裁定：卡片样式统一为「综测评测结果卡」形态，
  /// 「单一的其他颜色」的强调色一律改红）= 主题 `primary` 校红。
  ///
  /// 用在卡片标题竖条 / 卡片图标与图标底 / 分区点缀色 / TabBar 指示器 / 主按钮 上；
  /// 语义色（错误 / 成功 / 等级 / 假日 / 调课·补课·停课状态 / 图表配色）**不要**换成它。
  /// 与 `lib/design/app_card.dart` 的 `kAppCardAccent` 同值（那里是给无 context 场景的别名）。
  static const cardAccent = Color(0xFFC3282E);

  /// **全应用卡片强调色 · 深色档**（亮红 `#F2555A`）。
  ///
  /// 用户 2026-09-16 看过 `design_preview/dark_mode_preview.html` 后拍板：
  /// 深色下强调色提亮为亮红档，浅色保留校徽红 [cardAccent]。
  /// 深色主题的 `colorScheme.primary` 就是它（见 `lib/design/app_theme.dart`），
  /// 因此「主题红」在两侧始终是同一个值，不会漂移。
  ///
  /// ⚠ 它**不是** [featureTone] 对 [cardAccent] 的结果（那会得到 `#D96368`）：
  /// 预览里「主题强调色」是一档单独定死的取值（`--accent-strong`），
  /// 而功能色板里的红（如 [dashboard]）走的是 `tone()` 提亮，两者刻意分开。
  ///
  /// **2026-09-16 回调**：用户上机后反馈「成绩页、加载圈的红色太浅了，回调一些」——
  /// 亮红档由 `#FF6B6E` 收到 **`#F2555A`**（页面底 #121212 上 6.72:1 → **5.55:1**）。
  /// 仍保足够亮以压在暗底上读得清（[AppLadder.darkOnPrimary] 深字压它 = 5.16:1），
  /// 但不再泛粉。别再往亮里调。
  static const cardAccentDark = Color(0xFFF2555A);

  /// [cardAccent] 的 10% 淡底（图标底板等），等价 `cardAccent.withValues(alpha: 0.10)`。
  static const cardAccentSoft = Color(0x1AC3282E);

  /// 培养方案课程。
  static const curriculum = Color(0xFF5E35B1);

  /// 我的课表（今日课程同色）。
  static const schedule = Color(0xFF1565C0);

  /// 成绩 / 课程加权。
  static const grade = Color(0xFF2E7D32);

  /// 毕业学分要求。
  static const graduation = Color(0xFF00838F);

  /// 基本信息。
  static const studentInfo = Color(0xFF546E7A);

  /// 学校地址。
  static const campus = Color(0xFF00897B);

  /// 校区地图。
  static const campusMap = Color(0xFF283593);

  /// 志愿服务时长。
  static const volunteer = Color(0xFFEF6C00);

  /// 第二课堂学分。
  static const secondClass = Color(0xFF3949AB);

  /// 学科竞赛（申请与公示，取「赛事」语义的琥珀金）。
  static const competition = Color(0xFFB8860B);

  /// 蛟湖阅读。
  static const jhRead = Color(0xFF6D4C41);

  /// 新生入馆教育。
  static const libraryEdu = Color(0xFF00B8D4);

  /// 学生个人数据中心。
  static const dataCenter = Color(0xFFD81B60);

  /// 数据一览 / 仪表盘小组件（App 主红，取「总览」语义）。
  static const dashboard = Color(0xFFC3282E);

  /// 宿舍电费。
  static const electricity = Color(0xFFF9A825);

  /// 网费。
  static const netFee = Color(0xFF0277BD);

  /// 网络服务 · 账号正常 / 设备在线（绿，取「可用」语义）。
  ///
  /// ⚠ 「网络服务」**没有**自己的装饰性强调色：段与子页一律用主题红
  /// （AGENTS §16「单色强调一律改主题红」；曾用过青蓝 `#00838F`，与同页第一段
  /// 的主题红并列出两套强调色，已撤）。这里只留状态语义色。
  static const networkServiceOk = Color(0xFF2E7D32);

  /// 网络服务 · 账号停机 / 欠费（红，取警示语义）。
  static const networkServiceStop = Color(0xFFC62828);

  /// 我的邮箱（学校学生邮箱账号，靛蓝，取「邮件」语义，与成绩绿、网费蓝区分）。
  static const myMail = Color(0xFF5C6BC0);

  /// 综合测评（贴近主红，突出核心功能）。
  static const zongce = Color(0xFFC62828);

  /// 分数估计（靛蓝，取「测算」语义）。
  static const scoreEstimate = Color(0xFF536DFE);

  /// 分数估计 · 构成占比条的期末段（中性蓝灰，与平时分靛蓝成对）。
  static const scoreEstimateFinal = Color(0xFF90A4AE);

  /// 分数估计 · 平时占比已设但尚未配置分项时的浅色占位段。
  static const scoreEstimatePending = Color(0xFFB0BEC5);

  /// 体测成绩。
  static const tice = Color(0xFF558B2F);

  /// 材料库。
  static const materials = Color(0xFF795548);

  /// 校历。
  static const calendar = Color(0xFF039BE5);

  /// 规章制度。
  static const rules = Color(0xFF37474F);

  /// 请假。
  static const leave = Color(0xFF6A1B9A);

  /// 平台标识（GUID）获取向导。
  static const guidGuide = Color(0xFF455A64);

  /// 上课实况窗（青蓝，取「实时」语义，与课表的靛蓝区分）。
  static const liveClass = Color(0xFF00ACC1);

  /// 调课（砖橙，取「临时变更」语义，与志愿服务的亮橙区分）。
  static const reschedule = Color(0xFFD84315);

  /// 补课（深绿，取「额外补上」语义）。
  static const makeUpClass = Color(0xFF2E7D32);

  /// 停课（灰，取「取消/失效」语义）。
  static const classCancelled = Color(0xFF9E9E9E);

  /// 校历角标「假」（放假，红系）。
  static const calendarHoliday = Color(0xFFC3282E);

  /// 校历角标「班」（补课 / 调休上班，复用补课深绿）。
  static const calendarMakeup = makeUpClass;

  /// 校历角标「其它事件」（运/考/军/到/教，蓝灰）。
  static const calendarEvent = Color(0xFF546E7A);

  /// 经典阅读 · 畅想之星（深青，与校历浅蓝、上课实况青蓝区分）。
  static const cxstar = Color(0xFF006064);

  /// 公共查询（按教师/班级/教室/课程查课表 + 多班对照找无课时间，靛紫）。
  static const publicQuery = Color(0xFF4527A0);

  /// 选课（网上选课 / 选课结果 / 退选与扩容，玫红）。
  static const courseSelection = Color(0xFFAD1457);

  /// 教务会话（设置页「教务会话」节：令牌探活 / 手动换票，深青绿）。
  static const imsSession = Color(0xFF00695C);

  /// 截止日期 · 网课（青，取「在线」语义）。
  static const deadlineOnline = Color(0xFF00838F);

  /// 截止日期 · 作业（沿用分数估计靛蓝）。
  static const deadlineHomework = scoreEstimate;

  /// 截止日期 · 考试（紫）。
  static const deadlineExam = Color(0xFF7B1FA2);

  /// 截止日期 · 其它（灰蓝）。
  static const deadlineOther = Color(0xFF78909C);

  /// 截止日期 · 今天截止 / 3 天内（橙，取临近语义）。
  static const deadlineSoon = Color(0xFFEF6C00);

  /// 截止日期 · 已过期（红，取警示语义）。
  static const deadlineOverdue = Color(0xFFC62828);

  /// 截止日期 · 已完成（灰）。
  static const deadlineDone = Color(0xFF757575);

  /// 推免成绩（深紫 —— 与「公共查询 #4527A0」「请假 #6A1B9A」同族但更深，
  /// 白底上可读；深色下由 [featureTone] 提亮）。
  static const recommendation = Color(0xFF4A148C);

  /// 竞赛奖励（深橙红 —— 与「志愿 #EF6C00」「调课 #D84315」同族但更深）。
  static const competitionAward = Color(0xFFBF360C);
}

/// 深色下功能强调色的**明度下限**。
///
/// 与用户 2026-09-16 看过并拍板的 `design_preview/dark_mode_preview.html` 里
/// `tone(hex, dark, st.lift ? 0.62 : 0)` 的 `floor` 同值。
const double featureToneFloor = 0.62;

/// 深色下的功能强调色口径：**只抬 HSL 明度**（抬到 [featureToneFloor]），
/// 色相不动、饱和度 ×0.92 —— 保证「同一个色」还是它自己，只是亮到深底上看得清。
///
/// 明度已经 ≥ 下限的色（如 `#90A4AE`、`#9E9E9E`）原样返回。
/// 逐值对应预览里的 `tone()` 实现（含 `Math.round` 与 0..255 clamp），
/// 由 `test/theme_dark_test.dart` 用 Node 侧同款实现产出的期望值守卫。
Color featureTone(Color base) {
  final double r = base.r, g = base.g, b = base.b;
  final double mx = math.max(r, math.max(g, b));
  final double mn = math.min(r, math.min(g, b));
  final double l = (mx + mn) / 2;
  if (l >= featureToneFloor) return base;
  double h = 0;
  double s = 0;
  if (mx != mn) {
    final double d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  return _hslToColor(h, math.min(1, s * 0.92), featureToneFloor);
}

Color _hslToColor(double h, double s, double l) {
  double r, g, b;
  if (s == 0) {
    r = l;
    g = l;
    b = l;
  } else {
    final double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final double p = 2 * l - q;
    double hue2rgb(double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    r = hue2rgb(h + 1 / 3);
    g = hue2rgb(h);
    b = hue2rgb(h - 1 / 3);
  }
  int c(double v) => (v * 255).round().clamp(0, 255);
  return Color.fromARGB(255, c(r), c(g), c(b));
}

/// 当前亮度下的功能色表。
///
/// 用法（页面里一律这样取，别再用 `FeaturePalette.xxx` 的静态值）：
/// ```dart
/// final f = fp(context);          // 或在每个 build 里取一次
/// ... iconColor: f.schedule
/// ```
/// 浅色下逐值 = [FeaturePalette] 的原值；深色下逐值 = [featureTone] 提亮后的值。
class FeatureColors {
  const FeatureColors._(this._dark);

  final bool _dark;

  /// 浅色（原值）。
  static const FeatureColors light = FeatureColors._(false);

  /// 深色（提亮档）。
  static const FeatureColors dark = FeatureColors._(true);

  /// 按 `Theme` 的亮度取色表。
  static FeatureColors of(BuildContext context) =>
      forBrightness(Theme.of(context).brightness);

  /// 按亮度取色表。
  static FeatureColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  Color _t(Color base) => _dark ? featureTone(base) : base;

  /// **主题强调色**：浅色校徽红 / 深色亮红。
  ///
  /// 刻意**不走** [featureTone]：它是单独定死的一档（预览里的 `--accent-strong`），
  /// 必须与 `colorScheme.primary` 逐值相等，否则「卡片上的红」和「按钮上的红」会分家。
  Color get cardAccent =>
      _dark ? FeaturePalette.cardAccentDark : FeaturePalette.cardAccent;
  Color get cardAccentSoft =>
      cardAccent.withValues(alpha: _dark ? AppLadder.darkSoftAlpha : 0.10);
  Color get curriculum => _t(FeaturePalette.curriculum);
  Color get schedule => _t(FeaturePalette.schedule);
  Color get grade => _t(FeaturePalette.grade);
  Color get graduation => _t(FeaturePalette.graduation);
  Color get studentInfo => _t(FeaturePalette.studentInfo);
  Color get campus => _t(FeaturePalette.campus);
  Color get campusMap => _t(FeaturePalette.campusMap);
  Color get volunteer => _t(FeaturePalette.volunteer);
  Color get secondClass => _t(FeaturePalette.secondClass);
  Color get competition => _t(FeaturePalette.competition);
  Color get jhRead => _t(FeaturePalette.jhRead);
  Color get libraryEdu => _t(FeaturePalette.libraryEdu);
  Color get dataCenter => _t(FeaturePalette.dataCenter);
  Color get dashboard => _t(FeaturePalette.dashboard);
  Color get electricity => _t(FeaturePalette.electricity);
  Color get netFee => _t(FeaturePalette.netFee);
  Color get networkServiceOk => _t(FeaturePalette.networkServiceOk);
  Color get networkServiceStop => _t(FeaturePalette.networkServiceStop);
  Color get myMail => _t(FeaturePalette.myMail);
  Color get zongce => _t(FeaturePalette.zongce);
  Color get scoreEstimate => _t(FeaturePalette.scoreEstimate);
  Color get scoreEstimateFinal => _t(FeaturePalette.scoreEstimateFinal);
  Color get scoreEstimatePending => _t(FeaturePalette.scoreEstimatePending);
  Color get tice => _t(FeaturePalette.tice);
  Color get materials => _t(FeaturePalette.materials);
  Color get calendar => _t(FeaturePalette.calendar);
  Color get rules => _t(FeaturePalette.rules);
  Color get leave => _t(FeaturePalette.leave);
  Color get guidGuide => _t(FeaturePalette.guidGuide);
  Color get liveClass => _t(FeaturePalette.liveClass);
  Color get reschedule => _t(FeaturePalette.reschedule);
  Color get makeUpClass => _t(FeaturePalette.makeUpClass);
  Color get classCancelled => _t(FeaturePalette.classCancelled);
  Color get calendarHoliday => _t(FeaturePalette.calendarHoliday);
  Color get calendarMakeup => _t(FeaturePalette.calendarMakeup);
  Color get calendarEvent => _t(FeaturePalette.calendarEvent);
  Color get cxstar => _t(FeaturePalette.cxstar);
  Color get publicQuery => _t(FeaturePalette.publicQuery);
  Color get courseSelection => _t(FeaturePalette.courseSelection);
  Color get imsSession => _t(FeaturePalette.imsSession);
  Color get deadlineOnline => _t(FeaturePalette.deadlineOnline);
  Color get deadlineHomework => _t(FeaturePalette.deadlineHomework);
  Color get deadlineExam => _t(FeaturePalette.deadlineExam);
  Color get deadlineOther => _t(FeaturePalette.deadlineOther);
  Color get deadlineSoon => _t(FeaturePalette.deadlineSoon);
  Color get deadlineOverdue => _t(FeaturePalette.deadlineOverdue);
  Color get deadlineDone => _t(FeaturePalette.deadlineDone);
  Color get recommendation => _t(FeaturePalette.recommendation);
  Color get competitionAward => _t(FeaturePalette.competitionAward);
}

/// [FeatureColors.of] 的简写：`fp(context).schedule`。
FeatureColors fp(BuildContext context) => FeatureColors.of(context);
