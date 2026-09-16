/// 经典阅读 · 畅想之星（m.cxstar.com）页面。
///
/// 展示平台侧的**阅读本数 / 累计阅读时长 / 逐书阅读记录**。
/// 会话三档：统一身份认证（首选，个人）→ 手工令牌（高级回退）→
/// 校园网 IP 免密（公用账号，全校聚合，界面必须标注）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_refresh_gate_provider.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_book_report.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_reader_screen.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_shelf_screen.dart';
import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/widgets/read_credit_detail_view.dart';

class CxstarScreen extends ConsumerStatefulWidget {
  const CxstarScreen({super.key});

  @override
  ConsumerState<CxstarScreen> createState() => _CxstarScreenState();
}

class _CxstarScreenState extends ConsumerState<CxstarScreen> {
  /// 进入本页 / 回前台 → 重取统计（用户 2026-09-14：「总览卡片的时长…必须点击
  /// 重新获取令牌，然后才刷新数据」）。
  ///
  /// 自动刷新受「数据更新最小间隔 1 分钟」节流（见 [cxstarRefreshGateProvider]，
  /// 用户 2026-09-14 拍板，**仅限本功能**）。
  ///
  /// ⚠ 本页**不订阅路由观察者**（`subscribeRoute`）：它的子页面（阅读器 / 书架）
  /// 全部由 [_openChild] 用 `await push` 打开，返回时机是确定的；两条路都留着反而会
  /// 重复刷新（`ref.invalidate` 不同步生效，光靠「正在加载就跳过」拦不住同一 tick
  /// 里的第二次触发）。
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _autoRefreshAll,
  );

  /// 统计最近一次**取到新数据**的时刻（界面显示，用于区分「没刷新」与
  /// 「刷新了但平台还没结算」，见 [cxstarReturnSettleDelays]）。
  DateTime? _updatedAt;

  ProviderSubscription<AsyncValue<CxstarOverview>>? _overviewSub;

  /// 结算补刷是否已排队（多次返回不叠加）。
  bool _settleScheduled = false;

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
    _overviewSub = ref.listenManual<AsyncValue<CxstarOverview>>(
      cxstarOverviewProvider,
      (previous, next) {
        if (!mounted || next.isLoading || !next.hasValue) return;
        // 取到新数据 = 一次「数据更新」→ 重开 1 分钟节流窗口。窗口起点与卡片那行
        // 「统计更新于 HH:mm:ss」同源，界面显示与节流口径不会互相矛盾。
        ref.read(cxstarRefreshGateProvider).markUpdated();
        setState(() => _updatedAt = DateTime.now());
      },
    );
  }

  @override
  void dispose() {
    _overviewSub?.close();
    _autoRefresh.dispose();
    super.dispose();
  }

  /// [force] = true 的调用方 = 显式刷新（结算补刷等），不受 1 分钟窗口限制。
  void _refreshOverview({bool force = false}) {
    if (!mounted) return;
    if (!force && !ref.read(cxstarRefreshGateProvider).allowsAutoRefresh)
      return;
    invalidateIfLoaded(ref, cxstarOverviewProvider);
    // 逐书报告（累计时长 / 完成时间）随统计一起刷新；统计还没到位时不动，
    // 免得把记录行刚发起的报告请求作废重发。
    if (ref.read(cxstarOverviewProvider).hasValue) {
      ref.invalidate(cxstarBookReportProvider);
    }
  }

  /// 下拉刷新：连学分平台侧明细一起重取（该明细归并在本页，见
  /// [_ReadCreditClassicSection]）。
  void _refreshAll() {
    if (!mounted) return;
    ref.invalidate(cxstarOverviewProvider);
    ref.invalidate(readCreditDetailProvider(ReadCreditKind.classic));
  }

  /// 进入本页 / 从子页面返回 / 回前台时的自动刷新：
  /// 统计 + 学分平台明细，两者都走 [invalidateIfLoaded]（首帧加载尚未完成时不动，
  /// 免得 `build` 刚发出的请求被立刻重发）。
  void _autoRefreshAll() {
    if (!mounted) return;
    // 「数据更新」最小间隔 1 分钟（用户 2026-09-14）：首次进入 / 从子页面返回 /
    // 回前台这一组**自动**刷新，在一个窗口内只更新一次 —— 整组一起跳过。
    if (!ref.read(cxstarRefreshGateProvider).allowsAutoRefresh) return;
    _refreshOverview();
    invalidateIfLoaded(ref, readCreditDetailProvider(ReadCreditKind.classic));
  }

  /// 打开子页面（阅读器 / 书架 / 明细），**返回后立即刷新**，再按结算时刻表补刷。
  Future<void> _openChild(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    _autoRefreshAll();
    unawaited(_refreshAfterReturnSettle());
  }

  /// 返回后的补刷时刻表：平台统计是**批量结算**的（实测同一分钟内读数不动、
  /// 过几分钟一次跳好几分钟），返回那一瞬间取到的可能还是读完之前的旧值 ——
  /// 这几个时间点再各取一次，让刚读完的时长自己出现，用户不必手动下拉。
  Future<void> _refreshAfterReturnSettle() async {
    if (_settleScheduled) return;
    _settleScheduled = true;
    try {
      for (final delay in cxstarReturnSettleDelays) {
        await Future<void>.delayed(delay);
        if (!mounted) return;
        // 结算补刷**不受** 1 分钟窗口限制（用户 2026-09-14 拍板）：它本来就是
        // 「返回那一刻取到的可能还是旧值」的补偿，被节流等于让刚读完的时长不出现。
        _refreshOverview(force: true);
      }
    } finally {
      _settleScheduled = false;
    }
  }

  /// 「阅读会话」弹窗：会话档位说明 + 换个人会话 / 手工令牌 / 清除令牌。
  ///
  /// 用户 2026-09-14 裁定：「畅想之星页不要显示账号卡片」→ 原先页首那张
  /// 数据来源卡（账号名 + 个人/公用账号胶囊 + 三个按钮）整体撤出页面，改由
  /// 右上角图标按需打开；**只在落到校园网公用账号时**在页首留一行提醒
  /// （否则会把全校汇总值当成个人进度看）。
  Future<void> _openSessionDialog() async {
    final overview = ref.read(cxstarOverviewProvider).valueOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (overview == null) {
      messenger.showSnackBar(const SnackBar(content: Text('数据还在加载中，请稍后再试')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined),
        title: const Text('阅读会话'),
        scrollable: true,
        content: _SessionPanel(overview: overview),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overviewAsync = ref.watch(cxstarOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('经典阅读 · 畅想之星'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '阅读会话',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _openSessionDialog,
          ),
          IconButton(
            tooltip: '书架 · 找书',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => _openChild(const CxstarShelfScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: overviewAsync.when(
          loading: () => ListView(
            padding: _padding,
            children: const [_InfoCard(text: '正在连接畅想之星…')],
          ),
          error: (error, _) => ListView(
            padding: _padding,
            children: [_ErrorCard(message: '$error')],
          ),
          data: (overview) => ListView(
            padding: _padding,
            children: [
              if (!overview.personal) ...[
                _SharedAccountNotice(onTap: _openSessionDialog),
                const SizedBox(height: 10),
              ],
              _SummaryCard(
                summary: overview.summary,
                updating: overviewAsync.isLoading,
                updatedAt: _updatedAt,
              ),
              const SizedBox(height: 22),
              const _SectionTitle(text: '找书 · 书架'),
              const SizedBox(height: 10),
              _ShelfEntryCard(onOpenChild: _openChild),
              const SizedBox(height: 22),
              const _SectionTitle(text: '阅读记录'),
              const SizedBox(height: 10),
              if (overview.records.isEmpty)
                const _InfoCard(text: '该账号下暂无阅读记录。')
              else
                _RecordsCard(
                  records: overview.records,
                  onOpenChild: _openChild,
                ),
              const SizedBox(height: 22),
              const _SectionTitle(text: '学分平台 · 经典阅读明细'),
              const SizedBox(height: 6),
              Text(
                '服务端（阅读学分平台）认定的经典阅读记录，按书名汇总、时长精确到秒；'
                '与上方畅想之星实时计数不是同一套数据。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              const _ReadCreditClassicSection(),
              const SizedBox(height: 22),
              const _SectionTitle(text: '说明'),
              const SizedBox(height: 10),
              const _NoteCard(),
            ],
          ),
        ),
      ),
    );
  }
}

const EdgeInsets _padding = EdgeInsets.fromLTRB(16, 14, 16, 40);

/// 从子页面（阅读器 / 书架）返回后的**累计**补刷时刻表。
///
/// 依据：平台统计是批量结算的 —— 实测（`reverse_engineering/畅想之星接口.md` §7.4）
/// 同一分钟内 `readMinutes` 不动、过几分钟一次跳好几分钟。所以「返回即刷」有可能
/// 取到的还是读完前的旧值；再按这几个时间点补取，刚读完的时长就会自己出现。
const List<Duration> cxstarReturnSettleDelays = <Duration>[
  Duration(seconds: 10),
  Duration(seconds: 45),
  Duration(seconds: 150),
];

/// 落到校园网公用账号时页首的一行提醒（**不是卡片**）。
///
/// 公用账号（`IPUSER…` / 「IP用户」）的阅读本数与时长是**全校汇总值**，不是本人
/// 进度（实测 2160 册 vs 个人 13 册）→ 必须让用户知道自己看的不是自己的数据，
/// 点击即打开「阅读会话」弹窗换个人会话。
class _SharedAccountNotice extends StatelessWidget {
  final VoidCallback onTap;

  const _SharedAccountNotice({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 15, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '当前是校园网公用账号，统计为全校汇总值，不代表你的个人进度 · 点此切换为个人账号',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「阅读会话」弹窗内容：当前会话档位 + 换个人会话 / 手工令牌 / 清除令牌。
///
/// 原先是页面顶部的一张数据来源卡，用户 2026-09-14 裁定「畅想之星页不要显示账号
/// 卡片」后整体撤出页面，改为由右上角图标按需打开的弹窗内容（见
/// `_CxstarScreenState._openSessionDialog`）。
class _SessionPanel extends ConsumerWidget {
  final CxstarOverview overview;

  const _SessionPanel({required this.overview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final source = overview.source;
    final shared =
        source == CxstarSessionSource.ipShared ||
        overview.user.isSharedIpAccount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IconBox(
              icon: Icons.auto_stories_outlined,
              color: FeaturePalette.cardAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overview.user.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    source.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _Chip(
              text: shared ? '公用账号' : '个人账号',
              color: shared ? scheme.error : FeaturePalette.cxstar,
            ),
          ],
        ),
        if (shared) ...[
          const SizedBox(height: 10),
          Text(
            '当前网络在校园网内，畅想之星自动以「IP用户」登录，'
            '该账号的阅读本数与时长是全校汇总值，不代表你的个人进度。'
            '点下方「使用统一身份认证登录」即可切换为你的数据。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (overview.fallbackNote != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  overview.fallbackNote!,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _useUnifiedAuth(context, ref),
              icon: const Icon(Icons.verified_user_outlined, size: 16),
              label: Text(
                source == CxstarSessionSource.unifiedAuth
                    ? '重新获取个人会话'
                    : '使用统一身份认证登录',
              ),
            ),
            TextButton(
              onPressed: () => _showTokenDialog(context, ref),
              child: const Text('手工令牌'),
            ),
            if (source == CxstarSessionSource.manualToken)
              TextButton(
                onPressed: () => _clearToken(context, ref),
                child: const Text('清除令牌'),
              ),
          ],
        ),
        if (source == CxstarSessionSource.unifiedAuth) ...[
          const SizedBox(height: 8),
          Text(
            '个人会话由学校统一身份认证下发，有效期 24 小时，过期后自动重新换取。',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 走统一身份认证换取个人会话（复用项目既有 CAS TGC）。
  Future<void> _useUnifiedAuth(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final account = ref.read(currentAccountProvider);
    if (account.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('请先登录后再获取畅想之星个人会话')));
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('正在通过统一身份认证获取畅想之星会话…')),
    );
    final trace = <String>[];
    try {
      final repository = await ref.read(cxstarAuthRepositoryProvider.future);
      final token = await repository.refreshSessionToken(account, trace: trace);
      ref.invalidate(cxstarOverviewProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已取得个人会话（${CxstarAuthRemoteDataSource.maskToken(token)}），正在刷新数据',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('获取个人会话失败：$e')));
    }
  }

  Future<void> _showTokenDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.vpn_key_outlined),
        title: const Text('手工令牌（高级）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '一般不需要：优先用「使用统一身份认证登录」自动获取个人会话。'
              '若统一认证链路不可用，可在电脑浏览器登录 m.cxstar.com 后，'
              '从开发者工具复制 Cookie 里的 mtoken 值（或抓包拿到的 '
              'Authorization Bearer 令牌）粘贴到这里。',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'token',
                hintText: 'eyJhbGciOi…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final box = await ref.read(cxstarTokenBoxProvider.future);
    if (saved.isEmpty) {
      await box.delete(cxstarTokenKey);
    } else {
      await box.put(cxstarTokenKey, saved);
    }
    ref.invalidate(cxstarPersonalTokenProvider);
    ref.invalidate(cxstarOverviewProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved.isEmpty ? '已清除个人令牌' : '已保存个人令牌')),
    );
  }

  Future<void> _clearToken(BuildContext context, WidgetRef ref) async {
    final box = await ref.read(cxstarTokenBoxProvider.future);
    await box.delete(cxstarTokenKey);
    ref.invalidate(cxstarPersonalTokenProvider);
    ref.invalidate(cxstarOverviewProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除手工令牌')));
  }
}

/// 统计卡：阅读本数 / 读完 / 累计时长 / 今日。
///
/// 底部显示「正在更新统计…」/「统计更新于 HH:mm:ss」：平台是批量结算的，数字可能
/// 几分钟不动，没有这行就无法区分「页面没刷新」与「刷新了但还没结算」。
class _SummaryCard extends StatelessWidget {
  final CxstarReadSummary summary;
  final bool updating;
  final DateTime? updatedAt;

  const _SummaryCard({
    required this.summary,
    this.updating = false,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${summary.readCount}',
                key: const Key('cxstar_read_count'),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  color: FeaturePalette.cardAccent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '本',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '畅想之星 · 阅读本数',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              _Metric(label: '读完本数', value: '${summary.finishCount} 本'),
              _Metric(
                label: '累计时长',
                value: cxstarDurationText(summary.readMinutes),
              ),
              _Metric(
                label: '今日时长',
                value: cxstarDurationText(summary.todayReadMinutes),
              ),
              _Metric(
                label: '笔记 / 书评',
                value: '${summary.noteCount} / ${summary.commentCount}',
              ),
            ],
          ),
          if (updating || updatedAt != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (updating) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在更新统计…',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Text(
                    '统计更新于 ${_hhmmss(updatedAt!)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _hhmmss(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 逐书阅读记录（点书名可在 App 内在线阅读:时长由平台服务端累计）。
///
/// 打开阅读器走 [onOpenChild]（= `_CxstarScreenState._openChild`），返回时它负责刷新统计。
/// 每行右下角另给「阅读报告」入口（累计时长 / 阅读天数 / **完成时间**，逐书惰性拉取）。
class _RecordsCard extends StatelessWidget {
  final List<CxstarReadRecord> records;
  final Future<void> Function(Widget page) onOpenChild;

  const _RecordsCard({required this.records, required this.onOpenChild});

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecordRow(record: records[i], onOpenChild: onOpenChild),
          ],
        ],
      ),
    );
  }
}

/// 单条阅读记录行：书名 / 作者·最近阅读 / 逐书统计（惰性拉取）。
class _RecordRow extends ConsumerWidget {
  final CxstarReadRecord record;
  final Future<void> Function(Widget page) onOpenChild;

  const _RecordRow({required this.record, required this.onOpenChild});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 逐书报告（累计时长 / 阅读天数 / 完成时间）：取不到就静默省略这一行。
    final report = record.bookId.isEmpty
        ? null
        : ref.watch(cxstarBookReportProvider(record.bookId)).valueOrNull;
    final finished = report?.finished ?? record.ifReadFinish;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: record.bookId.isEmpty
          ? null
          : () => onOpenChild(
              CxstarReaderScreen(bookId: record.bookId, title: record.title),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBox(
              icon: Icons.menu_book_outlined,
              color: FeaturePalette.cardAccent,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title.isEmpty ? '（无书名）' : record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (record.author.isNotEmpty) record.author,
                      if (record.readingTime.isNotEmpty) record.readingTime,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (report != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        '累计 ${cxstarDurationText(report.readMinutes)}',
                        if (report.activityText.isNotEmpty) report.activityText,
                        if (report.finished)
                          report.finishText ?? '已读完'
                        else
                          '未读完',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: report.finished
                            ? FeaturePalette.cxstar
                            : scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Chip(
              text: finished ? '已读完' : '阅读中',
              color: finished ? FeaturePalette.cxstar : scheme.outline,
            ),
            if (record.bookId.isNotEmpty) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
            if (report != null)
              IconButton(
                tooltip: '阅读报告',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.query_stats),
                onPressed: () => _showReportDialog(context, record, report),
              ),
          ],
        ),
      ),
    );
  }
}

