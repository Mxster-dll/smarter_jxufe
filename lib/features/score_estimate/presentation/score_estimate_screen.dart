/// 分数估计 · 课程列表页（功能宫格入口）。
///
/// 多课程本地管理：每门课配置平时/期末占比与平时分项计数，
/// 点入详情页实时估算、反推与预警。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/dio_providers.dart';
import '../../../design/feature_palette.dart';
import '../../ims/schedule/data/providers/schedule_repository_provider.dart';
import '../../ims/schedule/domain/schedule_entry.dart';
import '../../school_calendar/data/providers/wxcal_providers.dart';
import '../../school_calendar/domain/school_term.dart';
import '../data/ge_curriculum.dart';
import '../data/ge_deadline_reminders.dart';
import '../data/ge_memo_providers.dart';
import '../data/ge_prior_grades.dart';
import '../data/ge_providers.dart';
import '../data/ge_store.dart';
import '../data/ge_summary.dart';
import '../domain/ge_engine.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';
import 'ge_dialogs.dart';
import 'ge_memo_card.dart';
import 'ge_ratio_bar.dart';
import 'course_detail_screen.dart';
import 'ge_summary_card.dart';

const _uuid = Uuid();

/// 单门课在「总加权平均」里的口径。
enum _ScoreKind {
  /// 教务已出成绩：以真实成绩计入。
  grades,

  /// 本模块估计：已填期末 → 以估计总评计入。
  estimate,

  /// 暂不计入：未填期末（或学分为 0）。
  pending,
}

/// 列表卡片右侧要显示的分数与贡献。
class _CourseScore {
  final _ScoreKind kind;

  /// 展示分数（[pending] 时为平时折算分，非总评）。
  final double score;

  /// 对总加权平均的贡献（百分点）；[pending] 恒为 0。
  final double contribution;

  /// 未计入原因（[pending] 专用）。
  final String pendingReason;

  /// 参与加权（或将要参与）的学分。
  final double credits;

  /// 学分来源标签：'培养方案' / '教务成绩' / '课程录入'。
  final String creditsSource;

  const _CourseScore({
    required this.kind,
    required this.score,
    this.contribution = 0,
    this.pendingReason = '',
    this.credits = 0,
    this.creditsSource = '',
  });
}

class ScoreEstimateScreen extends ConsumerStatefulWidget {
  const ScoreEstimateScreen({super.key});

  @override
  ConsumerState<ScoreEstimateScreen> createState() =>
      _ScoreEstimateScreenState();
}

class _ScoreEstimateScreenState extends ConsumerState<ScoreEstimateScreen> {
  static const _accent = FeaturePalette.cardAccent;

  GeStore? _store;
  List<GeCourse> _courses = const [];

  /// 教务成绩缓存中的已出成绩（离线可读，用于合计总加权平均）。
  List<GePriorGrade> _prior = const [];

  /// 本专业培养方案的学分索引（加权用学分优先取这里）。
  GeCurriculumIndex _curriculum = const GeCurriculumIndex.empty();
  bool _loading = true;
  String? _error;
  bool _importing = false;

