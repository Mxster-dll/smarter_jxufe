import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/campus_address/data/campus_map_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/data/providers/campus_map_providers.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_painter.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_style.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/my_campus_widgets.dart';

/// 一个校区的矢量地图条目：把「统一校区口径」[MyCampus] 接到渲染资源上。
///
/// [asset] = `assets/campus_map/<MyCampus.name>.json`，与生成脚本
/// `tool/jxufe_map/build_geometry.py` 的 `CAMPUS_KEYS` 一一对应；
/// [rasterAsset] = 官网原图（`campus_map_screen.dart` 的 `campusMapEntries` 那份），
/// 供卡片内的「矢量 / 官网」互切用。
class CampusVectorEntry {
  const CampusVectorEntry({
    required this.campus,
    required this.rasterAsset,
  });

  final MyCampus campus;

  /// 官网原图 asset。
  final String rasterAsset;

  /// 矢量数据 asset key。
  String get asset => 'assets/campus_map/${campus.name}.json';

  String get name => campus.label;

  /// 官网原图里属于本校区的条目名（蛟桥园 / 麦庐园各有南北两区两张图）。
  List<String> get rasterNames => campus.mapEntryNames;
}

/// 四校区矢量地图条目，顺序 = 学校地址列表的顺序（[MyCampus] 枚举顺序）。
const campusVectorEntries = <CampusVectorEntry>[
  CampusVectorEntry(
    campus: MyCampus.jiaoqiao,
    rasterAsset: 'assets/images/campus_maps/jqbq.jpg',
  ),
  CampusVectorEntry(
    campus: MyCampus.qingshan,
    rasterAsset: 'assets/images/campus_maps/qsxq.jpg',
  ),
  CampusVectorEntry(
    campus: MyCampus.mailu,
    rasterAsset: 'assets/images/campus_maps/mlbq.jpg',
  ),
  CampusVectorEntry(
    campus: MyCampus.fenglin,
    rasterAsset: 'assets/images/campus_maps/fly.jpg',
  ),
];

/// 四校区**矢量**地图面板（嵌在「校区地图」页里，自己不画 AppBar）。
///
/// 三件事：
/// 1. **切换校区**（顶部胶囊），默认选中「我的校区」（[myCampusStoreProvider]）；
/// 2. **两种风格**（浅色 / 深色）：页内可手动切，**没手选过时跟随 App 主题**；
/// 3. **两种底图**（矢量 / 官网原图）：矢量那个是 Flutter 原生绘制的。
///
/// 数据是随包 asset（不发网络），因此**不挂 `PageAutoRefresher`** ——
/// 没有会因为「回到本页 / 回前台」而变的东西，硬刷只会把用户的缩放位置重置掉。
class CampusVectorMapPane extends ConsumerStatefulWidget {
  const CampusVectorMapPane({super.key});

  @override
  ConsumerState<CampusVectorMapPane> createState() =>
      _CampusVectorMapPaneState();
}

class _CampusVectorMapPaneState extends ConsumerState<CampusVectorMapPane> {
  /// 当前查看的校区；`null` = 还没定（首次拿到「我的校区」后落一次）。
  MyCampus? _selected;

  /// 卡片内底图：false = 矢量，true = 官网原图。
  bool _showRaster = false;

