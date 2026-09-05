import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/jh_read_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/second_class_credit_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const minCard = 208.0;
                    const gap = 12.0;
                    final cols =
                        (constraints.maxWidth + gap) ~/ (minCard + gap);
                    final width =
                        (constraints.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in _items(context))
                          SizedBox(
                            width: width,
                            child: _buildFeatureCard(context, item),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
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
  Widget _buildFeatureCard(BuildContext context, _HomeItem item) {
    final scheme = Theme.of(context).colorScheme;
    final accentBg = scheme.primary.withValues(alpha: 0.10);

    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        hoverColor: scheme.primary.withValues(alpha: 0.05),
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
                child: Icon(item.icon, color: scheme.primary, size: 22),
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
    ];
  }
}

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
