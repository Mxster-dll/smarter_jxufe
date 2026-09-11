import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_exam_screen.dart';

/// 「一键通过全部章节」:从第 1 章顺序跑到最后一章。
///
/// 用户 2026-09-11 裁定:
/// - 入口 = 入馆教育首页的卡片(后门模式才显示);
/// - 单章反复失败时**每章重试 10 轮**(`TsgxsExamScreen.maxProbeRounds`),仍未通过就停下;
/// - 顺序锁(`/html/401.html`)决定后续章节必须先过前一章,所以**不跳过失败章节**。
///
/// 实现方式 = 逐章 `push` 答题页(`autoPass` + `autoPopOnPass`),由答题页自己跑
/// 「补全线索 → 自动探底 → 失败重开考」并把结果 `pop` 回来 —— **探底逻辑只有一份**
/// (在 `tsgxs_exam_screen.dart`),本页只负责接力、进度与汇总。
class TsgxsBatchPassScreen extends ConsumerStatefulWidget {
  const TsgxsBatchPassScreen({super.key});

  @override
  ConsumerState<TsgxsBatchPassScreen> createState() =>
      _TsgxsBatchPassScreenState();
}

/// 单章在批量流程里的状态。
enum _ChapterState { pending, running, passed, failed, skipped }

class _TsgxsBatchPassScreenState extends ConsumerState<TsgxsBatchPassScreen> {
  /// 本轮批量用到的章节快照(跑起来后不随 provider 刷新而错位)。
  List<TsgxsChapter> _chapters = const [];
  final Map<String, _ChapterState> _state = {};
  final List<String> _log = [];
  bool _running = false;

  bool get _isBackdoor => ref.read(tsgxsExamPrefsProvider).isBackdoor;

  @override
  void initState() {
    super.initState();
    // 章节列表可能已经在首页加载好;没有就自己拉一次。
    final cached = ref.read(tsgxsChaptersProvider).valueOrNull;
    if (cached != null && cached.isNotEmpty) {
      _chapters = cached;
    } else {
      ref
          .read(tsgxsChaptersProvider.future)
          .then((list) {
            if (!mounted) return;
            setState(() => _chapters = list);
          })
          .catchError((Object e) {
            if (!mounted) return;
            setState(() => _log.insert(0, '章节列表加载失败:$e'));
          });
    }
  }

  void _addLog(String line) {
    _log.insert(0, line);
    if (_log.length > 60) _log.removeLast();
  }

