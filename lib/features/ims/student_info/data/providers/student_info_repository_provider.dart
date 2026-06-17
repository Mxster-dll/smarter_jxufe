import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_mapper_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_remote_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_xml_parser_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/student_info_repository.dart';

part 'student_info_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<StudentInfoRepository> studentInfoRepository(
  StudentInfoRepositoryRef ref,
) async {
  final localDataSource = await ref.watch(
    studentInfoLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(studentInfoRemoteDataSourceProvider);
  final xmlParser = ref.watch(studentInfoXmlParserProvider);
  final mapper = ref.watch(studentInfoMapperProvider);
  final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

  return StudentInfoRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    xmlParser: xmlParser,
    mapper: mapper,
    imsAuthRepo: imsAuthRepo,
  );
}
