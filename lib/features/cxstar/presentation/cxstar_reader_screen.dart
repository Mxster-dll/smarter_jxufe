/// 畅想之星「经典阅读」App 内阅读器（原生渲染单页 PDF）。
///
/// 为什么用原生渲染而不是内嵌网页:每页正文是**单页 AES-128 加密 PDF**，
/// 口令 = `md5('<bookId>-<pageno>')`（逆向所得，见 [cxstarPdfPassword]），
/// 因此可以直接用 pdfrx（pdfium）解密渲染，无需 WebView 依赖。
///
/// 阅读时长如何计入（用户硬要求，2026-09-14 实测）:
/// - 时长由**服务端**按在线阅读行为累计，客户端不上报时长；
/// - 取正文（`pdfContent`）与读会话（`/read`）都会触发入账，
///   实测「取 1 页后空闲 120s」与「仅每 30s 调一次 `/read`」都各 +1 分钟；
/// - 因此本页在**前台停留期间每 60 秒发一次 `/read` 心跳**（轻量 JSON，
///   不重复拉正文），并在翻页时上报续读位；离开页面即停心跳。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';

/// 心跳间隔（实测该间隔可持续入账）。
const Duration cxstarReaderHeartbeat = Duration(seconds: 60);

/// 翻页后上报续读位的防抖时长。
const Duration cxstarReaderProgressDebounce = Duration(seconds: 2);

class CxstarReaderScreen extends ConsumerStatefulWidget {
  const CxstarReaderScreen({super.key, required this.bookId, this.title = ''});

  final String bookId;
  final String title;

  @override
  ConsumerState<CxstarReaderScreen> createState() => _CxstarReaderScreenState();
}