  /// 「按培养方案补齐学分」进行中（避免重复点击）。
  bool _creditsSyncing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final store = await ref.read(geStoreProvider.future);
      final courses = await store.loadCourses();
      final prior = await ref.read(gePriorGradesProvider.future);
      final curriculum = await ref.read(geCurriculumIndexProvider.future);
      if (!mounted) return;
      setState(() {
        _store = store;
        _courses = courses;
        _prior = prior;
        _curriculum = curriculum;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '存储初始化失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    final store = _store;
    if (store == null) return;
    final courses = await store.loadCourses();
    // 成绩页可能刚刷新过缓存 → 作废 provider 缓存后重读。
    ref.invalidate(gePriorGradesProvider);
    final prior = await ref.read(gePriorGradesProvider.future);
    if (!mounted) return;
    setState(() {
      _courses = courses;
      _prior = prior;
    });
  }

  /// 教务已出成绩：课程名 → 记录（同名课程以真实成绩为准，不重复计估计分）。
  Map<String, GePriorGrade> _priorByName() => {
    for (final p in _prior) p.courseName.trim(): p,
  };

  /// 卡片展示口径（分数 + 对总平均的贡献 + 参与加权的学分及其来源）。
  _CourseScore _scoreOf(
    GeCourse c,
    Map<String, GePriorGrade> prior,
    GeWeightedSummary summary,
  ) {
    final p = prior[c.name.trim()];
    if (p != null) {
      final item = GeWeightItem(
        name: c.name,
        score: p.score,
        credits: p.credits,
        fromGrades: true,
      );
      return _CourseScore(
        kind: _ScoreKind.grades,
        score: p.score,
        contribution: summary.contribution(item),
        credits: p.credits,
        creditsSource: '教务成绩',
      );
    }
    // 估计侧学分：本专业培养方案优先，未匹配则用课程录入的学分。
    final eff = geEffectiveCredits(_curriculum, c);
    final total = geTotalWithFinal(geCalc(c), c.finalScore);
    if (total != null && eff.credits > 0) {
      final item = GeWeightItem(
        name: c.name,
        score: total,
        credits: eff.credits,
      );
      return _CourseScore(
        kind: _ScoreKind.estimate,
        score: total,
        contribution: summary.contribution(item),
        credits: eff.credits,
        creditsSource: eff.fromCurriculum ? '培养方案' : '课程录入',
      );
    }
    return _CourseScore(
      kind: _ScoreKind.pending,
      score: geCalc(c).dailyContrib,
      pendingReason: eff.credits <= 0 ? '学分为 0' : '未填期末',
      credits: eff.credits,
      creditsSource: eff.fromCurriculum ? '培养方案' : '课程录入',
    );
  }

  /// 列表视图：顶部总加权平均汇总卡 + 逐课卡片（含当前分数与逐课贡献）。
  ///
  /// 总加权平均 = 成绩页全部已出成绩课程（按成绩页口径排除名单过滤）
  /// + 本模块已填期末的估计课程；同名课程以教务真实成绩计入，不重复。
  Widget _buildList(BuildContext context) {
    final prior = _priorByName();
    final scores = <String, _CourseScore>{};
    // 加权平均参与项 = 教务已出成绩（全量，排除名单已在读取层过滤）
    // + 本模块估计（同名课程由真实成绩计入，不重复；未填期末不计入）。
    // 估计侧学分用「培养方案优先」的有效学分（geEffectiveCredits）。
    final data = geSummarize(
      prior: _prior,
      courses: _courses,
      index: _curriculum,
    );
    final summary = data.summary;
    for (final c in _courses) {
      scores[c.id] = _scoreOf(c, prior, summary);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      children: [
        GeWeightedSummaryCard(
          summary: summary,
          pendingCount: data.pendingCount,
          planMajorName: _curriculum.majorName,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _courses.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _CourseCard(
            course: _courses[i],
            score: scores[_courses[i].id]!,
            onTap: () => _openDetail(_courses[i]),
            onDelete: () => _deleteCourse(_courses[i]),
          ),
        ],
      ],
    );
  }

  // ---- 新建课程：弹窗填名称与占比 → 落库 → 进入详情配置分项 ----
  Future<void> _addCourse() async {
    final draft = await showGeCourseDialog(
      context,
      title: '添加课程',
      initialName: '',
      initialDailyPercent: 30,
      initialCredits: 1,
    );
    if (draft == null || !mounted) return;
    final course = GeCourse(
      id: _uuid.v4(),
      name: draft.name,
      dailyPercent: draft.dailyPercent,
      credits: draft.credits,
      note: draft.note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final store = _store;
    if (store == null) return;
    await store.saveCourses([..._courses, course]);
    await _reload();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          course: course,
          planCredits: _curriculum.creditsOf(name: course.name),
        ),
      ),
    );
    await _reload();
  }

  Future<void> _deleteCourse(GeCourse c) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除课程',
      message: '「${c.name}」及其全部平时分项与进度将被删除，无法恢复。',
    );
    if (!ok || !mounted) return;
    final store = _store;
    if (store == null) return;
    await store.saveCourses([
      for (final x in _courses)
        if (x.id != c.id) x,
    ]);
    // 备忘录图片躺在私有目录里，不随课程记录一起消失 → 主动清掉。
    await _removeMemoFiles(c);
    // 截止提醒的排期也要立刻对齐（否则被删课程的提醒到点还会响）。
    await syncGeDeadlineReminders(
      courses: [
        for (final x in _courses)
          if (x.id != c.id) x,
      ],
    );
    await _reload();
  }

  /// 删除课程时清掉它的备忘录图片（失败不影响「课程已删除」这一事实）。
  Future<void> _removeMemoFiles(GeCourse c) async {
    if (c.memo.imageCount == 0) return;
    try {
      final memoStore = await ref.read(geMemoStoreProvider.future);
      await memoStore.removeAllOfCourse(ref.read(currentAccountProvider), c.id);
    } catch (e) {
      debugPrint('[score_estimate] 清理备忘录图片失败：$e');
    }
  }

  Future<void> _openDetail(GeCourse c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          course: c,
          planCredits: _curriculum.creditsOf(code: c.courseCode, name: c.name),
        ),
      ),
    );
    await _reload();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 按本专业培养方案补齐课程学分（先预览再写库，不静默改数据）。
  ///
  /// 学分的权威来源是培养方案：课表带来的学分可能缺失或与方案不一致
  /// （同名课在不同专业学分不同），这里把匹配到的课程学分写成本专业口径，
  /// 并列出未匹配的课程（如慕课/任选课）保留原学分。
  Future<void> _syncCreditsFromPlan() async {
    if (_creditsSyncing) return;
    setState(() => _creditsSyncing = true);
    try {
      // 强制重取：可能刚登录教务、或学籍/培养方案缓存刚就绪。
      ref.invalidate(geCurriculumIndexProvider);
      final index = await ref.read(geCurriculumIndexProvider.future);
      if (!mounted) return;
      if (index.isEmpty) {
        _snack('未能读取本专业培养方案（需先在「教务」页登录并同步过学籍/培养方案），暂无法补齐学分。');
        return;
      }
      setState(() => _curriculum = index);

      final changes = <({GeCourse course, double next})>[];
      final unmatched = <String>[];
      for (final c in _courses) {
        final plan = index.creditsOf(code: c.courseCode, name: c.name);
        if (plan == null || plan <= 0) {
          unmatched.add(c.name);
          continue;
        }
        if ((plan - c.credits).abs() > 1e-9) {
          changes.add((course: c, next: plan));
        }
      }
      if (changes.isEmpty) {
        _snack(
          '全部课程的学分已与培养方案一致'
          '${unmatched.isEmpty ? '。' : '（另有 ${unmatched.length} 门未在方案中匹配到，保留原学分）。'}',
        );
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _CreditSyncDialog(
          majorName: index.majorName,
          changes: changes,
          unmatched: unmatched,
        ),
      );
      if (ok != true || !mounted) return;
      final store = _store;
      if (store == null) return;
      final next = <GeCourse>[
        for (final c in _courses)
          if (changes.any((x) => x.course.id == c.id))
            c.copyWith(
              credits: changes.firstWhere((x) => x.course.id == c.id).next,
            )
          else
            c,
      ];
      await store.saveCourses(next);
      await _reload();
      _snack(
        '已按培养方案更新 ${changes.length} 门课程的学分'
        '${unmatched.isEmpty ? '。' : '，另有 ${unmatched.length} 门未匹配保留原学分。'}',
      );
    } catch (e) {
      _snack('培养方案读取失败：$e');
    } finally {
      if (mounted) setState(() => _creditsSyncing = false);
    }
  }

  /// 从本学期课表拉取课程并批量导入（按课程名去重，跳过已存在）。
  /// 课表条目噪声过滤：教务页面存在无上课安排的表头/占位行，
  /// 会被解析成名为「课程」等列头词的伪课程，导入时跳过。
  bool _isNoiseEntry(ScheduleEntry e) {
    if (e.classTimes.isNotEmpty) return false; // 有上课安排 = 真实课程
    final n = e.courseName.trim();
    if (n.isEmpty) return true;
    const headerWords = {
      '课程',
      '上课班级',
      '上课班级名称',
      '总学时',
      '学分',
      '修读性质',
      '任课教师',
      '选课状态',
      '教材',
      '上课时间地点',
      '备注',
    };
    return headerWords.contains(n) || e.courseCode.isEmpty;
  }

  Future<void> _importFromSchedule() async {
    if (_importing) return;
    final account = ref.read(currentAccountProvider);
    if (account.isEmpty) {
      _snack('尚未登录教务账号，无法读取课表。请先在「教务」页登录后再试。');
      return;
    }
    setState(() => _importing = true);
    try {
      // 当前学期口径与课表页统一（校历区间优先；原先的月份规则在 1 月下半月
      // 与 2 月会取错学期，导入到错误的课表）。
      final term = currentSchoolTerm(
        DateTime.now(),
        terms: ref.read(offlineSemesterTermsProvider),
      );
      final repo = await ref.read(scheduleRepositoryProvider.future);
      final entries = await repo.getSchedule(
        year: '${term.xn}',
        semester: '${term.xq}',
        studentId: account,
      );
      if (!mounted) return;

      // 同名课程合并为一条（课表一周多次出现同一门课）。
      final byName = <String, ScheduleEntry>{};
      for (final e in entries) {
        final n = e.courseName.trim();
        if (n.isEmpty || byName.containsKey(n)) continue;
        if (_isNoiseEntry(e)) continue; // 跳过表头等伪课程行
        byName[n] = e;
      }
      final existing = {for (final c in _courses) c.name.trim()};
      final fresh = [
        for (final n in byName.keys)
          if (!existing.contains(n)) byName[n]!,
      ];

      if (fresh.isEmpty) {
        _snack('本学期课表中的课程已全部添加过了。');
        return;
      }

      final termLabel = _termLabel('${term.xn}', '${term.xq}');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _ImportPreviewDialog(
          term: termLabel,
          fresh: fresh,
          skipped: byName.length - fresh.length,
        ),
      );
      if (confirmed != true || !mounted) return;

      final store = _store;
      if (store == null) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final added = <GeCourse>[
        for (var i = 0; i < fresh.length; i++)
          GeCourse(
            id: _uuid.v4(),
            name: fresh[i].courseName.trim(),
            courseCode: fresh[i].courseCode.trim(),
            // 课表自带学分 → 直接带入（缺失/为 0 时按 1 学分）；
            // 培养方案里有这门课时，加权与展示以培养方案学分为准。
            credits: fresh[i].credits > 0 ? fresh[i].credits : 1,
            note: _entryNote(fresh[i]),
            createdAt: nowMs + i, // 保持课表顺序
          ),
      ];
      await store.saveCourses([..._courses, ...added]);
      await _reload();
      _snack('已从课表导入 ${added.length} 门课程，点入可设置平时占比与分项。');
    } catch (e) {
      final text = '$e';
      final msg = (text.contains('timeout') || text.contains('timed out'))
          ? '教务服务器响应超时，请检查网络后重试。'
          : text.contains('凭证已失效')
          ? '登录教务的会话已过期，请先在「教务」页重新登录后再导入。'
          : text;
      _snack('课表拉取失败：$msg');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分数估计'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: _creditsSyncing ? '正在读取培养方案…' : '按培养方案补齐学分',
            icon: _creditsSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.school_outlined),
            onPressed: _creditsSyncing ? null : _syncCreditsFromPlan,
          ),
          IconButton(
            tooltip: _importing ? '正在读取课表…' : '从课表导入',
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.playlist_add),
            onPressed: _importing ? null : _importFromSchedule,
          ),
          IconButton(
            tooltip: '计分模型说明',
            icon: const Icon(Icons.help_outline),
            onPressed: () => geShowModelSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCourse,
        icon: const Icon(Icons.add),
        label: const Text('添加课程'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorRetry(message: _error!, onRetry: _init)
          : _courses.isEmpty
          ? _EmptyHint(
              accent: _accent,
              onAdd: _addCourse,
              onImport: _importFromSchedule,
            )
          : _buildList(context),
    );
  }
}

