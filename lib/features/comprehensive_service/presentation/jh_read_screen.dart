import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/jh_read_record.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/jh_read_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_home_screen.dart';
import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_progress_section.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_rules_card.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';

/// 蛟湖阅读页（阅读学分平台 + 入馆教育 + 学工平台记录的三源单一入口）。
///
/// 页面结构（用户 2026-09-11 裁定：每个部分只留**一张进度卡**，点进去再展开）：
/// 1. 「四部分进度」= 学分总卡 + 经典阅读 / 普通阅读 / 入馆教育 / 信息素养
///    各一张进度卡（实际 / 平台两档口径）；经典阅读那张点击进**畅想之星页**
///    （用户 2026-09-15 裁定：取消畅想之星独立入口，经典阅读 = 畅想之星），
///    入馆教育那张点击进入原「新生入馆教育」页（App 内闯关），其余两部分进
///    学分平台明细页。
/// 2. 「学分说明」= 平台规则原文（重排版）。
/// 3. 「学工平台加分记录」= SSP 认定记录，与平台侧不是同一套数据。
class JhReadScreen extends ConsumerStatefulWidget {
  const JhReadScreen({super.key});

  @override
  ConsumerState<JhReadScreen> createState() => _JhReadScreenState();
}

class _JhReadScreenState extends ConsumerState<JhReadScreen> {
  /// 进入本页 / 从入馆教育或畅想之星返回 / 回前台 → 重取全部三源数据。
  ///
  /// 用户 2026-09-14 反馈：「不论是进入此页面，还是从别的页面点击返回到此页面，
  /// 卡片里的数据都要刷新」（原先只能靠下拉刷新或重进页面）。
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _refreshAll,
  );

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoRefresh.subscribeRoute(context);
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  /// ⚠ 顺序：先畅想之星（进度卡里「经典阅读」的实际值来源），再 `readCreditProgress`
  /// —— 后者是用 `ref.read(cxstarOverviewProvider.future)` 取数的，失效晚了会读到旧值。
  void _refreshAll() {
    if (!mounted) return;
    invalidateIfLoaded(ref, cxstarOverviewProvider);
    invalidateIfLoaded(ref, readCreditScoreProvider);
    invalidateIfLoaded(ref, readCreditProgressProvider);
    invalidateIfLoaded(ref, jhReadRecordsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(jhReadRecordsProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('蛟湖阅读'),
        centerTitle: true,
        // 本页相关的设置：入馆教育答题模式（蛟湖阅读「入馆教育」部分的入口就在本页）。
        settingsSections: const [SettingsSection.libraryEdu],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: [
            _sectionTitle(context, '四部分进度'),
            const SizedBox(height: 10),
            // 入馆教育那张卡点进去 = 原「新生入馆教育」页（宫格磁贴已删）；
            // 经典阅读那张卡点进去 = 畅想之星页（用户 2026-09-15 裁定：不再有
            // 独立的畅想之星入口，经典阅读卡直达该页）。
            ReadCreditProgressSection(
              onOpenLibraryEdu: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TsgxsHomeScreen(),
                ),
              ),
              onOpenClassic: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CxstarScreen()),
              ),
            ),
            const SizedBox(height: 22),
            _sectionTitle(context, '学分说明'),
            const SizedBox(height: 10),
            const ReadCreditRulesCard(),
            const SizedBox(height: 22),
            _sectionTitle(context, '学工平台加分记录'),
            const SizedBox(height: 10),
            ...recordsAsync.when(
              loading: () => [_infoCard(context, '正在加载学工平台蛟湖阅读记录…')],
              error: (error, _) => [_errorCard(context, ref, '$error')],
              data: (records) => records.isEmpty
                  ? [_emptyRecordsCard(context, ref)]
                  : [
                      for (final record in records)
                        _buildRecordCard(context, record),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  /// SSP 侧无记录时的说明（记录为空不等于学分没达标，故只作引导）。
  Widget _emptyRecordsCard(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 17,
                color: fp(context).cardAccent,
              ),
              const SizedBox(width: 8),
              const Text(
                '学工平台暂无加分记录',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '当前账号在学工平台蛟湖阅读详单中暂无记录。记录为空通常意味着：'
            '① 学分四部分尚未全部完成；② 学院（团总支）尚未完成录入认定；'
            '③ 认定周期未到（学分更新时间为 5 月与 11 月）。'
            '可先看上方「阅读学分」平台的达标进度。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(jhReadRecordsProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, JhReadRecord record) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final f = fp(context);
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tint(context, f.cardAccent, 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  record.bonusName.isNotEmpty ? record.bonusName : '蛟湖阅读',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: f.cardAccent,
                  ),
                ),
              ),
              const Spacer(),
              if (record.credit.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successFill(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${record.credit} 学分',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success(context),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _rowItem(context, Icons.badge_outlined, '学号', record.studentId),
          _rowItem(context, Icons.person_outline, '姓名', record.name),
          _rowItem(context, Icons.school_outlined, '学院', record.college),
          _rowItem(context, Icons.groups_outlined, '班级', record.className),
          const SizedBox(height: 6),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 6),
          Row(
            children: [
              _statusPill(
                context,
                Icons.assignment_turned_in_outlined,
                '入馆学习',
                record.entryLearning,
              ),
              const SizedBox(width: 8),
              _statusPill(
                context,
                Icons.library_books_outlined,
                '借阅合格',
                record.borrowQualified,
              ),
            ],
          ),
          if (record.detailId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.open_in_new,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '学工平台已生成该记录详单',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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

  Widget _statusPill(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final isOk = value == '是';
    final isNo = value == '否';
    final Color bg;
    final Color fg;
    if (isOk) {
      bg = AppColors.successFill(context);
      fg = AppColors.success(context);
    } else if (isNo) {
      bg = AppColors.criticalFill(context);
      fg = AppColors.critical(context);
    } else {
      final scheme = Theme.of(context).colorScheme;
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, color: fg)),
            const SizedBox(width: 4),
            Text(
              value.isEmpty ? '未录入' : value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, WidgetRef ref, String message) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 17, color: scheme.error),
              const SizedBox(width: 8),
              const Text(
                '学工平台记录读取失败',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(jhReadRecordsProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    children: [
      Container(
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

Widget _infoCard(BuildContext context, String text) => _card(
  context,
  child: Row(
    children: [
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Text(text, style: const TextStyle(fontSize: 13)),
    ],
  ),
);

Widget _card(BuildContext context, {required Widget child}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.hairline(context, 0.6)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: child,
  );
}
