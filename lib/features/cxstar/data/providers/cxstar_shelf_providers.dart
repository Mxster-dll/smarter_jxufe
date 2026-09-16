/// 畅想之星书架 provider 链（分类字典 / 热门检索词）。
///
/// 书架与阅读器共用同一个**个人会话上下文**（[cxstarReaderContextProvider]）：
/// 校园网 IP 免密是全校公用账号，用它浏览得到的是公用藏书口径，
/// 与个人阅读记录对不上，故书架同样只接受统一身份认证 / 手工令牌。
/// 书单分页与检索由页面自己维护（无限滚动），不放进 provider 缓存。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_shelf.dart';

/// 分类字典（中图法 / 学科 / 院系）。
final cxstarShelfCategoriesProvider =
    FutureProvider<CxstarShelfCategories>((ref) async {
      final context = await ref.watch(cxstarReaderContextProvider.future);
      return ref
          .watch(cxstarRemoteDataSourceProvider)
          .fetchShelfCategories(context.token, pinst: context.pinst);
    });

/// 热门检索词（检索框为空时作推荐）。
final cxstarHotSearchProvider = FutureProvider<List<String>>((ref) async {
  final context = await ref.watch(cxstarReaderContextProvider.future);
  return ref
      .watch(cxstarRemoteDataSourceProvider)
      .fetchHotSearch(pinst: context.pinst);
});
