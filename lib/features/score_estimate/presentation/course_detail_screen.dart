/// 分数估计 · 课程详情（比例 / 分项录入 + 实时估算、反推、预警）。
///
/// 所有改动即时写 Hive（串行队列），返回列表页即见最新摘要。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/current_account_provider.dart';
import '../../../design/feature_palette.dart';
import '../data/ge_chaoxing_works.dart';
import '../data/ge_curriculum.dart';
import '../data/ge_deadline_reminders.dart';
import '../data/ge_memo_importer.dart';
import '../data/ge_memo_providers.dart';
import '../data/ge_memo_store.dart';
import '../data/ge_prior_grades.dart';
import '../data/ge_providers.dart';
import '../data/ge_store.dart';
import '../data/ge_summary.dart';
import '../domain/ge_chaoxing_sync.dart';
import '../domain/ge_deadline.dart';
import '../domain/ge_engine.dart';
import '../domain/ge_memo.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';
import 'ge_course_cards.dart';
import 'ge_deadline_card.dart';
import 'ge_dialogs.dart';
import 'ge_memo_card.dart';
import 'ge_ratio_bar.dart';
import 'ge_summary_card.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/section_title.dart';

class CourseDetailScreen extends ConsumerStatefulWidget {
  final GeCourse course;

  /// 本专业培养方案里这门课的学分（null = 未匹配到）；与课程学分不一致时提示。
  final double? planCredits;

  const CourseDetailScreen({super.key, required this.course, this.planCredits});

  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen> {
  late GeCourse _c;
  GeStore? _store;
  bool _loading = true;
  String? _error;
  Future<void> _saving = Future.value();

  /// 顶部「总加权平均」汇总卡的数据（与列表页同一口径，见 ge_summary.dart）。
  List<GePriorGrade> _prior = const [];
  List<GeCourse> _allCourses = const [];
  GeCurriculumIndex _curriculum = const GeCurriculumIndex.empty();
  bool _summaryReady = false;

  /// 学习通里本课的作业成绩（null = 没缓存 / 名字对不上 / 没有已批作业）。
  GeChaoxingHomework? _chaoxing;

  late final TextEditingController _finalCtrl;
  late final TextEditingController _goalCtrl;

  /// 备忘录图片存储（应用私有目录；初始化失败只是图片功能不可用）。
  GeMemoStore? _memoStore;
  bool _memoBusy = false;

  @override
  void initState() {
    super.initState();
    _c = widget.course;
    _finalCtrl = TextEditingController(
      text: _c.finalScore == null ? '' : geFmt(_c.finalScore!, decimals: 1),
    );
    _goalCtrl = TextEditingController(text: '85');
    _initStore();
    _initMemoStore();
  }

  @override
  void dispose() {
    _finalCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  /// 培养方案学分与课程学分不一致时的提示（null = 无需提示）。
  String? get _planCreditHint {
    final plan = widget.planCredits;
    if (plan == null || plan <= 0) return null;
    if ((plan - _c.credits).abs() < 1e-9) return null;
    return '培养方案里这门课为 ${geFmt(plan)} 学分（当前 ${geFmt(_c.credits)}），'
        '可在列表页用「按培养方案补齐学分」一键写入。';
  }

  Future<void> _initStore() async {
    try {
      final store = await ref.read(geStoreProvider.future);
      // 汇总卡要算全部课程（含教务已出成绩），所以整表读一次；本页保存时也写回整表。
      final all = await store.loadCourses();
      if (!mounted) return;
      setState(() {
        _store = store;
        _allCourses = all;
        _loading = false;
      });
      // 进详情页即按当前数据重排截止提醒（幂等，数据没变时不做任何事）。
      _syncDeadlineReminders();
      // 进详情页即把学习通作业均分同步进「作业」分项（同样幂等，值没变不写库）。
      await _syncChaoxingHomework();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '存储初始化失败：$e';
        _loading = false;
      });
      return;
    }
    await _initSummary();
  }

