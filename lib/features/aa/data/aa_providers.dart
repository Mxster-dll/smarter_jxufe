/// AA 算账 providers：账号隔离的本地存储 + 一次读全（成员 / 开销 / 结算）。
///
/// AA 是**纯本地**数据（没有教务接口），所以没有缓存型 `FutureProvider` 需要挂
/// `PageAutoRefresher`：页面只 watch [aaDataProvider]，任何写入之后
/// `ref.invalidate(aaDataProvider)` 即全页刷新。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/aa/data/aa_store.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_settlement.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_display_name_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';

/// AA 本地 box 的**基础**名（实际 box 按账号隔离 → `aa_<账号>`）。
const aaBoxName = 'aa';

/// AA 本地 box（**按账号隔离**：谁跟谁 AA 是私人账，不该跨账号串）。
///
/// 见 `core/storage/account_scoped_box.dart`。
final aaBoxProvider = FutureProvider<Box<String>>(
  (ref) => openAccountScopedBox(aaBoxName, ref.watch(currentAccountProvider)),
);

final aaStoreProvider = FutureProvider<AaStore>(
  (ref) async => AaStore(await ref.watch(aaBoxProvider.future)),
);

/// 页面唯一的数据源：成员 + 开销 + **结算结果**（结算在领域层算，界面层不重算）。
final aaDataProvider = FutureProvider<AaData>((ref) async {
  final store = await ref.watch(aaStoreProvider.future);
  final members = await store.loadMembers();
  final expenses = await store.loadExpenses();
  return AaData.of(members: members, expenses: expenses);
});

/// 「我自己」的**姓名 + 学号 + 班级** —— 「添加我自己」/「添加全部舍友」用。
///
/// 用户 2026-09-19 三轮：「允许添加自己」；五轮：「我希望成员可以显示学号和班级」。
///
/// 三个字段各有唯一来源，**都不发网络**：
/// - [AaSelfInfo.name] = 账号记录里的显示名（[currentAccountNameProvider] →
///   `Account.displayName`）：登录 / 启动 / 学籍页都用学籍姓名 `StudentInfo.name`
///   刷它（`login_viewmodel.dart:190`、`splash_screen.dart:175`、`account_screen.dart:344`），
///   所以它等价于「我的真名」；取不到再回落学籍缓存里的 `StudentInfo.name`。
/// - [AaSelfInfo.studentNo] = 学籍缓存里的学号（见 [aaStudentNoOf] 的取值序）。
/// - [AaSelfInfo.className] = 学籍缓存 `StudentInfo.className`（`<bjmc>`，如「25计算机2班」）。
///
/// 任何一个取不到 → 空串：界面层据此提示手填（[aaSelfNameMissingHint]），
/// **绝不能瞎猜一个名字写进账本**。
final aaSelfInfoProvider = FutureProvider<AaSelfInfo>((ref) async {
  var name = '';
  try {
    name = (await ref.watch(currentAccountNameProvider.future))?.trim() ?? '';
  } catch (_) {}

  var studentNo = '';
  var className = '';
  try {
    final repo = await ref.watch(studentInfoRepositoryProvider.future);
    final info = repo.getCachedStudentInfo().fold((_) => null, (i) => i);
    if (info != null) {
      if (name.isEmpty) name = info.name.trim();
      className = info.className.trim();
      studentNo = aaStudentNoOf(
        studentId: info.studentId,
        userId: info.userId,
        account: ref.read(currentAccountProvider),
      );
    }
  } catch (_) {}

  return (name: name, studentNo: studentNo, className: className);
});

/// 「我自己」的姓名 / 学号 / 班级。
typedef AaSelfInfo = ({String name, String studentNo, String className});

/// 学号取值序：学籍 `studentId`（`<bz>` 学号）→ `userId`（统一身份认证号，
/// 学生账号即是学号）→ 当前账号；**只认 8 位以上纯数字**，认不出给空串。
///
/// 为什么要判形：`studentId` 在部分账号里混进了体测编号等杂值，直接显示会把
/// 「学号」写成别人看不懂的一串；宁可留空（界面不显示），也不要写错。
String aaStudentNoOf({
  required String studentId,
  required String userId,
  required String account,
}) {
  for (final s in [studentId, userId, account]) {
    final t = s.trim();
    if (RegExp(r'^\d{8,}$').hasMatch(t)) return t;
  }
  return '';
}
