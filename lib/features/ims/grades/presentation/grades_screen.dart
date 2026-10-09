import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/curriculum_importance_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/recommendation_weighted.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/practice_course_filter_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_exclusions.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/transcript_sheet.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/widgets/grades_ranking_row.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/widgets/grades_summary_card.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/widgets/grades_table.dart';


import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/design/app_states.dart';

class GradesScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const GradesScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  bool _pickerHovered = false;

  String? _sortKey;
  bool _sortAsc = true;

  /// 重修成绩：课程代码 → 修改后的分数
  final Map<String, String> _retakeScores = {};

  /// 已提示过的 diff 哈希，避免同一次变更重复弹 SnackBar。
  int? _lastShownDiffHash;

  /// 上一次的汇总统计值，用于计算变动差值。
  Map<String, double> _prevStats = {};

  /// 当前差值，用于右上角浮动显示。
  Map<String, double> _deltaValues = {};
  bool _showDeltas = false;

  /// 上一帧的统计哈希，避免重复触发。
  int? _lastStatsHash;

  /// 首次进入时是否已触发自动后台刷新（检测与上次缓存的数据差异）。
  bool _initialAutoRefreshDone = false;

  /// 统计中排除的课程 = **实践类课程**（与分数估计模块共用同一份判据，
  /// 见 `grades_exclusions.dart`）。
  ///
  /// 2026-10-08 改：从前是写死的四个课名，现在由**本专业实践环节表**推导
  /// （`practiceCourseFilterProvider`），表拿不到时行为与从前逐字不变。
  /// 每帧在 [build] 里用 provider 重新赋值 —— 与 `_retakeScores` 同一套路。
  PracticeCourseFilter _practiceFilter = PracticeCourseFilter.fallback;

  /// 只看名称的便捷视图（老调用方要 `Set<String>`）。
  Set<String> get _excludedCourses => _practiceFilter.names;

  List<Grade> _sortGrades(List<Grade> grades, double avgScore) {
    if (_sortKey == null) return grades;
    final sorted = List<Grade>.from(grades);
    sorted.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'courseCode':
          cmp = a.courseCode.compareTo(b.courseCode);
        case 'courseName':
          cmp = a.courseName.compareTo(b.courseName);
        case 'credit':
          cmp = (double.tryParse(a.credit) ?? 0).compareTo(
            double.tryParse(b.credit) ?? 0,
          );
        case 'category':
          cmp = a.category.compareTo(b.category);
        case 'nature':
          cmp = a.nature.compareTo(b.nature);
        case 'examType':
          cmp = a.examType.compareTo(b.examType);
        case 'score':
          cmp = (double.tryParse(a.score) ?? 0).compareTo(
            double.tryParse(b.score) ?? 0,
          );
        case 'gradePoint':
          cmp = (double.tryParse(a.gradePoint) ?? 0).compareTo(
            double.tryParse(b.gradePoint) ?? 0,
          );
        case 'creditGradePoint':
          cmp = (double.tryParse(a.creditGradePoint) ?? 0).compareTo(
            double.tryParse(b.creditGradePoint) ?? 0,
          );
        case 'contribution':
          final ca =
              ((double.tryParse(a.score) ?? 0) - avgScore) *
              (double.tryParse(a.credit) ?? 0);
          final cb =
              ((double.tryParse(b.score) ?? 0) - avgScore) *
              (double.tryParse(b.credit) ?? 0);
          cmp = ca.compareTo(cb);
        case 'semester':
          cmp = a.semester.compareTo(b.semester);
        default:
          cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    // 排除课程始终排到最后
    if (_sortKey == 'contribution') {
      final excluded = sorted
          .where((g) => _practiceFilter.excludes(code: g.courseCode, name: g.courseName))
          .toList();
      sorted.removeWhere(
        (g) => _practiceFilter.excludes(code: g.courseCode, name: g.courseName),
      );
      sorted.addAll(excluded);
    }
    return sorted;
  }

  void _showChangesSnackBar(BuildContext context, GradesResult result) {
    final added = result.newCourseNames;
    final removed = result.removedCourseNames;
    final messages = <String>[];
    if (added != null) {
      for (final name in added) {
        messages.add('$name 出成绩了');
      }
    }
    if (removed != null) {
      for (final name in removed) {
        messages.add('$name 成绩已撤回');
      }
    }
    if (messages.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(messages.join('；')),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradesViewModelProvider);
    // 实践类课程（不计入加权）—— 每帧刷新，供下面所有统计用。
    _practiceFilter = ref.watch(practiceCourseFilterProvider);
    final gradesAsync = ref.watch(gradesProvider(state.params));
    final importanceMapAsync = ref.watch(curriculumImportanceMapProvider);
    final importanceMap = importanceMapAsync.valueOrNull;
    final rankingAsync = ref.watch(weightedGradeRankingProvider(1));

    // 排名比例的分母总人数：班级/专业取自个人数据中心（数据中心的
    // 「校内关系」人数，随会话实时刷新）；数据中心不可用（未登录 /
    // 会话失效 / 加载中）时回退到固定值。
    //
    // ⚠ 2026-10-01：改看 `dzjPeerCountsProvider`（**只发那 5 条人数查询**）。
    // 从前这里 watch 的是整个 `dataCenterOverviewProvider` —— 意味着
    // **打开成绩页会连带打数据中心首屏那 19 个请求**（学籍 / 学业 / 消费 /
    // 教材 / 图书 / 登录趋势…），只为拿这两个分母。
    final peerCounts =
        ref.watch(dzjPeerCountsProvider).valueOrNull ?? const <String, int>{};
    int totalOf(String key, int fallback) =>
        (peerCounts[key] ?? -1) > 0 ? peerCounts[key]! : fallback;
    final classTotal = totalOf('class', 46);
    final majorTotal = totalOf('major', 199);
    // 年级：分母改用数据中心算出来的**「同年级同学院」人数**
    // （用户 2026-09-20 立项：「把此项的人数，用作成绩页里，第三项排名的基数
    // 取代掉硬编码的 7900」——教务的年级排名本来就是同学院同年级口径，
    // 拿全校 7902 当分母会把比例算小一个数量级）。
    // 取不到（未登录 / 会话失效 / 数据中心不可用）时才回退到那个固定值。
    final gradeTotal =
        ref.watch(dzjGradeCollegeCountProvider).valueOrNull ?? 7902;

    // 监听成绩变更（新增 / 撤回），通过 SnackBar 提示
    ref.listen(gradesProvider(state.params), (prev, next) {
      if (next is AsyncData) {
        final result = next.value;
        if (result == null) return;
        if (result.hasChanges && mounted) {
          final diffHash = Object.hash(
            result.newCourseNames,
            result.removedCourseNames,
          );
          if (_lastShownDiffHash != diffHash) {
            _lastShownDiffHash = diffHash;
            _showChangesSnackBar(context, result);
          }
        }
      }
    });

    // 刷新完成后无变更时显示「无更新」提示
    if (ref.read(refreshRequestedProvider) && !gradesAsync.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(refreshRequestedProvider.notifier).state = false;
        final result = gradesAsync.valueOrNull;
        if (result != null && !result.hasChanges) {
          ref.read(noUpdateSignalProvider.notifier).state++;
        }
      });
    }

    // 首次进入成绩页时自动触发一次后台刷新，
    // 用于检测自上次退出应用后是否有新增/撤回的成绩
    if (!_initialAutoRefreshDone && gradesAsync.hasValue) {
      _initialAutoRefreshDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(refreshRequestedProvider.notifier).state = true;
        ref.invalidate(gradesProvider(state.params));
      });
    }

    double avgScore = 0;
    double recommendationScore = 0;
    double totalCredit = 0;
    double avgGp = 0;
    int courseCount = 0;
    gradesAsync.whenData((result) {
      avgScore = _calcAvgScore(result.grades);
      if (importanceMap != null) {
        recommendationScore = recommendationWeightedOf(
          courses: [
            for (final g in result.grades)
              RecommendationCourse(
                courseCode: g.courseCode,
                courseName: g.courseName,
                score: double.tryParse(g.score) ?? 0,
                credits: double.tryParse(g.credit) ?? 0,
              ),
          ],
          importance: importanceMap,
        ).score;
      }
      final filtered = result.grades
          .where(
            (g) =>
                !_practiceFilter.excludes(code: g.courseCode, name: g.courseName),
          )
          .toList();
      courseCount = filtered.length;
      double tc = 0, tgc = 0;
      for (final g in filtered) {
        final c = double.tryParse(g.credit) ?? 0;
        final rawScore =
            double.tryParse(_retakeScores[g.courseCode] ?? g.score) ?? 0;
        final gp = rawScore >= 60 ? c * (rawScore / 10 - 5) : 0;
        tc += c;
        tgc += gp;
      }
      totalCredit = tc;
      avgGp = tc > 0 ? tgc / tc : 0;
    });

    // 计算汇总差值并显示浮动提示（仅在数据就绪时计算，避免 loading 帧的零值污染）
    if (gradesAsync.hasValue) {
      final currentStats = <String, double>{
        '课程': courseCount.toDouble(),
        '总学分': double.parse(totalCredit.toStringAsFixed(1)),
        '课程加权': double.parse(avgScore.toStringAsFixed(5)),
        'GPA': double.parse(avgGp.toStringAsFixed(2)),
        if (importanceMap != null)
          '推免加权': double.parse(recommendationScore.toStringAsFixed(5)),
      };
      final statsHash = Object.hashAll(
        currentStats.entries.expand((e) => [e.key, e.value]),
      );

      if (_lastStatsHash != null && statsHash != _lastStatsHash) {
        final deltas = <String, double>{};
        for (final e in currentStats.entries) {
          final prev = _prevStats[e.key];
          if (prev != null) {
            final diff = e.value - prev;
            if (diff.abs() > 0.0001) deltas[e.key] = diff;
          }
        }
        if (deltas.isNotEmpty) {
          _deltaValues = deltas;
          _showDeltas = true;
          _prevStats = Map.from(currentStats);
          _lastStatsHash = statsHash;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showDeltas = false);
          });
        }
      } else if (_lastStatsHash == null) {
        _prevStats = Map.from(currentStats);
        _lastStatsHash = statsHash;
      }
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(context),
        _buildTranscriptRow(context),
        gradesAsync.when(
          data: (result) => GradesSummaryCard(
            grades: result.grades,
            avgScore: avgScore,
            recommendationScore: recommendationScore,
            hasImportanceMap: importanceMap != null,
            hasRetake: _retakeScores.isNotEmpty,
            deltas: _showDeltas ? _deltaValues : const {},
            excludedCourses: _excludedCourses,
            retakeScores: _retakeScores,
            showDeltas: _showDeltas,
          ),
          // 刷新期间保持旧数据可见，避免页面闪动
          loading: () => gradesAsync.hasValue
              ? GradesSummaryCard(
                  grades: gradesAsync.value!.grades,
                  avgScore: avgScore,
                  recommendationScore: recommendationScore,
                  hasImportanceMap: importanceMap != null,
                  hasRetake: _retakeScores.isNotEmpty,
                  deltas: _showDeltas ? _deltaValues : const {},
                  excludedCourses: _excludedCourses,
                  retakeScores: _retakeScores,
                  showDeltas: _showDeltas,
                )
              : const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        rankingAsync.when(
          data: (wg) => GradesRankingRow(
            wg: wg,
            classTotal: classTotal,
            majorTotal: majorTotal,
            gradeTotal: gradeTotal,
          ),
          loading: () => GradesRankingRow(
            wg: null,
            classTotal: classTotal,
            majorTotal: majorTotal,
            gradeTotal: gradeTotal,
          ),
          error: (e, _) => GradesRankingRow(
            wg: null,
            classTotal: classTotal,
            majorTotal: majorTotal,
            gradeTotal: gradeTotal,
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildGradeTable(context, avgScore, importanceMap),
          ),
        ),
      ],
    );

    return _wrapWithScaffold(context, content);
  }

  double _calcAvgScore(List<Grade> grades) {
    final filtered = grades
        .where(
          (g) =>
              !_practiceFilter.excludes(code: g.courseCode, name: g.courseName),
        )
        .toList();
    if (filtered.isEmpty) return 0;
    double totalCredit = 0, totalScoreCredit = 0;
    for (final g in filtered) {
      final c = double.tryParse(g.credit) ?? 0;
      final s = double.tryParse(_retakeScores[g.courseCode] ?? g.score) ?? 0;
      totalCredit += c;
      totalScoreCredit += s * c;
    }
    return totalCredit > 0 ? totalScoreCredit / totalCredit : 0;
  }

  /// 弹出重修成绩输入框
  Future<void> _onRetakeTap(Grade g) async {
    final controller = TextEditingController(
      text: _retakeScores[g.courseCode] ?? g.score,
    );
    final focusNode = FocusNode();
    final hasExisting = _retakeScores.containsKey(g.courseCode);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        // 自动选中输入框内容
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        });
        return AlertDialog(
          title: Text(g.courseName, style: const TextStyle(fontSize: 16)),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '重修成绩',
                    hintText: '分数',
                  ),
                  autofocus: true,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      focusNode.requestFocus();
                      final v = double.tryParse(controller.text) ?? 0;
                      controller.text = (v + 1).toStringAsFixed(
                        controller.text.contains('.') ? 1 : 0,
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        controller.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: controller.text.length,
                        );
                      });
                    },
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      size: 20,
                      color: AppColors.textMuted(ctx),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      focusNode.requestFocus();
                      final v = double.tryParse(controller.text) ?? 0;
                      final next = (v - 1).clamp(0, double.infinity);
                      controller.text = next.toStringAsFixed(
                        controller.text.contains('.') ? 1 : 0,
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        controller.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: controller.text.length,
                        );
                      });
                    },
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: AppColors.textMuted(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            if (hasExisting)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: Text(
                  '恢复',
                  style: TextStyle(color: AppColors.critical(ctx)),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty || double.tryParse(text) == null) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(const SnackBar(content: Text('请输入有效的分数')));
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        if (result.isEmpty) {
          _retakeScores.remove(g.courseCode);
        } else {
          _retakeScores[g.courseCode] = result;
        }
      });
    }
  }


  /// 本科生成绩单入口（2026-09-16 加）。
  ///
  /// 小程序「本科生成绩单」= 门户 H5：选报表类型 + 填邮箱 → 教务处把**盖章 PDF 发到
  /// 该邮箱**（没有下载接口，故本页只做申请，文件由用户在邮箱里取）。
  /// 放在筛选栏下方一行：内嵌（侧栏模式）时成绩页不画导航栏，入口必须落在内容里。
  Widget _buildTranscriptRow(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
        child: TextButton.icon(
          key: const Key('grades_transcript_entry'),
          onPressed: () => showTranscriptSheet(context),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: const Icon(Icons.description_outlined, size: 17),
          label: const Text('本科生成绩单'),
        ),
      ),
    );
  }

  Widget _wrapWithScaffold(BuildContext context, Widget child) {
    if (widget.showAppBar) {
      final params = ref.read(gradesViewModelProvider).params;
      final isLoading = ref.watch(gradesProvider(params)).isLoading;
      return Scaffold(
        appBar: AppBar(
          title: const Text('成绩'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: isLoading
                  ? null
                  : () {
                      ref.read(refreshRequestedProvider.notifier).state = true;
                      ref.invalidate(gradesProvider(params));
                    },
            ),
          ],
        ),
        body: child,
      );
    }
    return child;
  }

  Widget _buildFilters(BuildContext context) {
    final vm = ref.watch(gradesViewModelProvider.notifier);
    final state = ref.watch(gradesViewModelProvider);
    final showPicker = state.timeLimit != TimeLimit.sinceEnrollment;

    Widget wrapGroup(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);

    final groups = <Widget>[
      // Group 1: 年份 + 时间范围 + 学期
      wrapGroup([
        if (showPicker)
          AcademicYearPicker(
            startYear: 2018,
            endYear: 2030,
            initialYear: state.academicYear,
            onChanged: vm.setAcademicYear,
            onHoverChanged: (v) => setState(() => _pickerHovered = v),
          ),
        AnimatedOpacity(
          opacity: _pickerHovered ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: wrapGroup([
            const SizedBox(width: 8),
            _dropdown<TimeLimit>(
              context,
              value: state.timeLimit,
              items: TimeLimit.values,
              label: (t) => t.label,
              onChanged: (v) => vm.setTimeLimit(v!),
            ),
            if (state.timeLimit == TimeLimit.semester) ...[
              const SizedBox(width: 8),
              _dropdown<String>(
                context,
                value: state.semesterXq,
                items: const ['0', '1', '2'],
                label: (s) => s == '0'
                    ? '第一学期'
                    : s == '1'
                    ? '第二学期'
                    : '第二阶段',
                onChanged: (v) => vm.setSemesterXq(v!),
              ),
            ],
          ]),
        ),
      ]),
      // Group 2: 主修 辅修 微专
      wrapGroup([
        _toggle(
          context,
          '主修',
          state.selectMajor,
          () => vm.toggleCategory('major'),
        ),
        const SizedBox(width: 8),
        _toggle(
          context,
          '辅修',
          state.selectMinor,
          () => vm.toggleCategory('minor'),
        ),
        const SizedBox(width: 8),
        _toggle(
          context,
          '微专',
          state.selectWeiZhuan,
          () => vm.toggleCategory('weizhuan'),
        ),
      ]),
      // Group 3: 仅未通过 + 有效成绩 + 刷新
      wrapGroup([
        _toggle(context, '仅未通过', state.onlyNotPassed, vm.toggleOnlyNotPassed),
        const SizedBox(width: 8),
        _toggle(
          context,
          state.showRawGrade ? '原始成绩' : '有效成绩',
          !state.showRawGrade,
          vm.toggleShowRawGrade,
        ),
      ]),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w >= 720) {
            // 一行的空间：三组并排，悬浮年份时同行组件隐藏
            Widget opaque(Widget child) => AnimatedOpacity(
              opacity: _pickerHovered ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: child,
            );
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [groups[0], opaque(groups[1]), opaque(groups[2])],
            );
          } else if (w >= 450) {
            // 两行的空间：第一组独占一行，二、三组同行
            return Column(
              children: [
                Center(child: groups[0]),
                const SizedBox(height: 4),
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [groups[1], groups[2]],
                  ),
                ),
              ],
            );
          } else {
            // 三行：每组独占一行
            return Column(
              children: [
                for (int i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Center(child: groups[i]),
                ],
              ],
            );
          }
        },
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: items
            .map((t) => DropdownMenuItem(value: t, child: Text(label(t))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _toggle(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap, {
    Color? activeColor,
  }) {
    final color = active
        ? (activeColor ?? AppColors.errorFill(context))
        : Theme.of(context).colorScheme.surface;
    final fg = active
        ? AppColors.onErrorFill(context)
        : Theme.of(context).colorScheme.onSurface;
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      backgroundColor: color,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildGradeTable(
    BuildContext context,
    double avgScore,
    Map<String, CourseImportance>? importanceMap,
  ) {
    final state = ref.watch(gradesViewModelProvider);
    final resultAsync = ref.watch(gradesProvider(state.params));

    return resultAsync.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        error: e,
        retryIcon: false,
        onRetry: () {
          ref.read(refreshRequestedProvider.notifier).state = true;
          ref.invalidate(gradesProvider(state.params));
        },
      ),
      data: (result) => result.grades.isEmpty
          ? const AppEmptyState(message: '暂无成绩数据')
          : GradesTable(
              grades: _sortGrades(result.grades, avgScore),
              showSemester: state.timeLimit != TimeLimit.semester,
              avgScore: avgScore,
              importanceMap: importanceMap,
              sortKey: _sortKey,
              sortAsc: _sortAsc,
              onSort: (key) => setState(() {
                if (_sortKey == key) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sortKey = key;
                  _sortAsc = true;
                }
              }),
            
              excludedCourses: _excludedCourses,
              retakeScores: _retakeScores,
              onRetakeTap: _onRetakeTap,
          ),
    );
  }


}


final gradesProvider = FutureProvider.family<GradesResult, GradesQueryParams>((
  ref,
  params,
) async {
  final repo = await ref.watch(gradesRepositoryProvider.future);
  // ref.read（非 ref.watch）：不建立依赖关系。
  // refreshRequested 重置为 false 时不会触发 provider 重新执行，
  // 避免缓存数据覆盖刚拉取的含 diff 的新数据。
  final forceRefresh = ref.read(refreshRequestedProvider);
  final result = await repo.getGrades(params, forceRefresh: forceRefresh);
  return result.fold(
    (failure) => throw ImsApiException(failure.message ?? '获取成绩失败'),
    (gradesResult) => gradesResult,
  );
});

/// 递增以通知标题栏显示「无更新」提示。
final noUpdateSignalProvider = StateProvider<int>((ref) => 0);

/// 标记用户主动请求刷新（用于判断是否显示「无更新」）。
final refreshRequestedProvider = StateProvider<bool>((ref) => false);
