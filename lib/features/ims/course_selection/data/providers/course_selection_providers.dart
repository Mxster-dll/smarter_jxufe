/// 教务「选课」的 providers —— 数据源 / 仓库 / 各查询与写操作。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/course_selection_repository.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_write_check.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';

/// 选课数据源（复用全局 IMS Dio，与其它教务模块同一份会话）。
final courseSelectionRemoteDataSourceProvider =
    Provider<CourseSelectionRemoteDataSource>(
      (ref) =>
          CourseSelectionRemoteDataSource(ref.watch(currentImsDioProvider)),
    );

/// 选课仓库（自带「会话失效 → 续期 → 重试一次」）。
final courseSelectionRepositoryProvider =
    FutureProvider<CourseSelectionRepository>((ref) async {
      final remote = ref.watch(courseSelectionRemoteDataSourceProvider);
      final auth = await ref.watch(imsAuthRepositoryProvider.future);
      final session = ref.watch(imsSessionProvider);
      return CourseSelectionRepository(
        remote: remote,
        ticket: () async =>
            (await auth.getJsessionId()).fold((_) => null, (id) => id),
        session: session,
      );
    });

/// 选课请求里的学号 `xh` —— **优先用教务选课模块自己给的值**
/// （`getWsxkTimeRange.action` 响应里的 `xh`）。
///
/// ⚠ 2026-09-15 实测（用户点「选择」→「当前选课操作的用户不是选课学生本人！」）：
/// - 教务选课页的 `xh` 输入框由 `getWsxkTimeRange` 的 `xh` 字段填充，提交时原样回传
///   （`wsxk.zx_promt.jsp` 的提交 JS 只做「serialize → 去掉 electiveCourseForm.
///   前缀 → `getEncParams`」，**没有第二层加密**；被注释掉的 RSA/DES 两种方式已废弃），
///   本机该值 = `201600035929`（= 学籍 `<xh>` = `serialNo`）；
/// - **写操作**（`saveElectiveCourse.action`）拿表单里的 `xh` 与「本人」比对 →
///   传学籍 `<yhxh>`（旧 getter 取的那个 `2000000000`）会被拒；
/// - **只读端点对此完全不敏感**（实测：`isSelectableSkbjdm` / 确认页 / 额度 /
///   课表接口，传 `<xh>`、`<yhxh>`、空串结果逐字节一致），所以只有提交会暴露差异。
///
/// 因此这里以「教务给的值」为准，取不到才回退学籍。
final selectionStudentIdProvider = FutureProvider<String>((ref) async {
  final session = await ref.watch(
    selectionSessionProvider(SelectionChannel.plan).future,
  );
  if (session.xh.isNotEmpty) return session.xh;
  final repository = await ref.watch(studentInfoRepositoryProvider.future);
  return repository.getCachedStudentInfo().fold(
    (_) => '',
    (info) => info?.serialNo ?? '',
  );
});

/// 当前学生姓名（退选表单要回传 `zymc` 之外的展示信息，可空）。
final selectionStudentNameProvider = FutureProvider<String>((ref) async {
  final repository = await ref.watch(studentInfoRepositoryProvider.future);
  return repository.getCachedStudentInfo().fold((_) => '', (info) {
    return info?.name ?? '';
  });
});

/// 选课会话元信息（轮次 / 时间区段 / 课程范围 / 学籍年级专业）。
final selectionSessionProvider =
    FutureProvider.family<SelectionSession, SelectionChannel>((
      ref,
      channel,
    ) async {
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchSession(channel);
    });

/// 已选学分 / 门数额度。
final selectionQuotaProvider =
    FutureProvider.family<SelectionQuota, SelectionChannel>((
      ref,
      channel,
    ) async {
      final session = await ref.watch(selectionSessionProvider(channel).future);
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (!session.ok || studentId.isEmpty) return SelectionQuota.empty;
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchQuota(session, studentId);
    });

/// 课程范围下拉（`MsKcfw`）。
///
/// ⚠️ 原页面 `wsxk.zx.html` 里这一项的**最终选项**不是这个下拉，而是
/// `getWsxkTimeRange` 返回的 `kcfw`/`kcfwmc`（页面 `$("kcfw").length=0` 后重建）
/// → 界面层优先用 `SelectionSession.scopeCodes/scopeNames`，取不到才回退到这里。
final selectionScopeOptionsProvider =
    FutureProvider.family<List<CourseScope>, SelectionChannel>((
      ref,
      channel,
    ) async {
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchScopes(channel);
    });

