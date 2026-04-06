import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_viewmodel.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';

final curriculumViewModelProvider =
    StateNotifierProvider.autoDispose<CurriculumViewModel, CurriculumState>((
      ref,
    ) {
      final curriculumRepository = ref.watch(curriculumRepositoryProvider);
      final collegeRepository = ref.watch(collegeRepositoryProvider);
      final majorRepository = ref.watch(majorRepositoryProvider);

      return CurriculumViewModel(
        repository: curriculumRepository,
        collegeRepository: collegeRepository,
        majorRepository: majorRepository,
      );
    });
