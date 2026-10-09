import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';

/// 「培养方案 · 实践环节」远程数据源（页 `pyfa.sjhj.html`，表 `tableId=2509`）。
///
/// 形参、body、Referer 都与**理论课程**那条（`tableId=2508`）同构 —— 实测两页
/// 的表单字段一模一样（`count/initQry/nj_/sel_yxb/sel_zy/fzyxs/menucode_current`），
/// 只有页面名、menucode 与 tableId 不同。**少了 `nj_`/`sel_yxb`/`sel_zy`
/// 服务端会返回空表**（实测 total=0，且不报错），所以这三个参数不能省。
class PracticeCurriculumRemoteDataSource {
  final Dio _dio;

  PracticeCurriculumRemoteDataSource(this._dio);

  Future<String> getPracticeCurriculumHtml(
    int year,
    String collegeId,
    String majorId, {
    required String jsessionId,
  }) async {
    final response = await _dio.post(
      '/taglib/DataTable.jsp?tableId=2509',
      data: {
        'count': '1',
        'initQry': '0',
        'nj_': year,
        'sel_yxb': collegeId,
        'sel_zy': majorId,
        'fzyxs': 'zx',
        'menucode_current': 'S20102',
      },
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/pyfa.sjhj.html?menucode=S20102',
        },
      ),
    );

    final html = response.data as String?;
    if (html == null) throw ImsApiException('空的响应体');
    if (jwSessionExpired(html)) {
      throw const JwSessionExpiredException('凭证已失效，请重新登录!');
    }
    return html;
  }
}
