import 'package:flutter/material.dart';

/// 校区地图条目：内置压缩版资源(官网四校区地图,生成脚本 tools/_campus_maps_build.py)。
class CampusMapEntry {
  final String name;
  final String asset;

  const CampusMapEntry(this.name, this.asset);
}

const _assetBase = 'assets/images/campus_maps/';

/// 官网「校区印象」四校区地图(含交通示意图),顺序与官网 footer gallery 一致。
const campusMapEntries = <CampusMapEntry>[
  CampusMapEntry('江西财经大学交通示意图', '${_assetBase}nt16_i1.jpg'),
  CampusMapEntry('蛟桥园北区', '${_assetBase}jqbq.jpg'),
  CampusMapEntry('蛟桥园南区', '${_assetBase}jqnq.jpg'),
  CampusMapEntry('麦庐园北区', '${_assetBase}mlbq.jpg'),
  CampusMapEntry('麦庐园南区', '${_assetBase}mlnq.jpg'),
  CampusMapEntry('枫林园校区', '${_assetBase}fly.jpg'),
  CampusMapEntry('青山园校区', '${_assetBase}qsxq.jpg'),
];

/// 校区地图：展示官网四校区地图与交通示意图。
/// 图片为官网静态资源,按需网络加载;点击缩略图进入全屏缩放查看。
class CampusMapScreen extends StatelessWidget {
  const CampusMapScreen({super.key});

  void _openViewer(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _MapViewer(
          initialIndex: index,
          entries: campusMapEntries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('校区地图'), centerTitle: true),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: campusMapEntries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final e = campusMapEntries[index];
          return Material(
            color: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openViewer(context, index),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.asset(e.asset, fit: BoxFit.cover),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Row(
                      children: [
                        Icon(Icons.zoom_in,
                            size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.name,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '点击查看大图',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 全屏地图查看器:左右滑动切换 + 双指/滚轮缩放。
class _MapViewer extends StatefulWidget {
  final int initialIndex;
  final List<CampusMapEntry> entries;

  const _MapViewer({required this.initialIndex, required this.entries});

  @override
  State<_MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<_MapViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.entries.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              final e = widget.entries[index];
              return InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.asset(e.asset, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                Text(
                  '${widget.entries[_current].name}'
                  ' (${_current + 1}/${widget.entries.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
