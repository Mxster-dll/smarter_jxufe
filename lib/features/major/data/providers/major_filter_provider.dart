import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/major/data/anti_corruption/major_filter.dart';

part 'major_filter_provider.g.dart';

@riverpod
MajorFilter majorFilter(MajorFilterRef ref) => MajorFilter();
