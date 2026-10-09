import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';

/// 解析 `assets/general_education/ge_catalog.json`（由 `tool/make_ge_catalog.py` 生成）。
///
/// 容错口径照本仓约定（§3「模型」）：缺字段 / 类型不对一律用默认值，
/// **不让旧 asset 把页面打崩** —— 但也不静默丢弃整张表：认不出的行跳过、
/// 认得出的照收。
class GeneralEducationCatalogParser {
  const GeneralEducationCatalogParser();

  GeneralEducationCatalog parse(Map<String, dynamic> json) {
    final sheetsRaw = json['sheets'];
    final sheets = <GeneralEducationSheet>[];
    if (sheetsRaw is List) {
      for (final raw in sheetsRaw) {
        if (raw is! Map) continue;
        final sheet = _sheet(Map<String, dynamic>.from(raw));
        if (sheet != null) sheets.add(sheet);
      }
    }
    return GeneralEducationCatalog(
      revision: _str(json['revision']),
      sourceName: _str(json['sourceName']),
      sheets: sheets,
    );
  }

  GeneralEducationSheet? _sheet(Map<String, dynamic> raw) {
    final title = _str(raw['title']);
    final coursesRaw = raw['courses'];
    if (coursesRaw is! List) return null;
    final courses = <GeneralEducationCourse>[];
    for (final c in coursesRaw) {
      if (c is! Map) continue;
      final course = _course(Map<String, dynamic>.from(c), title);
      if (course != null) courses.add(course);
    }
    if (courses.isEmpty) return null;
    return GeneralEducationSheet(
      title: title,
      courses: courses,
      cohortFrom: _int(raw['cohortFrom']),
      cohortTo: _int(raw['cohortTo']),
      allCohorts: raw['allCohorts'] == true,
    );
  }

  GeneralEducationCourse? _course(Map<String, dynamic> raw, String sheetTitle) {
    final name = _str(raw['name']);
    final code = _str(raw['code']);
    if (name.isEmpty && code.isEmpty) return null;
    return GeneralEducationCourse(
      code: code,
      name: name,
      sheetTitle: sheetTitle,
      extraCodes: _strList(raw['extraCodes']),
      credit: _double(raw['credit']),
      creditText: _strOrNull(raw['creditText']),
      module: generalEducationModuleOf(_str(raw['module'])),
      dept: _str(raw['dept']),
      oldCodes: _strList(raw['oldCodes']),
      note: _strOrNull(raw['note']),
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';

  static String? _strOrNull(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static List<String> _strList(Object? v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  }
}
