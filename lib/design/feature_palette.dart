import 'package:flutter/material.dart';

/// 首页功能宫格 / 仪表盘指标卡的功能分色板。
///
/// 全局主题为红主框架（seed #C3282E，见 main.dart），此处为各功能入口的
/// 点缀色（Material 深色调，白底可读），避免首页通篇单红、便于按功能辨识。
class FeaturePalette {
  FeaturePalette._();

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

  /// 学生个人数据中心。
  static const dataCenter = Color(0xFFD81B60);

  /// 宿舍电费。
  static const electricity = Color(0xFFF9A825);

  /// 网费。
  static const netFee = Color(0xFF0277BD);

  /// 综合测评（贴近主红，突出核心功能）。
  static const zongce = Color(0xFFC62828);

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
}
