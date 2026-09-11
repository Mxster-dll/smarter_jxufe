import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/account_avatar_controller.dart';
import 'package:smarter_jxufe/features/auth/data/account_avatar_store.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';

/// 头像目录（应用私有目录 `avatars/`），进程内只解析一次。
final accountAvatarStoreProvider = FutureProvider<AccountAvatarStore>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, kAvatarDirName));
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  return AccountAvatarStore(directory);
});

/// 当前账号头像（本地文件 + 账户记录字段）。
///
/// 存储就绪 / 账号切换时自动重新绑定并 notify：首页顶栏与「我的」页
/// 共用一个实例，换图后两边同帧更新。
final accountAvatarProvider = ChangeNotifierProvider<AccountAvatarController>((
  ref,
) {
  final controller = AccountAvatarController();

  Future<void> sync() async {
    final cardNumber = ref.read(currentAccountProvider);
    final store = await ref.read(accountAvatarStoreProvider.future);
    final repository = await ref.read(accountRepositoryProvider.future);
    controller.bind(
      store: store,
      repository: repository,
      cardNumber: cardNumber,
    );
  }

  ref.listen(
    accountAvatarStoreProvider,
    (_, _) => sync(),
    fireImmediately: true,
  );
  ref.listen(currentAccountProvider, (_, _) => sync());
  return controller;
});
