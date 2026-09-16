/// 公共查询的「账号侧预填输入」provider。
///
/// 窄口径：页面只依赖它，不直接碰学籍仓库与「我的校区」偏好 store
/// （两者都要 `Hive.openBox`，在 widget 测试里会把错误同步抛进 `ref.read`）。
/// 测试用 `overrideWith` 给一个固定 profile 即可覆盖整条预填链路。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';

/// 学籍缓存 + 「我的校区」偏好 → 匹配用输入。
///
/// - 学籍走 `getCachedStudentInfo()`（**离线缓存，不发网络**）；取不到就留空串；
/// - 校区取 `MyCampus.label`（中文全称，教务校区选项同字面），不是 enum 的 `name`；
/// - 两项都取不到时返回 [PublicQueryAccountProfile.isEmpty] 的空对象，
///   调用方据此决定「不做任何预填」。
final publicQueryAccountProfileProvider =
    FutureProvider<PublicQueryAccountProfile>((ref) async {
      final campusStore = ref.watch(myCampusStoreProvider);
      try {
        await campusStore.ensureLoaded();
      } catch (_) {
        // 偏好读不到 / 存储不可用 → 当作「未设置」
      }
      StudentInfo? info;
      try {
        final repository = await ref.watch(studentInfoRepositoryProvider.future);
        info = repository.getCachedStudentInfo().fold((_) => null, (i) => i);
      } catch (_) {
        // 学籍取不到（未登录 / 尚未同步）→ 只保留「我的校区」能给出的部分
      }
      return PublicQueryAccountProfile(
        enrollYear: info?.enrollYear ?? '',
        college: info?.college ?? '',
        major: info?.major ?? '',
        className: info?.className ?? '',
        campusName: campusStore.campus?.label ?? '',
      );
    });
