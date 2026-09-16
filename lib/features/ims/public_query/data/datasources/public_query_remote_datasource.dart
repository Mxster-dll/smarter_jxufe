import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';

/// 公共查询数据源（教务 `/kbbp/*` 登录版页面背后的接口）。
///
/// 实测铁律（2026-09-14，见 `reverse_engineering/公共查询接口.md`）：
/// - **报告端点 `/kbbp/dykb.GS1.jsp` 是普通 JSP**：只解析
///   `application/x-www-form-urlencoded`。用 dio 的 `FormData`（multipart）提交时
///   服务端 `request.getParameter()` 全部为 null → 报告恒回「没有检索到记录！」。
///   所以这里**手工拼 urlencoded 字符串体**（同 `period_table_remote_datasource.dart`）。
/// - 编码三分：报告 = **GBK**；下拉列表 JSON 与选择器 XML = **UTF-8**。
/// - 大树响应（教室课表整栋楼 1.7MB）耗时 >20s，必须放宽 `receiveTimeout`。
class PublicQueryRemoteDataSource {
  PublicQueryRemoteDataSource(this._dio);

  final Dio _dio;

  /// 表单体一律手工拼接，避免被当成 multipart。
  static String encodeForm(Map<String, dynamic> form) => form.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}',
      )
      .join('&');

  Future<Response<List<int>>> _postWith(
    String jsessionId,
    String path,
    Map<String, dynamic> form, {
    required String referer,
    String query = '',
  }) {
    final full = query.isEmpty ? path : '$path?$query';
    return _dio.request<List<int>>(
      full,
      data: encodeForm(form),
      options: Options(
        method: 'POST',
        responseType: ResponseType.bytes,
        contentType: Headers.formUrlEncodedContentType,
        receiveTimeout: const Duration(seconds: 150),
        headers: {'Cookie': 'JSESSIONID=$jsessionId', 'Referer': referer},
      ),
    );
  }

  /// 下拉列表原始 JSON（UTF-8，调用方用 [parseDropListOptions] 解析）。
  Future<String> fetchDropListRaw({
    required String jsessionId,
    required String comboBoxName,
    String paramValue = '',
    bool isYXB = false,
    bool isCDDW = false,
    bool isXQ = false,
    bool isDJKSLB = false,
    bool isZY = false,
  }) async {
    final response = await _postWith(
      jsessionId,
      '/frame/droplist/getDropLists.action',
      {
        'comboBoxName': comboBoxName,
        'paramValue': paramValue,
        'isYXB': isYXB ? '1' : '0',
        'isCDDW': isCDDW ? '1' : '0',
        'isXQ': isXQ ? '1' : '0',
        'isDJKSLB': isDJKSLB ? '1' : '0',
        'isZY': isZY ? '1' : '0',
      },
      referer: 'https://jwxt.jxufe.edu.cn/kbbp/dykb.bjkb.html?menucode=SB03',
    );
    final body = _decodeUtf8(response.data ?? const []);
    if (isExpiredSession(body)) throw StateError('凭证已失效，请重新登录！');
    return body;
  }

  /// 取下拉列表并解析。
  Future<List<PublicQueryOption>> fetchDropList({
    required String jsessionId,
    required String comboBoxName,
    String paramValue = '',
  }) async => parseDropListOptions(
    await fetchDropListRaw(
      jsessionId: jsessionId,
      comboBoxName: comboBoxName,
      paramValue: paramValue,
    ),
  );

  /// 可选学年学期（`Ms_KBBP_FBXQLLJXAP` = **发布课表**的学年学期，逗号码 `2026,0`）。
  Future<List<PublicQueryTerm>> fetchTerms({
    required String jsessionId,
  }) async => parseTermOptions(
    await fetchDropListRaw(
      jsessionId: jsessionId,
      comboBoxName: 'Ms_KBBP_FBXQLLJXAP',
    ),
  );

  /// 校区列表（`MsSchoolArea`：`1` 蛟桥园 / `3` 麦庐园 / `4` 枫林园 / `05` 深圳 …）。
  Future<List<PublicQueryOption>> fetchCampuses({required String jsessionId}) =>
      fetchDropList(jsessionId: jsessionId, comboBoxName: 'MsSchoolArea');

  /// 教师部门列表（`MsDepartment`，教师课表的「部门」用）。
  Future<List<PublicQueryOption>> fetchDepartments({
    required String jsessionId,
  }) => fetchDropList(jsessionId: jsessionId, comboBoxName: 'MsDepartment');

  /// 学院列表（`MsYXB`，班级课表的「学院」用）。
  ///
  /// 实测（2026-09-14）：**必须 `isYXB=0`**——`isYXB=1` 恒返回 `[]`（曾因此误判
  /// 「分学院不可用」，实际是把查询参数写错）。`paramValue = "nj=<学年>"`，
  /// 选项值 = JSON 的 `code`（即学院代码 `dwh`，会计学院 = `05`）。
  Future<List<PublicQueryOption>> fetchColleges({
    required String jsessionId,
    required String year,
  }) => fetchDropListRaw(
    jsessionId: jsessionId,
    comboBoxName: 'MsYXB',
    paramValue: 'nj=$year',
  ).then(parseDropListOptions);

  /// 专业列表（`MsYXB_Specialty`，班级课表的「专业」用）。
  ///
  /// 实测：`paramValue = "nj=<学年>&dwh=<学院代码>"`（会计学院 → 9 个专业），
  /// 选项值 = `code`（= 专业代码 `zydm`）。
  Future<List<PublicQueryOption>> fetchMajors({
    required String jsessionId,
    required String year,
    required String collegeCode,
  }) => fetchDropList(
    jsessionId: jsessionId,
    comboBoxName: 'MsYXB_Specialty',
    paramValue: 'nj=$year&dwh=$collegeCode',
  );

  /// 培养层次列表（`MsCodeset` + `DM-PYCC`：`01`博士 … `05`本科 … `08`专升本）。
  ///
  /// 实测是**真过滤条件**：同一本科班级 `selPYCC=05` 命中，`=02`（统招本科）返回空，
  /// 空串 = 不限（与 `05` 对本科班级等价）。
  Future<List<PublicQueryOption>> fetchTrainLevels({
    required String jsessionId,
  }) => fetchDropList(
    jsessionId: jsessionId,
    comboBoxName: 'MsCodeset',
    paramValue: 'DM-PYCC',
  );

  /// 楼房列表（`MsSchoolArea_LF`，教室课表用）。
  Future<List<PublicQueryOption>> fetchBuildings({
    required String jsessionId,
    String campusCode = '',
  }) => fetchDropList(
    jsessionId: jsessionId,
    comboBoxName: 'MsSchoolArea_LF',
    paramValue: campusCode.isEmpty ? '' : 'xqdm=$campusCode',
  );

  /// 教室列表（`MsSchoolArea_LF_JS`）——**这是能拿到 `hidFJBH` 可用代码的唯一入口**。
  ///
  /// 实测（2026-09-14）：`paramValue = "xq_m=<校区>&jslx_m=&lf_m=<楼房>"` 返回
  /// `[{"code":"1000752","name":"蛟三教3101[40][一般教室]"}, …]`；该 code 直接作为
  /// `hidFJBH` + `selJSMC` 提交即可精确查到单间教室（`hidCXLX=fjsi`）。
  /// 注意 `CombBoxServlet.jsp` 的 `jxap_combbox_js` 用同样的 `lf_m` 会返回空表
  /// （`selLF` 的楼栋码与它内部使用的楼房码不是同一套），**别用它做教室选择器**。
  Future<List<PublicQueryOption>> fetchClassrooms({
    required String jsessionId,
    String campusCode = '',
    String buildingCode = '',
  }) => fetchDropList(
    jsessionId: jsessionId,
    comboBoxName: 'MsSchoolArea_LF_JS',
    paramValue: 'xq_m=$campusCode&jslx_m=&lf_m=$buildingCode',
  );

  /// 选择器（`/taglib/CombBoxServlet.jsp`，UTF-8 XML）：班级 / 教师 / 课程 / 教室。
  ///
  /// [params] 用 [PublicQueryRequest.comboParams] 生成（与页面 JS 同步）。
  Future<List<PublicQueryOption>> fetchComboBox({
    required String jsessionId,
    required String className,
    required Map<String, String> params,
    required String referer,
  }) async {
    final response = await _postWith(jsessionId, '/taglib/CombBoxServlet.jsp', {
      'className': className,
      'loadDataStyle': 'loadClass',
      ...params,
    }, referer: referer);
    final body = _decodeUtf8(response.data ?? const []);
    if (isExpiredSession(body)) throw StateError('凭证已失效，请重新登录！');
    return parseComboBoxXml(body);
  }

  /// 排课套数 `pkts`（页面的 `initPage()` 必跑：`../KB_ExpTeacherSchedualAction.do`）。
  ///
  /// 拿不到时返回空串（报告仍会请求，但很可能空结果）。
  Future<String> fetchPkts({
    required String jsessionId,
    required PublicQueryTerm term,
    required String referer,
  }) async {
    final response = await _postWith(
      jsessionId,
      '/KB_ExpTeacherSchedualAction.do',
      const {},
      referer: referer,
      query: 'hidOption=getpkts&xn=${term.xn}&xq_m=${term.xqM}',
    );
    return parsePkts(_decodeUtf8(response.data ?? const []));
  }

  /// 课表报表 HTML（GBK 已解码）。
  ///
  /// 空结果同样返回 HTML（`没有检索到记录！`），由调用方用 [isEmptyReport] 判定；
  /// 会话失效抛异常。
  Future<String> queryReport({
    required String jsessionId,
    required PublicQueryRequest request,
  }) async {
    final response = await _postWith(
      jsessionId,
      '/kbbp/dykb.GS1.jsp',
      buildReportFields(request),
      referer: 'https://jwxt.jxufe.edu.cn${request.kind.pagePath}',
      query: 'kblx=${request.kind.reportType}',
    );
    final html = decodeGbkBytes(response.data ?? const <int>[]);
    if (isExpiredSession(html)) throw StateError('凭证已失效，请重新登录！');
    return html;
  }
}

/// 按字节解 GBK；失败时退化为 UTF-8 / 逐字节（不抛，避免脏字节毁掉整页）。
///
/// ⚠ 顺序不能反：正文页是 GBK，但**会话失效页是 UTF-8**，而 GBK 对 UTF-8 字节
/// 不报错（只解出乱码）→ 必须由 [decodeJwPage] 先严格试 UTF-8 认失效页。
String decodeGbkBytes(List<int> bytes) => decodeJwPage(bytes);

String _decodeUtf8(List<int> bytes) =>
    bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true);
