import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';

part 'ims_auth_repository_provider.g.dart';

/// IMS 会话门面（无状态，每次重建都指向当前的全局会话实例）。
///
/// 会话本体是 [imsSessionProvider] 里那**唯一一个** `ImsSession`；
/// 账号切换时它随 `currentAccountProvider` 重建，本 provider 也会跟着
/// 重新构造门面，从而指向新会话。
@Riverpod(keepAlive: true)
Future<ImsAuthRepository> imsAuthRepository(ImsAuthRepositoryRef ref) {
  return Future.value(ImsAuthRepository(ref.watch(imsSessionProvider)));
}
