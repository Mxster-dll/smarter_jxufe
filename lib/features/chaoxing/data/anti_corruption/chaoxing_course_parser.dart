/// 学习通 · 课程清单解析（「学生端」`/visit/courses`）。
///
/// 实测结构（2026-09-19）：
/// ```html
/// <input type="hidden" name="courseId" value="266750349" />
/// <input type="hidden" name="classId" value="153775462" />
/// <a class="courseName"
///    href='/visit/stucoursemiddle?courseid=266750349&clazzid=153775462&vc=1&cpi=487826070'
///    title="261学期&nbsp;计算机组成原理">261学期&nbsp;计算机组成原理</a>
/// ```
///
/// 口径：**以 `a.courseName` 为准**（它三个标识齐全），不靠 hidden input 的先后配对
/// ——页面上还有别的 hidden 与「新建课程」占位项，按 input 顺序配对迟早错位。
/// 标题里的 `&nbsp;` 已被 DOM 解码成 U+00A0，这里统一收成普通空格。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';

/// 课程链接里的三个标识。
final RegExp _hrefRe = RegExp(
  r'''stucoursemiddle\?courseid=(\d+)[^"']*?clazzid=(\d+)[^"']*?cpi=(\d+)''',
  caseSensitive: false,
);

/// 解析课程清单；认不出的一律跳过（空页 → 空列表，不抛）。
///
/// ⚠ **两趟扫描**：每门课在页面里有**两个**指向 `stucoursemiddle` 的 `<a>`
/// （封面 `a.cover` 在前、课程名 `a.courseName` 在后）。只按 href 扫就会先命中封面
/// ——它是空的，课程名会被写成 courseId。所以第一趟只认 `a.courseName`，
/// 第二趟才用裸 href 兜底补漏。
List<ChaoxingCourse> parseChaoxingCourses(String html) {
  if (html.trim().isEmpty) return const [];
  final Document doc;
  try {
    doc = html_parser.parse(html);
  } catch (_) {
    return const [];
  }

  final out = <ChaoxingCourse>[];
  final seen = <String>{};

  void take(Element anchor) {
    final href = anchor.attributes['href'] ?? '';
    final m = _hrefRe.firstMatch(href);
    if (m == null) return;
    final courseId = m.group(1)!;
    final classId = m.group(2)!;
    if (courseId.isEmpty || classId.isEmpty) return;
    if (!seen.add('$courseId/$classId')) return;
    final titleAttr = _clean(anchor.attributes['title'] ?? '');
    final name = titleAttr.isEmpty ? _clean(anchor.text) : titleAttr;
    out.add(
      ChaoxingCourse(
        courseId: courseId,
        classId: classId,
        cpi: m.group(3)!,
        name: name.isEmpty ? courseId : name,
      ),
    );
  }

  for (final a in doc.querySelectorAll('a.courseName')) {
    take(a);
  }
  for (final a in doc.querySelectorAll('a[href*="stucoursemiddle"]')) {
    take(a);
  }
  return out;
}

/// 收拢空白（含 NBSP `\u00a0`）与首尾空格。
String _clean(String raw) => raw
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
