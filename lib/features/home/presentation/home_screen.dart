import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_address_screen.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/jh_read_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/second_class_credit_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';
import 'package:smarter_jxufe/features/leave/presentation/leave_screen.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_home_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/presentation/school_calendar_screen.dart';
import 'package:smarter_jxufe/features/tice/presentation/tice_screen.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_screen.dart';

/// 单页功能主页 —— 登录后的统一落地页。
///
/// 所有功能入口扁平平铺（无平台分组、无二级菜单），点击直达功能页面。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currentCard = ref.watch(currentAccountProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context, ref, scheme, currentCard),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                children: [
                  const DashboardPanel(),
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
                        cols = ((constraints.maxWidth + gap) /
                                (tileExtent + gap))
                            .ceil();
                        if (cols < 2) cols = 2;
                        width =
                            (constraints.maxWidth - gap * (cols - 1)) / cols;
                      } else {
                        cols =
                            (constraints.maxWidth + gap) ~/ (minCard + gap);
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

  // ---------- 顶部：品牌 + 当前账号 + 切号入口 ----------
  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    String currentCard,
  ) {
    final displayFuture = ref.watch(currentAccountNameProvider);

    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '智慧尼采',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                displayFuture.when(
                  data: (name) => Text(
                    name?.isNotEmpty == true ? name! : currentCard,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  loading: () => Text(
                    currentCard,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  error: (_, _) => Text(
                    currentCard,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
            },
            icon: const Icon(Icons.switch_account, size: 18),
            label: const Text('切换账号'),
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
      _HomeItem(
        ImsTab.studentInfo.icon,
        ImsTab.studentInfo.title,
        ImsTab.studentInfo.subtitle,
        () => push(imsTab(ImsTab.studentInfo)),
      ),
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
        '蛟湖阅读考核记录 · 入馆学习与借阅达标',
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
        Icons.vpn_key_outlined,
        '获取平台标识',
        '微信平台 GUID · 配置网费请假校历实时源',
        () => push(const GuidGuideScreen()),
      ),
      _HomeItem(
        Icons.workspace_premium_outlined,
        '综合测评',
        '证明材料自动测算 · 五育等次参考',
        () => push(const ZongceScreen()),
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
    ];
  }
}

// ---------- 宫格功能分色（与 FeaturePalette 一一对应） ----------
const _tileColors = <Color>[
  FeaturePalette.curriculum,
  FeaturePalette.schedule,
  FeaturePalette.grade,
  FeaturePalette.graduation,
  FeaturePalette.studentInfo,
  FeaturePalette.campus,
  FeaturePalette.campusMap,
  FeaturePalette.volunteer,
  FeaturePalette.secondClass,
  FeaturePalette.jhRead,
  FeaturePalette.dataCenter,
  FeaturePalette.electricity,
  FeaturePalette.netFee,
  FeaturePalette.leave,
  FeaturePalette.guidGuide,
  FeaturePalette.zongce,
  FeaturePalette.tice,
  FeaturePalette.materials,
  FeaturePalette.calendar,
  FeaturePalette.rules,
];

// ---------- 当前账号显示名 ----------
final currentAccountNameProvider = FutureProvider<String?>((ref) async {
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final accounts = accountRepo.getAccounts().fold(
    (_) => <Account>[],
    (list) => list,
  );
  final current = ref.watch(currentAccountProvider);
  if (current.isEmpty) return null;
  for (final a in accounts) {
    if (a.cardNumber == current && a.displayName.isNotEmpty) {
      return a.displayName;
    }
  }
  return null;
});

class _HomeItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeItem(this.icon, this.title, this.subtitle, this.onTap);
}
