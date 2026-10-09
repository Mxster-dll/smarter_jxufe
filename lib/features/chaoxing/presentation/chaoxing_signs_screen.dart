/// 学习通 · 「全部签到」页（按课程分组 + 手动全量更新）。
///
/// 用户 2026-10-09：「我希望还能接入学习通里的签到记录」；拍板：**主页区块 + 独立页**、
/// 自动刷新**只扫本学期课程**、**允许手动全量更新**。
///
/// 成本口径（决定这一页的两个按钮长什么样）：
/// - 自动刷新（进页面/返回/1 分钟闸门）：签到清单 **1 请求 / 课**，只扫本学期；
/// - 手动「补全全部状态」：清单 + **逐活动**查我的状态（**1 请求 / 活动**）；
/// - 手动「含往期课程」：连**全部课程**的清单一起扫（课程数 × 1 请求）。
///
/// ⚠ 学习通有请求配额（实测 ≈60 个/窗口就回验证码页），所以两个手动动作都要
/// 先弹确认、跑的时候显示进度、撞风控立刻收手（仓库层已实现），并把
/// 「已拿到的照算」如实说 —— 详见 `docs/agents/30` 与 `chaoxing_limits.dart`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_repository.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';

class ChaoxingSignsScreen extends ConsumerStatefulWidget {
  const ChaoxingSignsScreen({super.key});

  @override
  ConsumerState<ChaoxingSignsScreen> createState() => _ChaoxingSignsScreenState();
}

