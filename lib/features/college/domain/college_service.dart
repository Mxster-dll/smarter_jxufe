import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/data/common/models/college.dart';
import 'package:smarter_jxufe/features/college/data/repositories/unified_college_repository.dart';
import 'package:smarter_jxufe/features/college/domain/unified_college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/repositories/curriculum_college_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';

class CollegeService {
  final UnifiedCollegeRepository _collegeRepository;
  final CurriculumCollegeRepository _curriculumCollegeRepository;

  CollegeService({
    required UnifiedCollegeRepository collegeRepository,
    required CurriculumCollegeRepository curriculumCollegeRepository,
  }) : _collegeRepository = collegeRepository,
       _curriculumCollegeRepository = curriculumCollegeRepository;

  T? adaptFrom<T extends College>(UnifiedCollege college) {
    final queryResult = switch (T) {
      CurriculumCollege _ => _curriculumCollegeRepository.adaptFrom(college),
      _ => throw ArgumentError('不支持的学院类型: $T'),
    };
  }

  syncFromSystem(FunctionType function) {}
}
