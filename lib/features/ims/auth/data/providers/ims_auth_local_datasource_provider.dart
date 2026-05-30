import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_jsessionid_box_provider.dart';

part 'ims_auth_local_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
Future<ImsAuthLocalDataSource> imsAuthLocalDataSource(
  ImsAuthLocalDataSourceRef ref,
) async {
  final box = await ref.watch(imsAuthJsessionIdBoxProvider.future);
  return ImsAuthLocalDataSource(box);
}
