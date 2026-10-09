import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/credit_progress_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/graduation_requirements_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/widgets/credit_progress_widgets.dart';

/// 毕业学分**要求**数据 Provider（教务 `DataTable.jsp?tableId=6033`）。
///
/// ⚠ 这张表**只有要求值**，没有「已获学分」列。已修 / 还差的推算在
/// `credit_progress_provider.dart` 的 `graduationCreditReportProvider`。
/// 定义留在页面文件里是既成事实（`features/ai/tools/plan_tools.dart` 按这个路径 import），
/// 别为了层次好看复制一份。
final graduationRequirementsProvider =
    FutureProvider<List<GraduationRequirement>>((ref) async {
      final repo = await ref.watch(
        graduationRequirementsRepositoryProvider.future,
      );
      final result = await repo.getGraduationRequirements();
      return result.fold(
        (failure) => throw ImsApiException(failure.message ?? '获取毕业学分要求失败'),
        (requirements) => requirements,
      );
    });

/// 毕业学分页（Fluent / WinUI 3 视觉）。
///
/// 结构：两张指标卡（**必修进度** / **选修进度**）→「必修课进度」卡（总数 + 还差
/// 哪些课）→「选修课进度」卡（教务要求 7 项逐项 已修/要求/还差）→「未归类」卡
/// （两条链路都没算进去的课 + 原因）→ 口径脚注。
///
/// 口径全文见 `docs/agents/13-Fluent·Design（WinUI·3）基础层.md` §13.3 与
/// `domain/credit_progress.dart` 的 library doc。
class GraduationRequirementsScreen extends ConsumerStatefulWidget {
  /// 是否自建 AppBar：`ImsTabContainer` 里以 tab 正文形式挂载时为 false。
  final bool showAppBar;

  const GraduationRequirementsScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<GraduationRequirementsScreen> createState() =>
      _GraduationRequirementsScreenState();
}

class _GraduationRequirementsScreenState
    extends ConsumerState<GraduationRequirementsScreen> {
  /// 首次进入 / 从子页面返回 / App 回前台都重取一次（§3「页面数据自动刷新」）。
  /// 本页是 IMS 容器里的 tab 正文而非独立路由，`subscribeRoute` 会订阅到
  /// 容器的那个路由 —— 从子页面返回与回前台照常生效。
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _refreshIfLoaded,
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

  /// 自动刷新用：跳过首帧那次尚未完成的加载，免得把同一个请求重发一遍。
  void _refreshIfLoaded() {
    if (!mounted) return;
    invalidateIfLoaded(ref, graduationRequirementsProvider);
    invalidateIfLoaded(ref, graduationCreditReportProvider);
  }

  /// 手动刷新：要求表**没有本地缓存**（每次进页面都走网络），必须一起失效。
  void _refreshNow() {
    ref.invalidate(graduationRequirementsProvider);
    ref.invalidate(graduationCreditReportProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final asyncReport = ref.watch(graduationCreditReportProvider);

    final body = FluentPageBackground(
      child: asyncReport.when(
        loading: () => const FluentLoading(message: '正在推算毕业学分进度…'),
        error: (error, _) => _ErrorView(
          title: '推算毕业学分进度失败',
          message: '$error',
          onRetry: _refreshNow,
        ),
        data: (report) => _ReportView(
          report: report,
          refreshing: asyncReport.isLoading,
          onRefresh: _refreshNow,
        ),
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
          '毕业学分要求',
          style: FluentType.subtitle.copyWith(color: p.textPrimary),
        ),
      ),
      body: body,
    );
  }
}

/// 取数据失败：Fluent InfoBar（错误态）+ 重试按钮。
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

