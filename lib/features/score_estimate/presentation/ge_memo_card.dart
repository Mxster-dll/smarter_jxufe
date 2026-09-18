/// 分数估计 · 课程备忘录界面：详情页「备忘录」卡 + 大图查看器 + 取图弹层，
/// 以及列表页的「有备忘录」小图标。
///
/// 交互口径：**点击**一律用 `InkWell` / `GestureDetector`（触摸可用），
/// hover 只做增强；删除图片必须过确认框（`geConfirmDelete`）。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design/app_theme.dart';
import '../../../design/feature_palette.dart';
import '../data/ge_memo_importer.dart';
import '../domain/ge_memo.dart';
import 'ge_common.dart';

/// 缩略图边长。
const double geMemoThumbSize = 84;

/// 列表页「有备忘录」小图标（空备忘录 → 不占位）。
class GeMemoBadge extends StatelessWidget {
  final GeMemo memo;
  final double size;

  const GeMemoBadge({super.key, required this.memo, this.size = 15});

  @override
  Widget build(BuildContext context) {
    final summary = geMemoSummary(memo);
    if (summary.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: summary,
      child: Icon(
        memo.hasImages
            ? Icons.photo_library_outlined
            : Icons.sticky_note_2_outlined,
        size: size,
        color: fp(context).cardAccent.withValues(alpha: 0.9),
      ),
    );
  }
}

/// 取图来源图标。
IconData geMemoPickIcon(GeMemoPickSource source) => switch (source) {
  GeMemoPickSource.gallery => Icons.photo_library_outlined,
  GeMemoPickSource.camera => Icons.photo_camera_outlined,
  GeMemoPickSource.files => Icons.folder_open_outlined,
};

