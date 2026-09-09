import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/leave/data/providers/leave_providers.dart';
import 'package:smarter_jxufe/features/leave/domain/leave_models.dart';
import 'package:smarter_jxufe/features/leave/presentation/leave_detail_screen.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';

/// 「我的请假」：学生请假申请记录列表（只读，用户拍板本轮范围）。
///
/// 数据源 = 智慧江财小程序「学生请假」流程应用（金智 OA），需已配置平台
/// GUID（与网费/校历共用同一配置）。发起请假本轮不做。
class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  Future<void> _refresh() async {
    ref.invalidate(leaveListProvider);
    await ref.read(leaveListProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listAsync = ref.watch(leaveListProvider);
    final guid = ref.watch(wxGuidProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('请假'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            _buildSourceRow(context, scheme, guid),
            const SizedBox(height: 12),
            ...listAsync.when(
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
                if (e.toString().contains('未配置平台标识'))
                  _buildGuidHint(context, scheme)
                else
                  _errorCard(
                    scheme,
                    Icons.error_outline,
                    '加载失败：${e.toString().replaceAll('Exception: ', '')}',
                  ),
              ],
              data: (records) => [
                if (records.isEmpty)
                  _buildEmpty(context, scheme)
                else ...[
                  _sectionTitle(context, '请假记录 · ${records.length}'),
                  const SizedBox(height: 10),
                  for (var i = 0; i < records.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildRecordCard(context, scheme, records[i]),
                  ],
                ],
              ],
            ),
            if (listAsync.hasError &&
                listAsync.error.toString().contains('未配置平台标识')) ...[
              const SizedBox(height: 12),
              _buildGuidExplain(context, scheme),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- 顶部：来源 + 配置入口 ----------

  Widget _buildSourceRow(BuildContext context, ColorScheme scheme, String? guid) {
    return Row(
      children: [
        Icon(
          Icons.cloud_done_outlined,
          size: 16,
          color: scheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          '当前数据源：智慧江财请假流程',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _showGuidDialog,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: Icon(
            guid == null || guid.isEmpty
                ? Icons.add_link_outlined
                : Icons.settings_outlined,
            size: 16,
          ),
          label: Text(guid == null || guid.isEmpty ? '启用实时源' : '实时源配置'),
        ),
      ],
    );
  }

  Widget _buildGuidHint(BuildContext context, ColorScheme scheme) {
    return _errorCard(
      scheme,
      Icons.link_off_outlined,
      '未配置微信平台标识（GUID），无法读取请假记录。点击右上「启用实时源」填写后即可查看（与网费/校历共用同一配置）。',
    );
  }

  Widget _buildGuidExplain(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'GUID 是智慧江财平台在微信授权后下发的用户标识，App 内无法自动获取；'
              '请参考网费 / 校历页的配置说明填写一次，各处即共用生效。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.assignment_outlined,
              size: 44, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '暂无请假记录',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ---------- 记录卡片 ----------

  Widget _buildRecordCard(
    BuildContext context,
    ColorScheme scheme,
    LeaveListRecord record,
  ) {
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LeaveDetailScreen(
                instanceId: record.instanceId,
                title: record.formTitle,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: record.inProgress
                      ? scheme.primary.withValues(alpha: 0.10)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  record.inProgress
                      ? Icons.schedule_outlined
                      : Icons.task_alt_outlined,
                  size: 20,
                  color: record.inProgress
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.formTitle.isEmpty
                                ? record.defDescription
                                : record.formTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(scheme, record),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.startedByName}${record.startedByDept.isEmpty ? '' : ' · ${record.startedByDept}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(record),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(ColorScheme scheme, LeaveListRecord record) {
    final Color bg;
    final Color fg;
    final String label;
    if (record.inProgress) {
      bg = scheme.primary.withValues(alpha: 0.10);
      fg = scheme.primary;
      label = '审批中';
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      label = '已结束';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  String _subtitle(LeaveListRecord record) {
    final buf = <String>[
      if (record.startedAt != null) _fmtTime(record.startedAt!),
      if (record.sequenceName.isNotEmpty) '当前：${record.sequenceName}',
    ];
    return buf.join(' · ');
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  // ---------- GUID 配置对话框（与网费页同款，共享 box） ----------

  Future<void> _showGuidDialog() async {
    if (!mounted) return;
    final box = await ref.read(wxPlatformBoxProvider.future);
    if (!mounted) return;
    final existing = box.get('guid') ?? '';
    final controller = TextEditingController(text: existing);
    final scheme = Theme.of(context).colorScheme;

    final action = await showDialog<_GuidAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(        title: const Text('实时数据源配置'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '填写微信智慧江财平台的用户标识（GUID），即读取请假流程所需的访问凭证。'
                '它与网费、校历页共用同一配置，填写一次各处均生效。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: '平台 GUID',
                  hintText: '例如 00000000-0000-4000-8000-000000000000',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GuidGuideScreen(),
                      ),
                    );
                  },
                  child: const Text('不知道 GUID？查看获取方法'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const _GuidActionClear()),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _GuidActionCancel()),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_GuidActionSave(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (action == null || action is _GuidActionCancel) return;
    if (action is _GuidActionClear) {
      await box.delete('guid');
    } else if (action is _GuidActionSave) {
      if (action.guid.isEmpty) {
        await box.delete('guid');
      } else {
        await box.put('guid', action.guid);
      }
    }
    ref.invalidate(wxGuidProvider);
    ref.invalidate(leaveListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action is _GuidActionClear
                ? '已清除平台标识'
                : action is _GuidActionSave && action.guid.isNotEmpty
                    ? '已保存平台标识，正在刷新请假记录'
                    : '已清除平台标识',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------- 通用小块 ----------

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

  Widget _errorCard(
    ColorScheme scheme,
    IconData icon,
    String message, {
    bool light = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: light
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : scheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: light
              ? scheme.outlineVariant
              : scheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18, color: light ? scheme.onSurfaceVariant : scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: light ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- GUID 对话框动作 ----------

sealed class _GuidAction {
  const _GuidAction();
}

class _GuidActionCancel extends _GuidAction {
  const _GuidActionCancel();
}

class _GuidActionSave extends _GuidAction {
  final String guid;
  const _GuidActionSave(this.guid);
}

class _GuidActionClear extends _GuidAction {
  const _GuidActionClear();
}
