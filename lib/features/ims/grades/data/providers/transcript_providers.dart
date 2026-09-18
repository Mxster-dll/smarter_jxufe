import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/transcript_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/transcript_report.dart';
import 'package:smarter_jxufe/features/my_mail/data/providers/my_mail_providers.dart'
    show myMailboxProvider;
import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart'
    show myMailStudentAddress;
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart'
    show wxGuidProvider;

/// 未配置平台标识（GUID）时的固定文案。
const String kTranscriptNeedGuid = '未配置微信平台标识（GUID），无法申请成绩单';

/// 门户域专用 Dio（与网费/校历同款来源头）。
final transcriptDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://wxcourse.jxufe.cn',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
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

final transcriptRemoteDataSourceProvider = Provider<TranscriptRemoteDataSource>(
  (ref) => TranscriptRemoteDataSource(ref.watch(transcriptDioProvider)),
);

/// 加密账号（H5 的 `userId` 参数）——发送与查类型都要它。
final transcriptEncUserIdProvider = FutureProvider<String>((ref) async {
  final guid = (await ref.watch(wxGuidProvider.future))?.trim();
  if (guid == null || guid.isEmpty) {
    throw const TranscriptApiException(kTranscriptNeedGuid);
  }
  return ref.watch(transcriptRemoteDataSourceProvider).fetchEncUserId(guid);
});

/// 可申请的报表类型（有辅修才会多出两项）。
final transcriptReportTypesProvider =
    FutureProvider<List<TranscriptReportType>>((ref) async {
      final enc = await ref.watch(transcriptEncUserIdProvider.future);
      return ref
          .watch(transcriptRemoteDataSourceProvider)
          .fetchReportTypes(enc);
    });

/// 邮箱默认值 = **学生邮箱**地址。
///
/// ⚠ 不能拿学籍 `serialNo` 拼：本账号实测 `serialNo = 201600035929`（12 位，学籍 `<xh>`），
/// 而学生邮箱是 **10 位学号** `2000000000@stu.jxufe.edu.cn`。故：
/// 1. 首选邮箱接口给的权威地址（`myMailboxProvider` → `GET /api/wx/email/getPwd`）；
/// 2. 取不到（未配置 GUID / 未登录 / 网络失败）→ 用**登录账号**（= 学号）拼同一个域；
/// 3. 账号也没有 → null（不预填，让用户自己填）。
final transcriptDefaultEmailProvider = FutureProvider<String?>((ref) async {
  try {
    final mailbox = await ref.watch(myMailboxProvider.future);
    if (mailbox.email.isNotEmpty) return mailbox.email;
  } catch (_) {
    // 落到账号兜底。
  }
  return myMailStudentAddress(ref.watch(currentAccountProvider));
});