  /// 递增即让地图视图回到「整图适配」。
  int _resetToken = 0;

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myCampusStoreProvider).campus;
    // 默认落在「我的校区」；没设置过就用第一个（蛟桥园）。
    final selected = _selected ?? mine ?? campusVectorEntries.first.campus;
    final store = ref.watch(campusMapStoreProvider);
    final kind = resolveCampusMapStyle(
      manual: store.style,
      platformBrightness: Theme.of(context).brightness,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        myCampusHint(
          context,
          mine: mine,
          pinnedNames: const [],
          // 本页是切换式（不是列表置顶式），换一句话说，免得「已置顶」对不上。
          note: mine == null
              ? '未设置我的校区 · 可在「设置」中指定，本页会默认显示该校区'
              : null,
        ),
        const SizedBox(height: 12),
        _campusSelector(selected, mine),
        const SizedBox(height: 12),
        _mapCard(selected, kind, store.followsTheme),
      ],
    );
  }

  // ---------------------------------------------------------------- 校区切换

  Widget _campusSelector(MyCampus selected, MyCampus? mine) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: campusVectorEntries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = campusVectorEntries[i];
          final on = e.campus == selected;
          final isMine = mine != null && e.campus == mine;
          return Material(
            color: on ? scheme.primary : scheme.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: on ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('campusMapTab_${e.campus.name}'),
              onTap: () => setState(() {
                _selected = e.campus;
                _resetToken++;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (isMine) ...[
                      Icon(
                        Icons.my_location,
                        size: 13,
                        color: on ? scheme.onPrimary : scheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      e.campus.shortLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- 地图卡片

  Widget _mapCard(MyCampus campus, CampusMapStyleKind kind, bool followsTheme) {
    final entry = campusVectorEntries.firstWhere((e) => e.campus == campus);
    final geometry = ref.watch(campusMapGeometryProvider(campus.name));

    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // 地图高度：宽屏 16:9、窄屏 4:3，但两端都夹住 ——
              // 太矮手机上点不准一栋楼，太高会把下面的说明挤出屏幕。
              final wide = c.maxWidth >= Breakpoints.wide;
              final h = wide
                  ? (c.maxWidth * 9 / 16).clamp(300.0, 520.0)
                  : (c.maxWidth * 3 / 4).clamp(260.0, 460.0);
              return SizedBox(
                height: h,
                width: double.infinity,
                child: _showRaster
                    ? _rasterView(entry)
                    : geometry.when(
                        data: (g) => CampusMapView(
                          key: ValueKey('vector_${g.id}'),
                          geometry: g,
                          style: kind.resolve(),
                          resetToken: _resetToken,
                        ),
                        loading: () => const AppLoadingState(compact: true),
                        error: (e, _) => AppErrorState(
                          error: e,
                          compact: true,
                          title: '这个校区的矢量图没读出来',
                          onRetry: () => ref.invalidate(
                            campusMapGeometryProvider(campus.name),
                          ),
                        ),
                      ),
              );
            },
          ),
          _cardFooter(entry, kind, followsTheme),
          // 说明放进**卡片内**：放在 ListView 下方时，卡片本身很高（260–520px），
          // 说明会落在视口外 → ListView 不布局它 → 用户看不到、测试也找不到。
          _footnote(campus, kind, followsTheme),
        ],
      ),
    );
  }

  /// 官网原图（矢量之前就在用的那份栅格资源）。
  Widget _rasterView(CampusVectorEntry entry) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerLow),
        InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.asset(entry.rasterAsset, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }

  Widget _cardFooter(
    CampusVectorEntry entry,
    CampusMapStyleKind kind,
    bool followsTheme,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _showRaster
                      ? '官网原图'
                          '${entry.rasterNames.length > 1 ? '（含南北两区）' : ''}'
                      : '矢量图 · 可缩放拖动、点建筑看名字',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 底图切换：矢量 / 官网原图。
          IconButton(
            key: const Key('campusMapRasterToggle'),
            tooltip: _showRaster ? '切到矢量图' : '切到官网原图',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(_showRaster ? Icons.polyline : Icons.image_outlined),
            onPressed: () => setState(() => _showRaster = !_showRaster),
          ),
          // 风格切换：浅色 / 深色。
          IconButton(
            key: const Key('campusMapStyleToggle'),
            tooltip: followsTheme
                ? '跟随系统「${kind.label}」· 点击固定为「${kind.other.label}」'
                : '当前固定「${kind.label}」· 点击切到「${kind.other.label}」',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(kind.icon),
            onPressed: () => _toggleStyle(kind),
          ),
          // 复位。
          IconButton(
            key: const Key('campusMapReset'),
            tooltip: '回到整图',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: () => setState(() => _resetToken++),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStyle(CampusMapStyleKind current) async {
    // ⚠ 用 `.notifier` 取实例：`ref.read(provider)` 只会在**没被 watch 过**时
    // 懒建一个实例 —— 那边的 `ensureLoaded()` 还没跑完，`toggle()` 里
    // `await ensureLoaded()` 之后仍要等真异步 IO，写盘会来不及。
    // 页面 `build` 已经 `ref.watch` 过本 provider，这里的 notifier 就是同一个实例。
    final store = ref.read(campusMapStoreProvider.notifier);
    final next = await store.toggle(current);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('地图风格：${next.label}（${next.hint}）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------- 底部说明

  Widget _footnote(
    MyCampus campus,
    CampusMapStyleKind kind,
    bool followsTheme,
  ) {
    final g = ref.watch(campusMapGeometryProvider(campus.name)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g != null && g.isSparse) ...[
            // 如实说明，而不是给一张看着像出错的空图（§30 的教训）。
            const FluentInfoBar(
              severity: FluentInfoSeverity.warning,
              message: 'OSM（开放街图）在这个校区只测了很少的楼，所以矢量图比较空 —— '
                  '不是加载失败。点右上角图片图标可看官网原图的完整布局。',
            ),
            const SizedBox(height: 8),
          ],
          if (g != null)
            Text(
              '${g.buildingCount} 栋建筑 · ${g.roads.length} 条路'
              '${g.labels.isEmpty ? '' : ' · ${g.labels.length} 个标注'}'
              '${g.attribution.isEmpty ? '' : ' · ${g.attribution}'}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 3),
          Text(
            '矢量图由 Flutter 原生绘制（不联网、不依赖任何地图 SDK）；'
            '风格「${kind.label}」${followsTheme ? '跟随系统' : '已手动固定'}。',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
