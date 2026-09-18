/// 分数估计 · 课程详情（比例 / 分项录入 + 实时估算、反推、预警）。
///
/// 所有改动即时写 Hive（串行队列），返回列表页即见最新摘要。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/current_account_provider.dart';
import '../../../design/app_theme.dart';
import '../../../design/feature_palette.dart';
import '../data/ge_curriculum.dart';
import '../data/ge_deadline_reminders.dart';
import '../data/ge_memo_importer.dart';
import '../data/ge_memo_providers.dart';
import '../data/ge_memo_store.dart';
import '../data/ge_prior_grades.dart';
import '../data/ge_providers.dart';
import '../data/ge_store.dart';
import '../data/ge_summary.dart';
import '../domain/ge_deadline.dart';
import '../domain/ge_engine.dart';
import '../domain/ge_memo.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';
import 'ge_deadline_card.dart';
import 'ge_dialogs.dart';
import 'ge_memo_card.dart';
import 'ge_ratio_bar.dart';
import 'ge_summary_card.dart';

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
  }

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
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_c.name)),
        body: Center(child: Text(_error!)),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // 顶部汇总卡（与列表页同一口径）：教务已出成绩 + 本模块估计分的学分加权平均。
    final summaryData = _summaryReady
        ? geSummarize(
            prior: _prior,
            courses: _summaryCourses(),
            index: _curriculum,
          )
        : null;
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
          if (summaryData != null) ...[
            GeWeightedSummaryCard(
              summary: summaryData.summary,
              pendingCount: summaryData.pendingCount,
              planMajorName: _curriculum.majorName,
            ),
            const SizedBox(height: 12),
          ],
          _ratioCard(),
          const SizedBox(height: 12),
          _estimateCard(scheme),
          const SizedBox(height: 12),
          _partsCard(),
          const SizedBox(height: 12),
          _goalCard(scheme),
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
                  Container(
                    width: 3,
                    height: 13,
                    decoration: BoxDecoration(
                      color: fp(context).cardAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '计分模型说明',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
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

  // ---- 构成占比卡 ----

  /// 设平时占比（弹层内滑动条 / 手输 / 快捷比例统一走这里，即时写库）。
  void _setDailyPercent(double v) => _mutate(_c.copyWith(dailyPercent: v));

  /// 打开比例设置弹层（点构成占比条触发）。
  Future<void> _openRatioSheet() => showGeRatioSheet(
    context,
    parts: _c.parts,
    dailyPercent: _c.dailyPercent,
    onChanged: _setDailyPercent,
  );

  Widget _ratioCard() {
    final scheme = Theme.of(context).colorScheme;
    final dp = _c.dailyPercent;
    final fp = 100 - dp;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '构成占比',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${geFmt(_c.credits)} 学分 · 期末 ${geFmt(fp)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.tune, size: 14, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            if (_planCreditHint != null) ...[
              const SizedBox(height: 2),
              Text(
                _planCreditHint!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  // ⚠ 本方法内 `fp` 是「期末占比」的局部变量（line 560），
                  // 会遮蔽顶层 `fp(context)` → 这里走 FeatureColors.of(context)。
                  color: FeatureColors.of(context).cardAccent,
                ),
              ),
            ],
            const SizedBox(height: 10),
            GeRatioChart(
              parts: _c.parts,
              dailyPercent: dp,
              onTap: _openRatioSheet,
            ),
            const SizedBox(height: 8),
            Text(
              '总评 = 平时均分 × ${geFmt(dp)}% + 期末 × ${geFmt(fp)}%'
              '${_c.parts.isEmpty ? ' · 点条可调比例，加分项后按分值分段' : ' · 点条可调比例'}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 当前估计卡 ----
  Widget _estimateCard(ColorScheme scheme) {
    final calc = geCalc(_c);
    final hasParts = _c.parts.isNotEmpty;
    final finalScore = _c.finalScore;
    final total = geTotalWithFinal(calc, finalScore);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '当前估计',
              trailing: !hasParts
                  ? Text(
                      '先添加平时分项',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
            if (hasParts) ...[
              const SizedBox(height: 8),
              // 期末输入行
              Row(
                children: [
                  const Text('期末分', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: _finalCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        suffixText: '分',
                        suffixStyle: TextStyle(fontSize: 12),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (v.trim().isEmpty) {
                          _setFinal(null);
                          return;
                        }
                        var n = double.tryParse(v) ?? 0;
                        if (n > 100) {
                          n = 100;
                          _finalCtrl.text = '100';
                          _finalCtrl.selection = TextSelection.collapsed(
                            offset: 3,
                          );
                        }
                        _setFinal(n);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final preset in const [60.0, 70.0, 80.0, 90.0])
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              geFmt(preset),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onPressed: () {
                              _finalCtrl.text = geFmt(preset, decimals: 1);
                              _setFinal(preset);
                            },
                          ),
                        if (finalScore != null)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.close, size: 14),
                            label: const Text(
                              '清空',
                              style: TextStyle(fontSize: 11.5),
                            ),
                            onPressed: () {
                              _finalCtrl.text = '';
                              _setFinal(null);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 结果区
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    if (finalScore == null) ...[
                      Text(
                        '${geFmt(calc.dailyContrib + 0)} ~ '
                        '${geFmt(calc.dailyContrib + calc.finalWeight * 100)}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: fp(context).cardAccent,
                        ),
                      ),
                      Text(
                        '总评区间（期末按 0~100 计）',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      Text(
                        geFmt(total!, decimals: 1),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: total < 60
                              ? scheme.error
                              : fp(context).cardAccent,
                        ),
                      ),
                      Text(
                        '估计总评（满分 100）',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (total ?? calc.dailyContrib + 0) / 100,
                        minHeight: 7,
                        color: fp(context).cardAccent,
                        backgroundColor: AppColors.tint(
                          context,
                          fp(context).cardAccent,
                          0.12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      finalScore == null
                          ? '平时折算 ${geFmt(calc.dailyContrib)} 分'
                                '（均分 ${geFmt(calc.dailyMean)} × 平时 ${geFmt(_c.dailyPercent)}%）'
                          : '平时折算 ${geFmt(calc.dailyContrib)} 分'
                                '（均分 ${geFmt(calc.dailyMean)} × ${geFmt(_c.dailyPercent)}%）'
                                '  +  期末折算 ${geFmt(calc.finalContrib(finalScore))} 分',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    if (total != null && total < 60)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '低于及格线：距 60 还差 ${geFmt(60 - total)} 分'
                          '（可看下方反推）',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- 平时分项卡 ----
  Widget _partsCard() {
    final scheme = Theme.of(context).colorScheme;
    final calc = geCalc(_c);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '平时分项',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_c.parts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: fp(context).cardAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '满分 ${geFmt(calc.capSum, decimals: 2)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: fp(context).cardAccent.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addPart,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加分项'),
                  ),
                ],
              ),
            ),
            if (_c.parts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 10),
                child: Text(
                  '还没有分项。例如：考勤（负计数，从总课次向下扣）、'
                  '作业提交或课堂打卡（正计数，从 0 累计）、'
                  '期中测验或实验报告（直接分数，填满分与得分）。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var i = 0; i < _c.parts.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                _partTile(_c.parts[i]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _partTile(GePart p) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = gePartRatio(p);
    final score = gePartScore(p);
    final isDown = p.mode == GePartMode.down;
    final isScore = p.mode == GePartMode.score;
    final missed = p.target - p.current;

    final countLine = isScore
        ? '得分 ${geFmt(p.score, decimals: 2)} / 满分 ${p.target}'
        : isDown
        ? (missed <= 0
              ? '尚未扣减 · 剩余 ${p.current} / ${p.target}'
              : '已扣 $missed · 剩余 ${p.current} / ${p.target}')
        : '已完成 ${p.current} / ${p.target}';

    final ratioLine =
        '得分率 ${geFmt(ratio * 100, decimals: 1)}%'
        ' · 折算 ${geFmt(score, decimals: 2)} / ${geFmt(p.cap, decimals: 2)} 分';

    // 步进按钮语义随方向翻转
    final minusTip = isDown ? '记一次扣减（如缺勤）' : '撤销一次完成';
    final plusTip = isDown ? '撤销一次扣减' : '记一次完成（可超目标）';
    final minusEnabled = isDown ? p.current > 0 : p.current > 0;
    final plusEnabled = isDown ? p.current < p.target : true;

    Widget stepBtn(
      IconData icon,
      bool enabled,
      String tip,
      VoidCallback onTap,
    ) {
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 19,
              color: enabled
                  ? (isDown ? scheme.error : scheme.primary)
                  : scheme.outlineVariant,
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _editPart(p),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            GeModeBadge(mode: p.mode),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GeModeChip(mode: p.mode),
                      if (p.note.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            p.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    countLine,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    ratioLine,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ratio >= 1
                          ? AppColors.success(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (isScore)
              // 直接分数项没有步进语义：点整行弹窗改分。
              Tooltip(
                message: '点击修改得分',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: scheme.outline,
                  ),
                ),
              )
            else ...[
              stepBtn(
                Icons.remove_circle_outline,
                minusEnabled,
                minusTip,
                () => _bump(p, -1),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${p.current}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              stepBtn(
                Icons.add_circle_outline,
                plusEnabled,
                plusTip,
                () => _bump(p, 1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- 目标反推 / 达线预警卡 ----
  Widget _goalCard(ColorScheme scheme) {
    final calc = geCalc(_c);
    final hasParts = _c.parts.isNotEmpty;
    final goal = double.tryParse(_goalCtrl.text.trim());

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(context, text: '目标反推 · 达线预警'),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('目标总评', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 76,
                  child: TextField(
                    controller: _goalCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      isDense: true,
                      counterText: '',
                      suffixText: '分',
                      suffixStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final g in const [60.0, 70.0, 80.0, 90.0, 95.0])
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            g == 60 ? '60 及格' : geFmt(g),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onPressed: () {
                            _goalCtrl.text = geFmt(g);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!hasParts)
              Text(
                '先添加平时分项并录入进度，即可反推期末需要考多少分。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            else if (goal == null || goal <= 0 || goal > 100)
              Text(
                '输入 0~100 的目标总评，实时反推。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            else
              _goalResult(context, calc, goal, scheme),
          ],
        ),
      ),
    );
  }

  Widget _goalResult(
    BuildContext context,
    GeCalc calc,
    double goal,
    ColorScheme scheme,
  ) {
    final need = geRequiredFinal(calc, goal);
    final fw = calc.finalWeight;
    final hasFinal = fw > 0;

    final Color resultColor;
    final String headline;
    final String detail;

    switch (need.status) {
      case GeGoalStatus.reached:
        resultColor = AppColors.success(context);
        headline = '平时折算已达目标';
        detail =
            '即使期末 0 分，总评也有 '
            '${geFmt(calc.dailyContrib)} 分（≥ 目标 ${geFmt(goal)}）。';
      case GeGoalStatus.ok:
        resultColor = scheme.primary;
        headline = '期末需 ≥ ${geFmt(need.requiredFinal, decimals: 1)} 分';
        detail =
            '平时已折算 ${geFmt(calc.dailyContrib)} 分，距目标 '
            '${geFmt(goal)} 还差 ${geFmt(goal - calc.dailyContrib)} 总评点；'
            '期末占比 ${geFmt((100 - _c.dailyPercent))}%，'
            '每考 1 分得 ${geFmt(fw * 100, decimals: 0)}%。';
      case GeGoalStatus.recoverByDaily:
        resultColor = AppColors.caution(context);
        headline = hasFinal
            ? '期末满分也差 ${geFmt(need.dailyGap, decimals: 1)} 分'
            : '总分还差 ${geFmt(need.dailyGap, decimals: 1)} 分';
        detail = hasFinal
            ? '期末按满分 100 计仍差 ${geFmt(need.dailyGap, decimals: 1)} 总评点，'
                  '但平时还能再挣的分项（正计数 / 直接分数）拿满可补 '
                  '+${geFmt(calc.dailyCeiling - calc.dailyContrib, decimals: 1)} 分。'
            : '平时还能再挣的分项（正计数 / 直接分数）拿满可补 '
                  '+${geFmt(calc.dailyCeiling - calc.dailyContrib, decimals: 1)} 分'
                  '（该课期末不占比例）。';
      case GeGoalStatus.impossible:
        resultColor = scheme.error;
        headline = hasFinal
            ? '上限仅 ${geFmt(need.maxTotal, decimals: 1)} 分，无法达到 ${geFmt(goal)}'
            : '平时全部做满也仅 ${geFmt(need.maxTotal, decimals: 1)} 分';
        detail = hasFinal
            ? '即使期末 100 分、剩余平时分项全部做满，总评最高也只有 '
                  '${geFmt(need.maxTotal, decimals: 1)} 分。'
            : '平时剩余分项全部做满后总评最高 '
                  '${geFmt(need.maxTotal, decimals: 1)} 分（该课期末不占比例）。';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tint(context, resultColor, 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resultColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: resultColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
