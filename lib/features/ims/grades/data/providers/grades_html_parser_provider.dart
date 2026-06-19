import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/grades_html_parser.dart';

part 'grades_html_parser_provider.g.dart';

@Riverpod(keepAlive: true)
GradesHtmlParser gradesHtmlParser(GradesHtmlParserRef ref) =>
    GradesHtmlParser();