/// 课程卡片：名称 / 占比 / 分项数 / 当前分数与对总平均的贡献。
class _CourseCard extends StatelessWidget {
  final GeCourse course;
  final _CourseScore score;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CourseCard({
    required this.course,
    required this.score,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final calc = geCalc(course);
    final hasParts = course.parts.isNotEmpty;
    final pending = score.kind == _ScoreKind.pending;

    final detail = hasParts
        ? '平时 ${geFmt(course.dailyPercent)}% · 平时均分 ${geFmt(calc.dailyMean)}'
              ' · ${course.parts.length} 个分项'
        : '平时 ${geFmt(course.dailyPercent)}% · 尚未配置平时分项 · 点此设置';
    // 分数来源已由右侧分数块标注，这里只报「学分 + 来源」与未计入原因，
    // 避免过长被省略号截断（窄屏卡片可用宽度约 200px）。
    final stateText = pending ? score.pendingReason : '';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FeaturePalette.cardAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.calculate_outlined,
                  size: 22,
                  color: FeaturePalette.cardAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            course.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // 有备忘录（文字 / 图片）→ 课程名后一个小图标。
                        if (course.memo.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          GeMemoBadge(memo: course.memo),
                        ],
                        // 估计计入的课无需胶囊；未计入 / 教务成绩各给一个。
                        if (score.kind != _ScoreKind.estimate) ...[
                          const SizedBox(width: 6),
                          _pill(context),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 构成占比细条：平时分按分项分值断开（点行进详情页可调比例）。
                    const SizedBox(height: 6),
                    GeRatioBar(
                      parts: course.parts,
                      dailyPercent: course.dailyPercent,
                      height: geRatioBarThinHeight,
                      gap: 1.5,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '学分 ${geFmt(score.credits)}'
                      '（${score.creditsSource}）'
                      '${stateText.isEmpty ? '' : ' · $stateText'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: pending
                            ? const Color(0xFFE65100)
                            : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _scoreBlock(context),
              IconButton(
                tooltip: '删除课程',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: scheme.onSurfaceVariant,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右上角状态胶囊：暂不计入 / 教务成绩。
  Widget _pill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (score.kind) {
      _ScoreKind.pending => ('暂不计入', const Color(0xFFE65100)),
      _ScoreKind.grades => ('教务成绩', const Color(0xFF2E7D32)),
      _ScoreKind.estimate => ('', scheme.onSurfaceVariant),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// 右侧分数块：当前分数 + 分数来源 + 对加权平均的贡献。
  Widget _scoreBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = score.kind == _ScoreKind.pending;
    final color = switch (score.kind) {
      _ScoreKind.grades => const Color(0xFF2E7D32),
      _ScoreKind.estimate => FeaturePalette.cardAccent,
      _ScoreKind.pending => scheme.onSurfaceVariant,
    };
    final label = switch (score.kind) {
      _ScoreKind.grades => '教务成绩',
      _ScoreKind.estimate => '估计总评',
      _ScoreKind.pending => '平时折算',
    };
    return SizedBox(
      width: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            geFmt(score.score),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 1),
          Text(
            pending ? '未计入' : '贡献 ${geFmt(score.contribution, decimals: 2)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: pending
                  ? scheme.onSurfaceVariant
                  : FeaturePalette.cardAccent.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Color accent;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  const _EmptyHint({
    required this.accent,
    required this.onAdd,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.calculate_outlined, size: 34, color: accent),
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有课程',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '添加一门课，设置平时/期末占比与平时分项（计数 / 直接分数），\n即可实时估算总评、反推期末目标分数。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加课程'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.playlist_add),
              label: const Text('从本学期课表导入'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前学期文案：如「2025-2026 学年 · 第1学期」。
String _termLabel(String year, String semester) {
  final y = int.tryParse(year) ?? DateTime.now().year;
  return '$y-${y + 1} 学年 · ${semester == '1' ? '第2学期' : '第1学期'}';
}

/// 课表条目 → 课程备注（教师 / 学分，取得到才带）。
String _entryNote(ScheduleEntry e) => [
  if (e.teacherName.trim().isNotEmpty) '教师：${e.teacherName.trim()}',
  if (e.credits > 0) '学分 ${geFmt(e.credits, decimals: 1)}',
].join(' · ');

/// 导入预览确认弹窗。
class _ImportPreviewDialog extends StatelessWidget {
  final String term;
  final List<ScheduleEntry> fresh;
  final int skipped;

  const _ImportPreviewDialog({
    required this.term,
    required this.fresh,
    required this.skipped,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.playlist_add, size: 26),
      title: const Text('从课表导入'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将添加 $term 课表中的 $fresh.length 门课程'
            '${skipped > 0 ? '（已跳过 $skipped 门已存在）' : ''}：',
            style: style,
          ),
          const SizedBox(height: 2),
          // 注意：AlertDialog 内容不能用 ListView（IntrinsicWidth 约束），
          // 行直接展开，超出部分由 scrollable: true 的外层滚动兜底。
          for (final e in fresh)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.menu_book_outlined,
                size: 18,
                color: scheme.primary,
              ),
              title: Text(
                e.courseName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: e.teacherName.trim().isNotEmpty
                  ? Text(
                      e.teacherName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
          const SizedBox(height: 6),
          Text('导入后默认平时 30% / 期末 70%，点入课程即可设置分项开始计分。', style: style),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('导入 ${fresh.length} 门'),
        ),
      ],
    );
  }
}

/// 按培养方案补齐学分的确认弹窗：列出「课程 旧学分 → 新学分」与未匹配课程。
class _CreditSyncDialog extends StatelessWidget {
  final String majorName;
  final List<({GeCourse course, double next})> changes;
  final List<String> unmatched;

  const _CreditSyncDialog({
    required this.majorName,
    required this.changes,
    required this.unmatched,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.school_outlined, size: 26),
      title: const Text('按培养方案补齐学分'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('培养方案：$majorName。以下 ${changes.length} 门课程的学分将更新：', style: style),
          const SizedBox(height: 2),
          // 注意：AlertDialog 内容不能用 ListView（IntrinsicWidth 约束），
          // 行直接展开，超出部分由 scrollable: true 的外层滚动兜底。
          for (final x in changes)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: Text(
                x.course.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Text(
                '${geFmt(x.course.credits)} → ${geFmt(x.next)} 学分',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: FeaturePalette.cardAccent,
                ),
              ),
            ),
          if (unmatched.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('未在培养方案中找到（保留原学分）：', style: style),
            const SizedBox(height: 2),
            Text(
              unmatched.join('、'),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text('学分只影响「总加权平均」，不影响单门课的估分与达线预警。', style: style),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('更新 ${changes.length} 门'),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
