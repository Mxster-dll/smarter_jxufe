/// 首页服务目录 —— 宫格视图与左侧导航栏视图**共用同一份条目表**。
///
/// 历史：条目原本写在 `home_screen.dart` 的私有 `_items(context)` 里，强调色存在
/// 文件顶层的 `const _tileColors`，两者按**索引**对齐（AGENTS.md §3 的铁律：
/// 增删磁贴必须同步增删色表，否则后面所有磁贴错色）。
/// 2026-09-15 起强调色随条目一起定义（[HomeServiceEntry.accent]），
/// 索引对齐这条约定**作废** —— 侧栏要按分组重排，索引本来就会变。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_address_screen.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/jh_read_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/second_class_credit_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/course_selection_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_query_screen.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/leave/presentation/leave_screen.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_home_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/presentation/school_calendar_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/score_estimate_screen.dart';
import 'package:smarter_jxufe/features/tice/presentation/tice_screen.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_screen.dart';

/// 服务分组（只用于**左侧导航栏视图**的排版；宫格视图平铺不分节）。
///
/// 枚举顺序 = 侧栏里的分组顺序。
enum HomeServiceGroup {
  ims('教务系统'),
  study('学习与测评'),
  campus('校园生活'),
  info('数据与信息');

  const HomeServiceGroup(this.title);

  /// 侧栏里的分组标题。
  final String title;
}

/// 一条服务入口。
class HomeServiceEntry {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 所属分组（侧栏分组用）。
  final HomeServiceGroup group;

  /// 磁贴 / 侧栏图标的强调色（原来按索引取自 `_tileColors`）。
  final Color accent;

  /// 功能页构造器。
  ///
  /// 宫格视图（`onTap` → push 整页）与**左侧导航栏视图的右侧内嵌面板**
  /// （`HomeDetailPane` 把它装进面板自己的 Navigator）共用这一个入口
  /// —— 用户 2026-09-15 裁定第 2 条：点侧栏不再跳转整页。
  final Widget Function() builder;

  /// 宫格视图的点击行为（push 整页）。
  final VoidCallback onTap;

  const HomeServiceEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.group,
    required this.accent,
    required this.builder,
    required this.onTap,
  });
}

