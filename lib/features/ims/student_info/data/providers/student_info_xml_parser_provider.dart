import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_xml_parser.dart';

part 'student_info_xml_parser_provider.g.dart';

@Riverpod(keepAlive: true)
StudentInfoXmlParser studentInfoXmlParser(StudentInfoXmlParserRef ref) =>
    StudentInfoXmlParser();
