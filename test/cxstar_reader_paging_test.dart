/// 阅读器翻页守卫：页码、上一页/下一页按钮、拖拽三者必须同步。
///
/// 回归背景（用户 2026-09-14 实测报告）：「只能从第 1 页翻到第 2 页，内容变了，
/// 但底部页码还是 1，并且不能继续翻页，往回翻也不行」——根因是
/// `PageView.onPageChanged` 给的是**从 0 开始的索引**，而实现把它当页码用，
/// `_currentPage` 恒比真实页码小 1 → 页码显示旧值、`onNext` 恒跳第 2 页、
/// `onPrev` 恒禁用。本测试用假数据源驱动真实 `CxstarReaderScreen` 守住这条。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_reader_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_reader_screen.dart';

/// 假阅读数据源：5 页的书；**不取正文**（避免在单测里加载 pdfium），
/// 页内会显示「第 N 页加载失败」——正好可用来断言 PageView 真的翻了页。
class _FakeReaderDataSource extends CxstarReaderRemoteDataSource {
  _FakeReaderDataSource() : super(Dio());

  final List<int> reportedPages = [];

  @override
  Future<CxstarReadSession> fetchSession({
    required String token,
    required String bookId,
    required String pinst,
    int page = 1,
  }) async => const CxstarReadSession(
    title: '测试书',
    page: 1,
    totalPage: 5,
    trialPage: 1,
    logId: 'log-1',
    watermark: '',
    isbuy: true,
  );

  @override
  Future<Uint8List> fetchPagePdf({
    required String token,
    required String bookId,
    required String pinst,
    required int pageNo,
  }) async => throw const CxstarApiException('单测不取正文');

  @override
  Future<int?> fetchProgress({
    required String token,
    required String bookId,
  }) async => 1;

  @override
  Future<void> postProgress({
    required String token,
    required String bookId,
    required int page,
    String logId = '',
    int paragraph = 0,
    int charIndex = 0,
    int percent = 0,
  }) async {
    reportedPages.add(page);
  }
}

/// 假统计源：心跳里的「今日已计分钟」刷新不该联网。
class _FakeRemoteDataSource extends CxstarRemoteDataSource {
  _FakeRemoteDataSource() : super(Dio());

  @override
  Future<CxstarReadSummary> fetchSummary(String token) async =>
      throw const CxstarApiException('单测不联网');
}

Future<void> _pumpReader(WidgetTester tester, _FakeReaderDataSource ds) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cxstarReaderContextProvider.overrideWith(
          (ref) async => const CxstarReaderContext(token: 't', pinst: 'p'),
        ),
        cxstarReaderDataSourceProvider.overrideWithValue(ds),
        cxstarRemoteDataSourceProvider.overrideWithValue(
          _FakeRemoteDataSource(),
        ),
      ],
      child: const MaterialApp(
        home: CxstarReaderScreen(bookId: 'book-1', title: '测试书'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `find.byTooltip` 命中的是 Tooltip 自身，要断言按钮可用性得往上取 IconButton。
IconButton _bottomButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

void main() {
  testWidgets('拖拽翻页后页码同步（0 基索引 off-by-one 守卫）', (tester) async {
    final ds = _FakeReaderDataSource();
    await _pumpReader(tester, ds);

    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.textContaining('第 1 页'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    // 曾经的 bug：这里仍然显示 1 / 5（回调给的是索引 1）。
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.textContaining('第 2 页'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);

    // 往回拖也要能回去（`onPrev` 曾因 _currentPage 恒为 1 而被禁用）。
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('上一页 / 下一页按钮与页码一致', (tester) async {
    final ds = _FakeReaderDataSource();
    await _pumpReader(tester, ds);

    // 第 1 页时「上一页」应禁用。
    expect(_bottomButton(tester, '上一页').onPressed, isNull);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);

    // 翻过页后「上一页」必须可用（曾经恒为 null）。
    expect(_bottomButton(tester, '上一页').onPressed, isNotNull);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('4 / 5'), findsOneWidget);

    await tester.tap(find.byTooltip('上一页'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('末页「下一页」禁用', (tester) async {
    final ds = _FakeReaderDataSource();
    await _pumpReader(tester, ds);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
    }
    expect(find.text('5 / 5'), findsOneWidget);
    expect(_bottomButton(tester, '下一页').onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
