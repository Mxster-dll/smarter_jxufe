/// 教务「选课」远程数据源。
///
/// 全部端点与字段口径来自 2026-09-14 的实测（见 `reverse_engineering/选课接口.md`），
/// 三条硬规则：
/// ① 动态页/接口必须带有效 `JSESSIONID`，否则统一返回 547 字节「凭证已失效」；
/// ② 这些页面是 **GBK** 且 `Content-Type` 不带 charset → 一律 `ResponseType.bytes` + `fast_gbk`
///    （用 utf8 解会抛 `FormatException: Missing extension byte`）；
///    ⚠ **但那个「凭证已失效」alert 页是 UTF-8** —— 见 `lib/core/network/jw_page_decoding.dart`：
///    必须先严格试 UTF-8 认失效页，否则 GBK 会把乱码交出去、`凭证已失效` 永远判不出来，
///    页面静默变成「空数据」（2026-09-14 实测：选课结果显示「该学期没有已选课程」）；
/// ③ 表单体里的中文必须按 **GBK** 百分号编码（教务按 GBK 解），不能直接用 utf8。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/kingo_des.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_write_check.dart';

const String _host = 'https://jwxt.jxufe.edu.cn';
const String _refererOnline = '$_host/student/wsxk.zx.html?menucode=S2020202';
const String _refererResult = '$_host/student/wsxk.zxjg.jsp?menucode=S2020302';

/// 年级/专业级联下拉（原页面 `njzy`）的两段常量 —— 取自
/// `GET /taglib/DroplistControl.jsp?flag=mode&classname=STUD_preElcGradeSpecialty` 的实测返回。
const String _gradeMajorComboName = 'STUD_preElcGradeSpecialty';
const String _gradeMajorBean = 'com.kingosoft.dao.jw.student.DropListBean';

/// 教务「网上选课」的两个入口（`xktype`）。
enum SelectionChannel {
  /// 正选（按开课计划）。
  plan(2, '网上选课'),

  /// 外年级 / 外专业选课。
  crossGrade(88, '外年级/专业选课');

  const SelectionChannel(this.xktype, this.label);

  final int xktype;
  final String label;
}

/// 教务会话失效（547 字节 `凭证已失效` alert 页）—— 仓库层据此续期并重试一次。
class SelectionSessionExpired implements Exception {
  const SelectionSessionExpired();

  @override
  String toString() => 'SelectionSessionExpired(教务会话已失效)';
}

