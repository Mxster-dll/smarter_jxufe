/// 「填表助手」的数据装配：**把散在各模块的数据收成一份 [FillFormData]**。
///
/// 全部走**已有的** provider（不新开取数路径），且**离线优先**：
/// 学籍读本地缓存、成绩读成绩缓存、综测读本地库；任何一步失败都退化成
/// 「这一块没有数据」（对应的待填项留空），**绝不让整页报错**
/// —— 用户的原话是「填不了/不确定的，空着」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_year_sources.dart';

import '../domain/fill_form_data.dart';

/// 某**测评学年**（参数 = 学年结束年，如 2026 = 2025-2026 学年）的填表数据。
///
/// 与综测页同一套口径：材料**不按学年过滤**地喂给引擎（`zcCalculate`），
/// 另外单独给一份**按学年过滤**的材料（《附加分审核表》是按学年申报的）。
final fillFormDataProvider = FutureProvider.family<FillFormData, int>((
  ref,
  yearEnd,
) async {
  final info = await _cachedStudentInfo(ref);
  var data = FillFormData.ofStudent(info, yearEnd: yearEnd);

  // ---- 成绩（该学年）----
  double? autoWeight;
  try {
    final grades = await ref.watch(gePriorGradesProvider.future);
    final stats = zcYearGradeStats(grades, yearEnd: yearEnd);
    autoWeight = zcWeightedForYear(grades, yearEnd: yearEnd);
    data = data.copyWith(
      minScore: stats.minScore,
      credits: stats.credits,
      hasFail: stats.hasFail,
    );
  } catch (_) {
    // 成绩缓存读不到 → 加权/单科/学分全留空。
  }

  // ---- 自动源（加权 / 志愿时长）----
  double? autoVolunteer;
  try {
    autoVolunteer = await ref.watch(zcAutoVolunteerProvider(yearEnd).future);
  } catch (_) {
    autoVolunteer = null;
  }
  try {
    final fromProvider = await ref.watch(zcAutoWeightProvider(yearEnd).future);
    autoWeight = fromProvider ?? autoWeight;
  } catch (_) {
    // 保留上面从成绩缓存直接算的那一份。
  }

  // ---- 材料 + 手动项 ----
  var materials = const <ZcMaterial>[];
  try {
    materials = await ref.watch(zcMaterialsProvider.future);
  } catch (_) {
    materials = const [];
  }
  var manual = const ZcManual();
  try {
    manual = await (await ref.watch(zcStoreProvider.future)).loadManual(
      yearEnd,
    );
  } catch (_) {
    manual = const ZcManual();
  }

  final zc = zcCalculate(
    materials,
    manual: manual,
    autoWeight: autoWeight,
    autoVolunteer: autoVolunteer,
  );

  return data.copyWith(
    weighted: autoWeight,
    manual: manual,
    volunteerHours: autoVolunteer,
    zc: zc,
    allMaterials: materials,
    materials: zcFilterByYear(materials, yearEnd),
    now: DateTime.now(),
  );
});

Future<StudentInfo?> _cachedStudentInfo(Ref ref) async {
  try {
    final repo = await ref.watch(studentInfoRepositoryProvider.future);
    return repo.getCachedStudentInfo().fold((_) => null, (v) => v);
  } catch (_) {
    return null;
  }
}
