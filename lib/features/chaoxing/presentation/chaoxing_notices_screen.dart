/// 学习通 · 全部通知（二级页）。
///
/// 点一条通知弹全文 —— 弹窗本体是 `showChaoxingNoticeDetail`（与主页「通知消息」区块
/// **同一份实现**，别在这里再拼一个）。**不做「标记已读」**：本模块是只读接入，
/// 任何写操作都得先在 AGENTS 里立案（见模块 README）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';

/// 全部通知页。
class ChaoxingNoticesScreen extends ConsumerWidget {
  const ChaoxingNoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(chaoxingControllerProvider).valueOrNull;
    final now = DateTime.now();
    final notices = snapshot?.notices ?? const [];
    final available = snapshot?.noticesAvailable ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('通知消息'), centerTitle: true),
      body: notices.isEmpty
          ? Center(
              child: ChaoxingEmptyHint(
                text: available ? '暂时没有通知' : '通知暂不可用（本次会话没取到收件箱 token）',
                icon: Icons.notifications_none,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: notices.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.stroke(context)),
              itemBuilder: (context, i) => ChaoxingNoticeRow(
                notice: notices[i],
                now: now,
                snippetLength: 120,
                onTap: () => showChaoxingNoticeDetail(
                  context,
                  notices[i],
                  courseName: chaoxingCourseNameOf(snapshot, notices[i].courseId),
                ),
              ),
            ),
    );
  }
}
