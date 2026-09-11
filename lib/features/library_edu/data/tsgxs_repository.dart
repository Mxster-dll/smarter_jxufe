import 'dart:async';

import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_repository.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_clue_sweep.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 入馆教育业务仓库:负责「带会话调用 + 会话失效自动刷新重试一次」。
class TsgxsRepository {
  final TsgxsAuthRepository _auth;
  final TsgxsApiRemoteDataSource _api;

  TsgxsRepository({
    required TsgxsAuthRepository auth,
    required TsgxsApiRemoteDataSource api,
  }) : _auth = auth,
       _api = api;

  Future<T> _withSession<T>(
    String account,
    Future<T> Function(String cookie) run,
  ) async {
    final cookie = await _auth.getSessionCookie(account);
    try {
      return await run(cookie);
    } on TsgxsSessionExpiredException {
      // 会话失效(过期 / 被顶下线 / 服务器轮换)→ 重新走统一认证换取一次。
      final fresh = await _auth.refreshSessionCookie(account);
      return run(fresh);
    }
  }

  /// 首页章节与皮肤。
  Future<({List<String> chapterIds, String? themeId})> fetchHome(
    String account,
  ) => _withSession(account, (cookie) => _api.fetchHome(cookie));

  /// 章节地图。
  Future<TsgxsChapter> fetchChapter(
    String account, {
    required String chapterId,
    required String themeId,
  }) => _withSession(
    account,
    (cookie) =>
        _api.fetchChapter(cookie, chapterId: chapterId, themeId: themeId),
  );

  /// 学习内容页。
  Future<TsgxsContent> fetchContent(
    String account, {
    required String nodeId,
    required String themeId,
  }) => _withSession(
    account,
    (cookie) => _api.fetchContent(cookie, nodeId: nodeId, themeId: themeId),
  );

  /// **后门模式**:逐个「打开」本章线索内容页,诱导服务端把线索记为已学习。
  ///
  /// 实测(2026-09-11):服务端在 GET 内容页时即记账(无独立「标记已学」接口),
  /// 逐节点 GET 一遍后章节地图的 `isVisitAll` 会翻真,答题页随之放行。
  /// 每条线索之间停留 [dwell](默认 [tsgxsClueSweepDwell],2026-09-11 起 0.2 秒);拉完再复核
  /// [tsgxsClueSweepVerifyAttempts] 次(间隔 [tsgxsClueSweepVerifyGap]),把服务端是否真的放行如实返回。
  Future<TsgxsClueSweepResult> sweepClues(
    String account, {
    required String chapterId,
    required String themeId,
    Duration dwell = tsgxsClueSweepDwell,
    void Function(int done, int total, String nodeId)? onNodeFetched,
  }) async {
    var chapter = await fetchChapter(
      account,
      chapterId: chapterId,
      themeId: themeId,
    );
    final total = chapter.nodes.length;
    if (chapter.isVisitAll) {
      return TsgxsClueSweepResult(
        total: total,
        fetched: 0,
        alreadyLearned: true,
        verified: true,
        verifyAttempts: 0,
      );
    }
    var fetched = 0;
    for (var i = 0; i < chapter.nodes.length; i++) {
      final node = chapter.nodes[i];
      await fetchContent(account, nodeId: node.id, themeId: themeId);
      fetched++;
      onNodeFetched?.call(fetched, total, node.id);
      if (i < chapter.nodes.length - 1) {
        await Future<void>.delayed(dwell);
      }
    }
    var attempts = 0;
    var verified = false;
    while (attempts < tsgxsClueSweepVerifyAttempts) {
      attempts++;
      await Future<void>.delayed(tsgxsClueSweepVerifyGap);
      chapter = await fetchChapter(
        account,
        chapterId: chapterId,
        themeId: themeId,
      );
      if (chapter.isVisitAll) {
        verified = true;
        break;
      }
    }
    return TsgxsClueSweepResult(
      total: total,
      fetched: fetched,
      alreadyLearned: false,
      verified: verified,
      verifyAttempts: attempts,
    );
  }

  /// 我的成绩。
  Future<List<TsgxsGrade>> fetchGrades(String account) =>
      _withSession(account, (cookie) => _api.fetchGrades(cookie));

  /// 排行榜。
  Future<TsgxsRanking> fetchRanking(String account) =>
      _withSession(account, (cookie) => _api.fetchRanking(cookie));

  /// 个人资料。
  Future<TsgxsProfile> fetchProfile(String account) =>
      _withSession(account, (cookie) => _api.fetchProfile(cookie));

  /// 章节考试状态。
  Future<TsgxsExamStatus> fetchExamStatus(
    String account, {
    required String chapterId,
  }) => _withSession(
    account,
    (cookie) => _api.fetchExamStatus(cookie, chapterId: chapterId),
  );

  // ---------------- 闯关答题 ----------------

  /// 打开答题页(取本次考试的题目清单)。
  Future<TsgxsExamPage> fetchExamPage(
    String account, {
    required String chapterId,
  }) => _withSession(
    account,
    (cookie) => _api.fetchExamPage(cookie, chapterId: chapterId),
  );

  /// 取一道题。
  Future<TsgxsQuestion> fetchExamQuestion(
    String account, {
    required String questionId,
    String? examPageUrl,
  }) => _withSession(
    account,
    (cookie) => _api.fetchExamQuestion(
      cookie,
      questionId: questionId,
      examPageUrl: examPageUrl,
    ),
  );

  /// 提交单题评分。
  Future<TsgxsAnswerResult> submitAnswer(
    String account, {
    required String questionId,
    required String answer,
    required String chapterId,
    required String examRecordDetailsId,
    required int spendtime,
    String? helpId,
    String? examPageUrl,
  }) => _withSession(
    account,
    (cookie) => _api.submitAnswer(
      cookie,
      questionId: questionId,
      answer: answer,
      chapterId: chapterId,
      examRecordDetailsId: examRecordDetailsId,
      spendtime: spendtime,
      helpId: helpId,
      examPageUrl: examPageUrl,
    ),
  );

  /// 末题结算。
  Future<TsgxsExamFinishResult> finishExam(
    String account, {
    required String examRecordDetailsId,
    required String chapterId,
    required int spendtime,
    String? examPageUrl,
  }) => _withSession(
    account,
    (cookie) => _api.finishExam(
      cookie,
      examRecordDetailsId: examRecordDetailsId,
      chapterId: chapterId,
      spendtime: spendtime,
      examPageUrl: examPageUrl,
    ),
  );
}
