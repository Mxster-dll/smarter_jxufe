import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_content_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_exam_screen.dart';

/// 章节地图:展示本章全部线索,点击进入内容页;底部为闯关入口状态。
class TsgxsChapterScreen extends ConsumerWidget {
  final String chapterId;

  const TsgxsChapterScreen({super.key, required this.chapterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(tsgxsChapterProvider(chapterId));
    final visited =
        ref.watch(tsgxsVisitedStoreProvider).valueOrNull?.load() ??
        const <String>{};
    // 章节序号与上一章:未解锁章服务端不下发标题/地图,靠章节列表定位。
    final chapters =
        ref.watch(tsgxsChaptersProvider).valueOrNull ?? const <TsgxsChapter>[];
    final index = chapters.indexWhere((c) => c.id == chapterId);
    final loaded = async.valueOrNull;
    final headTitle = (loaded != null && loaded.title.isNotEmpty)
        ? loaded.title
        : (index >= 0 ? chapters[index].displayTitle(index) : '章节地图');

    return Scaffold(
      appBar: AppBar(title: Text(headTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is TsgxsAccessDeniedException
            ? _lockedView(context, ref, chapters, index)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: scheme.error),
                      const SizedBox(height: 10),
                      Text(
                        '$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: scheme.error),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () =>
                            ref.invalidate(tsgxsChapterProvider(chapterId)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
        data: (chapter) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // 后门模式:不显示线索卡片(用户裁定),只留一条「自动补全并答题」入口。
            if (ref.watch(tsgxsExamPrefsProvider).isBackdoor)
              _backdoorHeader(context, chapter)
            else ...[
              _progressHeader(context, chapter, visited),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  for (var i = 0; i < chapter.nodes.length; i++)
                    _nodeCard(context, ref, chapter.nodes[i], i, visited),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _examRow(context, ref, chapter),
          ],
        ),
      ),
    );
  }

  /// 未解锁章视图(顺序解锁):说明解锁条件并提供「去上一章」。
  Widget _lockedView(
    BuildContext context,
    WidgetRef ref,
    List<TsgxsChapter> chapters,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final prev = index > 0 ? chapters[index - 1] : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 38, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text(
              '本章尚未解锁',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              prev == null
                  ? '入馆教育按章节顺序解锁:请先完成前一章的线索学习,并通过其闯关考试。'
                  : '入馆教育按章节顺序解锁:需先学完「${prev.displayTitle(index - 1)}」'
                        '的全部线索,并通过该章的闯关考试,本章地图才会开放。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (prev != null) ...[
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => TsgxsChapterScreen(chapterId: prev.id),
                      ),
                    ),
                    child: const Text('去上一章'),
                  ),
                  const SizedBox(width: 10),
                ],
                FilledButton.tonal(
                  onPressed: () {
                    ref.invalidate(tsgxsChaptersProvider);
                    ref.invalidate(tsgxsChapterProvider(chapterId));
                  },
                  child: const Text('重新检查'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressHeader(
    BuildContext context,
    TsgxsChapter chapter,
    Set<String> visited,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final localVisited = chapter.nodes
        .where((n) => visited.contains(n.id))
        .length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.explore_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              chapter.isVisitAll
                  ? '本章线索已全部学习完成,可以开始闯关答题'
                  : '点击每个线索完成学习;全部线索学完后才能开始闯关',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$localVisited/${chapter.nodes.length}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 后门模式下的章节头:不展示线索卡片(用户裁定),只留一条自动补全入口。
  Widget _backdoorHeader(BuildContext context, TsgxsChapter chapter) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '后门模式:已隐藏线索卡片',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${chapter.nodes.length} 条线索',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点「通过此章节」即可:App 会自动补全本章线索(服务端据此放行答题)→ '
            '自动逐题提交收集正确答案,失败自动重新开考继续,直到本章通过。\n'
            '答题模式在「设置 → 入馆教育」切换。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _confirmPass(context, chapter),
            icon: const Icon(Icons.rocket_launch_outlined, size: 16),
            label: const Text('通过此章节'),
          ),
        ],
      ),
    );
  }

  /// 后门卡片主按钮「通过此章节」:确认后进入答题页并自动开跑一键通过流程。
  Future<void> _confirmPass(BuildContext context, TsgxsChapter chapter) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.rocket_launch_outlined),
        title: const Text('通过此章节'),
        content: const Text(
          'App 会自动:逐个打开本章线索(服务端据此放行答题)→ 自动逐题提交并收集正确答案;'
          '若被判「本章闯关失败」会自动重新开考继续,直到本章通过。\n\n'
          '过程会消耗本章的答题机会,请确认。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始通过'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TsgxsExamScreen(
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          autoPass: true,
        ),
      ),
    );
  }

  Widget _nodeCard(
    BuildContext context,
    WidgetRef ref,
    TsgxsNode node,
    int index,
    Set<String> visited,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final done = visited.contains(node.id);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TsgxsContentScreen(nodeId: node.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Image.network(
                    'http://tsgxs.jxufe.cn${node.imageUrl}',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.image_not_supported_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 13,
                    color: done ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      node.name ?? '线索 ${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: done ? scheme.primary : null,
                      ),
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

  Widget _examRow(BuildContext context, WidgetRef ref, TsgxsChapter chapter) {
    final scheme = Theme.of(context).colorScheme;
    final examAsync = ref.watch(tsgxsExamStatusProvider(chapter.id));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: examAsync.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '考试状态获取失败:$e',
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _rebuildSession(context, ref),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新建立会话'),
            ),
          ],
        ),
        data: (status) {
          final passed = status.state == TsgxsExamState.passed;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    passed ? Icons.verified_outlined : Icons.flag_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      passed
                          ? '本章考试已通过'
                          : (chapter.canStartExam
                                ? '可以开始闯关答题'
                                : (status.message.isNotEmpty
                                      ? status.message
                                      : '完成全部线索后可开始答题')),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _openExam(context, ref, passed, chapter),
                      child: Text(passed ? '查看考试状态' : '开始闯关'),
                    ),
                  ),
                  if (passed && status.nextChapterId != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => TsgxsChapterScreen(
                              chapterId: status.nextChapterId!,
                            ),
                          ),
                        ),
                        child: const Text('下一章'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 打开答题页。模式由设置页决定(本页不再提供切换入口):
  /// - **公共模式**:线索未学完时只提示(服务端同样不允许开考),不代做;
  /// - **后门模式**:直接进答题页 —— 那里会自动补全线索(必要时)后开考。
  Future<void> _openExam(
    BuildContext context,
    WidgetRef ref,
    bool passed,
    TsgxsChapter chapter,
  ) async {
    if (!passed && !chapter.canStartExam) {
      if (!ref.read(tsgxsExamPrefsProvider).isBackdoor) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.menu_book_outlined),
            title: const Text('还不能开始答题'),
            content: const Text(
              '本章线索尚未全部学完。请先回到章节地图,逐个点开线索完成学习,'
              '全部学完后「开始闯关」按钮才会生效。\n\n'
              '若想由 App 代劳(自动补全线索 + 题库/探底),请到「设置 → 入馆教育」'
              '把答题模式切到后门模式。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TsgxsExamScreen(chapterId: chapter.id, chapterTitle: chapter.title),
      ),
    );
  }

  /// 强制重走统一认证链,重建 tsgxs 会话。
  ///
  /// 缺 `uid` 的匿名 Cookie(旧版本误存、或被顶下线)会让所有需要登录的
  /// 接口 302 到 `/web/user/logout`,而首页/章节页仍能 200 —— 此时点此按钮
  /// 清缓存后重新换取即可自愈,无需退出登录。
  static Future<void> _rebuildSession(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final account = ref.read(currentAccountProvider);
    try {
      final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
      await repo.clearSessionCookie(account);
      await repo.refreshSessionCookie(account);
      ref.invalidate(tsgxsExamStatusProvider);
      ref.invalidate(tsgxsChapterProvider);
      ref.invalidate(tsgxsHomeProvider);
      ref.invalidate(tsgxsGradesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('已重新建立会话')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重建会话失败:$e')));
    }
  }
}