  /// 自动同步：把学习通作业均分写进本课的「作业」分项（用户口径 2026-09-22）。
  ///
  /// **只有这门课已经给出作业的占比**（= 已有带分值上限的「作业」分项）才接入，
  /// 且只覆盖 [gePartSourceChaoxing] 来源的分项；计数型分项要用户点「接入」才改写。
  /// 口径与边界全在 `domain/ge_chaoxing_sync.dart`，这里只负责取数 + 落库。
  /// ⚠ 取的是**学习通页最近一次取数的缓存**，本页不发任何超星请求（请求配额，见 §30）。
  Future<void> _syncChaoxingHomework() async {
    GeChaoxingHomework? homework;
    try {
      final snapshot = await ref.read(geChaoxingSnapshotProvider.future);
      homework = geChaoxingHomeworkFor(snapshot, _c.name);
    } catch (e) {
      debugPrint('[score_estimate] 读取学习通作业缓存失败：$e');
    }
    if (!mounted) return;
    final hw = homework;
    if (hw != null) {
      final result = geApplyChaoxingHomework(
        _c,
        average: hw.average,
        workCount: hw.count,
        fetchedAt: hw.fetchedAt,
      );
      if (result != null) {
        debugPrint(
          '[score_estimate] 学习通作业已接入「${result.part.name}」：'
          '均分 ${result.average}（${result.workCount} 条）',
        );
        _mutate(result.course);
      }
    }
    setState(() => _chaoxing = hw);
  }

  /// 用户明确点「接入」：允许把计数型分项改写成「直接分数」。
  ///
  /// 与自动同步只差 `force: true`（自动同步遇到计数型分项会收手，见
  /// `domain/ge_chaoxing_sync.dart` 的第 4 条）。
  void _bindChaoxingHomework() {
    final hw = _chaoxing;
    if (hw == null) return;
    final result = geApplyChaoxingHomework(
      _c,
      average: hw.average,
      workCount: hw.count,
      fetchedAt: hw.fetchedAt,
      force: true,
    );
    if (result != null) _mutate(result.course);
  }

  /// 汇总卡的辅助数据（教务成绩 / 培养方案）：失败只影响汇总卡，不阻塞本页。
  Future<void> _initSummary() async {
    var prior = const <GePriorGrade>[];
    var index = const GeCurriculumIndex.empty();
    try {
      prior = await ref.read(gePriorGradesProvider.future);
    } catch (e) {
      debugPrint('[score_estimate] 详情页读取教务成绩失败：$e');
    }
    try {
      index = await ref.read(geCurriculumIndexProvider.future);
    } catch (e) {
      debugPrint('[score_estimate] 详情页读取培养方案失败：$e');
    }
    if (!mounted) return;
    setState(() {
      _prior = prior;
      _curriculum = index;
      _summaryReady = true;
    });
  }

  /// 汇总用课程列表：把本课替换成编辑中的最新状态（即改即算，无需等写库）。
  List<GeCourse> _summaryCourses() {
    var replaced = false;
    final out = <GeCourse>[];
    for (final x in _allCourses) {
      if (x.id == _c.id) {
        out.add(_c);
        replaced = true;
      } else {
        out.add(x);
      }
    }
    if (!replaced) out.add(_c);
    return out;
  }

  // ---- 变更：setState + 写库（串行，防交错丢更新） ----
  void _mutate(GeCourse next) {
    setState(() => _c = next);
    _queueSave();
  }

  void _queueSave() {
    final store = _store;
    if (store == null) return;
    _saving = _saving.then((_) async {
      final list = await store.loadCourses();
      final idx = list.indexWhere((x) => x.id == _c.id);
      if (idx < 0) {
        list.add(_c);
      } else {
        list[idx] = _c;
      }
      await store.saveCourses(list);
    });
  }

