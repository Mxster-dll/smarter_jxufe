import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/my_mail/data/datasources/my_mail_remote_datasource.dart';
import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart'
    show wxGuidProvider;

/// 未配置平台标识（GUID）时的固定文案（UI 据此显示「去获取平台标识」入口）。
const String kMyMailNeedGuid = '未配置微信平台标识（GUID），无法读取邮箱账号';

/// 判断某个错误是不是「缺 GUID」（页面据此决定要不要给配置入口）。
bool myMailNeedsGuid(Object error) =>
    error is MyMailApiException && error.message.contains('GUID');

/// 门户域专用 Dio（智慧江财平台 `.cn` 域，与电费/校历同源反代）。
///
/// 服务器按来源放行：必须携带 servicewechat 页面 Referer 与浏览器 UA。
final myMailDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://wxcourse.jxufe.cn',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Referer':
            'https://servicewechat.com/wx70c0beda0bb7b021/143/page-frame.html',
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
});

/// 我的邮箱远程数据源。
final myMailRemoteDataSourceProvider = Provider<MyMailRemoteDataSource>(
  (ref) => MyMailRemoteDataSource(ref.watch(myMailDioProvider)),
);

/// 学生邮箱账号 + 初始密码。
///
/// 前置条件：已登录 + 已配置平台 GUID（与校园网/请假/校历共用 Hive `wxPlatform.guid`）。
final myMailboxProvider = FutureProvider<StudentMailbox>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const MyMailApiException('请先登录后再查看我的邮箱');
  }
  final guid = (await ref.watch(wxGuidProvider.future))?.trim();
  if (guid == null || guid.isEmpty) {
    throw const MyMailApiException(kMyMailNeedGuid);
  }
  return ref.watch(myMailRemoteDataSourceProvider).fetchMailbox(guid);
});
