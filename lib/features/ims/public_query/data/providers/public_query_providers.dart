import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/datasources/public_query_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';

/// 公共查询数据源（复用全局 IMS Dio：会话失效时拦截器自动续期并重试）。
final publicQueryRemoteDataSourceProvider =
    Provider<PublicQueryRemoteDataSource>(
      (ref) => PublicQueryRemoteDataSource(ref.watch(currentImsDioProvider)),
    );

/// 取教务会话 ID（有缓存即返回、不发网络；`getJsessionId` 本身不强制刷新）。
Future<String> _jsessionId(Ref ref) async {
  final repository = await ref.watch(imsAuthRepositoryProvider.future);
  final result = await repository.getJsessionId();
  return result.fold(
    (failure) => throw StateError('$failure'),
    (id) => id ?? '',
  );
}

/// 「发布课表」的学年学期列表（`Ms_KBBP_FBXQLLJXAP`，逗号码）。
final publicQueryTermsProvider = FutureProvider<List<PublicQueryTerm>>((
  ref,
) async {
  final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
  final jsessionId = await _jsessionId(ref);
  return dataSource.fetchTerms(jsessionId: jsessionId);
});

/// 校区列表（`MsSchoolArea`）。
final publicQueryCampusesProvider = FutureProvider<List<PublicQueryOption>>((
  ref,
) async {
  final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
  final jsessionId = await _jsessionId(ref);
  return dataSource.fetchCampuses(jsessionId: jsessionId);
});

/// 教师部门列表（`MsDepartment`，教师课表的「部门」过滤）。
final publicQueryDepartmentsProvider = FutureProvider<List<PublicQueryOption>>((
  ref,
) async {
  final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
  final jsessionId = await _jsessionId(ref);
  return dataSource.fetchDepartments(jsessionId: jsessionId);
});

/// 学院列表（`MsYXB`，班级课表的「学院」），键 = 学年（`nj`）。
///
/// 实测 `isYXB=0` 才有数据；数据源里已固定。
final publicQueryCollegesProvider =
    FutureProvider.family<List<PublicQueryOption>, String>((ref, year) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      return dataSource.fetchColleges(jsessionId: jsessionId, year: year);
    });

/// 专业列表（`MsYXB_Specialty`），键 = `"<学年>|<学院代码>"`。
final publicQueryMajorsProvider =
    FutureProvider.family<List<PublicQueryOption>, String>((ref, key) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      final parts = key.split('|');
      return dataSource.fetchMajors(
        jsessionId: jsessionId,
        year: parts.isEmpty ? '' : parts.first,
        collegeCode: parts.length > 1 ? parts[1] : '',
      );
    });

/// 培养层次列表（`MsCodeset` + `DM-PYCC`）。
final publicQueryTrainLevelsProvider = FutureProvider<List<PublicQueryOption>>((
  ref,
) async {
  final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
  final jsessionId = await _jsessionId(ref);
  return dataSource.fetchTrainLevels(jsessionId: jsessionId);
});

/// 楼房列表（`MsSchoolArea_LF`），按校区过滤。
final publicQueryBuildingsProvider =
    FutureProvider.family<List<PublicQueryOption>, String>((
      ref,
      campusCode,
    ) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      return dataSource.fetchBuildings(
        jsessionId: jsessionId,
        campusCode: campusCode,
      );
    });

/// 教室列表（`MsSchoolArea_LF_JS`），键 = `"<校区>|<楼房>"`。
final publicQueryClassroomsProvider =
    FutureProvider.family<List<PublicQueryOption>, String>((ref, key) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      final parts = key.split('|');
      return dataSource.fetchClassrooms(
        jsessionId: jsessionId,
        campusCode: parts.isEmpty ? '' : parts.first,
        buildingCode: parts.length > 1 ? parts[1] : '',
      );
    });

/// 选择器候选列表（班级 / 教师 / 课程 / 教室）。
///
/// 键 = 请求的 [PublicQueryRequest.cacheKey]（含 `kind/term/校区/学院/专业` 等，
/// 所以换了过滤条件会自动重新拉；`PublicQueryRequest` 已实现值语义相等）。
final publicQueryComboBoxProvider =
    FutureProvider.family<List<PublicQueryOption>, PublicQueryRequest>((
      ref,
      request,
    ) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      return dataSource.fetchComboBox(
        jsessionId: jsessionId,
        className: request.kind.comboClassName,
        params: request.comboParams(),
        referer: 'https://jwxt.jxufe.edu.cn${request.kind.pagePath}',
      );
    });

/// 排课套数 `pkts`（报告端点必需；页面 `initPage()` 也要先问一次）。
final publicQueryPktsProvider = FutureProvider.family<String, PublicQueryTerm>((
  ref,
  term,
) async {
  final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
  final jsessionId = await _jsessionId(ref);
  return dataSource.fetchPkts(
    jsessionId: jsessionId,
    term: term,
    referer: 'https://jwxt.jxufe.edu.cn/kbbp/dykb.bjkb.html?menucode=SB03',
  );
});

/// 一次公共查询的结果。
class PublicQueryResult {
  /// 原始 HTML（GBK 已解码）。
  final String html;

  /// 解析出的对象课表（一表一对象）。
  final List<PublicTimetable> timetables;

  const PublicQueryResult({required this.html, required this.timetables});

  /// 教务明确回了「没有检索到记录！」。
  bool get isEmpty => isEmptyReport(html) || timetables.isEmpty;

  @override
  String toString() => 'PublicQueryResult(${timetables.length} 个对象)';
}

/// 查询课表（自动补 `pkts`）。
final publicQueryReportProvider =
    FutureProvider.family<PublicQueryResult, PublicQueryRequest>((
      ref,
      request,
    ) async {
      final dataSource = ref.watch(publicQueryRemoteDataSourceProvider);
      final jsessionId = await _jsessionId(ref);
      var effective = request;
      if (effective.pkts.isEmpty) {
        final pkts = await dataSource.fetchPkts(
          jsessionId: jsessionId,
          term: request.term,
          referer: 'https://jwxt.jxufe.edu.cn${request.kind.pagePath}',
        );
        effective = request.copyWith(pkts: pkts);
      }
      final html = await dataSource.queryReport(
        jsessionId: jsessionId,
        request: effective,
      );
      return PublicQueryResult(
        html: html,
        timetables: parsePublicTimetableReport(
          html,
          ownerPrefixes: [
            switch (request.kind) {
              PublicQueryKind.klass => '班级',
              PublicQueryKind.teacher => '教师',
              PublicQueryKind.classroom => '教室',
              PublicQueryKind.course => '课程',
            },
          ],
        ),
      );
    });
