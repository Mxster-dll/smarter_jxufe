import 'package:get_storage/get_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_storage_provider.g.dart';

@riverpod
GetStorage accountStorage(AccountStorageRef ref, String account) {
  // 每个账号独立的存储文件，文件名包含账号
  return GetStorage('Account_$account');
}