/// 取图弹层（相册 / 拍照 / 文件多选）；取消 → null。
Future<GeMemoPickSource?> showGeMemoSourceSheet(
  BuildContext context, {
  required bool mobile,
  int remainingSlots = geMemoMaxImages,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<GeMemoPickSource>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              '添加图片',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              remainingSlots >= geMemoMaxImages
                  ? '最多 $geMemoMaxImages 张，导入时会压到最长边 $geMemoMaxEdge px。'
                  : '还能添加 $remainingSlots 张，导入时会压到最长边 $geMemoMaxEdge px。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          for (final source in geMemoPickSources(mobile: mobile))
            ListTile(
              leading: Icon(
                geMemoPickIcon(source),
                color: fp(context).cardAccent,
              ),
              title: Text(geMemoPickLabel(source, mobile: mobile)),
              subtitle: Text(
                geMemoPickHint(source, mobile: mobile),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, source),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 详情页「备忘录」卡：一段文字 + 图片网格。
///
/// 文字改动即时回调（父级 `_mutate` 写库，与页面其它输入一致）；
/// 图片的选图/落盘由父级编排（[onPickImages]），本组件只负责界面与确认框。
class GeMemoCard extends StatefulWidget {
  final GeMemo memo;

  /// 文件名 → 绝对路径（null = 文件缺失 → 占位图）。
  final String? Function(GeMemoImage image) resolvePath;

  final ValueChanged<GeMemo> onChanged;
  final Future<void> Function(GeMemoPickSource source) onPickImages;

  /// 删除一张图片（确认框已在卡片内弹过）。
  final Future<void> Function(GeMemoImage image) onRemoveImage;

  /// 正在导入（禁用添加入口 + 显示进度）。
  final bool busy;

  /// 移动端（决定取图弹层里是否出现「拍照」）。
  final bool mobile;

  const GeMemoCard({
    super.key,
    required this.memo,
    required this.resolvePath,
    required this.onChanged,
    required this.onPickImages,
    required this.onRemoveImage,
    this.busy = false,
    this.mobile = false,
  });

  @override
  State<GeMemoCard> createState() => _GeMemoCardState();
}

class _GeMemoCardState extends State<GeMemoCard> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.memo.text);
  }

  @override
  void didUpdateWidget(GeMemoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了文字（切换课程 / 清空）才回写，避免打断正在输入的光标。
    if (widget.memo.text != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.memo.text,
        selection: TextSelection.collapsed(offset: widget.memo.text.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _openSourceSheet() async {
    final remaining = widget.memo.remainingSlots;
    if (remaining <= 0) return;
    final source = await showGeMemoSourceSheet(
      context,
      mobile: widget.mobile,
      remainingSlots: remaining,
    );
    if (source == null || !mounted) return;
    await widget.onPickImages(source);
  }

  Future<void> _confirmRemove(GeMemoImage image) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除这张图片？',
      message: '图片文件会从应用私有目录里删除，无法恢复。',
    );
    if (!ok || !mounted) return;
    await widget.onRemoveImage(image);
  }

  Future<void> _openViewer(int index) async {
    final images = widget.memo.images;
    if (index < 0 || index >= images.length) return;
    await showGeMemoViewer(
      context,
      images: images,
      initialIndex: index,
      resolvePath: widget.resolvePath,
      onDelete: widget.onRemoveImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final memo = widget.memo;
    final sizeText = geMemoSizeText(memo.totalBytes);
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
              text: '备忘录',
              trailing: Text(
                memo.imageCount == 0
                    ? '还没有图片'
                    : '${memo.imageCount}/$geMemoMaxImages 张'
                          '${sizeText.isEmpty ? '' : ' · $sizeText'}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '例如：作业要求、考试范围、老师联系方式、复习要点…',
                hintStyle: TextStyle(fontSize: 13),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  widget.onChanged(memo.copyWith(text: value)),
            ),
            const SizedBox(height: 12),
            if (memo.hasImages)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < memo.images.length; i++)
                    _thumb(memo.images[i], i),
                ],
              )
            else
              Text(
                '还没有图片。作业要求截图、板书照片、老师发的通知都可以存进来。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.busy || memo.isFull
                      ? null
                      : _openSourceSheet,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('添加图片'),
                ),
                const SizedBox(width: 10),
                if (widget.busy) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在导入…',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (memo.isFull)
                  Expanded(
                    child: Text(
                      '已达 $geMemoMaxImages 张上限，删掉一些再加。',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.caution(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '图片压到最长边 $geMemoMaxEdge px 后存进应用私有目录，'
              '单张导入上限 ${geMemoSizeText(geMemoImportMaxBytes)}；'
              '删除原图不影响这里。',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 缩略图（缺文件 / 解码失败 → 占位图）。
  Widget _thumb(GeMemoImage image, int index) {
    final path = widget.resolvePath(image);
    return SizedBox(
      width: geMemoThumbSize,
      height: geMemoThumbSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openViewer(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: path == null
                    ? _missingThumb(context)
                    : Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _missingThumb(context),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _confirmRemove(image),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingThumb(BuildContext context) => ColoredBox(
    color: AppColors.fillStronger(context),
    child: Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 22,
        color: AppColors.textMuted(context),
      ),
    ),
  );
}

/// 大图查看器（可缩放、左右翻页、删除）。
Future<void> showGeMemoViewer(
  BuildContext context, {
  required List<GeMemoImage> images,
  int initialIndex = 0,
  required String? Function(GeMemoImage image) resolvePath,
  Future<void> Function(GeMemoImage image)? onDelete,
}) {
  if (images.isEmpty) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _GeMemoViewerScreen(
        images: images,
        initialIndex: initialIndex.clamp(0, images.length - 1),
        resolvePath: resolvePath,
        onDelete: onDelete,
      ),
    ),
  );
}

class _GeMemoViewerScreen extends StatefulWidget {
  final List<GeMemoImage> images;
  final int initialIndex;
  final String? Function(GeMemoImage image) resolvePath;
  final Future<void> Function(GeMemoImage image)? onDelete;

  const _GeMemoViewerScreen({
    required this.images,
    required this.initialIndex,
    required this.resolvePath,
    this.onDelete,
  });

  @override
  State<_GeMemoViewerScreen> createState() => _GeMemoViewerScreenState();
}

class _GeMemoViewerScreenState extends State<_GeMemoViewerScreen> {
  late final PageController _pageCtrl;
  late List<GeMemoImage> _images;
  late int _index;

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.images);
    _index = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _images.isEmpty) return;
    final image = _images[_index];
    final ok = await geConfirmDelete(
      context,
      title: '删除这张图片？',
      message: '图片文件会从应用私有目录里删除，无法恢复。',
    );
    if (!ok || !mounted) return;
    await onDelete(image);
    if (!mounted) return;
    final rest = [
      for (final x in _images)
        if (x.fileName != image.fileName) x,
    ];
    if (rest.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final next = _index >= rest.length ? rest.length - 1 : _index;
    setState(() {
      _images = rest;
      _index = next;
    });
    // PageView 的页数变了，跳回同一下标（内容已变）。
    _pageCtrl.jumpToPage(next);
  }

  @override
  Widget build(BuildContext context) {
    final image = _images.isEmpty ? null : _images[_index];
    final caption = image == null
        ? ''
        : [
            if (image.pixelText.isNotEmpty) image.pixelText,
            if (image.sizeText.isNotEmpty) image.sizeText,
          ].join(' · ');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${_images.length}'
          '${caption.isEmpty ? '' : '  ·  $caption'}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: '删除这张图片',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _images.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: _pageCtrl,
              itemCount: _images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final p = widget.resolvePath(_images[i]);
                if (p == null) {
                  return const Center(
                    child: Text(
                      '图片文件已丢失',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.file(File(p), fit: BoxFit.contain),
                  ),
                );
              },
            ),
    );
  }
}