/// 院(系)/部下拉（原页面 `sel_yxb` ← `MsDepartmentYXB`；只在「跨学期」范围显示）。
final selectionDepartmentOptionsProvider =
    FutureProvider.family<List<CourseScope>, SelectionChannel>((
      ref,
      channel,
    ) async {
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchDepartments();
    });

/// 年级/专业下拉（原页面 `njzy` ← `STUD_preElcGradeSpecialty` 级联）。
///
/// 实测：没有学生上下文时该端点回空 `<root></root>`（选项为空），
/// 界面按「无选项」处理即可 —— 「跨学期」范围下若为空，点「检索」会像原页面
/// 一样提示「需选定年级/专业！」。
final selectionGradeMajorOptionsProvider =
    FutureProvider.family<List<CourseScope>, GradeMajorQuery>((
      ref,
      query,
    ) async {
      final session = await ref.watch(
        selectionSessionProvider(query.channel).future,
      );
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (studentId.isEmpty) return const <CourseScope>[];
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchGradeMajors(
        session: session,
        studentId: studentId,
        query: query,
      );
    });

/// 可选课程列表。
final optionalCoursesProvider =
    FutureProvider.family<
      ({List<OptionalCourse> courses, int? total}),
      OptionalCourseQuery
    >((ref, query) async {
      final session = await ref.watch(
        selectionSessionProvider(query.channel).future,
      );
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (!session.ok || studentId.isEmpty) {
        return (courses: const <OptionalCourse>[], total: 0);
      }
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchOptionalCourses(
        session: session,
        studentId: studentId,
        query: query,
      );
    });

/// 某门课的教学班列表（选课确认用）。
final courseSectionsProvider =
    FutureProvider.family<List<CourseSection>, CourseSectionQuery>((
      ref,
      query,
    ) async {
      final session = await ref.watch(
        selectionSessionProvider(query.channel).future,
      );
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (!session.ok || studentId.isEmpty) return const <CourseSection>[];
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchSections(
        session: session,
        studentId: studentId,
        query: query,
      );
    });

/// 本学期选课结果（服务端渲染页）。
final selectionResultProvider = FutureProvider<SelectionResult>((ref) async {
  final repository = await ref.watch(courseSelectionRepositoryProvider.future);
  return repository.fetchResult();
});

/// 入学以来正选结果。
final allSelectionResultProvider = FutureProvider<SelectionResult>((ref) async {
  final studentId = await ref.watch(selectionStudentIdProvider.future);
  final session = await ref.watch(
    selectionSessionProvider(SelectionChannel.plan).future,
  );
  if (studentId.isEmpty) return SelectionResult.empty;
  final repository = await ref.watch(courseSelectionRepositoryProvider.future);
  return repository.fetchAllResult(
    studentId: studentId,
    nj: session.nj,
    zydm: session.zydm,
  );
});

/// 被取消课程。
final cancelledCoursesProvider = FutureProvider<List<CancelledCourse>>((
  ref,
) async {
  final repository = await ref.watch(courseSelectionRepositoryProvider.future);
  return repository.fetchCancelled();
});

/// 查询课表（`tableId=5327042` 的通用列表行）。
final selectionTimetableProvider =
    FutureProvider.family<
      ({List<Map<String, String>> rows, int? total}),
      SelectionChannel
    >((ref, channel) async {
      final session = await ref.watch(selectionSessionProvider(channel).future);
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (!session.ok || studentId.isEmpty) {
        return (rows: const <Map<String, String>>[], total: 0);
      }
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchTimetable(
        session: session,
        studentId: studentId,
        gradeMajor: '${session.nj}/${session.zydm}',
      );
    });

/// 申请扩容列表（`tableId=5929098`）。
final selectionExpandProvider =
    FutureProvider.family<
      ({List<Map<String, String>> rows, int? total}),
      SelectionChannel
    >((ref, channel) async {
      final session = await ref.watch(selectionSessionProvider(channel).future);
      final studentId = await ref.watch(selectionStudentIdProvider.future);
      if (!session.ok || studentId.isEmpty) {
        return (rows: const <Map<String, String>>[], total: 0);
      }
      final repository = await ref.watch(
        courseSelectionRepositoryProvider.future,
      );
      return repository.fetchExpand(
        session: session,
        studentId: studentId,
        gradeMajor: '${session.nj}/${session.zydm}',
      );
    });

/// 写操作门面（提交选课 / 退选），成功后自动刷新相关列表。
final courseSelectionActionsProvider = Provider<CourseSelectionActions>(
  (ref) => CourseSelectionActions(ref),
);

class CourseSelectionActions {
  CourseSelectionActions(this._ref);

