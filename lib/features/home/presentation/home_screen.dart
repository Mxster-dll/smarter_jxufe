import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_address_screen.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/jh_read_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/second_class_credit_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_sync_scope.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/live_class_screen.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/features/leave/presentation/leave_screen.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_home_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/presentation/school_calendar_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/score_estimate_screen.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';
import 'package:smarter_jxufe/features/tice/presentation/tice_screen.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_screen.dart';
import 'package:smarter_jxufe/shared/widgets/account_avatar.dart';

/// 单页功能主页 —— 登录后的统一落地页。
///
/// 所有功能入口扁平平铺（无平台分组、无二级菜单），点击直达功能页面。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context, scheme),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                children: [
                  // 桌面小组件同步触发点（首帧推送 + 回前台重推 + 冷启动路由）
                  const HomeWidgetSyncScope(child: DashboardPanel()),
                  const SizedBox(height: 26),
                  _buildSectionHeader(context, '全部服务'),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final items = _items(context);
                      const minCard = 208.0;
                      const gap = 12.0;
                      // 手机等窄屏：固定格子尺寸（单元格上限约 108px），
                      // 列数随可用宽度自适应（等价 SliverGridDelegate
                      // WithMaxCrossAxisExtent 语义），而不是固定列数。
                      final isCompact = constraints.maxWidth < 620;
                      var cols = 0;
                      double width = 0;
                      if (isCompact) {
                        const tileExtent = 108.0;
                        cols =
                            ((constraints.maxWidth + gap) / (tileExtent + gap))
                                .ceil();
                        if (cols < 2) cols = 2;
                        width =
                            (constraints.maxWidth - gap * (cols - 1)) / cols;
                      } else {
                        cols = (constraints.maxWidth + gap) ~/ (minCard + gap);
                        if (cols < 1) cols = 1;
                        if (cols > 6) cols = 6;
                        width =
                            (constraints.maxWidth - gap * (cols - 1)) / cols;
                      }
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            SizedBox(
                              width: width,
                              child: _buildFeatureCard(
                                context,
                                items[i],
                                _tileColors[i % _tileColors.length],
                                compact: isCompact,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ---------- 顶部：品牌 + 设置 + 头像（点头像进「我的」） ----------
  //
  // 顶栏不再显示账号名/卡号，也不再有「切换账号」按钮：
  // 姓名与卡号在「我的」页里看，账号管理（添加/切换/删除账户）走
  // 「我的」页右上角的退出图标 → AccountScreen。
  Widget _buildTopBar(BuildContext context, ColorScheme scheme) {
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '尼',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '智慧尼采',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          // 全局设置入口（紧凑排布，避免窄屏顶栏溢出）。
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          const SizedBox(width: 4),
          // 个人入口：本地头像（未设置则姓名首字，再退通用图标）。
          AccountAvatar(
            radius: 18,
            tooltip: '我的',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudentInfoScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- 功能卡片 ----------
  Widget _buildFeatureCard(
    BuildContext context,
    _HomeItem item,
    Color accent, {
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accentBg = accent.withValues(alpha: 0.10);

    if (compact) {
      // 窄屏紧凑宫格：图标在上、名称在下（表格视图）。
      return Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.onTap,
          hoverColor: accent.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: accent, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 16 / 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        hoverColor: accent.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 20 / 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_HomeItem> _items(BuildContext context) {
    void push(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    Widget imsTab(ImsTab tab) => ImsSplashScreen(initialTab: tab);

    return [
      _HomeItem(
        ImsTab.curriculum.icon,
        ImsTab.curriculum.title,
        ImsTab.curriculum.subtitle,
        () => push(imsTab(ImsTab.curriculum)),
      ),
      _HomeItem(
        ImsTab.schedule.icon,
        ImsTab.schedule.title,
        ImsTab.schedule.subtitle,
        () => push(imsTab(ImsTab.schedule)),
      ),
      _HomeItem(
        ImsTab.grade.icon,
        ImsTab.grade.title,
        ImsTab.grade.subtitle,
        () => push(imsTab(ImsTab.grade)),
      ),
      _HomeItem(
        ImsTab.graduationRequirements.icon,
        ImsTab.graduationRequirements.title,
        ImsTab.graduationRequirements.subtitle,
        () => push(imsTab(ImsTab.graduationRequirements)),
      ),
      // 「我的」不在宫格里（用户 2026-09-11 裁定）——入口 = 顶栏右上角头像。
      _HomeItem(
        Icons.place_outlined,
        '学校地址',
        '四校区地址与邮编一览',
        () => push(const CampusAddressScreen()),
      ),
      _HomeItem(
        Icons.map_outlined,
        '校区地图',
        '官网四校区地图与交通示意图',
        () => push(const CampusMapScreen()),
      ),
      _HomeItem(
        Icons.volunteer_activism,
        '志愿服务时长',
        '查看学生志愿活动时长统计',
        () => push(const VolunteerHoursScreen()),
      ),
      _HomeItem(
        Icons.school_outlined,
        '第二课堂学分',
        '成绩单与学分预警 · 毕业达标进度',
        () => push(const SecondClassCreditScreen()),
      ),
      _HomeItem(
        Icons.auto_stories_outlined,
        '蛟湖阅读',
        '阅读学分四部分进度 · 入馆教育与借阅达标',
        () => push(const JhReadScreen()),
      ),
      _HomeItem(
        Icons.insights,
        '学生个人数据中心',
        '学业成绩 · 消费 · 图书 · 校园卡全景',
        () => push(const DataCenterScreen()),
      ),
      _HomeItem(
        Icons.electrical_services,
        '宿舍电费',
        '选择宿舍查询剩余电量 · 未绑定可一键绑定',
        () => push(const ElectricityScreen()),
      ),
      _HomeItem(
        Icons.wifi_outlined,
        '网费',
        '校园网余额 · 充值记录一览',
        () => push(const NetFeeScreen()),
      ),
      _HomeItem(
        Icons.event_note_outlined,
        '请假',
        '学生请假申请记录 · 审批进度查看',
        () => push(const LeaveScreen()),
      ),
      _HomeItem(
        Icons.workspace_premium_outlined,
        '综合测评',
        '证明材料自动测算 · 五育等次参考',
        () => push(const ZongceScreen()),
      ),
      _HomeItem(
        Icons.calculate_outlined,
        '分数估计',
        '平时分项计数 · 期末反推 · 达线预警',
        () => push(const ScoreEstimateScreen()),
      ),
      _HomeItem(
        Icons.fitness_center,
        '体测成绩',
        '国家体质测试总分与分项 · 本人成绩查询',
        () => push(const TiceScreen()),
      ),
      _HomeItem(
        Icons.folder_outlined,
        '材料库',
        '证明文件归档 · 自动带入综测',
        () => push(const MaterialsScreen()),
      ),
      _HomeItem(
        Icons.calendar_month,
        '校历',
        '学期教学周历 · 开学与假期起止一览',
        () => push(const SchoolCalendarScreen()),
      ),
      _HomeItem(
        Icons.rule_folder_outlined,
        '规章制度',
        '校规校纪 · 学分学籍 · 竞赛目录 · 奖助办法',
        () => push(const RulesHomeScreen()),
      ),
      _HomeItem(
        Icons.podcasts_outlined,
        '上课实况窗',
        '上课中与下一节课 · 通知栏常驻倒计时',
        () => push(const LiveClassScreen()),
      ),
    ];
  }
}

// ---------- 宫格功能分色（与 FeaturePalette 一一对应） ----------
const _tileColors = <Color>[
  FeaturePalette.curriculum,
  FeaturePalette.schedule,
  FeaturePalette.grade,
  FeaturePalette.graduation,
  // 索引 4 原为 FeaturePalette.studentInfo（「我的」磁贴已删）——与 `_items` 严格按索引对齐，
  // 增删条目必须同步增删本列表（AGENTS.md §3）。
  FeaturePalette.campus,
  FeaturePalette.campusMap,
  FeaturePalette.volunteer,
  FeaturePalette.secondClass,
  FeaturePalette.jhRead,
  // 索引 9 原为 FeaturePalette.libraryEdu（「新生入馆教育」磁贴已并入「蛟湖阅读」页，
  // 用户 2026-09-11 裁定）——与 `_items` 严格按索引对齐，增删条目必须同步本列表。
  FeaturePalette.dataCenter,
  FeaturePalette.electricity,
  FeaturePalette.netFee,
  FeaturePalette.leave,
  // 索引 14 原为 FeaturePalette.guidGuide（「获取平台标识」磁贴已迁到设置页，2026-09-11）。
  FeaturePalette.zongce,
  FeaturePalette.scoreEstimate,
  FeaturePalette.tice,
  FeaturePalette.materials,
  FeaturePalette.calendar,
  FeaturePalette.rules,
  FeaturePalette.liveClass,
];

// ---------- 当前账号显示名 ----------
// 已迁到 `lib/features/auth/data/providers/account_display_name_provider.dart`
// （`currentAccountNameProvider`）——共享头像组件也要用它，放在页面文件里会
// 逼着共享件反向 import 首页。

class _HomeItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeItem(this.icon, this.title, this.subtitle, this.onTap);
}
