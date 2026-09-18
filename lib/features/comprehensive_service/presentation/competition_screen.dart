/// 第二课堂「学科竞赛」主页：我的申请 + 竞赛公示两个 Tab。
///
/// 数据全部来自综合管理服务平台团委模块（与第二课堂学分 / 志愿时长同一套会话），
/// 页面对应官网菜单「学科竞赛申请」「学科竞赛公示」。
///
/// 刷新口径：两个列表用的都是 `autoDispose` family provider，离开页面即释放；
/// 从子页面（新增申请 / 详情）返回时用 `await push` 后 `invalidate` 显式重取
/// —— 所以不需要 `PageAutoRefresher`（那套是给有本地缓存的页面用的）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_apply_form_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_detail_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_widgets.dart';

class CompetitionScreen extends ConsumerStatefulWidget {
  const CompetitionScreen({super.key});

  @override
  ConsumerState<CompetitionScreen> createState() => _CompetitionScreenState();
}

class _CompetitionScreenState extends ConsumerState<CompetitionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

  CompetitionApplyQuery _applyQuery = const CompetitionApplyQuery();
  CompetitionPublicityQuery _publicityQuery = const CompetitionPublicityQuery();

  final _applyYearCtrl = TextEditingController();
  final _applyGameCtrl = TextEditingController();
  final _pubIdCtrl = TextEditingController();
  final _pubNameCtrl = TextEditingController();
  final _pubClassCtrl = TextEditingController();

  bool _deleting = false;

  @override
  void dispose() {
    _tabs.dispose();
    _applyYearCtrl.dispose();
    _applyGameCtrl.dispose();
    _pubIdCtrl.dispose();
    _pubNameCtrl.dispose();
    _pubClassCtrl.dispose();
    super.dispose();
  }

  // ---- 动作 ----

  void _refreshCurrent() {
    if (_tabs.index == 0) {
      ref.invalidate(competitionApplyListProvider(_applyQuery));
    } else {
      ref.invalidate(competitionPublicityListProvider(_publicityQuery));
    }
  }

  Future<void> _openApplyForm() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CompetitionApplyFormScreen()),
    );
    if (submitted ?? false) {
      _refreshCurrent();
    }
  }

  Future<void> _openApplyDetail(CompetitionApply apply) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CompetitionDetailScreen(
          title: '申请详情',
          loader: competitionApplyDetailLoader(apply.id),
          summary: _summaryLines(
            title: apply.gameName,
            lines: [
              '${apply.year} · ${apply.type.label} · 申请 ${apply.applyTime}',
              '审批状态：${apply.status.isEmpty ? '—' : apply.status}',
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPublicityDetail(CompetitionPublicity item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CompetitionDetailScreen(
          title: '公示详情',
          loader: competitionPublicityDetailLoader(item.id, item.type),
          summary: _summaryLines(
            title: item.gameName,
            lines: [
              '${item.studentName} · ${item.studentId}',
              '${item.college} · ${item.className}',
              '公示时间：${item.time}',
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryLines({required String title, required List<String> lines}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Future<void> _deleteApply(CompetitionApply apply) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除这条申请？'),
        content: Text('「${apply.gameName}」的申请记录会被删除，删除后需要重新提交。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _deleting = true);
    try {
      final account = ref.read(currentAccountProvider);
      final repository = await ref.read(competitionRepositoryProvider.future);
      await repository.deleteApplies(account, [apply.id]);
      if (!mounted) return;
      showCompetitionMessage(context, '已删除');
      _refreshCurrent();
    } catch (error) {
      if (!mounted) return;
      showCompetitionMessage(context, '删除失败：$error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    final embedded = paneIsRoot(context);
    final tabs = TabBar(
      controller: _tabs,
      tabs: const [
        Tab(text: '我的申请'),
        Tab(text: '竞赛公示'),
      ],
    );
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('学科竞赛'),
        centerTitle: true,
        bottom: embedded ? null : tabs,
      ),
      body: PaneBody(
        height: kTextTabBarHeight,
        leading: embedded ? tabs : null,
        padding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshCurrent,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: TabBarView(
          controller: _tabs,
          children: [_buildApplyTab(), _buildPublicityTab()],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _openApplyForm,
              icon: const Icon(Icons.add),
              label: const Text('申请竞赛'),
            )
          : null,
    );
  }

  // ---- Tab 1：我的申请 ----

  Widget _buildApplyTab() {
    final async = ref.watch(competitionApplyListProvider(_applyQuery));
    return Column(
      children: [
        _searchCard(
          children: [
            SizedBox(
              width: 92,
              child: TextField(
                controller: _applyYearCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '比赛年份',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _applySearch(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _applyGameCtrl,
                decoration: const InputDecoration(
                  labelText: '比赛名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _applySearch(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '查询',
              onPressed: _applySearch,
              icon: const Icon(Icons.search),
            ),
          ],
          onReset: () => setState(() {
            _applyYearCtrl.clear();
            _applyGameCtrl.clear();
            _applyQuery = const CompetitionApplyQuery();
          }),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CompetitionErrorCard(
                error: error,
                onRetry: () =>
                    ref.invalidate(competitionApplyListProvider(_applyQuery)),
              ),
            ),
            data: (page) {
              if (page.items.isEmpty) {
                return const CompetitionEmptyHint(
                  icon: Icons.emoji_events_outlined,
                  title: '还没有申请记录',
                  subtitle:
                      '点右下角「申请竞赛」选择比赛、上传证书图片后提交，'
                      '审批进度会显示在这里。',
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(
                          competitionApplyListProvider(_applyQuery),
                        );
                        await ref.read(
                          competitionApplyListProvider(_applyQuery).future,
                        );
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: page.items.length,
                        itemBuilder: (context, index) =>
                            _applyCard(page.items[index]),
                      ),
                    ),
                  ),
                  CompetitionPagerBar(
                    page: page.page,
                    totalPages: page.totalPages,
                    onPage: (next) => setState(
                      () => _applyQuery = _applyQuery.copyWith(page: next),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _applySearch() => setState(() {
    _applyQuery = CompetitionApplyQuery(
      year: _applyYearCtrl.text.trim(),
      gameName: _applyGameCtrl.text.trim(),
    );
  });

  /// 申请条目右侧的**加分**胶囊。
  ///
  /// 用户 2026-09-18 原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」。
  /// 申请列表（`apply_list.html`）没有奖项与分值列 → 加分只能按行拉详情取，所以这里是一个
  /// 独立的小 provider（`autoDispose` + 卡片进视口才请求，与公示的等级胶囊同一套路）；
  /// 取到前显示占位「…」，失败就不显示（不打断列表）。点胶囊看该赛别的分值标准。
  Widget _applyAwardChip(CompetitionApply apply) {
    final async = ref.watch(
      competitionApplyAwardProvider((id: apply.id, type: apply.type)),
    );
    return async.when(
      data: (award) => CompetitionApplyAwardChip(
        award: award,
        onTap: () => showCompetitionApplyAwardSheet(
          context,
          gameName: apply.gameName,
          award: award,
        ),
      ),
      loading: () => const CompetitionApplyAwardChip(loading: true),
      error: (_, _) => const CompetitionApplyAwardChip(unknown: true),
    );
  }

  Widget _applyCard(CompetitionApply apply) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        onTap: () => _openApplyDetail(apply),
        child: Padding(
          padding: const EdgeInsets.all(kAppCardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      apply.gameName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _applyAwardChip(apply),
                  CompetitionStatusChip(status: apply.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CompetitionTypeChip(type: apply.type),
                  const SizedBox(width: 8),
                  Text(
                    '${apply.year} · 申请 ${apply.applyTime}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '删除申请',
                    visualDensity: VisualDensity.compact,
                    onPressed: _deleting ? null : () => _deleteApply(apply),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Tab 2：竞赛公示 ----

  Widget _buildPublicityTab() {
    final async = ref.watch(competitionPublicityListProvider(_publicityQuery));
    return Column(
      children: [
        _searchCard(
          children: [
            Expanded(
              child: TextField(
                controller: _pubIdCtrl,
                decoration: const InputDecoration(
                  labelText: '学号',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _publicitySearch(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _pubNameCtrl,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _publicitySearch(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _pubClassCtrl,
                decoration: const InputDecoration(
                  labelText: '班级',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _publicitySearch(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '查询',
              onPressed: _publicitySearch,
              icon: const Icon(Icons.search),
            ),
          ],
          onReset: () => setState(() {
            _pubIdCtrl.clear();
            _pubNameCtrl.clear();
            _pubClassCtrl.clear();
            _publicityQuery = const CompetitionPublicityQuery();
          }),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CompetitionErrorCard(
                error: error,
                onRetry: () => ref.invalidate(
                  competitionPublicityListProvider(_publicityQuery),
                ),
              ),
            ),
            data: (page) {
              if (page.items.isEmpty) {
                return const CompetitionEmptyHint(
                  icon: Icons.campaign_outlined,
                  title: '没有公示记录',
                  subtitle: '默认展示全校已公示的竞赛获奖，可按学号 / 姓名 / 班级搜索。',
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(
                          competitionPublicityListProvider(_publicityQuery),
                        );
                        await ref.read(
                          competitionPublicityListProvider(
                            _publicityQuery,
                          ).future,
                        );
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: page.items.length,
                        itemBuilder: (context, index) =>
                            _publicityCard(page.items[index]),
                      ),
                    ),
                  ),
                  CompetitionPagerBar(
                    page: page.page,
                    totalPages: page.totalPages,
                    onPage: (next) => setState(
                      () => _publicityQuery = _publicityQuery.copyWith(
                        page: next,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _publicitySearch() => setState(() {
    _publicityQuery = CompetitionPublicityQuery(
      studentId: _pubIdCtrl.text.trim(),
      name: _pubNameCtrl.text.trim(),
      className: _pubClassCtrl.text.trim(),
    );
  });

  Widget _publicityCard(CompetitionPublicity item) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        onTap: () => _openPublicityDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(kAppCardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.gameName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _publicityAwardChip(item),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CompetitionTypeChip(type: item.type),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${item.studentName} · ${item.studentId}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    item.time,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${item.college} · ${item.className}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 公示卡右上角的获奖等级胶囊。
  ///
  /// 公示列表（`gs_list.html`）**没有等级列** → 等级只能按行拉详情取，故这里是
  /// 一个独立的小 provider：卡片（`ListView.builder` 懒构建）进入视口才发请求，
  /// 取到前显示占位「…」，失败就不显示（不打断列表）。
  Widget _publicityAwardChip(CompetitionPublicity item) {
    final async = ref.watch(
      competitionPublicityAwardProvider((id: item.id, type: item.type)),
    );
    return async.when(
      data: (award) =>
          CompetitionAwardChip(award: award, unknown: award.isEmpty),
      loading: () => const CompetitionAwardChip(loading: true),
      error: (_, _) => const CompetitionAwardChip(unknown: true),
    );
  }

  // ---- 搜索卡 ----

  Widget _searchCard({
    required List<Widget> children,
    required VoidCallback onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          ...children,
          IconButton(
            tooltip: '重置',
            onPressed: onReset,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
    );
  }
}
