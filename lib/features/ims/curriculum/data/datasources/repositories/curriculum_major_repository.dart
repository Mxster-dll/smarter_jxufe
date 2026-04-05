import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/major_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/major_remote_datasource.dart';

class CurriculumMajorRepository {
  final MajorLocalDataSource _localDataSource;
  final MajorRemoteDataSource _remoteDataSource;

  CurriculumMajorRepository({
    required MajorLocalDataSource localDataSource,
    required MajorRemoteDataSource remoteDataSource,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource;
}