  // ---- 课程信息（改名 / 占比 / 学分 / 备注） ----
  Future<void> _editCourseInfo() async {
    final draft = await showGeCourseDialog(
      context,
      title: '课程信息',
      initialName: _c.name,
      initialDailyPercent: _c.dailyPercent,
      initialCredits: _c.credits,
      initialNote: _c.note,
    );
    if (draft == null || !mounted) return;
    _mutate(
      _c.copyWith(
        name: draft.name,
        dailyPercent: draft.dailyPercent,
        credits: draft.credits,
        note: draft.note,
      ),
    );
    // 改名会改变与学习通课程的匹配，立刻重对一次。
    _resyncChaoxing();
  }

  // ---- 期末成绩 ----
  void _setFinal(double? v) {
    _mutate(_c.copyWith(finalScore: v, clearFinalScore: v == null));
  }

  // ---- 分项 ----
  Future<void> _addPart() async {
    final out = await showGePartDialog(context);
    if (out == null || !mounted) return;
    _mutate(_c.copyWith(parts: [..._c.parts, out.part]));
    _resyncChaoxing();
  }

  /// 改完分项 / 课程名后立刻对一次学习通作业 —— 否则用户得「退出再进」才生效
  /// （缓存已在内存里，这一步零网络请求；没变化时 `geApplyChaoxingHomework` 返回
  /// null，不写库）。
  void _resyncChaoxing() => unawaited(_syncChaoxingHomework());

  Future<void> _editPart(GePart p) async {
    final out = await showGePartDialog(context, part: p);
    if (out == null || !mounted) return;
    if (out.deleted) {
      _mutate(
        _c.copyWith(
          parts: [
            for (final x in _c.parts)
              if (x.id != p.id) x,
          ],
        ),
      );
    } else {
      _mutate(
        _c.copyWith(
          parts: [
            for (final x in _c.parts)
              if (x.id == p.id) out.part else x,
          ],
        ),
      );
    }
    _resyncChaoxing();
  }

