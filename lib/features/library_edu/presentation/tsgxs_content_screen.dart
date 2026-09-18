import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 学习内容页阅读器:正文为平台下发的图片,支持缩放与上一节/下一节导航。
class TsgxsContentScreen extends ConsumerStatefulWidget {
  final String nodeId;

  const TsgxsContentScreen({super.key, required this.nodeId});

  @override
  ConsumerState<TsgxsContentScreen> createState() => _TsgxsContentScreenState();
}

class _TsgxsContentScreenState extends ConsumerState<TsgxsContentScreen> {
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markVisited());
  }

  /// 记录本地已浏览(仅用于章节地图上的勾选标记)。
  Future<void> _markVisited() async {
    if (_marked) return;
    _marked = true;
    try {
      final store = await ref.read(tsgxsVisitedStoreProvider.future);
      await store.markVisited(widget.nodeId);
      ref.invalidate(tsgxsVisitedStoreProvider);
    } catch (_) {
      // 本地记录失败不影响阅读
    }
  }

  void _open(String nodeId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TsgxsContentScreen(nodeId: nodeId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(tsgxsContentProvider(widget.nodeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          async.valueOrNull?.title ?? '学习内容',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
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
                      ref.invalidate(tsgxsContentProvider(widget.nodeId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (content) => Column(
          children: [
            Expanded(
              child: content.imageUrls.isEmpty
                  ? Center(
                      child: Text(
                        '本节点暂无图文内容',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: content.imageUrls.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: InteractiveViewer(
                          maxScale: 5,
                          child: Image.network(
                            'http://tsgxs.jxufe.cn${content.imageUrls[i]}',
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              final total = progress.expectedTotalBytes;
                              return AspectRatio(
                                aspectRatio: 4 / 3,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: total == null
                                        ? null
                                        : progress.cumulativeBytesLoaded /
                                              total,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, _, _) => AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Center(
                                child: Text(
                                  '图片加载失败',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            _navBar(context, content),
          ],
        ),
      ),
    );
  }

  Widget _navBar(BuildContext context, TsgxsContent content) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.hairline(context, 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: content.prevNodeId == null
                    ? null
                    : () => _open(content.prevNodeId!),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('上一节'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: content.chapterId == null
                    ? null
                    : () => Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.grid_view_outlined, size: 16),
                label: const Text('返回地图'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: content.nextNodeId == null
                    ? null
                    : () => _open(content.nextNodeId!),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('下一节'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
