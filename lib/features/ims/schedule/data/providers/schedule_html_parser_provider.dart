import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/schedule_html_parser.dart';

part 'schedule_html_parser_provider.g.dart';

@Riverpod(keepAlive: true)
ScheduleHtmlParser scheduleHtmlParser(ScheduleHtmlParserRef ref) =>
    ScheduleHtmlParser();
