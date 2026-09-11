import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';

part 'student_info_box_provider.g.dart';

/// 学籍缓存 box（**按账号隔离**，见 `core/storage/account_scoped_box.dart`）。
///
/// 以前是全校唯一的单键 `studentInfo`，切换账号会读到上一个账号的姓名、
/// 学院、专业（进而影响培养方案学分与军训角标判定）。
@Riverpod(keepAlive: true)
Future<Box<String>> studentInfoBox(StudentInfoBoxRef ref) => openAccountScopedBox(
  'studentInfo',
  ref.watch(currentAccountProvider),
);
