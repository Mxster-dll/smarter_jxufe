import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';

part 'grades_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
GradesRemoteDataSource gradesRemoteDataSource(GradesRemoteDataSourceRef ref) {
  // 手动验证「成绩变更提示（diff 检测）」曾靠一个临时的假数据源（按调用次数返回
  // 固定 HTML）—— 它是**测试用件**，已从 lib\ 移出（不再随包发布）。
  // 需要时从 git 历史取回 `lib/debug/fake_grades_remote_datasource.dart`
  // （2026-10-08 之前），放进 `test/` 用，**不要**再往 lib\ 里放调试数据源。

  final dio = ref.watch(currentImsDioProvider);
  return GradesRemoteDataSource(dio);
}
