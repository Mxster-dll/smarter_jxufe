import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/leave/data/providers/leave_providers.dart';
import 'package:smarter_jxufe/features/leave/domain/leave_models.dart';

/// 请假单详情（只读）：基本信息 + 审批时间线。
class LeaveDetailScreen extends ConsumerWidget {
  const LeaveDetailScreen({
    super.key,
    required this.instanceId,
    this.title,
  });

  /// 流程实例 id（getApplicationForLeaveInfo 参数）。
  final String instanceId;

  /// 列表页标题（事由），用于 AppBar 副标题。
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bundleAsync = ref.watch(leaveDetailBundleProvider(instanceId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请假详情', style: TextStyle(fontSize: 17)),
            if (title != null && title!.isNotEmpty)
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaveDetailBundleProvider(instanceId));
          await ref.read(leaveDetailBundleProvider(instanceId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            ...bundleAsync.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                _errorCard(
                  scheme,
                  '加载失败：${e.toString().replaceAll('Exception: ', '')}',
                ),
              ],
              data: (bundle) => [
                _buildInfoCard(context, scheme, bundle.info),
                if (bundle.info.reason.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildReasonCard(context, scheme, bundle.info),
                ],
                if (bundle.approvals.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(context, '审批进度 · ${bundle.approvals.length}'),
                  const SizedBox(height: 10),
                  _buildApprovalCard(context, scheme, bundle.approvals),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 基本信息卡 ----------

  Widget _buildInfoCard(
    BuildContext context,
    ColorScheme scheme,
    LeaveDetailInfo info,
  ) {
    final statusOk = info.statusName.contains('同意');
    return _whiteCard(
      context,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.event_available_outlined,
                          size: 22,
                          color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${info.leaveType} · ${info.leaveDays} 天',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.applyDate.isEmpty ? '' : '申请于 ${info.applyDate}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(scheme, statusOk, info.statusName),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                _kvRow(scheme, Icons.calendar_month_outlined, '请假时间',
                    _dateRange(info)),
                if (info.leaveNanchang.isNotEmpty)
                  _kvRow(scheme, Icons.location_on_outlined, '是否离昌',
                      info.leaveNanchang),
                if (info.classHours.isNotEmpty)
                  _kvRow(scheme, Icons.schedule_outlined, '课假节次',
                      '第 ${info.classHours} 节'),
                _kvRow(scheme, Icons.house_outlined, '宿舍',
                    info.buildingDormitory.isEmpty
                        ? '—'
                        : info.buildingDormitory),
                _kvRow(scheme, Icons.badge_outlined, '申请人',
                    '${info.appliedByName}（${info.appliedByUsername}）'),
                if (info.className.isNotEmpty)
                  _kvRow(scheme, Icons.school_outlined, '班级',
                      info.className),
                if (info.deptName.isNotEmpty)
                  _kvRow(scheme, Icons.account_balance_outlined, '学院',
                      info.deptName),
                if (info.myPhone.isNotEmpty)
                  _kvRow(scheme, Icons.phone_outlined, '本人电话',
                      info.myPhone),
                if (info.parentPhone.isNotEmpty)
                  _kvRow(scheme, Icons.contacts_outlined, '家长电话',
                      info.parentPhone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard(
    BuildContext context,
    ColorScheme scheme,
    LeaveDetailInfo info,
  ) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请假事由',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              info.reason,
              style: const TextStyle(fontSize: 13.5, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(
    ColorScheme scheme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 审批时间线 ----------

  Widget _buildApprovalCard(
    BuildContext context,
    ColorScheme scheme,
    List<LeaveApprovalStep> approvals,
  ) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            for (var i = 0; i < approvals.length; i++) ...[
              _buildApprovalRow(context, scheme, approvals[i], i,
                  isLast: i == approvals.length - 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalRow(
    BuildContext context,
    ColorScheme scheme,
    LeaveApprovalStep step,
    int index, {
    required bool isLast,
  }) {
    final isDone = step.operTime != null;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 时间线列：节点圆点 + 竖线。
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                  child: isDone
                      ? Icon(Icons.check,
                          size: 8,
                          color: scheme.onPrimary)
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.actName.isEmpty ? step.sequenceName : step.actName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (step.operTime != null)
                        Text(
                          _fmtDate(step.operTime!),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (step.assignName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '处理人：${step.assignName}${step.assignDept.isEmpty ? '' : '（${step.assignDept}）'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (step.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '意见：${step.comment}',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 通用小块 ----------

  String _dateRange(LeaveDetailInfo info) {
    if (info.leaveStart.isEmpty) return '—';
    if (info.leaveEnd.isEmpty || info.leaveEnd == info.leaveStart) {
      return info.leaveStart;
    }
    return '${info.leaveStart} 至 ${info.leaveEnd}';
  }

  Widget _statusChip(ColorScheme scheme, bool ok, String status) {
    final fg = ok ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty ? (ok ? '已同意' : '办理中') : status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
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

  Widget _whiteCard(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _errorCard(ColorScheme scheme, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}
