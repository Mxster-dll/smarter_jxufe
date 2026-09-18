/// 志愿活动「申报详情」页解析。
///
/// 来源：`GET /admin/tzz/DQXNVolWork/apply_one_detail.html?id=<id>&type=<type>`
/// （ssp.jxufe.edu.cn，列表页「详情」按钮的同款页面，**列表页本身没有时间列**）。
/// 页面标题为「短期校内活动申报详情」，活动时间在只读输入框里：
/// ```
/// <input ... id="startTime" name="startTime" readonly ... value="2026-05-26">
/// <input ... id="endTime"   name="endTime"   readonly ... value="2026-05-26">
/// ```
/// ⚠ 同一页还有一个 **备注 textarea 也叫 `id="startTime"`** → 必须只在 `<input>`
/// 标签里取值，且取**第一个**命中项（真实时间框在前，textarea 在后）。
library;

/// 从详情页 HTML 取活动起止日期；取不到返回空串。
({String start, String end}) parseVolunteerActivityTime(String html) {
  return (
    start: _inputValueById(html, 'startTime'),
    end: _inputValueById(html, 'endTime'),
  );
}

final RegExp _inputTag = RegExp(r'<input\b[^>]*>', caseSensitive: false);
final RegExp _valueAttr = RegExp('value=["\']([^"\']*)["\']');

String _inputValueById(String html, String id) {
  final idPattern = RegExp('id=["\']${RegExp.escape(id)}["\']');
  for (final match in _inputTag.allMatches(html)) {
    final tag = match.group(0)!;
    if (!idPattern.hasMatch(tag)) continue;
    final value = _valueAttr.firstMatch(tag);
    return (value?.group(1) ?? '').trim();
  }
  return '';
}
