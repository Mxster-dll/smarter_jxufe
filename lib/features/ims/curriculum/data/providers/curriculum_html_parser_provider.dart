import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_html_parser.dart';

part 'curriculum_html_parser_provider.g.dart';

@riverpod
CurriculumHtmlParser curriculumHtmlParser(CurriculumHtmlParserRef ref) =>
    CurriculumHtmlParser();
