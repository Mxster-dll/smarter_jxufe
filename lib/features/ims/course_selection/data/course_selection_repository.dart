/// 教务「选课」仓库 —— 把数据源、会话与解析拼成领域结果。
library;

import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';

/// 一次「网上选课」列表查询的条件（provider 的 family key）。
///
/// 字段 = 原页面 `wsxk.zx.html` 表单里**真正服务端生效**的那几个：
/// `kcfw`（课程范围）/ `njzy`（年级专业）/ `sel_yxb`（院系部）/ `kcmc`（课程）/ `xwxmkc`（限未选满）。
/// 「课程类别 `lbgl`」「课程属性 `kcsx`」不在这里 —— 它们是客户端过滤
/// （见 `domain/selection_filters.dart`）。
class OptionalCourseQuery {
  const OptionalCourseQuery({
    required this.channel,
    required this.scope,
    this.keyword = '',
    this.njzy = '',
    this.department = '',
    this.onlyWithVacancy = true,
  });

  final SelectionChannel channel;

  /// 课程范围码（`kcfw`，取自 `getWsxkTimeRange` 的 `kcfw`／`MsKcfw` 下拉）。
  final String scope;

  /// 课程名关键字（`kcmc`：课程代码前缀匹配或课程名模糊匹配）。
  final String keyword;

  /// 年级专业（教务 `njzy`，跨学期范围必填）。
  final String njzy;

  /// 院(系)/部代码（教务 `sel_yxb`，仅「跨学期」范围用）。
  final String department;

  /// 「限未选满的课程」（教务 `xwxmkc`；原页面默认勾选）。
  final bool onlyWithVacancy;

  OptionalCourseQuery copyWith({
    SelectionChannel? channel,
    String? scope,
    String? keyword,
    String? njzy,
    String? department,
    bool? onlyWithVacancy,
  }) => OptionalCourseQuery(
    channel: channel ?? this.channel,
    scope: scope ?? this.scope,
    keyword: keyword ?? this.keyword,
    njzy: njzy ?? this.njzy,
    department: department ?? this.department,
    onlyWithVacancy: onlyWithVacancy ?? this.onlyWithVacancy,
  );

  @override
  bool operator ==(Object other) =>
      other is OptionalCourseQuery &&
      other.channel == channel &&
      other.scope == scope &&
      other.keyword == keyword &&
      other.njzy == njzy &&
      other.department == department &&
      other.onlyWithVacancy == onlyWithVacancy;

  @override
  int get hashCode =>
      Object.hash(channel, scope, keyword, njzy, department, onlyWithVacancy);

  @override
  String toString() =>
      'OptionalCourseQuery(${channel.name}, $scope, "$keyword", '
      'njzy="$njzy", yxb="$department", 限未选满=$onlyWithVacancy)';
}

/// 年级/专业级联下拉的 family key（跟着课程范围与院系走）。
class GradeMajorQuery {
  const GradeMajorQuery({
    required this.channel,
    required this.scope,
    this.department = '',
  });

  final SelectionChannel channel;
  final String scope;
  final String department;

  @override
  bool operator ==(Object other) =>
      other is GradeMajorQuery &&
      other.channel == channel &&
      other.scope == scope &&
      other.department == department;

  @override
  int get hashCode => Object.hash(channel, scope, department);

  @override
  String toString() =>
      'GradeMajorQuery(${channel.name}, $scope, yxb="$department")';
}

/// 教学班查询的 family key。
class CourseSectionQuery {
  const CourseSectionQuery({
    required this.channel,
    required this.internalCode,
    required this.courseName,
  });

  final SelectionChannel channel;

  /// 教务内部课程代码（列表隐藏格 `kcdm`）。
  final String internalCode;
  final String courseName;

  @override
  bool operator ==(Object other) =>
      other is CourseSectionQuery &&
      other.channel == channel &&
      other.internalCode == internalCode;

  @override
  int get hashCode => Object.hash(channel, internalCode);

