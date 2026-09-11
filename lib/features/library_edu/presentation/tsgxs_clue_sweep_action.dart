import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_clue_sweep.dart';

/// 后门模式共用动作:逐节点「打开」本章线索,让服务端记账。
///
/// 答题页(自动 / 手动)与章节页拦截弹窗共用本函数,避免两处各写一套编排;
/// 顺带把节点写进本地已浏览记录(章节地图的勾选状态)、并刷新章节相关 provider。
/// 异常直接抛出,由调用方决定怎么提示。
Future<TsgxsClueSweepResult> runClueSweep(
  WidgetRef ref, {
  required String chapterId,
  void Function(int done, int total, String nodeId)? onProgress,
}) async {
  final repo = await ref.read(tsgxsRepositoryProvider.future);
  final account = ref.read(currentAccountProvider);
  final themeId = await ref.read(tsgxsThemeIdProvider.future);
  final store = await ref.read(tsgxsVisitedStoreProvider.future);
  final result = await repo.sweepClues(
    account,
    chapterId: chapterId,
    themeId: themeId,
    onNodeFetched: (done, total, nodeId) {
      unawaited(store.markVisited(nodeId));
      onProgress?.call(done, total, nodeId);
    },
  );
  ref.invalidate(tsgxsChapterProvider(chapterId));
  ref.invalidate(tsgxsChaptersProvider);
  ref.invalidate(tsgxsExamStatusProvider(chapterId));
  ref.invalidate(tsgxsHomeProvider);
  return result;
}
