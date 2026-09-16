/// 畅想之星书架：分类浏览 + 检索 + 点书进原生阅读器。
///
/// 数据（`/api` 前缀，2026-09-14 实测）：
/// - 分类字典 `GET /api/system/categories?pinst=` → 中图法 / 学科 / 院系；
/// - 书单 `GET /api/categories/{id}/books?page&size&pinst&sortField=orderno
///   &sortType=DESC&keyword=&…` → `data[]` + `total`；`keyword` 即检索词
///   （服务端会给命中词包 `<em>`，域层已清洗）；
/// - 热门词 `GET /api/system/hotSearch?pinst=`。
///
/// 会话 = 阅读器同一份**个人**上下文（`cxstarReaderContextProvider`）：
/// 校园网 IP 免密是全校公用账号，浏览口径与个人阅读记录对不上，故不采用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_shelf_providers.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_shelf.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_reader_screen.dart';

class CxstarShelfScreen extends ConsumerStatefulWidget {
  const CxstarShelfScreen({super.key, this.initialKeyword = ''});

  /// 进入即检索的词（如从热门词跳转）。
  final String initialKeyword;

  @override
  ConsumerState<CxstarShelfScreen> createState() => _CxstarShelfScreenState();
}

class _CxstarShelfScreenState extends ConsumerState<CxstarShelfScreen> {
  static const int _pageSize = 20;
  static const double _pad = 14;
  static const double _gap = 12;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  CxstarReaderContext? _context;
  CxstarShelfCategories? _categories;

  String _groupKey = 'clc';
  CxstarCategoryNode? _root;
  CxstarCategoryNode? _child;