  /// 步进器：+1 / −1（正计数上下移动完成数；负计数上下移动剩余数）。
  void _bump(GePart p, int delta) {
    final isDown = p.mode == GePartMode.down;
    if (isDown) {
      final next = (p.current + delta).clamp(0, p.target);
      _mutate(
        _c.copyWith(
          parts: [
            for (final x in _c.parts)
              if (x.id == p.id) x.copyWith(current: next) else x,
          ],
        ),
      );
    } else {
      final next = (p.current + delta).clamp(0, 1 << 30);
      _mutate(
        _c.copyWith(
          parts: [
            for (final x in _c.parts)
              if (x.id == p.id) x.copyWith(current: next) else x,
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_c.name)),
        body: const AppLoadingState(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_c.name)),
        body: Center(child: Text(_error!)),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final calc = geCalc(_c);
    // 顶部汇总卡（与列表页同一口径，见 ge_summary.dart）。
    // 用户口径（2026-09-26）：**既要算含本课、也要算不含本课** —— 主数字显示含本课的
    // 加权平均，右侧胶囊给出本课带来的提升 / 减少（`_withoutCourseAverage()`）。
    final summaryData = _summaryReady
        ? geSummarize(
            prior: _prior,
            courses: _summaryCourses(),
            index: _curriculum,
          )
        : null;
    final chaoxingNotice = _chaoxingNotice(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '课程信息（改名 / 占比 / 学分 / 备注）',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editCourseInfo,
          ),
          IconButton(
            tooltip: '计分模型说明',
            icon: const Icon(Icons.help_outline),
            onPressed: () => geShowModelSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          // 卡片 1 · 总加权平均（含本课 / 不含本课 + Δ 胶囊）。
          if (summaryData != null) ...[
            GeWeightedSummaryCard(
              summary: summaryData.summary,
              withoutCourseAverage: _withoutCourseAverage(),
              courseExcludedNote: _courseExcludedNote(),
            ),
            const SizedBox(height: 12),
          ],
          // 卡片 2 · 当前课程成绩现状（占比 + 各部分成绩 + 期末预估 + 目标反推）。
          GeCourseStatusCard(
            course: _c,
            calc: calc,
            finalCtrl: _finalCtrl,
            goalCtrl: _goalCtrl,
            planCreditHint: _planCreditHint,
            onFinalChanged: _setFinal,
            onGoalChanged: () => setState(() {}),
            onOpenRatio: _openRatioSheet,
          ),
          const SizedBox(height: 12),
          // 小节标题「平时成绩」（用户口径：卡片 2 与卡片 3 之间）。
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            child: appSectionTitle(
              context,
              text: '平时成绩',
              trailing: _c.parts.isEmpty
                  ? null
                  : Text(
                      '已得 ${geFmt(calc.scoreSum, decimals: 2)} / '
                      '${geFmt(calc.capSum, decimals: 2)} 分 · '
                      '折算 ${geFmt(calc.dailyContrib)} 分',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          // 卡片 3 / 4-x · 一个平时分项一张卡（「作业」那张排最前）。
          for (final p in _orderedParts()) ...[
            GePartCard(
              course: _c,
              part: p,
              chaoxingCount: _chaoxing?.count ?? 0,
              chaoxingHint: _chaoxingFetchedHint(),
              onTap: () => _editPart(p),
              onBump: (d) => _bump(p, d),
            ),
            const SizedBox(height: 8),
          ],
          if (chaoxingNotice != null) ...[
            chaoxingNotice,
            const SizedBox(height: 8),
          ],
          // 末尾那张「添加」卡。
          GeAddPartCard(onTap: _addPart, showEmptyHint: _c.parts.isEmpty),
          const SizedBox(height: 12),
          _memoCard(),
          const SizedBox(height: 12),
          _deadlineCard(),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: geCardShape(context),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  appSectionTitle(
                    context,
                    text: '计分模型说明',
                    accent: fp(context).cardAccent,
                  ),
                ],
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [geModelHintBody(context)],
            ),
          ),
        ],
      ),
    );
  }

  // ---- 备忘录（文字 + 图片） ----

  /// 当前账号（备忘录图片按账号分档存放，切号不串图）。
  String get _account => ref.read(currentAccountProvider);

  Future<void> _initMemoStore() async {
    try {
      final store = await ref.read(geMemoStoreProvider.future);
      if (!mounted) return;
      setState(() => _memoStore = store);
    } catch (e) {
      // 私有目录拿不到只是「不能存图片」，文字备忘录与整页功能照常。
      debugPrint('[score_estimate] 备忘录目录初始化失败：$e');
    }
  }

  /// 图片文件名 → 绝对路径（目录未就绪 / 文件缺失 → null，界面出占位图）。
  String? _memoPath(GeMemoImage image) =>
      _memoStore?.resolve(_account, _c.id, image.fileName);

  Widget _memoCard() => GeMemoCard(
    memo: _c.memo,
    busy: _memoBusy,
    mobile: geMemoMobilePlatformOn(defaultTargetPlatform.name),
    resolvePath: _memoPath,
    onChanged: (memo) => _mutate(_c.copyWith(memo: memo)),
    onPickImages: _addMemoImages,
    onRemoveImage: _removeMemoImage,
  );

  /// 选图 → 按 1600px 压缩 → 落盘 → 追加进备忘录（逐张失败原因汇总提示）。
  Future<void> _addMemoImages(GeMemoPickSource source) async {
    final store = _memoStore;
    if (store == null) {
      _memoSnack('备忘录目录还没准备好，请稍后重试');
      return;
    }
    if (_memoBusy) return;
    if (_c.memo.isFull) {
      _memoSnack('已达 $geMemoMaxImages 张上限，删掉一些再加');
      return;
    }

    setState(() => _memoBusy = true);
    try {
      final sources = await ref.read(geMemoPickerProvider).pick(source);
      if (sources.isEmpty) return; // 用户取消
      final result = await importGeMemoImages(
        store: store,
        account: _account,
        courseId: _c.id,
        sources: sources,
        remainingSlots: _c.memo.remainingSlots,
      );
      if (!mounted) return;
      if (result.added.isNotEmpty) {
        _mutate(
          _c.copyWith(
            memo: _c.memo.copyWith(
              images: [..._c.memo.images, ...result.added],
            ),
          ),
        );
      }
      _memoReport(result);
    } catch (e) {
      debugPrint('[score_estimate] 备忘录导入异常：$e');
      _memoSnack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _memoBusy = false);
    }
  }

  /// 删除一张图片：先摘记录（界面同帧消失），再删私有目录里的文件。
  Future<void> _removeMemoImage(GeMemoImage image) async {
    _mutate(
      _c.copyWith(
        memo: _c.memo.copyWith(
          images: [
            for (final x in _c.memo.images)
              if (x.fileName != image.fileName) x,
          ],
        ),
      ),
    );
    await _memoStore?.remove(
      account: _account,
      courseId: _c.id,
      fileName: image.fileName,
    );
  }

  /// 导入结果提示（成功条数 + 前 3 条跳过原因）。
  void _memoReport(GeMemoImportResult result) {
    if (result.isEmpty) return;
    final lines = <String>[result.summary];
    for (final skip in result.skipped.take(3)) {
      lines.add('· ${geMemoSkipText(skip)}');
    }
    if (result.skipped.length > 3) {
      lines.add('· 另有 ${result.skipped.length - 3} 张被跳过');
    }
    _memoSnack(lines.join('\n'));
  }

  void _memoSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  // ---- 截止日期（网课 / 作业 / 考试） ----

  Widget _deadlineCard() => GeDeadlineCard(
    deadlines: _c.deadlines,
    onAdd: () => _openDeadlineEditor(),
    onEdit: _openDeadlineEditor,
    onToggleDone: _toggleDeadlineDone,
    onDelete: _deleteDeadline,
  );

  /// 新增 / 编辑一条（弹层返回 null = 取消）。
  Future<void> _openDeadlineEditor([GeDeadline? existing]) async {
    final result = await showGeDeadlineEditor(context, existing: existing);
    if (result == null || !mounted) return;
    final next = [..._c.deadlines];
    final idx = next.indexWhere((x) => x.id == result.id);
    if (idx < 0) {
      next.add(result);
    } else {
      next[idx] = result;
    }
    _mutate(_c.copyWith(deadlines: next));
    _syncDeadlineReminders();
  }

  /// 勾选 / 取消完成。重复条目 = **完成本期**：周期滚过去后完成态自动失效，
  /// 不需要任何后台任务重置（见 `geDeadlineDoneNow`）。
  void _toggleDeadlineDone(GeDeadline d) {
    final now = DateTime.now();
    final wasDone = geDeadlineDoneNow(d, now);
    _mutate(
      _c.copyWith(
        deadlines: [
          for (final x in _c.deadlines)
            if (x.id == d.id)
              (wasDone ? x.copyWith(clearDone: true) : x.copyWith(doneAt: now))
            else
              x,
        ],
      ),
    );
    _syncDeadlineReminders();
  }

  /// 删除一条（确认框；已排的提醒会在重排时一并撤销）。
  Future<void> _deleteDeadline(GeDeadline d) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除截止日期',
      message: '确定删除「${d.displayTitle}」吗？已排的提醒会一并撤销。',
    );
    if (!ok || !mounted) return;
    _mutate(
      _c.copyWith(
        deadlines: [
          for (final x in _c.deadlines)
            if (x.id != d.id) x,
        ],
      ),
    );
    _syncDeadlineReminders();
  }

  /// 把系统里的通知排期对齐到当前数据（幂等；失败只打日志，不影响页面）。
  void _syncDeadlineReminders() {
    unawaited(syncGeDeadlineReminders(courses: _summaryCourses()));
  }

  /// 学习通有作业成绩、但**没能接入**时的说明（null = 不需要说）。
  ///
  /// 用户口径（2026-09-22）：「前提是该课程给出了作业的占比」→ 本课没有「作业」分项
  /// 就没有占比，**不接入**（也绝不替用户造一个分项）；「作业」分项是计数型时，
  /// 改写成「直接分数」是结构性变更，要用户点「接入」才做。
  Widget? _chaoxingNotice(BuildContext context) {
    final hw = _chaoxing;
    if (hw == null) return null;
    final target = geHomeworkPartOf(_c);
    if (target != null && target.source == gePartSourceChaoxing) return null;
    final avg = geFmt(hw.average, decimals: 1);
    final text = target == null
        ? '学习通里这门课有 ${hw.count} 条已批作业（均分 $avg），但本课还没配「作业」分项 '
              '—— 占比未知，没有接入。加一个「作业」分项并填上分值，下次进本页会自动接入。'
        : '「${target.name}」是计数型分项：学习通作业均分（$avg）没有接进来 —— '
              '接入会把它改成「直接分数」，原计数被覆盖。';
    return GeChaoxingNotice(
      text: text,
      onBind: target == null ? null : _bindChaoxingHomework,
    );
  }

  /// 「学习通同步」芯片的悬浮说明：数据来自哪一刻的缓存（本页不发超星请求）。
  String _chaoxingFetchedHint() {
    final at = _chaoxing?.fetchedAt;
    final when = at == null
        ? '取数时间未知'
        : '${at.year}-${_two(at.month)}-${_two(at.day)} '
              '${_two(at.hour)}:${_two(at.minute)}';
    return '作业均分来自学习通（$when）\n进本页会自动同步；'
        '要停止同步，点开该分项关掉开关。';
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  // ---- 占比设置（点卡片 2 的标题或占比条触发） ----

  /// 设平时占比（弹层内滑动条 / 手输 / 快捷比例统一走这里，即时写库）。
  void _setDailyPercent(double v) => _mutate(_c.copyWith(dailyPercent: v));

  /// 打开比例设置弹层（点构成占比条触发）。
  Future<void> _openRatioSheet() => showGeRatioSheet(
    context,
    parts: _c.parts,
    dailyPercent: _c.dailyPercent,
    onChanged: _setDailyPercent,
  );

  // ---- 卡片 1 的「含本课 / 不含本课」口径（用户 2026-09-26） ----

  /// 不含本课的加权平均（`null` = 不比较）。
  ///
  /// 与含本课那份（`build` 里的 `summaryData`）走**同一个** `geSummarize`，
  /// 只差课程列表里有没有本课 —— 两份口径不可能漂移。
  double? _withoutCourseAverage() {
    if (!_summaryReady || _allCourses.isEmpty) return null;
    final others = [
      for (final x in _summaryCourses())
        if (x.id != _c.id) x,
    ];
    return geSummarize(
      prior: _prior,
      courses: others,
      index: _curriculum,
    ).summary.average;
  }

  /// 本课没进合计的原因（`null` = 已计入 → 汇总卡显示 Δ 胶囊）。
  ///
  /// 与 `data/ge_summary.dart` 的计入条件逐条对齐：同名教务成绩优先、
  /// 学分为 0 不计入、未填期末不计入。
  String? _courseExcludedNote() {
    final priorNames = {for (final p in _prior) p.courseName.trim()};
    if (priorNames.contains(_c.name.trim())) return '同名教务成绩已计入';
    if (geEffectiveCredits(_curriculum, _c).credits <= 0) {
      return '学分为 0，暂未计入';
    }
    if (_c.finalScore == null) return '未填期末，暂未计入';
    return null;
  }

  /// 平时分项的渲染顺序：**「作业」那张排最前**（用户口径里它是卡片 3），
  /// 其余保持用户添加顺序；没有作业分项时顺序完全不变。
  List<GePart> _orderedParts() {
    final hw = geHomeworkPartOf(_c);
    if (hw == null || _c.parts.isEmpty || hw.id == _c.parts.first.id) {
      return _c.parts;
    }
    return [
      hw,
      for (final p in _c.parts)
        if (p.id != hw.id) p,
    ];
  }
}
