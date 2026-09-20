import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_peer_sheet.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_sub_page_screen.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/design/app_states.dart';

/// 学生个人数据中心（dzj.jxufe.edu.cn）原生聚合页。
///
/// 与网页「个人首页」等价的全量概览：
/// 学籍概要 / 班主任 / 本周课程 / 学业（成绩·绩点·学分）/
/// 基础指标 / 校园卡消费与明细 / 奖助贷勤 / 教材 / 图书借阅 / 门户登录趋势。
class DataCenterScreen extends ConsumerWidget {
  const DataCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(dataCenterOverviewProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        // 内嵌进主页右侧面板时（该面板路由栈的首页）整条导航栏都不画，见 §17.7 / §19。
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('学生个人数据中心'),
        // 本页数据（校园网余额等）依赖平台标识（GUID）。
        settingsSections: const [SettingsSection.platformGuid],
        centerTitle: true,
      ),
      body: overviewAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载个人数据中心...'),
            ],
          ),
        ),
        error: (error, _) => AppErrorState(
          title: '加载失败',
          error: error,
          onRetry: () => ref.invalidate(dataCenterOverviewProvider),
        ),
        data: (overview) => _buildContent(context, ref, overview),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    DataCenterOverview o,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildStudentCard(context, o),
        const SizedBox(height: 12),
        _buildSubPageCard(context, ref),
        const SizedBox(height: 12),
        _buildWeekCard(context, o),
        const SizedBox(height: 12),
        _buildAcademicCard(context, o),
        const SizedBox(height: 12),
        ..._extraCards(context, ref, const [DzjExtraModule.courses]),
        _buildPeerCard(context, ref, o),
        const SizedBox(height: 12),
        _buildRelatedCard(context, ref),
        const SizedBox(height: 12),
        _buildMetricsCard(context, o),
        const SizedBox(height: 12),
        _buildCardSpendCard(context, o),
        const SizedBox(height: 12),
        _buildTextbookCard(context, o),
        const SizedBox(height: 12),
        _buildBorrowCard(context, o),
        const SizedBox(height: 12),
        ..._extraCards(context, ref, const [DzjExtraModule.seat]),
        _buildAwardCard(context, o),
        const SizedBox(height: 12),
        ..._extraCards(context, ref, const [DzjExtraModule.aid]),
        _buildLoginTrendCard(context, o),
      ],
    );
  }

  // ---- 子页面入口（学校「个人数据中心」下的九个页面） ----

  /// 「个人数据中心 · 子页面」卡：学校那十个子页面的入口（除「基本信息」）。
  ///
  /// 用户 2026-09-19 五轮原话：「我希望个人数据中心里加子页面 … 一共有十个这样的
  /// 子页面，我希望你找到获取这十个子页面链接的方式，并把这十个子页面中除了
  /// 『基本信息』整合到我的里面，其余九个子页面都做成 app 数据中心里的子页面」。
  ///
  /// 清单**不在 App 里写死**：watch [dzjPageTreeProvider]（服务端
  /// `manageTreeByVersion` 的页面树）→ [DzjPageTree.subPages] 已剔除首页与
  /// 「基本信息」（后者并入「我的」页）。学校加页面，这里自动多一行。
  Widget _buildSubPageCard(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dzjPageTreeProvider);
    final tree = async.valueOrNull;
    final pages = tree?.subPages ?? const <DzjPageNode>[];
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: AppColors.tone(context, Colors.teal[400]!),
                ),
                const SizedBox(width: 6),
                const Text(
                  '个人数据中心',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (pages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '共 ${pages.length} 个子页面',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ),
                if (async.hasError)
                  IconButton(
                    key: const Key('dzjSubPageTreeRetry'),
                    tooltip: '重新读取子页面清单',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => ref.invalidate(dzjPageTreeProvider),
                  ),
              ],
            ),
            if (pages.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
                child: Text(
                  async.hasError
                      ? '子页面清单读取失败：${friendlyErrorText(async.error!)}'
                      : (async.isLoading ? '正在读取子页面清单…' : '没有读到子页面'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(context),
                  ),
                ),
              )
            else
              for (final p in pages)
                ListTile(
                  key: Key('dzjSubPage-${p.pageKey}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    dzjSubPageIcon(p.title),
                    size: 20,
                    color: AppColors.tone(context, Colors.teal[400]!),
                  ),
                  title: Text(p.title, style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '学校「个人数据中心」子页面',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DzjSubPageScreen(
                        pageKey: p.pageKey,
                        title: p.title,
                      ),
                    ),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 8, 4),
              child: Text(
                '「基本信息」已并入「我的」页；页面清单来自学校中台，改版后自动更新。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 学籍概要 ----

  Widget _buildStudentCard(BuildContext context, DataCenterOverview o) {
    final name = o.username.isEmpty ? '?' : o.username;
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.infoFill(context),
              child: Text(
                name.characters.first,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info(context),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.username,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '校园卡号 ${o.userid}',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                  ),
                  Text(
                    o.college,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                  ),
                  if (o.advisorName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: AppColors.textMuted(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '班主任 ${o.advisorName}${o.advisorPhone.isNotEmpty ? ' · ${o.advisorPhone}' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 本周课程 ----

  Widget _buildWeekCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note, size: 18, color: AppColors.info(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    o.weekTitle.isEmpty ? '本周课程' : o.weekTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (o.weekDays.isNotEmpty)
                  Text(
                    '今日 ${o.todayClassCount} 节',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                  ),
              ],
            ),
            if (o.weekDays.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '暂无课程安排',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: o.weekDays.map((d) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoFill(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.info(
                            context,
                          ).withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        d.weekday,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 学业情况 ----

  Widget _buildAcademicCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.menu_book,
                  size: 18,
                  color: AppColors.tone(context, Colors.deepPurple[500]!),
                ),
                const SizedBox(width: 6),
                const Text(
                  '学业情况',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '加权平均',
                  value: _fmt(o.weightedScore),
                  unit: '分',
                  color: AppColors.tone(context, Colors.deepPurple[600]!),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '平均绩点',
                  value: _fmt(o.gpa),
                  unit: '',
                  color: AppColors.tone(context, Colors.indigo[600]!),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '修读学分',
                  value: _fmt(o.semesterCredit),
                  unit: '本学年',
                  color: AppColors.tone(context, Colors.teal[600]!),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '已获学分',
                  value: _fmt(o.earnedCredit),
                  unit: '初修',
                  color: AppColors.caution(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 补充模块（本学期课程 / 图书馆座位预约 / 助学金与勤工助学）----

  /// 每个模块一张卡。
  ///
  /// 用户 2026-09-19 三轮原话「其他的，都显示在数据中心内」→ **三张卡恒定渲染**
  /// （正在读取 / 读取失败 / 本期没有记录 / 条目），悄悄不画会让人以为没接上。
  /// 数据来自按需 provider [dzjExtraProvider]（3 个请求，不进首屏）。
  List<Widget> _extraCards(
    BuildContext context,
    WidgetRef ref,
    List<DzjExtraModule> modules,
  ) {
    final async = ref.watch(dzjExtraProvider);
    return [
      for (final m in modules)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _extraCard(context, ref, m, async),
        ),
    ];
  }

  /// 一个补充模块卡上最多列几条（其余靠「共 N 条」交代）。
  static const int _extraRowsShown = 8;

  Widget _extraCard(
    BuildContext context,
    WidgetRef ref,
    DzjExtraModule module,
    AsyncValue<DzjExtraInfo> async,
  ) {
    final block = async.valueOrNull?.block(module);
    final accent = AppColors.tone(context, module.accent);
    final muted = TextStyle(fontSize: 12, color: AppColors.textMuted(context));

    final Widget body;
    if (block == null && async.isLoading) {
      body = Text('正在读取…', style: muted);
    } else if (block == null && async.hasError) {
      body = Text(
        '读取失败：${friendlyErrorText(async.error!)}',
        style: muted,
      );
    } else if (block == null || block.isEmpty) {
      body = Text(module.emptyText, style: muted);
    } else {
      final rows = block.items.take(_extraRowsShown).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in rows) _extraRow(context, it),
          if (block.total > rows.length)
            Text(
              '共 ${block.total} 条 · 只列最近 ${rows.length} 条',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted(context),
              ),
            ),
        ],
      );
    }

    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(module.icon, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    module.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (block != null && block.total > 0)
                  Text(
                    '${block.total} 条',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                if (block == null && async.hasError)
                  IconButton(
                    key: Key('dzjExtraRetry-${module.key}'),
                    tooltip: '重新读取',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 17),
                    onPressed: () => ref.invalidate(dzjExtraProvider),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            body,
          ],
        ),
      ),
    );
  }

  /// 一条补充信息：左标签 + 右值 +（可选）下一行小字说明。
  Widget _extraRow(BuildContext context, DzjInfoItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (item.value.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (item.detail.isNotEmpty)
            Text(
              item.detail,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted(context),
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }

  // ---- 校内关系 / 相关人员（点人数看名单）----

  /// 「校内关系」卡（组件 `u:fcd2d17a9131`，5 维 + 派生 1 维）。
  ///
  /// 维度表 = [DzjPeerDimension.relationDims]（键与 `peerCounts` 一一对应）；
  /// 点人数看名单（「舍友 3 人」到底是哪三位）。
  ///
  /// 额外挂一枚 **「同年级同学院」**（用户 2026-09-20 立项）：它不在服务端五路里，
  /// 是「同年级」行集按本人学院过滤出来的（[dzjCollegeFilterSql] 一次请求拿 total），
  /// 排在同年级后面；取不到就整枚不画（不谎报 0 人）。
  Widget _buildPeerCard(
    BuildContext context,
    WidgetRef ref,
    DataCenterOverview o,
  ) {
    final visible = DzjPeerDimension.relationDims.where((d) {
      final v = o.peerCounts[d.key];
      return v != null && v >= 0;
    }).toList();
    final gradeCollege = ref.watch(dzjGradeCollegeCountProvider).valueOrNull;
    if (gradeCollege != null && gradeCollege > 0) {
      final at = visible.indexOf(DzjPeerDimension.grade);
      visible.insert(at < 0 ? 0 : at + 1, DzjPeerDimension.gradeCollege);
    }
    // 有哪一枚就画哪一枚：五维来自 `peerCounts`，「同年级同学院」来自它自己那条
    // 过滤查询 —— 后者拿到了就该显示，哪怕五维那一份整体没取到。
    final hasData = visible.isNotEmpty;
    return _rosterCard(
      context,
      icon: Icons.people_outline,
      accent: Colors.pink[400]!,
      title: '校内关系',
      visible: visible,
      countOf: (d) => d == DzjPeerDimension.gradeCollege
          ? (gradeCollege ?? 0)
          : (o.peerCounts[d.key] ?? 0),
      hint: '点人数可查看名单（含学号 / 班级 / 年级）',
      emptyText: hasData ? null : '暂无关系数据',
    );
  }

  /// 「相关人员」卡（组件 `u:af43933a919c`，6 维）。
  ///
  /// 用户 2026-09-19 二轮原话点名了学校第二个页面（`228583a5077f`）——
  /// 「这两个部分的同学名单我都要，但是后者可以查看学号班级和年级，前者只能看姓名学院」
  /// → 与「校内关系」并列的第二张名单卡；这六个维度**只有姓名 / 性别 / 校园卡号 / 学院**，
  /// 所以名单行里不会有班级年级（那是服务端本来就没给的列）。
  ///
  /// 人数单独按需取（[dzjRelatedCountsProvider]）：首屏 20 个请求已经够重，
  /// 这张卡先画「正在读取…」，到了再填数；失败给「重试」，不谎报 0 人。
  Widget _buildRelatedCard(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dzjRelatedCountsProvider);
    final counts = async.valueOrNull;
    final visible = DzjPeerDimension.relatedDims
        .where((d) => (counts?[d.key] ?? -1) >= 0)
        .toList();
    final String? emptyText;
    if (async.hasError) {
      emptyText = '读取失败：${friendlyErrorText(async.error!)}';
    } else if (visible.isEmpty) {
      emptyText = async.isLoading ? '正在读取…' : '暂无相关人员数据';
    } else {
      emptyText = null;
    }
    return _rosterCard(
      context,
      icon: Icons.hub_outlined,
      accent: Colors.indigo[400]!,
      title: '相关人员',
      visible: visible,
      countOf: (d) => counts?[d.key] ?? 0,
      hint: '点人数可查看名单（该名单只有姓名 / 学院）',
      emptyText: emptyText,
      onRetry: () => ref.invalidate(dzjRelatedCountsProvider),
    );
  }

  /// 名单卡外壳：标题 + 人数胶囊（可点）+ 脚注。
  ///
  /// 两张名单卡（校内关系 / 相关人员）只有**来源组件与配色**不同，壳子共用一份
  /// —— 免得胶囊的圆角、点击区、key 规则在两边各写一遍后慢慢分叉。
  Widget _rosterCard(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required List<DzjPeerDimension> visible,
    required int Function(DzjPeerDimension) countOf,
    required String hint,
    required String? emptyText,
    VoidCallback? onRetry,
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
                Icon(icon, size: 18, color: AppColors.tone(context, accent)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (onRetry != null)
                  IconButton(
                    key: const Key('dzjRelatedRetry'),
                    tooltip: '重新读取',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 17),
                    onPressed: onRetry,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (emptyText != null)
              Text(
                emptyText,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted(context),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in visible)
                    _peerPill(
                      context,
                      dimension: d,
                      value: countOf(d),
                      accent: accent,
                    ),
                ],
              ),
            if (emptyText == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 人数胶囊：`3 人 / 舍友`，整格可点 → 该维度的名单弹层。
  Widget _peerPill(
    BuildContext context, {
    required DzjPeerDimension dimension,
    required int value,
    required Color accent,
  }) {
    final tone = AppColors.tone(context, accent);
    return InkWell(
      key: Key('dzjPeer-${dimension.key}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () =>
          showDzjPeerSheet(context, dimension: dimension, count: value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.statusFill(context, tone),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value 人',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: value > 0 ? tone : AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              dimension.label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 基础指标 ----

  Widget _buildMetricsCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.speed, size: 18, color: AppColors.textMuted(context)),
                const SizedBox(width: 6),
                const Text(
                  '基础指标',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '校园卡余额',
                  value: _fmt(o.cardBalance),
                  unit: '元',
                  color: AppColors.success(context),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '今日进出校门',
                  value: _fmt(o.gateToday),
                  unit: '次',
                  color: AppColors.info(context),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '今日登录门户',
                  value: _fmt(o.todayLoginCount),
                  unit: '次',
                  color: AppColors.caution(context),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '校园网余额',
                  value: _fmt(o.networkBalance),
                  unit: '元',
                  color: AppColors.tone(context, Colors.cyan[800]!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 校园卡消费 ----

  Widget _buildCardSpendCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.credit_card,
                  size: 18,
                  color: AppColors.critical(context),
                ),
                const SizedBox(width: 6),
                const Text(
                  '校园卡消费',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '本年消费',
                  value: _fmt(o.spendYear),
                  unit: '元',
                  color: AppColors.critical(context),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '当月消费',
                  value: _fmt(o.spendMonth),
                  unit: '元',
                  color: AppColors.caution(context),
                ),
                _scoreDivider(context),
                _scoreCell(
                  context,
                  label: '本周消费',
                  value: _fmt(o.spendWeek),
                  unit: '元',
                  color: AppColors.caution(context),
                ),
              ],
            ),
            if (o.consumeRecords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '最近消费',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
              ),
              const SizedBox(height: 6),
              ...o.consumeRecords.take(5).map(
                (r) => _buildConsumeTile(context, r),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsumeTile(BuildContext context, DzjConsumeRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.fillSoft(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.stroke(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.shopName, style: const TextStyle(fontSize: 12.5)),
                Text(
                  r.time,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '¥${_fmt(r.amount)}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: AppColors.critical(context),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 教材 ----

  Widget _buildTextbookCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 18,
              color: AppColors.tone(context, Colors.brown[600]!),
            ),
            const SizedBox(width: 6),
            const Text(
              '本学期教材',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _scoreCell(
              context,
              label: '教材费用',
              value: _fmt(o.textbookFee),
              unit: '元',
              color: AppColors.tone(context, Colors.brown[600]!),
            ),
            _scoreDivider(context),
            _scoreCell(
              context,
              label: '教材数量',
              value: _fmt(o.textbookCount),
              unit: '本',
              color: AppColors.tone(context, Colors.brown[700]!),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 图书借阅 ----

  Widget _buildBorrowCard(BuildContext context, DataCenterOverview o) {
    const order = ['本周', '本月', '本年'];
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_library, size: 18, color: AppColors.tone(context, Colors.teal[700]!)),
                const SizedBox(width: 6),
                const Text(
                  '图书借阅',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: order.map((label) {
                final count = o.borrowCounts[label] ?? 0;
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$count 本',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: count > 0
                              ? AppColors.tone(context, Colors.teal[700]!)
                              : AppColors.textMuted(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 奖助贷勤 ----

  Widget _buildAwardCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 18,
                  color: AppColors.caution(context),
                ),
                const SizedBox(width: 6),
                const Text(
                  '奖助贷勤',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (o.awards.isEmpty)
              Text(
                '暂无奖助贷勤记录',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              )
            else
              ...o.awards.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_right,
                        size: 15,
                        color: AppColors.textMuted(context),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          a,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted(context),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 门户登录趋势 ----

  Widget _buildLoginTrendCard(BuildContext context, DataCenterOverview o) {
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 18, color: AppColors.tone(context, Colors.indigo[400]!)),
                const SizedBox(width: 6),
                const Text(
                  '门户登录趋势（本周）',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (o.loginTrend.isEmpty)
              Text(
                '暂无登录数据',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: o.loginTrend.map((d) {
                  final max = o.loginTrend.fold<int>(
                    1,
                    (m, x) => x.count > m ? x.count : m,
                  );
                  final height = 60.0 * (d.count / max);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Text(
                            '${d.count}',
                            style: TextStyle(
                              fontSize: 10,
                              color: d.count > 0
                                  ? AppColors.tone(context, Colors.indigo[700]!)
                                  : AppColors.textMuted(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 60,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: height.clamp(2, 60),
                              decoration: BoxDecoration(
                                color: d.count > 0
                                    ? AppColors.tone(context, Colors.indigo[400]!)
                                    : AppColors.fillStrong(context),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.weekday.replaceAll('星期', '周'),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textMuted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 通用小组件 ----

  Widget _scoreCell(
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

  Widget _scoreDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.stroke(context),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
