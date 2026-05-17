import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/major/data/major_mapper.dart';

part 'major_mapper_provider.g.dart';

@riverpod
MajorMapper majorMapper(MajorMapperRef ref) => MajorMapper();