/// 主内容：指标卡 + 必修进度 + 选修进度 + 未归类 + 脚注。
class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.report,
    required this.refreshing,
    required this.onRefresh,
  });

  final GraduationCreditReport report;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final progress = report.progress;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.wide;
        final pagePadding = wide ? FluentSpacing.xl : FluentSpacing.lg;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            pagePadding,
            pagePadding,
            FluentSpacing.xxxl,
          ),
          children: [
            // 挂科警示：**排在指标卡上面**。挂科会直接改变「已修 / 还差」的含义
            // （挂掉的课不算已修），用户必须先看到再往下读数字。
            if (progress.hasFailed) ...[
              FailedWarningBar(courses: progress.failedCourses),
              const SizedBox(height: FluentSpacing.xl),
            ],

            CreditOverviewCards(
              progress: progress,
              refreshing: refreshing,
              onRefresh: onRefresh,
            ),
            const SizedBox(height: FluentSpacing.xl),

            FluentSectionHeader(
              title: '必修课进度',
              description: progress.curriculumLabel == null
                  ? '培养方案拿不到'
                  : '理论课程 ${progress.curriculumLabel}',
            ),
            CompulsoryProgressCard(progress: progress.compulsory),
            const SizedBox(height: FluentSpacing.xl),

            FluentSectionHeader(
              title: '实践环节进度',
              description: progress.practice.label == null
                  ? '实践环节表拿不到'
                  : '培养方案实践环节 ${progress.practice.label}',
            ),
            PracticeProgressCard(progress: progress.practice),
            const SizedBox(height: FluentSpacing.xl),

            FluentSectionHeader(
              title: '选修课进度',
              description: progress.hasElectives
                  ? '教务「毕业学分要求」${progress.electives.length} 项 · '
                        '合计 ${creditText(progress.electiveRequired)} 学分'
                  : '教务「毕业学分要求」',
            ),
            _ElectiveSection(report: report, onRetry: onRefresh),

            if (progress.unmatched.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.xl),
              FluentSectionHeader(
                title: '未归类课程（${progress.unmatched.length} 门）',
                description:
                    '这些课没被算进上面任何一项，共 '
                    '${creditText(progress.unmatchedCredits)} 学分',
              ),
              UnmatchedCoursesCard(courses: progress.unmatched),
            ],

            if (progress.notCounted.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.xl),
              FluentSectionHeader(
                title: '不计入总学分（${progress.notCounted.length} 门）',
                description: '学校文件规定不算毕业学分，只作毕业资格审核依据',
              ),
              NotCountedCoursesCard(courses: progress.notCounted),
            ],

            const SizedBox(height: FluentSpacing.lg),
            CreditProgressNotes(
              notes: [
                ...progress.notes,
                '已修学分合计 ${creditText(progress.earnedTotal)} 学分'
                    '（含未归类课程），与成绩页口径一致。',
                '数据来源：教务「毕业学分要求」表 + 本专业培养方案 + '
                    '通识课程库${progress.catalogScope == null ? '' : '（${progress.catalogScope!.sheetTitles.join('」「')}）'}'
                    ' + 成绩页缓存。',
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 选修段：要求表挂了只影响这一节，必修进度照常显示。
class _ElectiveSection extends StatelessWidget {
  const _ElectiveSection({required this.report, required this.onRetry});

  final GraduationCreditReport report;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = report.requirementsError;
    if (error != null) {
      return FluentCard(
        padding: const EdgeInsets.all(FluentSpacing.lg),
        child: FluentInfoBar(
          severity: FluentInfoSeverity.error,
          title: '教务「毕业学分要求」表读取失败',
          message: error,
          action: FluentButton(label: '重试', onPressed: onRetry),
        ),
      );
    }
    if (!report.progress.hasElectives) {
      return const FluentCard(
        padding: EdgeInsets.all(FluentSpacing.lg),
        child: FluentInfoBar(message: '教务未返回毕业学分要求数据，可稍后重试。'),
      );
    }

    final items = report.progress.electives;
    return FluentCard(
      padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const FluentDivider(),
            ElectiveProgressRow(index: i + 1, item: items[i]),
          ],
        ],
      ),
    );
  }
}
