/// 畅想之星阅读器 provider 链（个人会话 + 单页正文）。
///
/// 阅读器**必须**用个人会话:校园网 IP 免密得到的是全校公用账号
/// `IP用户`，用它阅读会把进度与时长记到公用账号上（对个人学分无意义），
/// 因此这里只接受「统一身份认证」或「手工令牌」两档，取不到直接给引导文案。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_reader_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_book_report.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';

final cxstarReaderDataSourceProvider = Provider<CxstarReaderRemoteDataSource>(
  (ref) => CxstarReaderRemoteDataSource(ref.watch(cxstarDioProvider)),
);

/// 阅读器上下文:个人令牌 + 机构号（`pinst`）。
final cxstarReaderContextProvider = FutureProvider<CxstarReaderContext>((
  ref,
) async {
  final dataSource = ref.watch(cxstarRemoteDataSourceProvider);
  final account = ref.watch(currentAccountProvider);
  final failures = <String>[];

  Future<CxstarReaderContext?> tryToken(String token, String how) async {
    try {
      final user = await dataSource.fetchUser(token);
      if (user.isSharedIpAccount) {
        failures.add('$how 得到的是校园网公用账号，不能用于个人阅读');
        return null;
      }
      final pinst = user.schoolId.isEmpty ? cxstarJxufePinst : user.schoolId;
      return CxstarReaderContext(token: token, pinst: pinst);
    } on CxstarApiException catch (e) {
      failures.add('$how 不可用:$e');
      return null;
    }
  }

  // ① 统一身份认证（首选，24h，过期自动重换）。
  if (account.isNotEmpty) {
    try {
      final authRepository = await ref.watch(
        cxstarAuthRepositoryProvider.future,
      );
      final token = await authRepository.getSessionToken(account);
      if (token != null) {
        final context = await tryToken(token, '统一身份认证会话');
        if (context != null) return context;
      }
    } catch (e) {
      failures.add('统一身份认证换取失败:$e');
    }
  }

  // ② 手工令牌（高级回退）。
  final manual = await ref.watch(cxstarPersonalTokenProvider.future);
  if (manual != null) {
    final context = await tryToken(manual, '手工令牌');
    if (context != null) return context;
  }

  throw CxstarApiException(
    '在线阅读需要个人会话:请在「经典阅读 · 畅想之星」页点「使用统一身份认证登录」'
    '${failures.isEmpty ? '' : '（${failures.join('；')}）'}',
  );
});

/// 阅读会话（总页数 / 试读页 / 水印 / logId）。
final cxstarReadSessionProvider =
    FutureProvider.family<CxstarReadSession, String>((ref, bookId) async {
      final context = await ref.watch(cxstarReaderContextProvider.future);
      return ref
          .watch(cxstarReaderDataSourceProvider)
          .fetchSession(
            token: context.token,
            bookId: bookId,
            pinst: context.pinst,
          );
    });

/// 目录（章级，`page` 用于跳页）。
final cxstarCatalogProvider =
    FutureProvider.family<List<CxstarCatalogNode>, String>((ref, bookId) async {
      final context = await ref.watch(cxstarReaderContextProvider.future);
      return ref
          .watch(cxstarReaderDataSourceProvider)
          .fetchCatalog(token: context.token, bookId: bookId);
    });

/// 续读位（上次读到第几页；取不到为 null）。
final cxstarReadProgressProvider = FutureProvider.family<int?, String>((
  ref,
  bookId,
) async {
  final context = await ref.watch(cxstarReaderContextProvider.future);
  return ref
      .watch(cxstarReaderDataSourceProvider)
      .fetchProgress(token: context.token, bookId: bookId);
});

/// 逐书阅读报告（累计时长 / 阅读天数 / **读完时间**），阅读记录行内联展示。
///
/// 与阅读器同用**个人会话**（[cxstarReaderContextProvider] 拒收校园网公用账号）：
/// 公用账号是全校聚合，把它当个人逐书时长会严重高估。
/// 取不到时返回 null（记录行的报告行静默省略，不打扰阅读记录本身）。
final cxstarBookReportProvider =
    FutureProvider.family<CxstarBookReport?, String>((ref, bookId) async {
      if (bookId.isEmpty) return null;
      final context = await ref.watch(cxstarReaderContextProvider.future);
      return ref
          .watch(cxstarRemoteDataSourceProvider)
          .fetchBookReport(context.token, bookId);
    });
