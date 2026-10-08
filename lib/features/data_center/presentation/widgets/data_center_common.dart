/// 数据中台 · 页面骨架与共用小件
///
/// 骨架卡 / 错误卡（含重登）/ 指标小件。这三件被 overview 与 social 两组共用，所以单独一层，避免两组互相 import。
///
/// 拆分自 `data_center_screen.dart`（2026-10-08 架构审计第三轮）：
/// 原文件是一个 1389 行的 `ConsumerWidget`，49 个成员里没有一个碰状态，
/// 全部是 `(context, …)` 的纯渲染件 —— 因此**整组外提为顶层函数**，
/// 屏幕文件只留壳（口径见 AGENTS.md §33.4.4 ①②）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/design/app_states.dart';

// ---- 概览未到 / 概览失败时的两枚件 ----

/// 概览还没回来时的**卡片骨架**：标题已知、值未到。
///
/// [lead] = 列表里最上面那一枚（学籍概要）——只有它挂转圈，其余骨架只留
/// 一行灰字。9 张卡各转一个圈既吵又浪费；而且它们其实**同时**回来
/// （同一个 `dataCenterOverviewProvider`）。
///
/// ⚠ 刻意不用零值占位：拿 `DataCenterOverview()` 的默认 0 画上去，就是把
/// 「没取到」说成「就是 0 分 / 0 元」（§30 的教训）。
Widget dcSkeletonCard(
  BuildContext context, {
  required String title,
  required IconData icon,
  bool lead = false,
}) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textMuted(context)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (lead)
            const AppLoadingState(
              compact: true,
              padding: EdgeInsets.only(top: 10),
              message: '正在读取学籍 / 学业 / 消费 / 图书…',
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '正在读取…',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 概览失败的**唯一**错误卡（页面顶部）。
///
/// 会话过期走**「重新登录」**而不是裸「重试」：裸重试只会把 Hive 里那份
/// 死会话再捞回来（`dzj_auth_local_datasource.dart` 的 `getSession` 不看
/// TTL），白转一圈还是失败。
Widget dcOverviewErrorCard(BuildContext context, WidgetRef ref, Object error) {
  final expired = error is SessionExpiredException;
  return Card(
    shape: appCardShape(context),
    child: AppErrorState(
      compact: true,
      title: expired ? '登录已过期' : '数据中心加载失败',
      error: error,
      retryKey: const Key('dzjOverviewRetry'),
      retryLabel: expired ? '重新登录' : '重试',
      onRetry: expired
          ? () => dcRelogin(context, ref)
          : () => ref.invalidate(dataCenterOverviewProvider),
    ),
  );
}

/// 会话过期后的「重新登录」：**换一次新会话**，再把本页所有取数 provider
/// 一起作废重取。
///
/// 不只是重取概览 —— 页面现在各卡自己取数，会话死的时候子页面清单 /
/// 补充模块 / 校内关系 / 相关人员会**一起**失败，只刷概览的话它们会一直
/// 停在错误态（用户看不出为什么别的卡还是红的）。
Future<void> dcRelogin(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final account = ref.read(currentAccountProvider);
  try {
    final repository = await ref.read(dataCenterRepositoryProvider.future);
    await repository.renewSession(account);
  } catch (e) {
    // 统一认证那边也过期（TGC 失效 / 需要 MFA 而用户取消）：如实说，
    // 别装作换成功了 —— 下面照样重取，重新失败时错误卡会显示真实原因。
    messenger.showSnackBar(
      SnackBar(content: Text('重新登录失败：${friendlyErrorText(e)}')),
    );
  }
  if (!context.mounted) return;
  for (final provider in <ProviderOrFamily>[
    dataCenterOverviewProvider,
    dzjPageTreeProvider,
    dzjExtraProvider,
    dzjPeerCountsProvider,
    dzjRelatedCountsProvider,
    dzjGradeCollegeCountProvider,
  ]) {
    ref.invalidate(provider);
  }
}

// ---- 通用小组件 ----

Widget dcScoreCell(
  BuildContext context, {
  required String label,
  required String value,
  required String unit,
  required Color color,
}) {
  return Expanded(
    child: Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (unit.isNotEmpty)
              Text(
                unit,
                style: TextStyle(fontSize: 9.5, color: AppColors.textMuted(context)),
              ),
          ],
        ),
      ],
    ),
  );
}

Widget dcScoreDivider(BuildContext context) {
  return Container(
    width: 1,
    height: 32,
    color: AppColors.stroke(context),
  );
}

String dcFmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
