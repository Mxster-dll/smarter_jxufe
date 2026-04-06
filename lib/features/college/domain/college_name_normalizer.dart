import 'package:smarter_jxufe/features/college/alias_conflict_exception.dart';
import 'package:smarter_jxufe/features/college/domain/college_default_aliases.dart';

class CollegeNameNormalizer {
  static final Map<String, String> normalizeNames = _invertMap(
    CollegeDefaultAliases.defaultAliases,
  );

  static Map<String, String> _invertMap(Map<String, Set<String>> original) {
    final inverted = <String, String>{};
    for (final entry in original.entries) {
      for (final value in entry.value) {
        if (inverted.containsKey(value)) {
          throw AliasConflictException(
            '冲突：值 "$value" 同时出现在键 "${inverted[value]}" 和 "${entry.key}" 中',
          );
        }
        inverted[value] = entry.key;
      }
    }
    return inverted;
  }

  static String normalize(String rawName) {
    final trimmed = rawName.trim();

    return normalizeNames[rawName] ?? trimmed;
  }

  // 提取代码和名称（针对如"[001]学院"格式）
  static (String code, String name) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[(\d+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
    return ('', raw);
  }
}