String _gbkPercentEncode(String value) {
  final bytes = gbk.encode(value);
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final isUnreserved =
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2d ||
        byte == 0x5f ||
        byte == 0x2e ||
        byte == 0x7e;
    if (isUnreserved) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

/// 用 GBK 百分号编码拼表单体（教务这些 JSP 按 GBK 解参数）。
String encodeGbkForm(Map<String, String> fields) {
  final buffer = StringBuffer();
  fields.forEach((key, value) {
    if (buffer.isNotEmpty) buffer.write('&');
    buffer.write(_gbkPercentEncode(key));
    buffer.write('=');
    buffer.write(_gbkPercentEncode(value));
  });
  return buffer.toString();
}

class CourseSelectionRemoteDataSource {
  CourseSelectionRemoteDataSource(this._dio);

  final Dio _dio;

  Map<String, String> _headers(String referer, {bool form = false}) => {
    'Cookie': _cookie,
    if (form) 'Content-Type': 'application/x-www-form-urlencoded',
    'Referer': referer,
  };

  /// 由仓库在每次请求前注入（会话续期后要换新票）。
  String _cookie = '';

  set jsessionId(String value) => _cookie = 'JSESSIONID=$value';

  String get jsessionId => _cookie;

  Future<List<int>> _bytes(
    String url, {
    required String referer,
    Map<String, String>? fields,
    String? rawBody,
    bool utf8Body = false,
  }) async {
    final isPost = fields != null || rawBody != null;
    final String? body =
        rawBody ??
        (fields == null
            ? null
            : (utf8Body ? _utf8Form(fields) : encodeGbkForm(fields)));
    final response = await _dio.request<List<int>>(
      url,
      data: body,
      options: Options(
        method: isPost ? 'POST' : 'GET',
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 150),
        headers: _headers(referer, form: isPost),
      ),
    );
    return response.data ?? const [];
  }

  /// 与浏览器 `jQuery.serialize()` 同款：UTF-8 百分号编码（加密提交路径要用它）。
  String _utf8Form(Map<String, String> fields) => fields.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  String _gbk(List<int> bytes) {
    final text = _decodeGbk(bytes);
    _guardExpired(text);
    return text;
  }

  String _decodeGbk(List<int> bytes) {
    // 正文页 GBK、失效页 UTF-8 —— 统一走 `decodeJwPage`（见该文件顶部说明）。
    try {
      return decodeJwPage(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 会话失效统一抛异常（`ResponseType.bytes` 下拦截器看不到字符串，必须自己判）。
  void _guardExpired(String text) {
    if (isExpiredSession(text)) throw const SelectionSessionExpired();
  }

  String _ascii(List<int> bytes) => ascii.decode(bytes, allowInvalid: true);

  /// 会话失效的统一判据（547 字节 alert 页；原文见 `jw_page_decoding.dart`）。
  static bool isExpiredSession(String body) => jwSessionExpired(body);

  // ---------------------------------------------------------------- 元信息

  /// `GET jw/common/getWsxkTimeRange.action?xktype=<2|88>`。
  Future<SelectionSession> fetchSession({
    required SelectionChannel channel,
  }) async {
    final bytes = await _bytes(
      '/jw/common/getWsxkTimeRange.action?xktype=${channel.xktype}',
      referer: _refererOnline,
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    _guardExpired(text);
    final envelope = tryJsonMap(text);
    if (envelope == null) return SelectionSession.unknown;
    return SelectionSession.fromEnvelope(envelope, xktype: channel.xktype);
  }

  /// `GET jw/common/getSelectLessonScoreKcsInfo.action`（已选学分/门数）。
  Future<SelectionQuota> fetchQuota({
    required String xn,
    required String xqM,
    required String studentId,
  }) async {
    final bytes = await _bytes(
      '/jw/common/getSelectLessonScoreKcsInfo.action'
      '?xn=$xn&xq_m=$xqM&xh=$studentId',
      referer: _refererOnline,
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    _guardExpired(text);
    final envelope = tryJsonMap(text);
    if (envelope == null) return SelectionQuota.empty;
    return SelectionQuota.fromEnvelope(envelope);
  }

  /// `GET jw/common/getStuGradeSpeciatyInfo.action?xh=`（年级/专业/培养层次）。
  Future<StudentGradeMajor> fetchGradeMajor({required String studentId}) async {
    final bytes = await _bytes(
      '/jw/common/getStuGradeSpeciatyInfo.action?xh=$studentId',
      referer: _refererOnline,
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    _guardExpired(text);
    final envelope = tryJsonMap(text);
    if (envelope == null) return StudentGradeMajor.empty;
    return StudentGradeMajor.fromEnvelope(envelope);
  }

  /// `POST frame/droplist/getDropLists.action`（`comboBoxName=MsKcfw`，UTF-8 JSON）。
  Future<List<CourseScope>> fetchScopes({required int xktype}) async {
    final bytes = await _bytes(
      '/frame/droplist/getDropLists.action',
      referer: _refererOnline,
      fields: {
        'comboBoxName': 'MsKcfw',
        'paramValue': '$xktype',
        'isYXB': '0',
        'isCDDW': '0',
        'isXQ': '0',
        'isDJKSLB': '0',
        'isZY': '0',
      },
      utf8Body: true,
    );
    return parseCourseScopes(utf8.decode(bytes, allowMalformed: true));
  }

  /// 院(系)/部下拉 —— 原页面 `sel_yxb` 的
  /// `loadDropList4Single({selId:"sel_yxb", cbName:"MsDepartmentYXB", isYXB:"0", …})`。
  ///
  /// 实测（2026-09-15）：`MsDepartmentYXB` 是**静态部门表**，没有会话也能取到
  /// （2489 B / 84 项），名字自带 `[040]会计学院` 前缀；原页面原样显示 → 这里也原样。
  Future<List<CourseScope>> fetchDepartments() async {
    final bytes = await _bytes(
      '/frame/droplist/getDropLists.action',
      referer: _refererOnline,
      fields: {
        'comboBoxName': 'MsDepartmentYXB',
        'paramValue': '',
        'isYXB': '0',
        'isCDDW': '0',
        'isXQ': '0',
        'isDJKSLB': '0',
        'isZY': '0',
      },
      utf8Body: true,
    );
    return parseCourseScopes(utf8.decode(bytes, allowMalformed: true));
  }

  /// 年级/专业级联下拉（原页面 `CKDList().IKInitDropList('njzy','STUD_preElcGradeSpecialty')`）。
  ///
  /// 请求形态来自 `js_Ref_DropList.js` 的 `CKDList.prototype.initDropList_list()`：
  /// 先 `?flag=mode&classname=STUD_preElcGradeSpecialty` 取定义
  /// （实测回 `list|com.kingosoft.dao.jw.student.DropListBean|xh,xn,xq,nj,zydm,kcfw,xktype,sel_yxb|STUD_preElcGradeSpecialty`），
  /// 再按它拼数据调用：`?id=&classname=<第 4 段>&state=0&flag=list&class=<第 2 段>` + 第 3 段声明的表单字段。
  ///
  /// ⚠️ 无学生上下文/会话时该端点回 `<root></root>`（选项为空）→ 调用方按「无选项」展示，
  /// 不要当成错误。
  Future<String> fetchGradeMajorsXml({
    required SelectionSession session,
    required String studentId,
    required String scope,
    String department = '',
  }) {
    final query = <String, String>{
      'id': '',
      'classname': _gradeMajorComboName,
      'state': '0',
      'flag': 'list',
      'class': _gradeMajorBean,
      'xh': studentId,
      'xn': session.xn,
      'xq': session.xqM,
      'nj': session.nj,
      'zydm': session.zydm,
      'kcfw': scope,
      'xktype': '${session.xktype}',
      'sel_yxb': department,
    };
    final qs = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return _bytes(
      '/taglib/DroplistControl.jsp?$qs',
      referer: _refererOnline,
    ).then((bytes) {
      final text = utf8.decode(bytes, allowMalformed: true);
      _guardExpired(text);
      return text;
    });
  }

  // ---------------------------------------------------------------- 只读列表

  /// 可选课程列表（`taglib/DataTable.jsp?tableId=2568&fre=1`）。
  ///
  /// ⚠️ `initQry` 必须是 `0`：传 `1`（页面表单初值）时服务端只回表头、0 条。
  /// ⚠️ 「课程类别 `lbgl`」「课程属性 `kcsx`」**不是**服务端过滤（原页面这两个
  /// select 是 disabled，浏览器不提交）→ 它们恒发空，过滤走
  /// `domain/selection_filters.dart` 的客户端实现（2026-09-15 对照页面 JS 订正）。
  Future<String> fetchOptionalCoursesHtml({
    required SelectionSession session,
    required String studentId,
    required String scope,
    String keyword = '',
    String njzy = '',
    String department = '',
    bool onlyWithVacancy = true,
  }) {
    return _bytes(
      '/taglib/DataTable.jsp?tableId=2568&fre=1',
      referer: _refererOnline,
      fields: {
        'xktype': '${session.xktype}',
        'xh': studentId,
        'xn': session.xn,
        'xq': session.xqM,
        'nj': session.nj,
        'zydm': session.zydm,
        'yxbdm': session.yxbdm,
        '_kcfw': scope,
        'kcfw': scope,
        'items': '',
        'is_xjls': session.isXjls,
        'zysx': session.zysx,
        'sfbd': session.sfbd,
        'lcid': session.lcid,
        'djs': session.djs,
        'kxkc': '0',
        'xxkckzfs': session.xxkckzfs,
        'yxkzyfxxk': session.yxkzyfxxk,
        'yxsjct': session.yxsjct,
        'xfsx': '',
        'mssx': '',
        'hidkcmc': '',
        'sel_yxb': department,
        'njzy': njzy,
        'lbgl': '',
        'kcsx': '',
        'kcmc': keyword,
        // 原页面 `input#xwxmkc` 默认勾选（只有 11819 那所学校默认不勾）。
        if (onlyWithVacancy) 'xwxmkc': 'on',
        'kclb1': '',
        'kclb2': '',
        'initQry': '0',
        'count': '1',
      },
    ).then(_gbk);
  }

  /// 课程范围下拉（教务返回 UTF-8 JSON 数组，但接口是 GET 形态的静态表）。
  Future<String> fetchOptionalCoursesHtmlByUrl(String url) =>
      _bytes(url, referer: _refererOnline).then(_gbk);

  /// 教学班列表（`taglib/DataTable.jsp?tableId=6142&fre=1&<明文查询串>`）。
  ///
  /// ⚠️ 该表的 JSP **只认带 `electiveCourseForm.` 前缀的参数字段**（plain 名一律 0 条）。
  Future<String> fetchSectionsHtml({
    required SelectionSession session,
    required String studentId,
    required String internalCode,
  }) {
    final query =
        'xn=${session.xn}&xq_m=${session.xqM}&xh=$studentId'
        '&kcdm=$internalCode&skbjdm=&xktype=${session.xktype}'
        '&kcfw=${session.scopeCodes.isEmpty ? 'zxbnj' : session.scopeCodes.first}'
        '&isyxkc=false&lcid=${session.lcid}';
    return _bytes(
      '/taglib/DataTable.jsp?tableId=6142&fre=1&$query',
      referer: '$_host/student/report/wsxk.zx_promt.jsp',
      fields: {
        'electiveCourseForm.xktype': '${session.xktype}',
        'electiveCourseForm.lcid': session.lcid,
        'electiveCourseForm.yxsjct': session.yxsjct,
        'electiveCourseForm.xn': session.xn,
        'electiveCourseForm.xq': session.xqM,
        'electiveCourseForm.xh': studentId,
        'electiveCourseForm.nj': session.nj,
        'electiveCourseForm.zydm': session.zydm,
        'electiveCourseForm.kcdm': internalCode,
        'electiveCourseForm.is_checkTime': '1',
        'electiveCourseForm.zfx_m': '0',
        'electiveCourseForm.outnumber': '0',
        'electiveCourseForm.kcfw': session.scopeCodes.isEmpty
            ? 'zxbnj'
            : session.scopeCodes.first,
        'xxkckzfs': session.xxkckzfs,
        'yxkzyfxxk': session.yxkzyfxxk,
        'xsszxq': '3',
        'xqdm': '',
        'kcmc': '',
      },
    ).then(_gbk);
  }

  /// 选课结果整页（`student/wsxk.zxjg.jsp`，服务端渲染）。
  Future<String> fetchResultHtml() => _bytes(
    '/student/wsxk.zxjg.jsp?menucode=S2020302',
    referer: _refererResult,
  ).then(_gbk);

  /// 入学以来正选结果（`student/wsxk.zxjg_all.jsp`）。
  Future<String> fetchAllResultHtml({
    required String studentId,
    required String nj,
    required String zydm,
  }) => _bytes(
    '/student/wsxk.zxjg_all.jsp?xh=$studentId&nj=$nj&zydm=$zydm',
    referer: _refererResult,
  ).then(_gbk);

  /// 被取消课程（`student/wsxk.qxbxkc.jsp`）。
  Future<String> fetchCancelledHtml() => _bytes(
    '/student/wsxk.qxbxkc.jsp?menucode=S2020303',
    referer: _refererResult,
  ).then(_gbk);

  /// 查询课表（`taglib/DataTable.jsp?tableId=5327042`）。
  Future<String> fetchTimetableHtml({
    required SelectionSession session,
    required String studentId,
    required String gradeMajor,
  }) => _bytes(
    '/taglib/DataTable.jsp?tableId=5327042&clientWidth=1200',
    referer: '$_host/student/wsxk.kcbcx10319.html?menucode=S2020103',
    fields: {
      'initQry': '0',
      'xktype': '${session.xktype}',
      'xn': session.xn,
      'xq': session.xqM,
      'nj': session.nj,
      'pycc': '05',
      'dwh': session.yxbdm,
      'zydm': session.zydm,
      'kclb1': '',
      'kclb2': '',
      'isbyk': '',
      'items': '',
      'sel_nj': session.nj,
      'sel_pycc': '05',
      'sel_yxb': session.yxbdm,
      'sel_zydm': session.zydm,
      'sel_kc': '',
      'sel_rkjs': '',
      'sel_kclb1': '',
      'sel_kclb2': '',
      'sel_schoolarea': '',
      'njzy': gradeMajor,
      'count': '1',
    },
  ).then(_gbk);

  /// 申请扩容列表（`taglib/DataTable.jsp?tableId=5929098`）。
  Future<String> fetchExpandHtml({
    required SelectionSession session,
    required String studentId,
    required String gradeMajor,
  }) => _bytes(
    '/taglib/DataTable.jsp?tableId=5929098',
    referer: '$_host/student/wsxk.sqkr.html?menucode=S2020104',
    fields: {
      'initQry': '0',
      'xktype': '${session.xktype}',
      'xh': studentId,
      'xn': session.xn,
      'xq': session.xqM,
      'nj': session.nj,
      'pycc': '05',
      'dwh': session.yxbdm,
      'zydm': session.zydm,
      'yxbdm': session.yxbdm,
      'kcfw': session.scopeCodes.isEmpty ? 'zxbnj' : session.scopeCodes.first,
      'njzy': gradeMajor,
      'kgmc': 'xk_xs_sqkrsj',
      'menucode': 'S2020104',
      'kclb1': '',
      'kclb2': '',
      'isbyk': '',
      'items': '',
      'sel_nj': session.nj,
      'sel_pycc': '05',
      'sel_yxb': session.yxbdm,
      'sel_yxbdm': session.yxbdm,
      'sel_zydm': session.zydm,
      'sel_kc': '',
      'sel_rkjs': '',
      'sel_kclb1': '',
      'sel_kclb2': '',
      'count': '1',
    },
  ).then(_gbk);

  // ---------------------------------------------------------------- 写操作

  /// 是否允许选择该课程（`jw/common/isSelectableSkbjdm.action`，明文）。
  Future<SelectionWriteResult> checkSelectable({
    required String xn,
    required String xqM,
    required String studentId,
    required String internalCode,
  }) async {
    final bytes = await _bytes(
      '/jw/common/isSelectableSkbjdm.action',
      referer: _refererOnline,
      fields: {'xn': xn, 'xq_m': xqM, 'xh': studentId, 'kcdm': internalCode},
    );
    final envelope = tryJsonMap(utf8.decode(bytes, allowMalformed: true));
    if (envelope == null) return SelectionWriteResult.networkFailure;
    return SelectionWriteResult.fromEnvelope(envelope);
  }

  /// 取临时 DES 密钥与时间戳（`/frame/homepage?method=getTempDeskey|getTempNowtime`）。
  Future<({String deskey, String timestamp})> fetchEncryptMaterial() async {
    final deskeyBytes = await _bytes(
      '/frame/homepage?method=getTempDeskey',
      referer: _refererOnline,
    );
    final timeBytes = await _bytes(
      '/frame/homepage?method=getTempNowtime',
      referer: _refererOnline,
    );
    return (
      deskey: _ascii(deskeyBytes).trim(),
      timestamp: _ascii(timeBytes).trim(),
    );
  }

  /// 提交选课（`jw/common/saveElectiveCourse.action`，**DES 加密**）。
  ///
  /// 教务前端的做法：`serialize()` 整张确认页表单 → 剥掉 `electiveCourseForm.` 前缀
  /// → `getEncParams()`（`params=base64(strEnc(明文,临时密钥))&token=&timestamp=`）→ POST。
  Future<SelectionWriteResult> submitSelection({
    required SelectionSession session,
    required String studentId,
    required Map<String, String> fields,
  }) async {
    final material = await fetchEncryptMaterial();
    if (material.deskey.isEmpty || material.timestamp.isEmpty) {
      return SelectionWriteResult.networkFailure;
    }
    // 与教务前端一致：serialize() 出来的明文串（UTF-8 百分号编码）再整体加密。
    final body = kingoEncParams(
      _utf8Form(fields),
      tempDeskey: material.deskey,
      timestamp: material.timestamp,
    );
    final bytes = await _bytes(
      '/jw/common/saveElectiveCourse.action',
      referer: '$_host/student/report/wsxk.zx_promt.jsp',
      rawBody: body,
    );
    // 写响应可能是裸 JSON，也可能是 iframe 回调页（`parent._callBack("…")`）——见 parseWriteEnvelope。
    final envelope = parseWriteEnvelope(_decodeEnvelopeText(bytes));
    if (envelope == null) return SelectionWriteResult.networkFailure;
    return SelectionWriteResult.fromEnvelope(envelope);
  }

  /// 退选（选课结果页的明文端点 `../STU_ElectCourseResultAction.do?hidOption=cancel`）。
  ///
  /// `items` = 表格末格「上课班组代码」+ `|`（可多个），实测该页**不加密**。
  ///
  /// ⚠ 该端点是 **fire-and-forget**：空 `items`、不存在的码都返回
  /// `<script>parent._callBack("{\"status\":\"200\",\"message\":\"操作成功!\"}")</script>`
  /// ⇒ 这里的返回值**只能说明「教务收下了」，不能说明「退掉了」**；
  /// 是否真的生效必须由 `verifyCancellation`（重读选课结果页）判定。
  Future<SelectionWriteResult> cancelSelection({
    required String studentId,
    required String xn,
    required String xqM,
    required String nj,
    required String zydm,
    required String zymc,
    required List<String> itemCodes,
    bool withinWindow = true,
  }) async {
    final bytes = await _bytes(
      '/STU_ElectCourseResultAction.do?hidOption=cancel',
      referer: _refererResult,
      fields: {
        'xktype': '2',
        'xh': studentId,
        'xn': xn,
        'xq': xqM,
        'nj': nj,
        'zydm': zydm,
        'zymc': zymc,
        'xktime_flag': withinWindow ? '1' : '0',
        'items': itemCodes.map((e) => '$e|').join(),
      },
    );
    final envelope = parseWriteEnvelope(_decodeEnvelopeText(bytes));
    if (envelope == null) return SelectionWriteResult.networkFailure;
    return SelectionWriteResult.fromEnvelope(envelope);
  }

  /// 写操作返回的是 JSON（UTF-8）；解不出来时退回 GBK 文本。
  String _decodeEnvelopeText(List<int> bytes) {
    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    final text = utf8Text.contains('{') ? utf8Text : _decodeGbk(bytes);
    _guardExpired(text);
    return text;
  }
}