class _CxstarReaderScreenState extends ConsumerState<CxstarReaderScreen>
    with WidgetsBindingObserver {
  PageController? _controller;
  CxstarReaderContext? _context;
  CxstarReadSession? _session;
  String? _error;
  bool _loading = true;
  int _currentPage = 1;
  int _totalPage = 0;
  int? _todayMinutes;

  /// 最近一次「今日已计分钟」取回的时刻（底部栏显示，让用户看到确实在刷）。
  DateTime? _todayUpdatedAt;

  /// 当前页是否处于放大态：放大时把 `PageView` 的翻页手势关掉，
  /// 让 `InteractiveViewer` 独占拖拽（两者手势会互相抢）。
  bool _zoomed = false;

  Timer? _heartbeat;
  Timer? _progressDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _progressDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只在读屏在前台时计时:切后台就停心跳（服务端按阅读行为累计，不需要空转）。
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      unawaited(_ping());
    } else {
      _heartbeat?.cancel();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await ref.read(cxstarReaderContextProvider.future);
      final dataSource = ref.read(cxstarReaderDataSourceProvider);
      final session = await dataSource.fetchSession(
        token: context.token,
        bookId: widget.bookId,
        pinst: context.pinst,
      );
      final progress = await dataSource.fetchProgress(
        token: context.token,
        bookId: widget.bookId,
      );
      if (!mounted) return;
      final total = session.totalPage <= 0
          ? (progress ?? 1)
          : session.totalPage;
      final initial = (progress ?? 1).clamp(1, total <= 0 ? 1 : total);
      setState(() {
        _context = context;
        _session = session;
        _totalPage = total;
        _currentPage = initial;
        _controller = PageController(initialPage: initial - 1);
        _loading = false;
      });
      unawaited(_refreshTodayMinutes());
      _startHeartbeat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      cxstarReaderHeartbeat,
      (_) => unawaited(_ping()),
    );
  }

  /// 心跳:一次轻量 `/read`（服务端据此累计阅读时长）。
  Future<void> _ping() async {
    final context = _context;
    if (context == null || !mounted) return;
    try {
      await ref
          .read(cxstarReaderDataSourceProvider)
          .fetchSession(
            token: context.token,
            bookId: widget.bookId,
            pinst: context.pinst,
            page: _currentPage,
          );
      // 每次心跳（60 秒）都刷新一次「今日已计分钟」。
      //
      // 用户 2026-09-14 要求「阅读页的时长要每分钟更新 1 次」；此前每 5 次心跳
      // 才刷一次（5 分钟），看起来像根本不刷新。⚠ 平台侧统计是**批量结算**的
      // （几分钟不动、然后一次跳好几分钟），所以数值本身不一定每分钟都变，
      // 底部栏因此同时显示「更新于 HH:mm」，用来区分「没刷新」与「还没结算」。
      unawaited(_refreshTodayMinutes());
    } catch (_) {
      // 心跳失败不打扰阅读；下一次心跳或翻页会重试。
    }
  }

  Future<void> _refreshTodayMinutes() async {
    final context = _context;
    if (context == null) return;
    try {
      final summary = await ref
          .read(cxstarRemoteDataSourceProvider)
          .fetchSummary(context.token);
      if (!mounted) return;
      setState(() {
        _todayMinutes = summary.todayReadMinutes;
        _todayUpdatedAt = DateTime.now();
      });
    } catch (_) {
      // 统计刷新失败忽略。
    }
  }

  /// 翻页回调。
  ///
  /// ⚠️ `PageView.onPageChanged` 给的是**从 0 开始的索引，不是页码**。
  /// 早期直接 `_currentPage = page` 造成 off-by-one（用户 2026-09-14 实测报告
  /// 「只能从第 1 页翻到第 2 页，内容变了但底部页码还是 1，且翻不动、翻不回」）：
  /// `_currentPage` 恒比真实页码小 1 → 底部显示旧页码、`onNext` 恒
  /// `_jumpTo(2)` 停在原页、`onPrev` 的 `_currentPage > 1` 恒 false 而被禁用。
  void _onPageChanged(int index) {
    final page = index + 1;
    setState(() {
      _currentPage = page;
      _zoomed = false; // 换页即退出缩放，避免缩放态把翻页手势吃掉
    });
    _progressDebounce?.cancel();
    _progressDebounce = Timer(cxstarReaderProgressDebounce, () {
      unawaited(_reportProgress(page));
    });
  }

  Future<void> _reportProgress(int page) async {
    final context = _context;
    if (context == null) return;
    try {
      await ref
          .read(cxstarReaderDataSourceProvider)
          .postProgress(
            token: context.token,
            bookId: widget.bookId,
            page: page,
            logId: _session?.logId ?? '',
          );
    } catch (_) {
      // 进度上报失败不影响阅读。
    }
  }

  /// 跳到指定页码（**1 起**；按钮 / 目录 / 跳页框 / 方向键共用）。
  ///
  /// 不依赖 `onPageChanged` 回调更新状态：`jumpToPage` 在部分版本/平台上不派发
  /// 滚动通知，这里直接落状态，保证页码与上一页/下一页按钮立刻正确。
  void _jumpTo(int page) {
    final total = _totalPage <= 0 ? 1 : _totalPage;
    final target = page.clamp(1, total);
    final controller = _controller;
    if (controller == null) return;
    if (controller.hasClients) controller.jumpToPage(target - 1);
    setState(() {
      _currentPage = target;
      _zoomed = false;
    });
    _progressDebounce?.cancel();
    _progressDebounce = Timer(cxstarReaderProgressDebounce, () {
      unawaited(_reportProgress(target));
    });
  }

  /// 相对翻页（方向键 / PageUp / PageDown 用）。
  void _step(int delta) => _jumpTo(_currentPage + delta);

  Future<void> _showCatalog() async {
    if (_context == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final nodesAsync = ref.read(cxstarCatalogProvider(widget.bookId));
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (_, scrollController) => nodesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text('目录获取失败:$e'),
            ),
            data: (nodes) {
              final rows = <CxstarCatalogNode>[
                for (final n in nodes) ...[n, ...n.children],
              ];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('这本书没有可用目录，可用「跳页」直接定位。'),
                );
              }
              return ListView.builder(
                controller: scrollController,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final node = rows[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      node.page > 0 ? '第 ${node.page} 页' : '—',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    onTap: node.jumpable
                        ? () {
                            Navigator.of(sheetContext).pop();
                            _jumpTo(node.page);
                          }
                        : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showJumpDialog() async {
    final controller = TextEditingController(text: '$_currentPage');
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.find_in_page_outlined),
        title: const Text('跳转到页'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '页码（1 - $_totalPage）',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) =>
              Navigator.of(dialogContext).pop(int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(int.tryParse(controller.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (page != null) _jumpTo(page);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.title.isNotEmpty
        ? widget.title
        : (_session?.title.isNotEmpty ?? false)
        ? _session!.title
        : '在线阅读';

    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '目录',
            onPressed: _context == null
                ? null
                : () => unawaited(_showCatalog()),
            icon: const Icon(Icons.list_alt_outlined),
          ),
          IconButton(
            tooltip: '跳页',
            onPressed: _totalPage > 0
                ? () => unawaited(_showJumpDialog())
                : null,
            icon: const Icon(Icons.find_in_page_outlined),
          ),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 34, color: Colors.white70),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => unawaited(_bootstrap()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final context = _context;
    final controller = _controller;
    if (context == null || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return CallbackShortcuts(
      // 桌面端翻页：← → / PageUp / PageDown（鼠标拖拽与按钮同样可用）。
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: controller,
                    itemCount: _totalPage <= 0 ? 1 : _totalPage,
                    // 放大态把翻页手势让给 InteractiveViewer，否则两者互抢，
                    // 表现为拖不动 / 翻页乱跳。
                    physics: _zoomed
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    itemBuilder: (_, index) => _CxstarPageView(
                      key: ValueKey('cxstar-page-$index'),
                      bookId: widget.bookId,
                      pageNo: index + 1,
                      context: context,
                      pinst: context.pinst,
                      onZoomChanged: (zoomed) {
                        if (zoomed != _zoomed) {
                          setState(() => _zoomed = zoomed);
                        }
                      },
                    ),
                  ),
                  if ((_session?.watermark ?? '').isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Text(
                              _session!.watermark,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _BottomBar(
              page: _currentPage,
              totalPage: _totalPage,
              todayMinutes: _todayMinutes,
              todayUpdatedAt: _todayUpdatedAt,
              accent: scheme.primary,
              onPrev: _currentPage > 1 ? () => _step(-1) : null,
              onNext: _currentPage < _totalPage ? () => _step(1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单页阅读区:按需拉取该页（拉取本身即触发服务端计时），解密后原生渲染。
class _CxstarPageView extends ConsumerStatefulWidget {
  const _CxstarPageView({
    super.key,
    required this.bookId,
    required this.pageNo,
    required this.context,
    required this.pinst,
    this.onZoomChanged,
  });

  final String bookId;
  final int pageNo;
  final CxstarReaderContext context;
  final String pinst;

  /// 放大态变化时通知父级（父级据此开关 `PageView` 的翻页手势）。
  final ValueChanged<bool>? onZoomChanged;

  @override
  ConsumerState<_CxstarPageView> createState() => _CxstarPageViewState();
}

class _CxstarPageViewState extends ConsumerState<_CxstarPageView> {
  final TransformationController _transform = TransformationController();
  PdfDocument? _document;
  String? _error;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _transform.dispose();
    final document = _document;
    _document = null;
    unawaited(document?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _document = null;
    });
    try {
      final bytes = await ref
          .read(cxstarReaderDataSourceProvider)
          .fetchPagePdf(
            token: widget.context.token,
            bookId: widget.bookId,
            pinst: widget.pinst,
            pageNo: widget.pageNo,
          );
      final document = await _open(bytes);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<PdfDocument> _open(Uint8List bytes) async {
    // pdfrx 要先初始化才会设置 Pdfrx.getCacheDirectory / loadAsset，
    // 否则 openData 抛 `Bad state: Pdfrx getCacheDirectory is not set.`
    // （main.dart 已调用一次，这里兜底，函数本身幂等）。
    await pdfrxFlutterInitialize();
    final password = cxstarPdfPassword(widget.bookId, widget.pageNo);
    return PdfDocument.openData(
      bytes,
      sourceName: 'cxstar-${widget.bookId}-${widget.pageNo}',
      firstAttemptByEmptyPassword: false,
      passwordProvider: () async => password,
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 32,
                color: Colors.white70,
              ),
              const SizedBox(height: 10),
              Text(
                '第 ${widget.pageNo} 页加载失败\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => unawaited(_load()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试本页'),
              ),
            ],
          ),
        ),
      );
    }
    final document = _document;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 5,
      // 未放大时把水平手势让给 PageView 翻页;放大后才允许拖动查看。
      panEnabled: _zoomed,
      onInteractionUpdate: (_) {
        final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
        if (zoomed != _zoomed) {
          setState(() => _zoomed = zoomed);
          widget.onZoomChanged?.call(zoomed);
        }
      },
      child: PdfPageView(
        document: document,
        pageNumber: 1,
        backgroundColor: Colors.white,
        decoration: const BoxDecoration(color: Colors.white),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.totalPage,
    required this.todayMinutes,
    required this.accent,
    this.todayUpdatedAt,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final int totalPage;
  final int? todayMinutes;

  /// 最近一次统计取回时刻（每分钟随心跳刷新）。
  final DateTime? todayUpdatedAt;
  final Color accent;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// 「今日已计 X 分 · 15:04 更新」。
  ///
  /// 平台统计是批量结算的，数值可能几分钟不变；显示刷新时刻是为了让用户能分辨
  /// 「没有刷新」和「刷新了但平台还没结算」。
  String get _todayLabel {
    if (todayMinutes == null) return '计时中';
    final at = todayUpdatedAt;
    if (at == null) return '今日已计 $todayMinutes 分';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '今日已计 $todayMinutes 分 · $hh:$mm 更新';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F1F1F),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
              ),
              Text(
                totalPage > 0 ? '$page / $totalPage' : '$page',
                key: const Key('cxstar_reader_page_label'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
              ),
              const Spacer(),
              Icon(Icons.timer_outlined, size: 15, color: accent),
              const SizedBox(width: 5),
              Text(
                _todayLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
