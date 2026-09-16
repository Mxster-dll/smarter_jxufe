/// 「网上选课」检索栏的**客户端过滤**口径 —— 复刻教务 `student/wsxk.zx.html`（S2020202）。
///
/// 原页面的「课程类别」「课程属性」两个下拉**不是服务端参数**：
/// 它们初始 `disabled`（disabled 表单项根本不会提交），每次检索返回后由
/// `showTotalRecord(tableId,total)` 调 `cTypeFilter()` / `cTypeFilter_kcsx()`
/// 从**当前结果表格**去重生成选项，选中后走 `ctyQryData()` / `ctyQryData2()`
/// 只做 `style.display` 显隐（2026-09-15 从页面 JS 实证）：
///
/// * 课程类别：比较键 = `kclb2 + "_" + kclb1`，显示文本 = `lb` 列
///   （`opts[kclb2+"_"+kclb1] = kutil.getValue4TD(_tr,"lb")`）；
///   ⚠ 实测数据里 `lb` 常常是**空串**，此时原页面会渲染一个空文本选项 ——
///   我们退回显示比较键本身，避免出现一个看不见的选项。
/// * 课程属性：比较键与文本都是 `kcsx` 列（如「理论课」）。
///
/// 一处**有意的偏离**：原页面两个过滤函数各写一次 `rows[i].style.display`，
/// 后执行的那个会覆盖前一个（等于「改了类别，属性筛选就失效」）。这里改为
/// 取**交集**（类别 ∧ 属性），语义更符合直觉且不丢条件。
library;

import 'selection_models.dart';

/// 一个客户端过滤项（`key` 用于比较，`label` 用于显示）。
class SelectionFilterOption {
  const SelectionFilterOption({required this.key, required this.label});

  final String key;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SelectionFilterOption &&
      other.key == key &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, label);

  @override
  String toString() => 'SelectionFilterOption($key, $label)';
}

/// 课程类别的比较键 = 原页面 `kclb2 + "_" + kclb1`。
String optionalCourseCategoryKey(OptionalCourse course) =>
    '${course.kclb2}_${course.kclb1}';

/// 课程类别选项：按结果顺序去重（原页面用对象键去重，等价）。
List<SelectionFilterOption> optionalCourseCategoryOptions(
  List<OptionalCourse> courses,
) {
  final seen = <String, SelectionFilterOption>{};
  for (final course in courses) {
    final key = optionalCourseCategoryKey(course);
    if (seen.containsKey(key)) continue;
    final label = course.category.isNotEmpty ? course.category : key;
    seen[key] = SelectionFilterOption(key: key, label: label);
  }
  return seen.values.toList(growable: false);
}

/// 课程属性选项：按结果顺序去重、跳过空值。
List<String> optionalCourseAttributeOptions(List<OptionalCourse> courses) {
  final seen = <String>{};
  for (final course in courses) {
    if (course.attribute.isEmpty) continue;
    seen.add(course.attribute);
  }
  return seen.toList(growable: false);
}

/// 类别 + 属性过滤（空值 = 不过滤）。
List<OptionalCourse> filterOptionalCourses(
  List<OptionalCourse> courses, {
  String categoryKey = '',
  String attribute = '',
}) {
  if (categoryKey.isEmpty && attribute.isEmpty) return courses;
  return courses
      .where(
        (course) =>
            (categoryKey.isEmpty ||
                optionalCourseCategoryKey(course) == categoryKey) &&
            (attribute.isEmpty || course.attribute == attribute),
      )
      .toList(growable: false);
}

/// 结果集换了一批之后校正已选过滤项。
///
/// 原页面每次检索都 `$("lbgl").options.length=0` 重建下拉 → **选择被清空**；
/// 这里保留仍然存在的选项，只把失效的清掉（用户不会因为翻页/换范围而莫名丢条件）。
({String categoryKey, String attribute}) reconcileOptionalCourseFilters(
  List<OptionalCourse> courses, {
  required String categoryKey,
  required String attribute,
}) {
  final categoryOk =
      categoryKey.isNotEmpty &&
      optionalCourseCategoryOptions(
        courses,
      ).any((option) => option.key == categoryKey);
  final attributeOk =
      attribute.isNotEmpty &&
      optionalCourseAttributeOptions(courses).contains(attribute);
  return (
    categoryKey: categoryOk ? categoryKey : '',
    attribute: attributeOk ? attribute : '',
  );
}