class _ChaoxingSignsScreenState extends ConsumerState<ChaoxingSignsScreen> {
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _autoRefreshAll,
  );

  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  /// 从子页面返回 / 回前台：按主页同一口径刷一次（**受 1 分钟闸门约束**，
  /// 不传 `force` —— 自动刷新要尊重风控冷却）。
  void _autoRefreshAll() {
    if (!mounted) return;
    final snapshot = ref.read(chaoxingControllerProvider).valueOrNull;
    final gate = ref.read(chaoxingRefreshGateProvider);
    if (snapshot != null && !snapshot.isEmpty && !gate.allowsAutoRefresh) {
      setState(() => _now = DateTime.now());
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _now = DateTime.now());
    await ref.read(chaoxingControllerProvider.notifier).refresh();
    if (mounted) setState(() => _now = DateTime.now());
  }

  Future<void> _loadStatus(ChaoxingSign sign) async {
    await ref.read(chaoxingControllerProvider.notifier).loadSignDetail(sign);
    if (mounted) setState(() => _now = DateTime.now());
  }

  /// 手动全量更新（清单 + 状态）。[allCourses] = 含往期课程。
  Future<void> _fullUpdate({required bool allCourses}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sync_problem_outlined),
        title: Text(allCourses ? '含往期课程更新？' : '补全全部签到状态？'),
        content: SizedBox(
          width: 380,
          child: Text(
            allCourses
                ? '会把**全部课程**（含往期学期）的签到清单重新取一遍，再逐条补「我的状态」。\n\n'
                      '学习通有请求配额：约 60 个请求就会回验证码页（实测），'
                      '所以这次可能只完成一部分 —— 已拿到的照算，剩下的下次再补。'
                : '会逐条打开每个签到活动的详情页来取「我的状态」（1 个活动 = 1 个请求）。\n\n'
                      '学习通有请求配额：约 60 个请求就会回验证码页（实测），'
                      '所以这次可能只完成一部分 —— 已拿到的照算，剩下的下次再补。',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('chaoxingSignFullUpdateConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref
        .read(chaoxingControllerProvider.notifier)
        .refreshSignsFull(allCourses: allCourses);
    if (mounted) setState(() => _now = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chaoxingControllerProvider);
    final snapshot = async.valueOrNull ?? ChaoxingSnapshot.empty;
    final progress = ref.watch(chaoxingProgressProvider);
    final busy = progress?.phase == ChaoxingPhase.signs;
    final byCourse = snapshot.signsByCourse();
    final courseNames = {
      for (final c in snapshot.courses) c.courseId: c.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('全部签到')),
      body: PaneBody(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 2),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 48),
          children: [
            _buildActionsCard(snapshot, busy, progress),
            const SizedBox(height: 12),
            if (snapshot.signs.isEmpty)
              ChaoxingSectionCard(
                title: '签到记录',
                children: [
                  ChaoxingEmptyHint(
                    text: snapshot.failedSignCourseKeys.isEmpty
                        ? '还没有签到记录 —— 学习通里这门/这些课还没有签到活动，'
                              '或者本轮还没扫到（切到主页下拉刷新一次）。'
                        : '签到记录没取到：${snapshot.failedSignCourseKeys.length} 门课失败'
                              '（可能是请求太密触发了学习通的安全验证，'
                              '过一两分钟再试）。',
                    icon: Icons.how_to_reg_outlined,
                  ),
                ],
              )
            else
              for (final entry in byCourse.entries) ...[
                _buildCourseCard(
                  courseNames[entry.key] ?? entry.value.first.courseName,
                  entry.key,
                  entry.value,
                  snapshot,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(
    ChaoxingSnapshot snapshot,
    bool busy,
    ChaoxingProgress? progress,
  ) {
    final unknown = snapshot.unknownSignStatusCount;
    final muted = AppColors.textMuted(context);
    return ChaoxingSectionCard(
      title: '签到',
      trailing: Text(
        chaoxingSignSummary(snapshot, _now),
        style: TextStyle(fontSize: 12, color: muted),
      ),
      children: [
        Text(
          '签到清单是 1 个请求/课；「我的状态」（已签 / 未签 / 迟到…）学习通只在'
          '每个活动的详情页给，所以默认不查 —— 点开某条会顺手查（1 个请求），'
          '也可以用下面的按钮一次补全。',
          style: TextStyle(fontSize: 12, height: 1.45, color: muted),
        ),
        if (busy) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress == null || progress.fraction == 0
                  ? null
                  : progress.fraction,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '正在更新签到 ${progress?.done ?? 0}/${progress?.total ?? 0} 步'
            '（撞上学习通安全验证会自动停下，已拿到的照算）',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonal(
              key: const Key('chaoxingSignFillStatus'),
              onPressed: busy ? null : () => _fullUpdate(allCourses: false),
              child: Text(unknown > 0 ? '补全全部状态（$unknown 条）' : '补全全部状态'),
            ),
            OutlinedButton(
              key: const Key('chaoxingSignFullUpdate'),
              onPressed: busy ? null : () => _fullUpdate(allCourses: true),
              child: const Text('含往期课程一起更新'),
            ),
          ],
        ),
        if (snapshot.throttled) ...[
          const SizedBox(height: 6),
          Text(
            '上一轮撞上了学习通的安全验证（限流），本轮沿用了上次数据 ——'
            '过一两分钟再试更稳。',
            style: TextStyle(fontSize: 12, color: AppColors.critical(context)),
          ),
        ],
      ],
    );
  }

  Widget _buildCourseCard(
    String courseName,
    String courseId,
    List<ChaoxingSign> signs,
    ChaoxingSnapshot snapshot,
  ) {
    final failed = snapshot.failedSignCourseKeys.any(
      (k) => k.split('/').first == courseId,
    );
    return ChaoxingSectionCard(
      title: courseName.isEmpty ? '（未知课程）' : courseName,
      trailing: _countChip(chaoxingSignCourseSummary(signs)),
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '这门课的签到清单本轮没取到，显示的是上次数据。',
              style: TextStyle(fontSize: 12, color: AppColors.critical(context)),
            ),
          ),
        for (final sign in signs)
          ChaoxingSignRow(
            sign: sign,
            now: _now,
            showCourse: false,
            onTap: () => showChaoxingSignDetail(
              context,
              sign,
              now: _now,
              onRefresh: () => _loadStatus(sign),
            ),
          ),
      ],
    );
  }

  Widget _countChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.tint(context, appCardAccent(context), 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: appCardAccent(context),
      ),
    ),
  );
}