  final Ref _ref;

  /// 提交选课前先问教务「该课程是否可选」，避免白提交一次。
  Future<SelectionWriteResult> checkSelectable({
    required SelectionChannel channel,
    required String internalCode,
  }) async {
    final session = await _ref.read(selectionSessionProvider(channel).future);
    final studentId = await _ref.read(selectionStudentIdProvider.future);
    if (!session.ok || studentId.isEmpty) {
      return const SelectionWriteResult(ok: false, message: '未取到教务会话，请稍后重试');
    }
    final repository = await _ref.read(
      courseSelectionRepositoryProvider.future,
    );
    return repository.checkSelectable(
      session: session,
      studentId: studentId,
      internalCode: internalCode,
    );
  }

  Future<SelectionWriteResult> submit({
    required SelectionChannel channel,
    required OptionalCourse course,
    required CourseSection section,
    required bool buyBook,
    required bool isCx,
    required bool isYxtj,
    required bool allowTimeConflict,
  }) async {
    final session = await _ref.read(selectionSessionProvider(channel).future);
    final studentId = await _ref.read(selectionStudentIdProvider.future);
    if (!session.ok || studentId.isEmpty) {
      return const SelectionWriteResult(ok: false, message: '未取到教务会话，请稍后重试');
    }
    final repository = await _ref.read(
      courseSelectionRepositoryProvider.future,
    );
    final result = await repository.submit(
      session: session,
      studentId: studentId,
      internalCode: course.internalCode,
      section: section,
      credits: course.credits?.toStringAsFixed(1) ?? '',
      nj: session.nj,
      zydm: session.zydm,
      kclb1: course.kclb1,
      kclb2: course.kclb2,
      kclb3: course.kclb3,
      khfs: course.examMode,
      buyBook: buyBook,
      isCx: isCx,
      isYxtj: isYxtj,
      allowTimeConflict: allowTimeConflict,
    );
    if (result.ok) _invalidateAfterWrite();
    return result;
  }

  /// 选课（提交）+ **提交后对账**（2026-09-15 事故后新增）。
  ///
  /// 教务回 `status=200` 不等于「真的选上了」（时间冲突 / 容量被抢 / 静默失败都出现过），
  /// 所以**无论写入应答是什么**都重新拉一次选课结果对账，并刷新界面。
  Future<({SelectionWriteResult write, SelectionSubmitCheck? check})>
  submitAndVerify({
    required SelectionChannel channel,
    required OptionalCourse course,
    required CourseSection section,
    required bool buyBook,
    required bool isCx,
    required bool isYxtj,
    required bool allowTimeConflict,
  }) async {
    final write = await submit(
      channel: channel,
      course: course,
      section: section,
      buyBook: buyBook,
      isCx: isCx,
      isYxtj: isYxtj,
      allowTimeConflict: allowTimeConflict,
    );
    // ⚠ 不在 `!write.ok` 时早退（2026-09-15 二轮）：教务的写应答零信息量
    //   （见 parseWriteEnvelope），而早退还会跳过 `_invalidateAfterWrite()`
    //   → 界面停在过期列表上，用户再点一次就可能出事。
    final check = await _verifySubmit(course);
    _invalidateAfterWrite();
    return (write: write, check: check);
  }

  Future<SelectionSubmitCheck?> _verifySubmit(OptionalCourse course) async {
    try {
      final repository = await _ref.read(
        courseSelectionRepositoryProvider.future,
      );
      final fresh = await repository.fetchResult();
      return verifySubmission(
        after: fresh,
        courseCode: course.courseCode,
        courseName: course.name,
      );
    } catch (_) {
      // 对账失败不等于写入失败：界面会说「已提交，但无法核对结果」。
      return null;
    }
  }

  /// 退选①：**写前重读**最新选课结果并核对目标行（只读，**不写入**）。
  ///
  /// 给确认弹窗提供新鲜数据：弹窗展示的那一门就是马上要提交的那一门。
  /// 核对不过（列表里已没有这个码 / 同码多行 / 码对应的课名不是用户看到的那门）
  /// → 一律拦下并刷新列表，**绝不提交**。
  Future<SelectionCancelPreparation> prepareCancel({
    required String itemCode,
    required String courseName,
  }) async {
    final fresh = await _readFreshResult();
    if (fresh == null) {
      _invalidateAfterWrite();
      return const SelectionCancelPreparation(
        fresh: null,
        readFailed: true,
        message: '无法读取最新选课结果（网络或教务会话异常），**已阻止本次退选**，请刷新后重试',
      );
    }
    final check = checkFreshCancelTarget(
      fresh: fresh,
      itemCode: itemCode,
      courseName: courseName,
    );
    if (!check.ok) _invalidateAfterWrite(); // 列表已过期 → 让界面换成最新数据
    return SelectionCancelPreparation(fresh: check, message: check.message);
  }

