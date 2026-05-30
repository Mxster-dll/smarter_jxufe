import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';

part 'function_type.g.dart';

@HiveType(typeId: kFunctionTypeTypeId)
enum FunctionType {
  @HiveField(0)
  curriculum,
}
