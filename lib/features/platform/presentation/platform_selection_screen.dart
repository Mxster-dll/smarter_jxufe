/// 平台选择器：选完**替换当前页**进入对应平台（2026-09-20 架构审查 ⑦：三条落点都走
/// 「跳转缝」，本文件不再 import 三个 feature 的页面 —— 它们反过来 import 本页做入口，
/// 直接 import 会构成 `ims ⇄ platform` / `comprehensive_service ⇄ platform` 双向环）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';

class PlatformSelectionScreen extends ConsumerWidget {
  const PlatformSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = fp(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智慧江财'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '请选择服务平台',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48),
              _buildPlatformButton(
                context,
                icon: Icons.school,
                label: '教学信息服务',
                subtitle: 'IMS 教务管理系统',
                color: f.schedule,
                onTap: () =>
                    replaceServiceScreen(context, kServiceIms),
              ),
              const SizedBox(height: 24),
              _buildPlatformButton(
                context,
                icon: Icons.manage_accounts,
                label: '综合管理服务平台',
                subtitle: '志愿服务时长等',
                color: f.grade,
                onTap: () =>
                    replaceServiceScreen(context, kServiceComprehensive),
              ),
              const SizedBox(height: 24),
              _buildPlatformButton(
                context,
                icon: Icons.insights,
                label: '学生个人数据中心',
                subtitle: '学业成绩 · 消费 · 图书 · 校园卡全景',
                color: f.courseSelection,
                onTap: () =>
                    replaceServiceScreen(context, kServiceDataCenter),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 280,
      height: 100,
      child: Card(
        shape: appCardShape(context),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kAppCardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, color, 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 30, color: color),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
