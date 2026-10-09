/// 本专业**实践环节**（学籍 → 学院 → 专业 → 实践环节表），与
/// [myCurriculumProvider]（理论课程）同一条链、只差最后一步。
///
/// 缓存优先（命中本地不发网络）；拿不到返回 null，调用方按「没有实践环节数据」处理。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/providers/my_curriculum_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/practice_curriculum_providers.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

final myPracticeCurriculumProvider = FutureProvider<PracticeCurriculum?>((
  ref,
) async {
  try {
    final key = await ref.watch(myPlanKeyProvider.future);
    if (key == null) return null;
    final repo = await ref.watch(practiceCurriculumRepositoryProvider.future);
    final result = await repo.getPracticeCurriculumIn(
      key.year,
      key.college,
      key.major,
    );
    return result.fold((_) => null, (c) => c);
  } catch (_) {
    return null;
  }
});
