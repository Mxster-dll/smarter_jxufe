import 'package:hive/hive.dart';

part 'function_type.g.dart';

@HiveType(typeId: 7)
enum FunctionType {
  @HiveField(0)
  curriculum,
}