  @override
  String toString() => 'CourseSectionQuery($internalCode)';
}

/// 选课仓库：所有方法都自带「会话失效 → 续期 → 重试一次」。
class CourseSelectionRepository {
  CourseSelectionRepository({
    required CourseSelectionRemoteDataSource remote,
    required Future<String?> Function() ticket,
    required ImsSession? session,
  }) : _remote = remote,
       _ticket = ticket,
       _session = session;

  final CourseSelectionRemoteDataSource _remote;

  /// 取当前 JSESSIONID（有缓存即返回，不发网络）。
  final Future<String?> Function() _ticket;

  /// 续期用（`ImsSession.renew`）；测试环境可为 null。
  final ImsSession? _session;

  Future<T> _run<T>(Future<T> Function() action) async {
    _remote.jsessionId = await _ticket() ?? '';
    try {
      return await action();
    } on SelectionSessionExpired {
      final session = _session;
      if (session == null) rethrow;
      final fresh = await session.renew();
      if (fresh.isEmpty) rethrow;
      _remote.jsessionId = fresh;
      return action();
    }
  }

  // ------------------------------------------------------------- 元信息

  Future<SelectionSession> fetchSession(SelectionChannel channel) =>
      _run(() => _remote.fetchSession(channel: channel));

  Future<SelectionQuota> fetchQuota(
    SelectionSession session,
    String studentId,
  ) => _run(
    () => _remote.fetchQuota(
      xn: session.xn,
      xqM: session.xqM,
      studentId: studentId,
    ),
  );

  Future<StudentGradeMajor> fetchGradeMajor(String studentId) =>
      _run(() => _remote.fetchGradeMajor(studentId: studentId));

  Future<List<CourseScope>> fetchScopes(SelectionChannel channel) =>
      _run(() => _remote.fetchScopes(xktype: channel.xktype));

  /// 院(系)/部下拉（原页面 `sel_yxb`）。
  Future<List<CourseScope>> fetchDepartments() =>
      _run(() => _remote.fetchDepartments());

  /// 年级/专业下拉（原页面 `njzy`，级联；无选项时返回空列表）。
  Future<List<CourseScope>> fetchGradeMajors({
    required SelectionSession session,
    required String studentId,
    required GradeMajorQuery query,
  }) async {
    final xml = await _run(
      () => _remote.fetchGradeMajorsXml(
        session: session,
        studentId: studentId,
        scope: query.scope,
        department: query.department,
      ),
    );
    return parseDropListXml(xml);
  }

  // ------------------------------------------------------------- 只读列表

  Future<({List<OptionalCourse> courses, int? total})> fetchOptionalCourses({
    required SelectionSession session,
    required String studentId,
    required OptionalCourseQuery query,
  }) async {
    final html = await _run(
      () => _remote.fetchOptionalCoursesHtml(
        session: session,
        studentId: studentId,
        scope: query.scope,
        keyword: query.keyword,
        njzy: query.njzy,
        department: query.department,
        onlyWithVacancy: query.onlyWithVacancy,
      ),
    );
    return parseOptionalCourses(html);
  }

  Future<List<CourseSection>> fetchSections({
    required SelectionSession session,
    required String studentId,
    required CourseSectionQuery query,
  }) async {
    final html = await _run(
      () => _remote.fetchSectionsHtml(
        session: session,
        studentId: studentId,
        internalCode: query.internalCode,
      ),
    );
    final page = parseSections(html);
    return page;
  }

  Future<SelectionResult> fetchResult() async {
    final html = await _run(_remote.fetchResultHtml);
    return parseSelectionResult(html);
  }

  Future<SelectionResult> fetchAllResult({
    required String studentId,
    required String nj,
    required String zydm,
  }) async {
    final html = await _run(
      () =>
          _remote.fetchAllResultHtml(studentId: studentId, nj: nj, zydm: zydm),
    );
    return parseSelectionResult(html);
  }

