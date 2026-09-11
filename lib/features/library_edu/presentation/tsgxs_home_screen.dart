import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_batch_pass_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_chapter_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_grade_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_profile_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_ranking_screen.dart';
import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_edu_card.dart';

/// 新生入馆教育首页。
///
/// 结构（用户 2026-09-11 裁定）：
/// 1. 顶部 = 「阅读学分 · 第三部分 入馆教育」卡（进度条 + 学分平台侧信息 + 明细入口）；
/// 2. 成绩概览（后门模式下多一张「一键通过全部章节」）；
/// 3. 五章学习进度 + 排行榜 / 个人资料入口。
/// 底部原「诊断工具」入口与说明性提示文本已按要求删除。
class TsgxsHomeScreen extends ConsumerWidget {
  const TsgxsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final gradesAsync = ref.watch(tsgxsGradesProvider);
    final chaptersAsync = ref.watch(tsgxsChaptersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('新生入馆教育'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(tsgxsGradesProvider);
              ref.invalidate(tsgxsChaptersProvider);
              ref.invalidate(tsgxsHomeProvider);
              ref.invalidate(readCreditProgressProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tsgxsHomeProvider);
          ref.invalidate(tsgxsChaptersProvider);
          ref.invalidate(tsgxsGradesProvider);
          ref.invalidate(readCreditProgressProvider);
          await ref.read(tsgxsChaptersProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            const ReadCreditEduCard(),
            const SizedBox(height: 12),
            _buildGradeCard(context, ref, scheme, gradesAsync),
            // 一键通过全部章节:后门模式专属(模式切换只在设置页,见 tsgxs_prefs.dart)。
            if (ref.watch(tsgxsExamPrefsProvider).isBackdoor) ...[
              const SizedBox(height: 12),
              _buildBatchPassCard(context, scheme, chaptersAsync),
            ],
            const SizedBox(height: 20),
            _sectionTitle(context, '学习进度', Icons.map_outlined),
            const SizedBox(height: 10),
            ...chaptersAsync.when(
              loading: () => [_loadingCard(context)],
              error: (e, _) => [
                _errorCard(context, ref, '$e', () {
                  ref.invalidate(tsgxsHomeProvider);
                  ref.invalidate(tsgxsChaptersProvider);
                }),
              ],
              data: (chapters) => [
                for (var i = 0; i < chapters.length; i++) ...[
                  _chapterTile(context, ref, scheme, chapters[i], i, chapters),
                  const SizedBox(height: 10),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _sectionTitle(context, '更多', Icons.more_horiz),
            const SizedBox(height: 10),
            _entryTile(
              context,
              Icons.emoji_events_outlined,
              '排行榜',
              '全校闯关成绩排名',
              const TsgxsRankingScreen(),
            ),
            const SizedBox(height: 8),
            _entryTile(
              context,
              Icons.badge_outlined,
              '个人资料',
              '账号 / 姓名 / 学院信息',
              const TsgxsProfileScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradeCard(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    AsyncValue<List<TsgxsGrade>> gradesAsync,
  ) {
    final card = _whiteCard(
      context,
      child: gradesAsync.when(
        loading: () => const SizedBox(
          height: 108,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _inlineError(context, '$e', () {
          ref.invalidate(tsgxsGradesProvider);
        }),
        data: (grades) {
          if (grades.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '暂无成绩记录 · 完成五章闯关后自动生成',
                style: TextStyle(fontSize: 13),
              ),
            );
          }
          final g = grades.first;
          return Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.military_tech_outlined,
                  size: 24,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '入馆教育成绩',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          g.score,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '分',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '考试时间 ${g.examTime} · 通关用时 ${g.elapsed}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '成绩明细',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TsgxsGradeScreen()),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
        },
      ),
    );
    return card;
  }

  /// 「一键通过全部章节」入口卡:仅后门模式显示(模式切换只在设置页)。
  Widget _buildBatchPassCard(
    BuildContext context,
    ColorScheme scheme,
    AsyncValue<List<TsgxsChapter>> chaptersAsync,
  ) {
    final total = chaptersAsync.valueOrNull?.length ?? 0;
    return _whiteCard(
      context,
      child: Column(
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
                      '一键通过全部章节',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      total == 0
                          ? '正在获取章节列表…'
                          : '从第 1 章顺序跑到第 $total 章 · 每章最多 10 轮自动重试',
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
          const SizedBox(height: 8),
          Text(
            '自动补全线索 → 自动逐题探底 → 被判失败自动重开考;已通过的章节自动快进,'
            '某章 10 轮仍未通过就停下并报告。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: total == 0
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TsgxsBatchPassScreen(),
                    ),
                  ),
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('开始全部通过'),
          ),
        ],
      ),
    );
  }

  Widget _chapterTile(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    TsgxsChapter c,
    int index,
    List<TsgxsChapter> chapters,
  ) {
    final locked = c.locked;
    final status = locked
        ? '未解锁'
        : (c.canStartExam ? '可闯关' : (c.isVisitAll ? '学习中' : '待学习'));
    final accent = locked ? scheme.onSurfaceVariant : scheme.primary;
    final statusColor = locked
        ? scheme.onSurfaceVariant
        : (c.canStartExam ? scheme.primary : scheme.onSurfaceVariant);
    final subtitle = locked ? '未解锁 · 需先通过上一章的闯关考试' : '线索 ${c.nodes.length} 个';
    final prev = index > 0 ? chapters[index - 1] : null;
    final tile = _whiteCard(
      context,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (locked) {
            _showLockedHint(context, prev, index);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TsgxsChapterScreen(chapterId: c.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  locked ? Icons.lock_outline : Icons.menu_book_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayTitle(index),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                locked ? Icons.lock_outline : Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
    // 未解锁章整体降透明度(仍可点击,点击给出解锁指引)。
    return locked ? Opacity(opacity: 0.62, child: tile) : tile;
  }

  /// 未解锁章点击提示:说明锁定原因并提供「去上一章」。
  void _showLockedHint(BuildContext context, TsgxsChapter? prev, int index) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          prev == null
              ? '本章未解锁:请先完成前一章的线索学习与闯关'
              : '本章未解锁:需先通过「${prev.displayTitle(index - 1)}」的闯关考试',
        ),
        action: prev == null
            ? null
            : SnackBarAction(
                label: '去上一章',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TsgxsChapterScreen(chapterId: prev.id),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _entryTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return _whiteCard(
      context,
      padding: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: scheme.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
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

  Widget _whiteCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  Widget _loadingCard(BuildContext context) => _whiteCard(
    context,
    child: const SizedBox(
      height: 68,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  Widget _errorCard(
    BuildContext context,
    WidgetRef ref,
    String message,
    VoidCallback onRetry,
  ) {
    return _whiteCard(context, child: _inlineError(context, message, onRetry));
  }

  Widget _inlineError(
    BuildContext context,
    String message,
    VoidCallback onRetry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12.5, color: scheme.error),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
