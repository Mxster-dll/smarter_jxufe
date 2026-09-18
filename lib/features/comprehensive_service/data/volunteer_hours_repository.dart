import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/volunteer_form_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/volunteer_hours_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_export_file.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 志愿服务时长业务仓库。
///
/// 组合 [SspAuthRepository]（会话管理）与
/// [VolunteerHoursRemoteDataSource]（数据拉取），实现：
/// - 首次进入：自动换取并持久化 JSESSIONID；
/// - 会话过期：自动刷新会话后重试一次；
/// - 反复过期：向上抛出明确错误，交由 UI 提示用户。
class VolunteerHoursRepository {
  final SspAuthRepository _sspAuthRepository;
  final VolunteerHoursRemoteDataSource _remoteDataSource;

  VolunteerHoursRepository({
    required SspAuthRepository sspAuthRepository,
    required VolunteerHoursRemoteDataSource remoteDataSource,
  }) : _sspAuthRepository = sspAuthRepository,
       _remoteDataSource = remoteDataSource;

  /// 拉取指定账户的志愿活动列表（含每个活动的日期）。
  ///
  /// 列表页没有时间列，日期来自两处：
  /// 1. **认定登记表**（`downloadInfo.do` 的 Word 原件，一次请求拿到逐条
  ///    「认定日期」，见 `anti_corruption/volunteer_form_parser.dart`）；
  /// 2. 兜底：逐行拉「详情」页 `apply_one_detail.html` 的 `startTime`——
  ///    ⚠ 服务端 2026-09-18 起对该页一律返回「出错了」，这条链路实测已失效，
  ///    保留是为了它哪天恢复；单条详情失败只让该行时间为空，不影响列表。
  Future<List<VolunteerActivity>> fetchActivities(String account) async {
    // 第一次尝试：命中本地持久化会话即直接使用
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await _fetchActivitiesWithTime(sessionId);
    } on SspSessionExpiredException {
      // 会话过期 → 走统一认证重新换取后重试一次
      final freshSessionId = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await _fetchActivitiesWithTime(freshSessionId);
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }

  Future<List<VolunteerActivity>> _fetchActivitiesWithTime(
    String sessionId,
  ) async {
    final rows = await _remoteDataSource.fetchVolunteerActivities(
      sessionId: sessionId,
    );
    if (rows.isEmpty) return rows;

    // ① 认定登记表：一次请求拿到逐条「认定日期」（列表页与详情页都不给）。
    final withDates = await _applyRecognitionForm(sessionId, rows);

    // ② 仍然没有日期的行 → 退回逐行详情页（服务端现已失效，留作恢复兜底）。
    final pending = <int>[
      for (var i = 0; i < withDates.length; i++)
        if (withDates[i].activityDate == null &&
            withDates[i].detailId.isNotEmpty)
          i,
    ];
    if (pending.isEmpty) return withDates;

    final fixed = <int, VolunteerActivity>{};
    await Future.wait(
      pending.map((position) async {
        final row = withDates[position];
        try {
          final time = await _remoteDataSource.fetchActivityTime(
            sessionId: sessionId,
            detailId: row.detailId,
            detailType: row.detailType,
          );
          if (time.start.isEmpty && time.end.isEmpty) return;
          fixed[position] = row.copyWith(
            startDate: time.start,
            endDate: time.end,
          );
        } catch (_) {
          // 单条详情失败（会话/网络/页面变动）→ 该行只缺时间
        }
      }),
    );
    if (fixed.isEmpty) return withDates;
    return [
      for (var i = 0; i < withDates.length; i++) fixed[i] ?? withDates[i],
    ];
  }

  /// 用《志愿服务时长认定登记表》补齐日期。
  ///
  /// 拿不到（会话过期 / 服务器返回 HTML / 解析不出）→ 原样返回，交给详情页兜底。
  Future<List<VolunteerActivity>> _applyRecognitionForm(
    String sessionId,
    List<VolunteerActivity> rows,
  ) async {
    try {
      final form = await _remoteDataSource.fetchRecognitionForm(
        sessionId: sessionId,
      );
      return volunteerApplyFormDates(rows, parseVolunteerForm(form.bytes));
    } catch (_) {
      return rows;
    }
  }

  /// 下载指定账户的「志愿服务时长认定登记表」（Word 原件）。
  ///
  /// 会话处理与 [fetchActivities] 完全一致：命中本地会话直接下载，
  /// 过期则自动刷新后重试一次，仍失败给出明确错误。
  Future<VolunteerExportFile> exportRecognitionForm(String account) async {
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await _remoteDataSource.fetchRecognitionForm(sessionId: sessionId);
    } on SspSessionExpiredException {
      final freshSessionId = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await _remoteDataSource.fetchRecognitionForm(
          sessionId: freshSessionId,
        );
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }
}