  Future<List<CancelledCourse>> fetchCancelled() async {
    final html = await _run(_remote.fetchCancelledHtml);
    return parseCancelledCourses(html).courses;
  }

  Future<({List<Map<String, String>> rows, int? total})> fetchTimetable({
    required SelectionSession session,
    required String studentId,
    required String gradeMajor,
  }) async {
    final html = await _run(
      () => _remote.fetchTimetableHtml(
        session: session,
        studentId: studentId,
        gradeMajor: gradeMajor,
      ),
    );
    final page = parseDataTableRows(html);
    return (rows: page.rows, total: page.total);
  }

  Future<({List<Map<String, String>> rows, int? total})> fetchExpand({
    required SelectionSession session,
    required String studentId,
    required String gradeMajor,
  }) async {
    final html = await _run(
      () => _remote.fetchExpandHtml(
        session: session,
        studentId: studentId,
        gradeMajor: gradeMajor,
      ),
    );
    final page = parseDataTableRows(html);
    return (rows: page.rows, total: page.total);
  }

  // ------------------------------------------------------------- 写操作

  Future<SelectionWriteResult> checkSelectable({
    required SelectionSession session,
    required String studentId,
    required String internalCode,
  }) => _run(
    () => _remote.checkSelectable(
      xn: session.xn,
      xqM: session.xqM,
      studentId: studentId,
      internalCode: internalCode,
    ),
  );

  /// 提交选课：把确认页表单字段（**不带** `electiveCourseForm.` 前缀）交给教务。
  Future<SelectionWriteResult> submit({
    required SelectionSession session,
    required String studentId,
    required String internalCode,
    required CourseSection section,
    required String credits,
    required String nj,
    required String zydm,
    required String kclb1,
    required String kclb2,
    required String kclb3,
    required String khfs,
    required bool buyBook,
    required bool isCx,
    required bool isYxtj,
    required bool allowTimeConflict,
  }) {
    final fields = <String, String>{
      'xktype': '${session.xktype}',
      'yxsjct': session.yxsjct,
      'xn': session.xn,
      'xq': session.xqM,
      'xh': studentId,
      'nj': nj,
      'zydm': zydm,
      'kcdm': internalCode,
      'kclb1': kclb1,
      'kclb2': kclb2,
      'kclb3': kclb3,
      'khfs': khfs,
      'xfsx': '',
      'mssx': '',
      'skbjdm': section.classCode,
      'skbzdm': section.classGroupCode,
      'xf': credits,
      'is_checkTime': allowTimeConflict ? '0' : '1',
      'zfx_m': section.timeConflictFlag,
      'outnumber': section.outnumber,
      'kcfw': session.scopeCodes.isEmpty ? 'zxbnj' : session.scopeCodes.first,
      'njzy': '',
      'xk_points': '0',
      'is_buy_book': buyBook ? '1' : '0',
      'is_cx': isCx ? '1' : '0',
      'is_yxtj': isYxtj ? '1' : '0',
      'lcid': session.lcid,
      'xxkckzfs': session.xxkckzfs,
      'yxkzyfxxk': session.yxkzyfxxk,
      'xsszxq': '3',
      'xqdm': section.campusCode,
      'kcmc': section.className,
    };
    return _run(
      () => _remote.submitSelection(
        session: session,
        studentId: studentId,
        fields: fields,
      ),
    );
  }

  /// 退选（选课结果页的明文端点）。
  Future<SelectionWriteResult> cancel({
    required String studentId,
    required String xn,
    required String xqM,
    required String nj,
    required String zydm,
    required String zymc,
    required List<String> itemCodes,
    required bool withinWindow,
  }) => _run(
    () => _remote.cancelSelection(
      studentId: studentId,
      xn: xn,
      xqM: xqM,
      nj: nj,
      zydm: zydm,
      zymc: zymc,
      itemCodes: itemCodes,
      withinWindow: withinWindow,
    ),
  );
}
