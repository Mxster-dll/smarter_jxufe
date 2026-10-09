import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_common.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_sections.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_summary_cards.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_toolbar.dart';

/// ### 培养方案（Fluent / WinUI 3 视觉）
///
/// 结构 = 范围选择器 → 两张指标卡（理论课程 / 实践环节）→ 工具条（搜索 + 分组形态
/// + 快筛）→ 理论课程分组清单 → 实践环节 → 口径脚注。**不再使用**
/// `shared/widgets/reorderable_table`（那套自研半成品表格 2026-10-09 停用，本体保留）。
///
/// 三种分组形态（用户 2026-10-09 要求「支持各种显示方式，例如按分类聚合、
/// 按开课时间聚合；还要支持搜索」）与搜索 / 快筛的算法全在
/// `domain/curriculum_browse.dart`（纯逻辑，有单测）。
///
/// 口径全文见 `docs/agents/13-Fluent·Design（WinUI·3）基础层.md` §13.9。
class CurriculumScreen extends ConsumerStatefulWidget {
  /// 是否自建 AppBar：`ImsTabContainer` 里以 tab 正文形式挂载时为 false。
  final bool showAppBar;

  const CurriculumScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<CurriculumScreen> createState() => _CurriculumScreenState();
}

class _CurriculumScreenState extends ConsumerState<CurriculumScreen> {
  /// 首次进入 / 从子页面返回 / App 回前台都重取一次（§3「页面数据自动刷新」）。
  /// 走 `reload()` 的**缓存优先**路径：命中缓存时零网络，不会一回来就刷屏。
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _refreshFromCache,
  );

  final TextEditingController _search = TextEditingController();

  /// 已展开学时明细的课程键（[CurriculumCourseItem.key]）。
  final Set<String> _expanded = <String>{};

  CurriculumGroupMode _mode = CurriculumGroupMode.category;
  CurriculumQuickFilter _filter = CurriculumQuickFilter.all;
  String _query = '';

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
    _search.dispose();
    super.dispose();
  }

  /// 自动刷新：缓存优先（`force: false`）。
  void _refreshFromCache() {
    if (!mounted) return;
    ref.read(curriculumViewModelProvider.notifier).reload();
  }

  /// 用户点「刷新」：绕过缓存，从教务重抓两张表。
  void _refreshNow() {
    ref.read(curriculumViewModelProvider.notifier).reload(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final viewModel = ref.read(curriculumViewModelProvider.notifier);
    final asyncState = ref.watch(curriculumViewModelProvider);

    final body = FluentPageBackground(
      maxContentWidth: 1000,
      child: asyncState.when(
        loading: () => const FluentLoading(message: '正在读取培养方案…'),
        error: (error, _) => _ErrorView(
          title: '培养方案读取失败',
          message: '$error',
          onRetry: () => ref.invalidate(curriculumViewModelProvider),
        ),
        data: (state) => _buildContent(context, state, viewModel),
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: p.bgBase,
      appBar: AppBar(
        backgroundColor: p.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          '培养方案查询',
          style: FluentType.subtitle.copyWith(color: p.textPrimary),
        ),
      ),
      body: body,
    );
  }

  Widget _buildContent(
    BuildContext context,
    CurriculumState state,
    CurriculumViewModel viewModel,
  ) {
    final curriculum = state.curriculum;
    final courses = curriculum?.courses ?? const <Course>[];
    final browse = browseCurriculum(
      courses: courses,
      semesters: state.semesters,
      mode: _mode,
      query: _query,
      filter: _filter,
    );
    final summary = summarizeCurriculum(courses);
    final practice = state.practice;
    final practiceBrowse = practice == null
        ? null
        : browsePractice(
            stages: practice.stages,
            mode: _mode,
            query: _query,
            filter: _filter,
          );
    final refreshing =
        state.isLoadingTable ||
        state.isLoadingSemesters ||
        state.isLoadingPractice;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.wide;
        final padding = wide ? FluentSpacing.xl : FluentSpacing.lg;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            padding,
            padding,
            FluentSpacing.xxxl,
          ),
          children: [
            CurriculumSelectorCard(
              years: state.years,
              selectedYear: state.selectedYear,
              onYearChanged: viewModel.onYearChanged,
              colleges: state.colleges,
              selectedCollege: state.selectedCollege,
              onCollegeChanged: viewModel.onCollegeChanged,
              isLoadingColleges: state.isLoadingColleges,
              majors: state.majors,
              selectedMajor: state.selectedMajor,
              onMajorChanged: viewModel.onMajorChanged,
              isLoadingMajors: state.isLoadingMajors,
            ),
            const SizedBox(height: FluentSpacing.xl),

            if (state.errorMessage != null) ...[
              FluentInfoBar(
                severity: FluentInfoSeverity.error,
                title: '取数失败',
                message: state.errorMessage!,
                action: FluentButton(label: '重试', onPressed: _refreshNow),
              ),
              const SizedBox(height: FluentSpacing.xl),
            ],

            if (curriculum == null)
              _NoCurriculumHint(state: state)
            else ...[
              CurriculumOverviewCards(
                summary: summary,
                practice: practice,
                refreshing: refreshing,
                onRefresh: _refreshNow,
              ),
              const SizedBox(height: FluentSpacing.xl),

              CurriculumToolbar(
                searchController: _search,
                onQueryChanged: (value) => setState(() => _query = value),
                mode: _mode,
                onModeChanged: (value) => setState(() => _mode = value),
                filter: _filter,
                onFilterChanged: (value) => setState(() => _filter = value),
                matchedCount: browse.matchedCount,
                matchedCredits: browse.matchedCredits,
                totalCount: browse.totalCount,
                totalCredits: browse.totalCredits,
                filtered: browse.filtered,
                refreshing: refreshing,
              ),
              const SizedBox(height: FluentSpacing.lg),

              if (_mode == CurriculumGroupMode.term)
                _TermNotice(state: state, onRetry: _refreshNow),

              if (courses.isEmpty)
                const FluentInfoBar(
                  message: '这个专业的培养方案里没有课程条目 —— '
                      '可能是教务还没下发这一版教学计划表，或者它只有实践环节。',
                )
              else if (browse.isEmpty)
                FluentInfoBar(
                  message: _query.trim().isEmpty
                      ? '当前筛选下没有课程（共 ${browse.totalCount} 门）。'
                      : '没有匹配「${_query.trim()}」的课程（共 ${browse.totalCount} 门）—— '
                            '可以试课程名 / 课程代码 / 课程类别。',
                )
              else
                CurriculumSections(
                  result: browse,
                  mode: _mode,
                  expandedKeys: _expanded,
                  onToggle: (key) => setState(() {
                    if (!_expanded.remove(key)) _expanded.add(key);
                  }),
                ),

              PracticeSection(
                browse: practiceBrowse,
                error: state.practiceError,
                loading: state.isLoadingPractice,
                onRetry: _refreshNow,
              ),

              _SourceFootnote(
                summary: summary,
                practice: practice,
                overlap: practice == null
                    ? 0
                    : curriculumPracticeOverlap(
                        courses: courses,
                        practice: practice,
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 还没拿到理论课程表时的提示（区分「还没选」/「正在取」/「取不到」）。
class _NoCurriculumHint extends StatelessWidget {
  const _NoCurriculumHint({required this.state});

  final CurriculumState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingTable) {
      return const FluentCard(
        padding: EdgeInsets.all(FluentSpacing.lg),
        child: FluentLoading(message: '正在从教务读取培养方案…'),
      );
    }
    if (state.errorMessage != null) {
      // 失败原因已经在上面那条 InfoBar 里说清楚了，这里不重复。
      return const SizedBox.shrink();
    }
    return FluentInfoBar(
      message: state.selectedMajor == null
          ? '先在上面选好年级 / 学院 / 专业（有学籍缓存时会自动对上本专业），'
                '这里就会列出这份培养方案的理论课程与实践环节。'
          : '教务没有返回这个专业的培养方案 —— 换一个年级或专业再试，'
                '或者点上面的「重试」。',
    );
  }
}

/// 「按开课学期」聚合时的前置提示：没取到 / 教务没排定。
class _TermNotice extends StatelessWidget {
  const _TermNotice({required this.state, required this.onRetry});

  final CurriculumState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingSemesters) {
      return const Padding(
        padding: EdgeInsets.only(bottom: FluentSpacing.lg),
        child: FluentInfoBar(message: '正在读取每门课的开课学期…'),
      );
    }
    if (state.semestersError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FluentSpacing.lg),
        child: FluentInfoBar(
          severity: FluentInfoSeverity.warning,
          title: '开课学期没取到',
          message: '${state.semestersError}（这一列来自教务教学计划表，需要教务会话）。'
              '下面先把它们归到「未排定」里。',
          action: FluentButton(label: '重试', onPressed: onRetry),
        ),
      );
    }
    if (state.semesters.every((s) => s.trim().isEmpty)) {
      return const Padding(
        padding: EdgeInsets.only(bottom: FluentSpacing.lg),
        child: FluentInfoBar(
          message: '教务这一版教学计划表的「学年学期」列是空的 —— '
              '这些课还没排定开课学期，所以都归在「未排定」里。',
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 口径脚注：数据来源 + 学分合计 + 两张表的重叠说明。
class _SourceFootnote extends StatelessWidget {
  const _SourceFootnote({
    required this.summary,
    required this.practice,
    required this.overlap,
  });

  final CurriculumSummary summary;
  final PracticeCurriculum? practice;
  final int overlap;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final practiceCredits = practice?.totalCredits ?? 0;
    final lines = <String>[
      '数据来源：教务「培养方案 → 查看教学计划表」（理论课程）与「实践环节」两张表；'
          '开课学期取自理论课程表的「学年学期」列。',
      '学分合计：理论课程 ${crCreditText(summary.totalCredits)} 学分'
          '${practice == null ? '' : ' + 实践环节 ${crCreditText(practiceCredits)} 学分'}'
          '${practice == null ? '' : ' = ${crCreditText(summary.totalCredits + practiceCredits)} 学分'}。',
      if (overlap > 0)
        '其中 $overlap 门课两张表都有（如「劳动教育」）—— 两张表各算各的学分，这里不做去重。',
      '「主干课程」= 教务的课程地位为「主干」；学时明细点开每一门课即可看到。',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
            child: Text(
              line,
              style: FluentType.caption.copyWith(color: p.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// 整页取数失败（依赖装配阶段就抛了）：Fluent InfoBar + 重试。
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FluentInfoBar(
            severity: FluentInfoSeverity.error,
            title: title,
            message: message,
            action: FluentButton(label: '重试', onPressed: onRetry),
          ),
        ),
      ),
    );
  }
}
