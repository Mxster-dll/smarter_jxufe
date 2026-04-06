import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college_default_aliases.dart';

part 'college.g.dart';

@HiveType(typeId: 9, adapterName: 'CollegeAdapter')
class College {
  @HiveField(0)
  final String uuid;

  @HiveField(1)
  String standardName;

  @HiveField(2)
  final Map<FunctionType, String> functionIdIn;

  @HiveField(3)
  List<String> _aliases;

  College(
    this.uuid,
    this.standardName, {
    Map<FunctionType, String>? functionIdIn,
    List<String>? aliases,
  }) : functionIdIn = functionIdIn ?? {},
       _aliases =
           aliases ??
           CollegeDefaultAliases.getDefaultAliases(standardName).toList();

  @override
  String toString() => 'College(uuid: $uuid, standardName: $standardName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is College &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  Set<String> get aliases => _aliases.toSet();

  bool hasAlias(String alias) => _aliases.contains(alias);
  bool isKnownAs(String name) => standardName == name || hasAlias(name);

  void addAlias(String alias) {
    if (!_aliases.contains(alias)) {
      _aliases.add(alias);
    }
  }

  void removeAlias(String alias) => _aliases.remove(alias);

  void restoreDefaultAliases() =>
      _aliases = CollegeDefaultAliases.getDefaultAliases(standardName).toList();
}
