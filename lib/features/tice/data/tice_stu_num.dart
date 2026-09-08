import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';

/// 解析体测查询用的学号。
///
/// 登录账号（一卡通/统一身份号）≠ 体测库学号：优先取教务学生信息中的
/// 7 位学号（登录成功时已拉取缓存），不可用时回退登录账号，均无则返回空串。
Future<String> resolveTiceStuNum(WidgetRef ref) async {
  try {
    final repo = await ref.read(studentInfoRepositoryProvider.future);
    final result = await repo.getStudentInfo(forceRefresh: false);
    var stuNum = '';
    result.fold((_) {}, (info) => stuNum = info.studentId.trim());
    if (stuNum.isNotEmpty) return stuNum;
  } catch (_) {
    // 学生信息不可用（未登录 IMS 等）→ 走兜底
  }
  return ref.read(currentAccountProvider);
}

/// 解析体测可查起始学年（入学年份，教务字段 rxnj），解析失败返回 null。
///
/// 体测只在入学后存在，年度切换条应从入学年显示到今年，而非固定窗口。
Future<int?> resolveTiceEnrollYear(WidgetRef ref) async {
  try {
    final repo = await ref.read(studentInfoRepositoryProvider.future);
    final result = await repo.getStudentInfo(forceRefresh: false);
    var enrollYear = '';
    result.fold((_) {}, (info) => enrollYear = info.enrollYear.trim());
    final parsed = int.tryParse(enrollYear);
    if (parsed != null && parsed > 0) return parsed;
  } catch (_) {
    // 忽略：调用方回退默认窗口
  }
  return null;
}