  final List<CxstarBook> _books = [];
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _searchMode = false;
  String _keyword = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword.trim();
    _searchMode = _keyword.isNotEmpty;
    _searchCtrl.text = _keyword;
    _scroll.addListener(_maybeLoadMore);
    _init();
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      _load(reset: false);
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await ref.read(cxstarReaderContextProvider.future);
      final categories = await ref
          .read(cxstarRemoteDataSourceProvider)
          .fetchShelfCategories(context.token, pinst: context.pinst);
      if (!mounted) return;
      _context = context;
      _categories = categories;
      final group =
          categories.groupOf(_groupKey) ??
          (categories.groups.isNotEmpty ? categories.groups.first : null);
      if (group != null) {
        _groupKey = group.key;
        _root = group.roots.isNotEmpty ? group.roots.first : null;
        _child = null;
      }
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _load({required bool reset}) async {
    final context = _context;
    if (context == null) return;
    if (reset) {
      setState(() {
        _page = 0;
        _books.clear();
        _exhausted = false;
        _loading = true;
        _loadingMore = false;
        _error = null;
      });
    } else {
      if (_loadingMore || _exhausted || _loading) return;
      setState(() => _loadingMore = true);
    }
    final nextPage = _page + 1;
    final categoryId = _keyword.isNotEmpty
        ? '0'
        : (_child?.id ?? _root?.id ?? '0');
    try {
      final result = await ref
          .read(cxstarRemoteDataSourceProvider)
          .fetchCategoryBooks(
            context.token,
            categoryId: categoryId,
            pinst: context.pinst,
            page: nextPage,
            size: _pageSize,
            keyword: _keyword,
          );
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _total = result.total;
        _books.addAll(result.books);
        _exhausted = result.books.isEmpty || !result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _selectGroup(CxstarCategoryGroup group) {
    setState(() {
      _groupKey = group.key;
      _root = group.roots.isNotEmpty ? group.roots.first : null;
      _child = null;
      _keyword = '';
      _searchCtrl.clear();
    });
    _load(reset: true);
  }

  void _selectRoot(CxstarCategoryNode node) {
    setState(() {
      _root = node;
      _child = null;
    });
    _load(reset: true);
  }

  void _selectChild(CxstarCategoryNode? node) {
    setState(() => _child = node);
    _load(reset: true);
  }

  void _submitSearch([String? raw]) {
    final text = (raw ?? _searchCtrl.text).trim();
    _searchCtrl.text = text;
    setState(() {
      _keyword = text;
      _searchMode = true;
    });
    if (text.isEmpty) {
      _load(reset: true);
      return;
    }
    _load(reset: true);
  }

  void _clearKeyword() {
    _searchCtrl.clear();
    setState(() => _keyword = '');
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _searchMode
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '书名 / 作者 / 关键词',
                  border: InputBorder.none,
                ),
                onSubmitted: _submitSearch,
              )
            : const Text('书架 · 畅想之星'),
        actions: [
          if (_searchMode) ...[
            IconButton(
              tooltip: '检索',
              icon: const Icon(Icons.search),
              onPressed: () => _submitSearch(),
            ),
            IconButton(
              tooltip: '退出检索',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _searchMode = false;
                  _keyword = '';
                  _searchCtrl.clear();
                });
                _load(reset: true);
              },
            ),
          ] else
            IconButton(
              tooltip: '检索',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searchMode = true),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_searchMode && _categories != null) _categoryBar(scheme),
          if (!(_searchMode && _keyword.isEmpty)) _resultBar(scheme),
          Expanded(child: _booksArea(scheme)),
        ],
      ),
    );
  }

  /// 分类选择区：体系（中图法 / 学科 / 院系）→ 根分类 → 子分类。
  Widget _categoryBar(ColorScheme scheme) {
    final group = _categories?.groupOf(_groupKey);
    final roots = group?.roots ?? const <CxstarCategoryNode>[];
    final children = _root?.children ?? const <CxstarCategoryNode>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories?.groups.length ?? 0,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final g = _categories!.groups[i];
                return _chip(
                  scheme,
                  label: '${g.label}（${g.roots.length}）',
                  selected: g.key == _groupKey,
                  onTap: () => _selectGroup(g),
                );
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: roots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _chip(
                scheme,
                label: roots[i].name,
                selected: _root?.id == roots[i].id,
                onTap: () => _selectRoot(roots[i]),
              ),
            ),
          ),
          if (children.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: children.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _chip(
                      scheme,
                      label: '全部',
                      selected: _child == null,
                      onTap: () => _selectChild(null),
                    );
                  }
                  final node = children[i - 1];
                  return _chip(
                    scheme,
                    label: node.name,
                    selected: _child?.id == node.id,
                    onTap: () => _selectChild(node),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    ColorScheme scheme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: selected
            ? FeaturePalette.cardAccent.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? FeaturePalette.cardAccent : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultBar(ColorScheme scheme) {
    final scope = _keyword.isEmpty
        ? (_child?.name ?? _root?.name ?? '全部图书')
        : '「$_keyword」';
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, 10, _pad, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$scope · 共 $_total 本',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (_keyword.isNotEmpty)
            TextButton.icon(
              onPressed: _clearKeyword,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('清除检索'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _booksArea(ColorScheme scheme) {
    if (_searchMode && _keyword.isEmpty) return _hotSearchPanel(scheme);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _books.isEmpty) return _errorView(scheme, _error!);
    if (_books.isEmpty) {
      return _hintView(
        scheme,
        icon: Icons.search_off,
        text: _keyword.isEmpty ? '该分类下暂无图书。' : '没有匹配的图书，换个关键词试试。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980
            ? 5
            : width >= 720
            ? 4
            : 3;
        final tileWidth = (width - _pad * 2 - _gap * (columns - 1)) / columns;
        return RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(_pad, 10, _pad, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: _gap,
                    mainAxisExtent: tileWidth * 1.34 + 50,
                  ),
                  itemCount: _books.length,
                  itemBuilder: (context, i) => _bookTile(scheme, _books[i]),
                ),
              ),
              SliverToBoxAdapter(child: _tail(scheme)),
            ],
          ),
        );
      },
    );
  }

  Widget _tail(ColorScheme scheme) {
    final text = _loadingMore
        ? '正在加载…'
        : _exhausted
        ? '已到底部 · 共 $_total 本'
        : '上滑加载更多';
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, 18, _pad, 34),
      child: Center(
        child: Text(
          text,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _bookTile(ColorScheme scheme, CxstarBook book) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: book.id.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CxstarReaderScreen(bookId: book.id, title: book.title),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _cover(scheme, book),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.author.isEmpty ? book.publishDate : book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _cover(ColorScheme scheme, CxstarBook book) {
    final fallback = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.menu_book_outlined,
        size: 26,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
    if (!book.hasCover) return fallback;
    return Image.network(
      book.cover,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }

  Widget _hotSearchPanel(ColorScheme scheme) {
    final hotAsync = ref.watch(cxstarHotSearchProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(_pad, 14, _pad, 40),
      children: [
        Text(
          '热门检索',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        hotAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            '热门词获取失败：$error',
            style: TextStyle(fontSize: 11.5, color: scheme.error),
          ),
          data: (words) => words.isEmpty
              ? Text(
                  '暂无热门词，直接输入关键词检索即可。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final word in words)
                      _chip(
                        scheme,
                        label: word,
                        selected: false,
                        onTap: () => _submitSearch(word),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Text(
          '提示：按分类浏览请点右上角「退出检索」。书架与阅读器共用个人会话，'
          '在校园网内会自动 IP 免密，但个人进度需先「使用统一身份认证登录」。',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _hintView(
    ColorScheme scheme, {
    required IconData icon,
    required String text,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(ColorScheme scheme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 34, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