  /// 顺序跑完全部章节;任何一章未通过就停下(顺序锁会让后续章节必然 401)。
  Future<void> _runAll() async {
    if (_running) return;
    final chapters = _chapters;
    if (chapters.isEmpty) {
      _snack('章节列表还没加载好,请稍后重试');
      return;
    }
    if (!_isBackdoor) {
      _snack('当前不是后门模式:请到「设置 → 入馆教育」切换后再用本功能');
      return;
    }
    const rounds = 10;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.rocket_launch_outlined),
        title: const Text('一键通过全部章节'),
        content: Text(
          '将从第 1 章顺序跑到第 ${chapters.length} 章,每章自动:\n'
          '① 逐个打开本章线索(服务端据此放行答题);\n'
          '② 自动逐题提交,把服务端返回的正确答案存入本地题库;\n'
          '③ 被判「本章闯关失败」就自动重新开考继续,最多 $rounds 轮。\n\n'
          '任何一章 $rounds 轮后仍未通过就停下并报告(顺序锁下后续章节本来也进不去)。\n'
          '已通过的章节会自动快进,不重复消耗答题机会。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始全部通过'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _running = true;
      _log.clear();
      _state.clear();
      for (final c in chapters) {
        _state[c.id] = _ChapterState.pending;
      }
    });

    for (var i = 0; i < chapters.length; i++) {
      if (!mounted) return;
      final chapter = chapters[i];
      final title = chapter.displayTitle(i);
      setState(() => _state[chapter.id] = _ChapterState.running);
      _addLog('第 ${i + 1} 章 · $title:开始(补全线索 → 自动探底,最多 $rounds 轮)');

      final passed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TsgxsExamScreen(
            chapterId: chapter.id,
            chapterTitle: title,
            autoPass: true,
            autoPopOnPass: true,
            maxProbeRounds: rounds,
          ),
        ),
      );
      if (!mounted) return;

      if (passed == null) {
        // 用户中途返回(答题页被关掉)→ 无法判定结果,停止接力。
        setState(() {
          _state[chapter.id] = _ChapterState.skipped;
          _running = false;
        });
        _addLog('第 ${i + 1} 章 · $title:中途退出,批量流程停止(已通过的章节保留)');
        _refreshProviders();
        return;
      }

      setState(() {
        _state[chapter.id] = passed
            ? _ChapterState.passed
            : _ChapterState.failed;
      });
      if (passed) {
        _addLog('第 ${i + 1} 章 · $title:通过');
        _refreshProviders();
        continue;
      }

      setState(() => _running = false);
      _addLog(
        '第 ${i + 1} 章 · $title:未通过($rounds 轮后仍未过)→ 批量流程停止。'
        '可稍后再点「开始全部通过」续跑,题库已收集的正确答案会继续复用。',
      );
      _refreshProviders();
      return;
    }

    setState(() => _running = false);
    _addLog('全部 ${chapters.length} 章处理完毕');
    _refreshProviders();
  }

  void _refreshProviders() {
    ref.invalidate(tsgxsChaptersProvider);
    ref.invalidate(tsgxsHomeProvider);
    ref.invalidate(tsgxsGradesProvider);
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackdoor = ref.watch(tsgxsExamPrefsProvider).isBackdoor;
    final chapters = _chapters.isEmpty
        ? (ref.watch(tsgxsChaptersProvider).valueOrNull ??
              const <TsgxsChapter>[])
        : _chapters;
    final done = chapters
        .where((c) => _state[c.id] == _ChapterState.passed)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('一键通过全部章节')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _buildHeaderCard(context, scheme, chapters.length, done, isBackdoor),
          const SizedBox(height: 20),
          _sectionTitle(context, '章节进度', Icons.map_outlined),
          const SizedBox(height: 10),
          if (chapters.isEmpty)
            _card(
              context,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            for (var i = 0; i < chapters.length; i++) ...[
              _buildChapterRow(
                context,
                scheme,
                chapters[i].displayTitle(i),
                _state[chapters[i].id] ?? _ChapterState.pending,
              ),
              const SizedBox(height: 8),
            ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle(context, '运行记录', Icons.article_outlined),
            const SizedBox(height: 10),
            _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _log)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildNotice(context, scheme),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    ColorScheme scheme,
    int total,
    int done,
    bool isBackdoor,
  ) {
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.rocket_launch_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '从第 1 章顺序跑到最后',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      total == 0
                          ? '正在获取章节列表…'
                          : '共 $total 章 · 已通过 $done 章 · 每章最多 10 轮自动重试',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total > 0)
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              minHeight: 3,
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_running || total == 0) ? null : _runAll,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_outlined),
            label: Text(_running ? '正在逐章通过…' : '开始全部通过'),
          ),
          if (!isBackdoor) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '当前不是后门模式:请到「设置 → 入馆教育」切换后再用本功能。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChapterRow(
    BuildContext context,
    ColorScheme scheme,
    String title,
    _ChapterState state,
  ) {
    final (icon, color, label) = switch (state) {
      _ChapterState.passed => (
        Icons.check_circle,
        const Color(0xFF0F7B0F),
        '已通过',
      ),
      _ChapterState.failed => (Icons.error_outline, scheme.error, '未通过(已停止)'),
      _ChapterState.running => (Icons.sync, scheme.primary, '进行中…'),
      _ChapterState.skipped => (
        Icons.remove_circle_outline,
        scheme.onSurfaceVariant,
        '已中断',
      ),
      _ChapterState.pending => (
        Icons.radio_button_unchecked,
        scheme.onSurfaceVariant,
        '待处理',
      ),
    };
    return _card(
      context,
      Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '顺序锁:第 N 章的答题页在第 N-1 章通过前会返回 /html/401.html,'
              '所以本流程不跳过失败章节。每章的答题机会会被消耗,'
              '但探底收集到的正确答案存入本地题库(跨账号共享),重跑会越来越快。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(width: 3, height: 14, color: scheme.primary),
        const SizedBox(width: 8),
        Icon(icon, size: 15, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}
