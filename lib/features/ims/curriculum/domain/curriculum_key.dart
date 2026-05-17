import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumKey {
  final int year;
  final College college;
  final Major major;

  CurriculumKey({
    required this.year,
    required this.college,
    required this.major,
  });
}
