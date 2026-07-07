import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/features/ims/graduation_requirements/data/anti_corruption/graduation_requirements_html_parser.dart';

/// 毕业学分要求 HTML 解析器 Provider。
final graduationRequirementsHtmlParserProvider =
    Provider<GraduationRequirementsHtmlParser>((ref) {
      return GraduationRequirementsHtmlParser();
    });