/// 阅读报告弹窗：逐书统计全量（平台时长精度为分钟）。
void _showReportDialog(
  BuildContext context,
  CxstarReadRecord record,
  CxstarBookReport report,
) {
  final scheme = Theme.of(context).colorScheme;
  Widget row(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              color: highlight ? FeaturePalette.cxstar : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.query_stats),
      title: const Text('阅读报告'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            record.title.isEmpty ? '（无书名）' : record.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          row('累计阅读', cxstarDurationText(report.readMinutes), highlight: true),
          row('阅读天数', report.readDays > 0 ? '${report.readDays} 天' : '—'),
          row('阅读次数', report.readNo > 0 ? '${report.readNo} 次' : '—'),
          row(
            '首次阅读',
            report.startReadTime.isEmpty ? '—' : report.startReadTime,
          ),
          row('最近阅读', report.endReadTime.isEmpty ? '—' : report.endReadTime),
          row(
            '完成时间',
            report.finished
                ? (report.finishReadTime.isEmpty
                      ? '已读完'
                      : report.finishReadTime)
                : '未读完',
            highlight: report.finished,
          ),
          if (report.longestMinutes > 0)
            row(
              '单次最长',
              '${cxstarDurationText(report.longestMinutes)}'
                  '${report.longestDate.isEmpty ? '' : '（${report.longestDate}）'}',
            ),
          if (report.noteCount > 0) row('笔记数', '${report.noteCount}'),
          const SizedBox(height: 8),
          Text(
            '时长由畅想之星服务端累计，精度为分钟（平台不提供秒级数据）；'
            '仅在 App 内在线阅读或网页端阅读才会计入。',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 书架入口卡：分类浏览 20 万册 + 检索，点书进原生阅读器。
class _ShelfEntryCard extends StatelessWidget {
  final Future<void> Function(Widget page) onOpenChild;

  const _ShelfEntryCard({required this.onOpenChild});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpenChild(const CxstarShelfScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const _IconBox(
                icon: Icons.grid_view_rounded,
                color: FeaturePalette.cardAccent,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '书架 · 找书阅读',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '按中图法 / 学科 / 院系浏览 · 支持书名与关键词检索',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      child: Text(
        '数据来自畅想之星「经典阅读」平台（m.cxstar.com）自身统计，'
        '与阅读学分平台的「经典阅读」明细（10 册 + 20 小时口径）不是同一套记录：'
        '前者是平台内所有阅读行为，后者是学校认定的学分明细。\n'
        '会话三档：统一身份认证换取的个人会话（推荐，24 小时有效）→ '
        '手工令牌 → 校园网 IP 免密登录（公用账号，全校聚合）。\n'
        '平台的阅读时长由服务端按在线阅读行为累计（翻页/取内容都会计入），'
        '在网页端或 App 内阅读都会正常计入你的账号。\n'
        'App 内阅读器为原生渲染（不内嵌网页）:每页正文是平台下发的单页加密 PDF，'
        '按页解密后本地渲染；停留期间每 60 秒向平台发一次轻量心跳，'
        '因此只要在阅读页前台停留，时长就会持续计入。',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.7,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 学分平台（jhread）侧的「经典阅读」明细，归并展示在畅想之星页内。
///
/// 用户 2026-09-15 裁定：「取消畅想之星的独立入口…删除目前点击蛟湖阅读-经典阅读
/// 的界面，而是把点击后跳转的页面改成畅想之星」+「原页面所对应的数据源不删除，
/// 而是把信息归并到畅想之星功能内」——故：
/// - 蛟湖阅读页的经典阅读进度卡 → 本页（不再有独立入口卡、不再进原明细页）；
/// - 原明细页的数据源 [readCreditDetailProvider]`(classic)` **照旧保留**，改由
///   这里渲染（同一 [ReadCreditDetailView]）。
class _ReadCreditClassicSection extends ConsumerWidget {
  const _ReadCreditClassicSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const kind = ReadCreditKind.classic;
    final async = ref.watch(readCreditDetailProvider(kind));
    return async.when(
      loading: () => const _InfoCard(text: '正在读取学分平台明细…'),
      error: (error, _) => _InfoCard(text: '学分平台明细读取失败：$error'),
      data: (detail) {
        if (detail.isEmpty) {
          return const _InfoCard(text: '学分平台侧暂无经典阅读明细记录。');
        }
        return ReadCreditDetailView(
          detail: detail,
          onRefresh: () => ref.invalidate(readCreditDetailProvider(kind)),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;

  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends ConsumerWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 17, color: scheme.error),
              const SizedBox(width: 8),
              const Text(
                '畅想之星数据获取失败',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
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
              onPressed: () => ref.invalidate(cxstarOverviewProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
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
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _IconBox({required this.icon, required this.color, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;

  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
