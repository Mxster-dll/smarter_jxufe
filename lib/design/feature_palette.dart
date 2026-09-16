import 'package:flutter/material.dart';

/// 首页功能宫格 / 仪表盘指标卡的功能分色板。
///
/// 全局主题为红主框架（seed #C3282E，见 main.dart），此处为各功能入口的
/// 点缀色（Material 深色调，白底可读），避免首页通篇单红、便于按功能辨识。
class FeaturePalette {
  FeaturePalette._();

  /// **全应用卡片强调色**（2026-09-15 用户裁定：卡片样式统一为「综测评测结果卡」形态，
  /// 「单一的其他颜色」的强调色一律改红）= 主题 `primary` 校红。
  ///
  /// 用在卡片标题竖条 / 卡片图标与图标底 / 分区点缀色 / TabBar 指示器 / 主按钮 上；
  /// 语义色（错误 / 成功 / 等级 / 假日 / 调课·补课·停课状态 / 图表配色）**不要**换成它。
  /// 与 `lib/design/app_card.dart` 的 `kAppCardAccent` 同值（那里是给无 context 场景的别名）。
  static const cardAccent = Color(0xFFC3282E);

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
}
