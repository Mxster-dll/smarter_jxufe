import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/qr_login/data/providers/mfa_login_remote_datasource_provider.dart';
import 'package:smarter_jxufe/features/qr_login/data/providers/scan_login_remote_datasource_provider.dart';
import 'package:smarter_jxufe/features/qr_login/data/providers/wechat_login_remote_datasource_provider.dart';
import 'package:smarter_jxufe/features/qr_login/data/repositories/qr_code_repository.dart';

part 'qr_code_repository_provider.g.dart';

@Riverpod(keepAlive: true)
QrCodeRepository qrCodeRepository(QrCodeRepositoryRef ref) {
  final scanLoginDs = ref.watch(scanLoginRemoteDataSourceProvider);
  final wechatLoginDs = ref.watch(wechatLoginRemoteDataSourceProvider);
  final mfaLoginDs = ref.watch(mfaLoginRemoteDataSourceProvider);

  return QrCodeRepository(
    scanLoginDs: scanLoginDs,
    wechatLoginDs: wechatLoginDs,
    mfaLoginDs: mfaLoginDs,
  );
}