/// 全部服务入口（顺序 = 宫格里的铺排顺序；侧栏按 [HomeServiceGroup] 重排）。
///
/// [push] 由调用方给（页面用 `Navigator.of(context).push`，测试可注入记录器）。
List<HomeServiceEntry> homeServiceEntries({
  required void Function(Widget screen) push,
}) {
  Widget imsTab(ImsTab tab) => ImsSplashScreen(initialTab: tab);

  HomeServiceEntry entry(
    IconData icon,
    String title,
    String subtitle,
    HomeServiceGroup group,
    Color accent,
    Widget Function() screen,
  ) => HomeServiceEntry(
    icon: icon,
    title: title,
    subtitle: subtitle,
    group: group,
    accent: accent,
    builder: screen,
    onTap: () => push(screen()),
  );

  return [
    entry(
      ImsTab.curriculum.icon,
      ImsTab.curriculum.title,
      ImsTab.curriculum.subtitle,
      HomeServiceGroup.ims,
      FeaturePalette.curriculum,
      () => imsTab(ImsTab.curriculum),
    ),
    entry(
      ImsTab.schedule.icon,
      ImsTab.schedule.title,
      ImsTab.schedule.subtitle,
      HomeServiceGroup.ims,
      FeaturePalette.schedule,
      () => imsTab(ImsTab.schedule),
    ),
    entry(
      ImsTab.grade.icon,
      ImsTab.grade.title,
      ImsTab.grade.subtitle,
      HomeServiceGroup.ims,
      FeaturePalette.grade,
      () => imsTab(ImsTab.grade),
    ),
    entry(
      ImsTab.graduationRequirements.icon,
      ImsTab.graduationRequirements.title,
      ImsTab.graduationRequirements.subtitle,
      HomeServiceGroup.ims,
      FeaturePalette.graduation,
      () => imsTab(ImsTab.graduationRequirements),
    ),
    // 「我的」不在宫格里（用户 2026-09-11 裁定）——入口 = 顶栏右上角头像。
    entry(
      Icons.place_outlined,
      '学校地址',
      '四校区地址与邮编一览',
      HomeServiceGroup.campus,
      FeaturePalette.campus,
      () => const CampusAddressScreen(),
    ),
    entry(
      Icons.map_outlined,
      '校区地图',
      '官网四校区地图与交通示意图',
      HomeServiceGroup.campus,
      FeaturePalette.campusMap,
      () => const CampusMapScreen(),
    ),
    entry(
      Icons.volunteer_activism,
      '志愿服务时长',
      '查看学生志愿活动时长统计',
      HomeServiceGroup.campus,
      FeaturePalette.volunteer,
      () => const VolunteerHoursScreen(),
    ),
    entry(
      Icons.school_outlined,
      '第二课堂学分',
      '成绩单与学分预警 · 毕业达标进度',
      HomeServiceGroup.study,
      FeaturePalette.secondClass,
      () => const SecondClassCreditScreen(),
    ),
    entry(
      Icons.auto_stories_outlined,
      '蛟湖阅读',
      '阅读学分四部分进度 · 入馆教育与借阅达标',
      HomeServiceGroup.study,
      FeaturePalette.jhRead,
      () => const JhReadScreen(),
    ),
    entry(
      Icons.insights,
      '学生个人数据中心',
      '学业成绩 · 消费 · 图书 · 校园卡全景',
      HomeServiceGroup.info,
      FeaturePalette.dataCenter,
      () => const DataCenterScreen(),
    ),
    entry(
      Icons.electrical_services,
      '宿舍电费',
      '选择宿舍查询剩余电量 · 未绑定可一键绑定',
      HomeServiceGroup.campus,
      FeaturePalette.electricity,
      () => const ElectricityScreen(),
    ),
    entry(
      Icons.wifi_outlined,
      '网费',
      '校园网余额 · 充值记录一览',
      HomeServiceGroup.campus,
      FeaturePalette.netFee,
      () => const NetFeeScreen(),
    ),
    entry(
      Icons.event_note_outlined,
      '请假',
      '学生请假申请记录 · 审批进度查看',
      HomeServiceGroup.campus,
      FeaturePalette.leave,
      () => const LeaveScreen(),
    ),
    entry(
      Icons.workspace_premium_outlined,
      '综合测评',
      '证明材料自动测算 · 五育等次参考',
      HomeServiceGroup.study,
      FeaturePalette.zongce,
      () => const ZongceScreen(),
    ),
    entry(
      Icons.calculate_outlined,
      '分数估计',
      '平时分项计数 · 期末反推 · 达线预警',
      HomeServiceGroup.study,
      FeaturePalette.scoreEstimate,
      () => const ScoreEstimateScreen(),
    ),
    entry(
      Icons.fitness_center,
      '体测成绩',
      '国家体质测试总分与分项 · 本人成绩查询',
      HomeServiceGroup.study,
      FeaturePalette.tice,
      () => const TiceScreen(),
    ),
    entry(
      Icons.folder_outlined,
      '材料库',
      '证明文件归档 · 自动带入综测',
      HomeServiceGroup.study,
      FeaturePalette.materials,
      () => const MaterialsScreen(),
    ),
    entry(
      Icons.calendar_month,
      '校历',
      '学期教学周历 · 开学与假期起止一览',
      HomeServiceGroup.info,
      FeaturePalette.calendar,
      () => const SchoolCalendarScreen(),
    ),
    entry(
      Icons.rule_folder_outlined,
      '规章制度',
      '校规校纪 · 学分学籍 · 竞赛目录 · 奖助办法',
      HomeServiceGroup.info,
      FeaturePalette.rules,
      () => const RulesHomeScreen(),
    ),
    // 「上课实况窗」2026-09-15 从宫格迁到设置页（用户裁定：主页不要显示）。
    entry(
      Icons.travel_explore_outlined,
      '公共查询',
      '按教师/班级/教室/课程查课表 · 多班对照找共同空课时间',
      HomeServiceGroup.ims,
      FeaturePalette.publicQuery,
      () => const PublicQueryScreen(),
    ),
    entry(
      Icons.how_to_reg_outlined,
      '选课',
      '网上选课与选课结果 · 可选课程/教学班 · 退选与扩容申请',
      HomeServiceGroup.ims,
      FeaturePalette.courseSelection,
      () => const CourseSelectionScreen(),
    ),
  ];
}

/// 取某个分组的条目（保持 [homeServiceEntries] 的原始顺序）。
List<HomeServiceEntry> homeServiceEntriesInGroup(
  List<HomeServiceEntry> all,
  HomeServiceGroup group,
) => [for (final e in all) if (e.group == group) e];
