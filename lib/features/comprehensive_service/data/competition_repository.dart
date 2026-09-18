import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/competition_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 第二课堂「学科竞赛」业务仓库。
///
/// 组合 [SspAuthRepository]（综合管理平台会话）与 [CompetitionRemoteDataSource]：
/// - 首次进入自动换取并持久化 JSESSIONID（与第二课堂学分 / 志愿时长同一套会话）；
/// - 会话过期自动刷新后重试一次；
/// - 反复过期向上抛出明确错误。
///
/// 每次调用都独立走一遍「取会话 → 请求 → 失败刷新重试」，所以列表翻页 / 搜索之间不会
/// 互相影响（浏览器靠 Cookie 保持筛选条件，客户端靠每次重复带筛选参数，见
/// `competitionPageRequestParams`）。
class CompetitionRepository {
  final SspAuthRepository _sspAuthRepository;
  final CompetitionRemoteDataSource _remote;

  CompetitionRepository({
    required SspAuthRepository sspAuthRepository,
    required CompetitionRemoteDataSource remoteDataSource,
  }) : _sspAuthRepository = sspAuthRepository,
       _remote = remoteDataSource;

  /// 我的申请列表。
  Future<CompetitionPage<CompetitionApply>> fetchApplyList(
    String account, {
    int page = 1,
    String year = '',
    String gameName = '',
  }) => _withSession(
    account,
    (sessionId) => _remote.fetchApplyList(
      sessionId: sessionId,
      page: page,
      year: year,
      gameName: gameName,
    ),
  );

  /// 竞赛公示列表（全校，可按学号 / 姓名 / 班级搜索）。
  Future<CompetitionPage<CompetitionPublicity>> fetchPublicityList(
    String account, {
    int page = 1,
    String studentId = '',
    String name = '',
    String className = '',
  }) => _withSession(
    account,
    (sessionId) => _remote.fetchPublicityList(
      sessionId: sessionId,
      page: page,
      studentId: studentId,
      name: name,
      className: className,
    ),
  );

  /// 比赛目录（选比赛用）。
  Future<CompetitionPage<CompetitionGame>> fetchGames(
    String account, {
    int page = 1,
    String year = '',
    String gameName = '',
  }) => _withSession(
    account,
    (sessionId) => _remote.fetchGames(
      sessionId: sessionId,
      page: page,
      year: year,
      gameName: gameName,
    ),
  );

  /// 学生检索（团队申请加成员）。
  Future<CompetitionPage<CompetitionStudent>> fetchStudents(
    String account, {
    int page = 1,
    String name = '',
    String studentId = '',
  }) => _withSession(
    account,
    (sessionId) => _remote.fetchStudents(
      sessionId: sessionId,
      page: page,
      name: name,
      studentId: studentId,
    ),
  );

  /// 某比赛的奖项（`getCredit.do`）。
  Future<List<CompetitionAward>> fetchAwards(
    String account, {
    required int gameId,
  }) => _withSession(
    account,
    (sessionId) => _remote.fetchAwards(sessionId: sessionId, gameId: gameId),
  );

  /// 申请详情。
  Future<CompetitionDetail> fetchApplyDetail(
    String account, {
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) => _withSession(
    account,
    (sessionId) =>
        _remote.fetchApplyDetail(sessionId: sessionId, id: id, type: type),
  );

  /// 一条记录的加分信息（申报奖项 / 最终奖项 / 个人得分 / 该赛别分值表）。
  Future<CompetitionApplyAward> fetchApplyAward(
    String account, {
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) => _withSession(
    account,
    (sessionId) =>
        _remote.fetchApplyAward(sessionId: sessionId, id: id, type: type),
  );

  /// 公示详情。
  Future<CompetitionDetail> fetchPublicityDetail(
    String account, {
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) => _withSession(
    account,
    (sessionId) =>
        _remote.fetchPublicityDetail(sessionId: sessionId, id: id, type: type),
  );

  /// 上传证书图片 → 附件 id（失败时抛异常，由界面提示）。
  Future<int> uploadAttachment(
    String account,
    CompetitionAttachment attachment,
  ) => _withSession(
    account,
    (sessionId) =>
        _remote.uploadAttachment(sessionId: sessionId, attachment: attachment),
  );

  /// 提交申请（返回官网提示文案）。
  Future<String> submitApply(
    String account, {
    required int gameId,
    required String remark,
    required CompetitionType type,
    List<String> memberIds = const [],
    required List<int> attachmentIds,
  }) => _withSession(
    account,
    (sessionId) => _remote.submitApply(
      sessionId: sessionId,
      gameId: gameId,
      remark: remark,
      type: type,
      memberIds: memberIds,
      attachmentIds: attachmentIds,
    ),
  );

  /// 删除申请。
  Future<void> deleteApplies(String account, List<int> ids) => _withSession(
    account,
    (sessionId) => _remote.deleteApplies(sessionId: sessionId, ids: ids),
  );

  /// 取会话 → 执行 → 会话过期则刷新后重试一次。
  Future<T> _withSession<T>(
    String account,
    Future<T> Function(String sessionId) run,
  ) async {
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await run(sessionId);
    } on SspSessionExpiredException {
      final fresh = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await run(fresh);
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }
}