  /// 退选②：再重读核对 → 提交 → **无论应答如何都重读 + 对账 + 刷新界面**。
  ///
  /// 三条硬规矩（2026-09-15 用户实测「课已退但 App 报网络异常、列表还留着那门课」后立）：
  /// 1. 提交前必须拿到**刚刚重读**的列表（[before]），核对不过就不提交；
  /// 2. 教务应答只代表「收下了」，**不代表退掉了** → 提交后必须重读并对账；
  /// 3. 任何分支（成功 / 拒绝 / 抛异常 / 读不到结果）都要 `_invalidateAfterWrite()`，
  ///    绝不能让界面停在**已经过期**的列表上。
  Future<SelectionCancelOutcome> cancelChecked({
    required String itemCode,
    required String courseName,
  }) async {
    final before = await _readFreshResult();
    if (before == null) {
      _invalidateAfterWrite();
      return SelectionCancelOutcome(
        freshReadFailed: true,
        message: selectionCancelMessage(
          fresh: null,
          write: null,
          check: null,
          refreshed: false,
          freshReadFailed: true,
          writeAttempted: false,
        ),
      );
    }
    final fresh = checkFreshCancelTarget(
      fresh: before,
      itemCode: itemCode,
      courseName: courseName,
    );
    if (!fresh.ok) {
      _invalidateAfterWrite();
      return SelectionCancelOutcome(
        fresh: fresh,
        refreshed: true,
        message: selectionCancelMessage(
          fresh: fresh,
          write: null,
          check: null,
          refreshed: true,
          freshReadFailed: false,
          writeAttempted: false,
        ),
      );
    }
    final targetCode = fresh.course?.itemCode.trim() ?? itemCode.trim();
    final studentId = await _ref.read(selectionStudentIdProvider.future);
    final session = await _ref.read(
      selectionSessionProvider(SelectionChannel.plan).future,
    );
    if (studentId.isEmpty || !session.ok) {
      _invalidateAfterWrite();
      return SelectionCancelOutcome(
        fresh: fresh,
        refreshed: true,
        message: selectionCancelMessage(
          fresh: fresh,
          write: const SelectionWriteResult(
            ok: false,
            message: '未取到教务会话，请稍后重试',
          ),
          check: null,
          refreshed: true,
          freshReadFailed: false,
          writeAttempted: false,
        ),
      );
    }
    final repository = await _ref.read(
      courseSelectionRepositoryProvider.future,
    );
    SelectionWriteResult? write;
    try {
      write = await repository.cancel(
        studentId: studentId,
        xn: session.xn,
        xqM: session.xqM,
        nj: session.nj,
        zydm: session.zydm,
        zymc: session.zymc,
        itemCodes: [targetCode],
        withinWindow: session.open,
      );
    } catch (_) {
      // 请求可能已经到达教务 —— 不能当成「没退成」，下面照样重读对账。
      write = null;
    }
    SelectionCancelCheck? check;
    var refreshed = false;
    try {
      final after = await repository.fetchResult();
      check = verifyCancellation(
        before: before,
        after: after,
        requestedItemCode: targetCode,
      );
      refreshed = true;
    } catch (_) {
      check = null;
    }
    _invalidateAfterWrite(); // ⚠ 无条件刷新：绝不留过期列表
    return SelectionCancelOutcome(
      fresh: fresh,
      write: write,
      check: check,
      refreshed: refreshed,
      writeAttempted: true,
      message: selectionCancelMessage(
        fresh: fresh,
        write: write,
        check: check,
        refreshed: refreshed,
        freshReadFailed: false,
        writeAttempted: true,
      ),
    );
  }

  /// 重读选课结果（失败返回 null，调用方负责拦下写入）。
  Future<SelectionResult?> _readFreshResult() async {
    try {
      final repository = await _ref.read(
        courseSelectionRepositoryProvider.future,
      );
      return await repository.fetchResult();
    } catch (_) {
      return null;
    }
  }

  void _invalidateAfterWrite() {
    _ref.invalidate(selectionResultProvider);
    _ref.invalidate(allSelectionResultProvider);
    _ref.invalidate(selectionQuotaProvider);
    _ref.invalidate(optionalCoursesProvider);
    _ref.invalidate(cancelledCoursesProvider);
  }
}
