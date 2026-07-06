import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';

/// 从学籍信息和培养方案中提取每门课程的「课程地位」（主干/非主干）。
final _curriculumImportanceMapProvider =
    FutureProvider<Map<String, CourseImportance>?>((ref) async {
      final studentInfoRepo = await ref.watch(
        studentInfoRepositoryProvider.future,
      );
      StudentInfo? info;
      studentInfoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      if (info == null) return null;
      final si = info!;

      final year = int.tryParse(si.enrollYear);
      if (year == null) return null;

      final collegeRepo = await ref.watch(collegeRepositoryProvider.future);
      College? matchedCollege;
      final collegesResult = await collegeRepo.getAllCollege();
      collegesResult.fold((_) {}, (colleges) {
        for (final c in colleges) {
          if (c.name == si.college) {
            matchedCollege = c;
            break;
          }
        }
      });
      if (matchedCollege == null) return null;
      final mc = matchedCollege!;

      final majorRepo = await ref.watch(majorRepositoryProvider.future);
      Major? matchedMajor;
      final majorsResult = await majorRepo.getAllMajorIn(mc, year: year);
      majorsResult.fold((_) {}, (majors) {
        for (final m in majors) {
          if (m.name == si.major) {
            matchedMajor = m;
            break;
          }
        }
      });
      if (matchedMajor == null) return null;
      final mm = matchedMajor!;

      final curriculumRepo = await ref.watch(
        curriculumRepositoryProvider.future,
      );
      final curriculumResult = await curriculumRepo.getCurriculumIn(
        year,
        mc,
        mm,
      );
      final map = <String, CourseImportance>{};
      curriculumResult.fold((_) {}, (curriculum) {
        for (final course in curriculum.courses) {
          map[course.code] = course.importance;
        }
      });
      return map;
    });

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

  static const _excludedCourses = <String>{'军事训练', '创新创业实践活动', '毕业设计', '毕业论文'};

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
          .where((g) => _excludedCourses.contains(g.courseName))
          .toList();
      sorted.removeWhere((g) => _excludedCourses.contains(g.courseName));
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
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '知道了', onPressed: () {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradesViewModelProvider);
    final gradesAsync = ref.watch(gradesProvider(state.params));
    final importanceMapAsync = ref.watch(_curriculumImportanceMapProvider);
    final importanceMap = importanceMapAsync.valueOrNull;
    final rankingAsync = ref.watch(weightedGradeRankingProvider(1));

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

    double avgScore = 0;
    double recommendationScore = 0;
    gradesAsync.whenData((result) {
      avgScore = _calcAvgScore(result.grades);
      if (importanceMap != null) {
        recommendationScore = _calcRecommendationScore(
          result.grades,
          importanceMap,
        );
      }
    });

    return _wrapWithScaffold(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilters(context),
          gradesAsync.when(
            data: (result) => _buildSummary(
              context,
              result.grades,
              avgScore,
              recommendationScore,
              importanceMap != null,
              _retakeScores.isNotEmpty,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _2) => const SizedBox.shrink(),
          ),
          rankingAsync.when(
            data: (wg) => _buildRankingRow(context, wg),
            loading: () => _buildRankingRow(context, null),
            error: (e, _) => _buildRankingRow(context, null),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildGradeTable(context, avgScore, importanceMap),
            ),
          ),
        ],
      ),
    );
  }

  double _calcAvgScore(List<Grade> grades) {
    final filtered = grades
        .where((g) => !_excludedCourses.contains(g.courseName))
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

  double _calcRecommendationScore(
    List<Grade> grades,
    Map<String, CourseImportance> importanceMap,
  ) {
    final filtered = grades
        .where((g) => !_excludedCourses.contains(g.courseName))
        .toList();
    double coreCredit = 0, coreScoreCredit = 0;
    double nonCoreCredit = 0, nonCoreScoreCredit = 0;
    for (final g in filtered) {
      final c = double.tryParse(g.credit) ?? 0;
      final s = double.tryParse(g.score) ?? 0;
      final importance = importanceMap[g.courseCode];
      if (importance == CourseImportance.core) {
        coreCredit += c;
        coreScoreCredit += s * c;
      } else {
        nonCoreCredit += c;
        nonCoreScoreCredit += s * c;
      }
    }
    final coreAvg = coreCredit > 0 ? coreScoreCredit / coreCredit : 0;
    final nonCoreAvg = nonCoreCredit > 0
        ? nonCoreScoreCredit / nonCoreCredit
        : 0;
    return coreAvg * 0.7 + nonCoreAvg * 0.3;
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
                    child: const Icon(
                      Icons.keyboard_arrow_up,
                      size: 20,
                      color: Colors.grey,
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
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.grey,
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
                child: const Text('恢复', style: TextStyle(color: Colors.red)),
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

  Widget _buildSummary(
    BuildContext context,
    List<Grade> grades,
    double avgScore,
    double recommendationScore,
    bool hasImportanceMap,
    bool hasRetake,
  ) {
    if (grades.isEmpty) return const SizedBox.shrink();
    final filtered = grades
        .where((g) => !_excludedCourses.contains(g.courseName))
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    double totalCredit = 0, totalGpCredit = 0;
    for (final g in filtered) {
      final c = double.tryParse(g.credit) ?? 0;
      final rawScore =
          double.tryParse(_retakeScores[g.courseCode] ?? g.score) ?? 0;
      final gp = rawScore >= 60
          ? (double.tryParse(g.credit) ?? 0) * (rawScore / 10 - 5)
          : 0;
      totalCredit += c;
      totalGpCredit += gp;
    }
    final avgGp = totalCredit > 0 ? totalGpCredit / totalCredit : 0;

    Widget _statCard(String label, String value, {bool dashed = false}) {
      final borderColor = Theme.of(
        context,
      ).colorScheme.error.withValues(alpha: 0.7);
      final dotIndex = value.indexOf('.');
      final baseStyle = TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.error,
      );
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: dashed ? null : Border.all(color: borderColor),
        ),
        foregroundDecoration: dashed
            ? DashedBorderDecoration(
                color: borderColor,
                strokeWidth: 1.5,
                radius: 12,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  text: dotIndex == -1 ? value : value.substring(0, dotIndex),
                  style: baseStyle,
                  children: dotIndex == -1
                      ? null
                      : [
                          TextSpan(
                            text: value.substring(dotIndex),
                            style: baseStyle.copyWith(fontSize: 11),
                          ),
                        ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cardData = <(String, String, bool)>[
      ('课程', '${filtered.length}', false),
      ('总学分', totalCredit.toStringAsFixed(1), false),
      ('课程加权', avgScore.toStringAsFixed(5), hasRetake),
      ('加权绩点', avgGp.toStringAsFixed(2), hasRetake),
    ];
    if (hasImportanceMap) {
      cardData.add(('推免加权', recommendationScore.toStringAsFixed(5), false));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          // 用 TextPainter 估算每张卡的内容宽度
          final painter = TextPainter(textDirection: TextDirection.ltr);
          double intrinsicSum = 0;
          final widths = <double>[];
          for (final d in cardData) {
            double maxW = 0;
            for (final text in [d.$2, d.$1]) {
              final isValue = text == d.$2;
              painter
                ..text = TextSpan(
                  text: text,
                  style: TextStyle(
                    fontSize: isValue ? 15 : 11,
                    fontWeight: isValue ? FontWeight.bold : FontWeight.normal,
                  ),
                )
                ..layout();
              if (painter.width > maxW) maxW = painter.width;
            }
            final w = maxW + 32;
            widths.add(w);
            intrinsicSum += w;
          }
          final extra = (totalWidth - intrinsicSum) / cardData.length;
          final extraPerCard = extra > 0 ? extra : 0.0;

          return Row(
            children: [
              for (int i = 0; i < cardData.length; i++) ...[
                SizedBox(
                  width: widths[i] + extraPerCard,
                  child: _statCard(
                    cardData[i].$1,
                    cardData[i].$2,
                    dashed: cardData[i].$3,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRankingRow(BuildContext context, WeightedGrade? wg) {
    const classTotal = 46;
    const majorTotal = 199;
    const gradeTotal = 7902;
    final isLoading = wg == null;

    final classRank = wg?.classRank ?? 0;
    final majorRank = wg?.majorRank ?? 0;
    final gradeRank = wg?.gradeRank ?? 0;

    Widget _wideCard(int rank, int total) {
      final ratio = rank / total;
      return Expanded(
        child: Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ $total',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(ratio * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: isLoading ? 0 : ratio.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _narrowRow(int rank, int total, double rankWidth, double pctWidth) {
      final ratio = rank / total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: rankWidth,
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      children: [
                        Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ $total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: isLoading ? 0 : ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: pctWidth,
              child: Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 400) {
            // 计算最宽行的排名和百分比宽度，使进度条对齐
            final tp = TextPainter(textDirection: TextDirection.ltr);
            double maxRankW = 0, maxPctW = 0;
            for (final (r, t) in [
              (classRank, classTotal),
              (majorRank, majorTotal),
              (gradeRank, gradeTotal),
            ]) {
              // 排名用20px bold + 4px间距 + "/ total"用12px
              tp.text = TextSpan(
                text: '$r',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              );
              tp.layout();
              double w = tp.width + 4;
              tp.text = TextSpan(
                text: '/ $t',
                style: const TextStyle(fontSize: 12),
              );
              tp.layout();
              w += tp.width;
              if (w > maxRankW) maxRankW = w;
              tp.text = TextSpan(
                text: '${(r / t * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11),
              );
              tp.layout();
              if (tp.width > maxPctW) maxPctW = tp.width;
            }
            maxRankW += 18;
            maxPctW += 8;

            return Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    _narrowRow(classRank, classTotal, maxRankW, maxPctW),
                    _narrowRow(majorRank, majorTotal, maxRankW, maxPctW),
                    _narrowRow(gradeRank, gradeTotal, maxRankW, maxPctW),
                  ],
                ),
              ),
            );
          }
          return Row(
            children: [
              _wideCard(classRank, classTotal),
              _wideCard(majorRank, majorTotal),
              _wideCard(gradeRank, gradeTotal),
            ],
          );
        },
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

    Widget _wrapGroup(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);

    final groups = <Widget>[
      // Group 1: 年份 + 时间范围 + 学期
      _wrapGroup([
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
          child: _wrapGroup([
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
      _wrapGroup([
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
      _wrapGroup([
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
            Widget _opaque(Widget child) => AnimatedOpacity(
              opacity: _pickerHovered ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: child,
            );
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [groups[0], _opaque(groups[1]), _opaque(groups[2])],
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
        ? (activeColor ?? Theme.of(context).colorScheme.error)
        : Theme.of(context).colorScheme.surface;
    final fg = active
        ? Theme.of(context).colorScheme.onError
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$e', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(refreshRequestedProvider.notifier).state = true;
                ref.invalidate(gradesProvider(state.params));
              },
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (result) => result.grades.isEmpty
          ? const Center(child: Text('暂无成绩数据'))
          : _buildGradeTableWidget(
              context,
              _sortGrades(result.grades, avgScore),
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
            ),
    );
  }

  Widget _buildGradeTableWidget(
    BuildContext context,
    List<Grade> grades, {
    required bool showSemester,
    required double avgScore,
    required Map<String, CourseImportance>? importanceMap,
    required String? sortKey,
    required bool sortAsc,
    required ValueChanged<String> onSort,
  }) {
    final theme = Theme.of(context);

    List<String> buildHeaders(bool isNarrow) {
      final h = isNarrow
          ? <String>['课程名称', '学分', '分数', '贡献']
          : <String>[
              '课程代码',
              '课程名称',
              '学分',
              '类别',
              '性质',
              '考核',
              '成绩',
              '绩点',
              '学分绩点',
              '贡献',
            ];
      if (showSemester && !isNarrow) h.add('学期');
      return h;
    }

    List<String> buildSortKeys(bool isNarrow) {
      final keys = isNarrow
          ? <String>['courseName', 'credit', 'score', 'contribution']
          : <String>[
              'courseCode',
              'courseName',
              'credit',
              'category',
              'nature',
              'examType',
              'score',
              'gradePoint',
              'creditGradePoint',
              'contribution',
            ];
      if (showSemester && !isNarrow) keys.add('semester');
      return keys;
    }

    Map<int, double> _computeIntrinsicWidths(bool isNarrow) {
      final headers = buildHeaders(isNarrow);
      final painter = TextPainter(textDirection: TextDirection.ltr);
      final w = <int, double>{};

      // 用表头文字估算
      for (int i = 0; i < headers.length; i++) {
        painter
          ..text = TextSpan(
            text: headers[i],
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          )
          ..layout();
        w[i] = painter.width + 28; // padding + margin
      }

      // 抽几个数据行做抽样，取更大者
      if (!isNarrow) {
        final fieldGetters = showSemester
            ? <String Function(Grade)>[
                (g) => g.courseCode,
                (g) => g.courseName,
                (g) => g.credit,
                (g) => g.category,
                (g) => g.nature,
                (g) => g.examType,
                (g) => g.score,
                (g) => g.gradePoint,
                (g) => g.creditGradePoint,
                (g) => '', // 贡献
                (g) => g.semester,
              ]
            : <String Function(Grade)>[
                (g) => g.courseCode,
                (g) => g.courseName,
                (g) => g.credit,
                (g) => g.category,
                (g) => g.nature,
                (g) => g.examType,
                (g) => g.score,
                (g) => g.gradePoint,
                (g) => g.creditGradePoint,
                (g) => '',
              ];

        final sample = grades.length > 5 ? grades.sublist(0, 5) : grades;
        for (int i = 0; i < headers.length; i++) {
          double maxCell = 0;
          for (final g in sample) {
            final text = fieldGetters[i](g);
            painter
              ..text = TextSpan(
                text: text,
                style: const TextStyle(fontSize: 12),
              )
              ..layout();
            if (painter.width > maxCell) maxCell = painter.width;
          }
          final cellW = maxCell + 28;
          if (cellW > w[i]!) w[i] = cellW;
        }
      }

      return w;
    }

    List<Widget> buildHeaderCells(bool isNarrow) {
      final headers = buildHeaders(isNarrow);
      final keys = buildSortKeys(isNarrow);
      return List.generate(headers.length, (i) {
        final active = sortKey == keys[i];
        return GestureDetector(
          onTap: () => onSort(keys[i]),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(right: active ? 14 : 0),
                child: Text(
                  headers[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.bold,
                    fontSize: active ? 11 : 13,
                  ),
                ),
              ),
              if (active)
                Positioned(
                  right: 0,
                  child: Icon(
                    sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: theme.colorScheme.onError,
                  ),
                ),
            ],
          ),
        );
      });
    }

    List<List<Widget>> buildDataRows(bool isNarrow) {
      return grades.map((g) {
        final isExcluded = _excludedCourses.contains(g.courseName);
        final hasRetake = _retakeScores.containsKey(g.courseCode);
        final displayScore = hasRetake ? _retakeScores[g.courseCode]! : g.score;
        final s = double.tryParse(displayScore) ?? 0;
        final c = double.tryParse(g.credit) ?? 0;
        final contrib = (s - avgScore) * c;
        final contribWidget = Text(
          isExcluded ? '' : contrib.toStringAsFixed(1),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: !isExcluded && contrib < 0 ? Colors.red : null,
          ),
        );

        final scoreWidget = GestureDetector(
          onTap: () => _onRetakeTap(g),
          child: Text.rich(
            TextSpan(
              text: displayScore,
              children: [
                if (hasRetake)
                  const TextSpan(
                    text: '*',
                    style: TextStyle(color: Color(0xFF800000)),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        );

        final cells = isNarrow
            ? <Widget>[
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                scoreWidget,
                contribWidget,
              ]
            : <Widget>[
                Text(g.courseCode, style: const TextStyle(fontSize: 11)),
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                Text(g.category, style: const TextStyle(fontSize: 11)),
                Text(
                  hasRetake ? '重修' : g.nature,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasRetake ? const Color(0xFF800000) : null,
                  ),
                ),
                Text(g.examType, textAlign: TextAlign.center),
                scoreWidget,
                Text(g.gradePoint, textAlign: TextAlign.center),
                Text(g.creditGradePoint, textAlign: TextAlign.center),
                contribWidget,
              ];
        if (showSemester && !isNarrow) {
          cells.add(Text(g.semester, textAlign: TextAlign.center));
        }
        return cells;
      }).toList();
    }

    final rowBackgrounds = importanceMap != null
        ? grades
              .map(
                (g) => importanceMap[g.courseCode] == CourseImportance.core
                    ? Colors.red.shade50
                    : null,
              )
              .toList()
        : null;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            final headers = buildHeaders(isNarrow);
            final nCols = headers.length;

            // ── 宽度算法：固有宽度 + d ──
            final intrinsicWidths = _computeIntrinsicWidths(isNarrow);
            double intrinsicSum = 0;
            for (int i = 0; i < nCols; i++) {
              intrinsicSum += intrinsicWidths[i]!;
            }
            final extraPerCol = (constraints.maxWidth - intrinsicSum) / nCols;
            final colWidths = <int, TableColumnWidth>{};
            for (int i = 0; i < nCols; i++) {
              colWidths[i] = FixedColumnWidth(
                intrinsicWidths[i]! + (extraPerCol > 0 ? extraPerCol : 0),
              );
            }

            return _StickyHeaderTable(
              headerCells: buildHeaderCells(isNarrow),
              dataRows: buildDataRows(isNarrow),
              headerBgColor: theme.colorScheme.error,
              columnWidths: colWidths,
              rowBackgrounds: rowBackgrounds,
              availableWidth: constraints.maxWidth,
              availableHeight: constraints.maxHeight,
            );
          },
        ),
      ),
    );
  }
}

/// 固定表头表格：表头始终可见，内容区可垂直滚动，横向滚动同步。
class _StickyHeaderTable extends StatefulWidget {
  final List<Widget> headerCells;
  final List<List<Widget>> dataRows;
  final Color headerBgColor;
  final Map<int, TableColumnWidth> columnWidths;
  final List<Color?>? rowBackgrounds;
  final double availableWidth;
  final double availableHeight;

  const _StickyHeaderTable({
    required this.headerCells,
    required this.dataRows,
    required this.headerBgColor,
    required this.columnWidths,
    this.rowBackgrounds,
    required this.availableWidth,
    required this.availableHeight,
  });

  @override
  State<_StickyHeaderTable> createState() => _StickyHeaderTableState();
}

class _StickyHeaderTableState extends State<_StickyHeaderTable> {
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  bool _syncing = false;

  static const _headerHt = 50.0;
  static const _rowHt = 40.0;

  double get _intrinsicBodyHeight => widget.dataRows.length * _rowHt;

  @override
  void initState() {
    super.initState();
    _headerH.addListener(_syncHeaderToBody);
    _bodyH.addListener(_syncBodyToHeader);
  }

  void _syncHeaderToBody() {
    if (_syncing) return;
    _syncing = true;
    if (_bodyH.hasClients && _bodyH.offset != _headerH.offset) {
      _bodyH.jumpTo(_headerH.offset);
    }
    _syncing = false;
  }

  void _syncBodyToHeader() {
    if (_syncing) return;
    _syncing = true;
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(_bodyH.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(
      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
      width: 0.5,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 固定表头（带悬浮阴影）
        Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: widget.headerBgColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _headerH,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: widget.availableWidth),
              child: Table(
                columnWidths: widget.columnWidths,
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: widget.headerCells
                        .map(
                          (cell) => TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              child: cell,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ), // ConstrainedBox (header)
          ),
        ),
        // 表体：min(固有高度, 可用高度 - 表头高度)
        LayoutBuilder(
          builder: (context, constraints) {
            final maxH = widget.availableHeight - _headerHt;
            final bodyH = _intrinsicBodyHeight < maxH
                ? _intrinsicBodyHeight
                : maxH;
            return SizedBox(
              height: bodyH,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _bodyH,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: widget.availableWidth,
                    ),
                    child: Table(
                      columnWidths: widget.columnWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(horizontalInside: borderSide),
                      children: [
                        for (int i = 0; i < widget.dataRows.length; i++)
                          TableRow(
                            decoration:
                                widget.rowBackgrounds != null &&
                                    widget.rowBackgrounds![i] != null
                                ? BoxDecoration(
                                    color: widget.rowBackgrounds![i],
                                  )
                                : i.isOdd
                                ? BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                  )
                                : null,
                            children: widget.dataRows[i]
                                .map(
                                  (cell) => TableCell(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      child: cell,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 虚线边框 Decoration，用于 Container.foregroundDecoration。
class DashedBorderDecoration extends Decoration {
  final Color color;
  final double strokeWidth;
  final double radius;

  const DashedBorderDecoration({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _DashedBoxPainter(color, strokeWidth, radius, onChanged);
  }
}

class _DashedBoxPainter extends BoxPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  _DashedBoxPainter(this.color, this.strokeWidth, this.radius, super.onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final rect = offset & cfg.size!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }
}

final gradesProvider = FutureProvider.family<GradesResult, GradesQueryParams>((
  ref,
  params,
) async {
  final repo = await ref.watch(gradesRepositoryProvider.future);
  final result = await repo.getGrades(
    params,
    forceRefresh: true,
  ); // [DEBUG] 测试完恢复为 getGrades(params)
  return result.fold(
    (failure) => throw Exception(failure.message ?? '获取成绩失败'),
    (gradesResult) => gradesResult,
  );
});

/// 递增以通知标题栏显示「无更新」提示。
final noUpdateSignalProvider = StateProvider<int>((ref) => 0);

/// 标记用户主动请求刷新（用于判断是否显示「无更新」）。
final refreshRequestedProvider = StateProvider<bool>((ref) => false);
