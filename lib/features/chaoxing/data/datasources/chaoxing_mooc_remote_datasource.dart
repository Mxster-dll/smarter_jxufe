/// 学习通 · 课程与作业的数据源。
///
/// 成本口径（实测）：**课程 1 个请求；作业每门课 2 个请求**
/// （课程详情页取 `enc`/`openc` → 作业页）。34 门课 ≈ 69 个请求，
/// 因此仓库层做并发池 + Hive 缓存，见 `chaoxing_repository.dart`。
library;

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_course_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_work_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

/// 课程 / 作业远端数据源。
class ChaoxingMoocRemoteDataSource {
  ChaoxingMoocRemoteDataSource(this._http);

  final ChaoxingHttpClient _http;

  /// 课程清单（「学生端」）。
  ///
  /// ⚠ **解析出 0 门 = 失败，不是「这个学生没课」**：实测 5/5 次都是 35 门，
  /// 而唯一能给出 0 门的情形是风控挑战页（`202`，正文无课程锚点）。
  /// 首版返回空列表 → 整个快照连课程带作业一起空掉（用户报「课程也刷新没」）。
  Future<List<ChaoxingCourse>> courses(ChaoxingSession session) async {
    final response = await _http.get(
      'https://${ChaoxingEndpoints.moocHost}${ChaoxingEndpoints.moocCoursesPath}',
      jar: session.jar,
      referer: ChaoxingEndpoints.spaceBase,
      followRedirects: true,
      throttle: true,
    );
    final body = _body(response);
    ChaoxingHttpClient.ensureUsable(response, body);
    final courses = parseChaoxingCourses(body);
    if (courses.isEmpty) {
      throw ChaoxingPageException(
        '学习通课程清单里一门课都没有（页面 ${body.length} B）——'
        '多半是取到了验证页，本次取数作废',
      );
    }
    return courses;
  }

  /// 某门课的作业列表（2 个请求：课程详情 → 作业页）。
  ///
  /// 三种结果**必须区分开**（首版把它们混成「空列表」，于是刷新会静默丢作业）：
  /// - 该课确实没作业 → **空列表**（作业页明确写着「暂无内容」）；
  /// - 课程页里没有作业入口 → **抛 [ChaoxingPageException]**（实测：真课程页
  ///   `getAllWork` 命中数恒为 1；抠不出必然是拿到了 `202` 验证页，见
  ///   `reverse_engineering/学习通接口.md`）；
  /// - 作业页拿到了但一条都解析不出、也没写「暂无内容」→ 同样是**失败**。
  Future<List<ChaoxingWork>> worksOf(
    ChaoxingSession session,
    ChaoxingCourse course,
  ) async {
    final middle = await _http.get(
      'https://${ChaoxingEndpoints.moocHost}${ChaoxingEndpoints.moocCourseMiddlePath}',
      jar: session.jar,
      query: {
        'courseid': course.courseId,
        'clazzid': course.classId,
        'vc': '1',
        'cpi': course.cpi,
      },
      referer:
          'https://${ChaoxingEndpoints.moocHost}${ChaoxingEndpoints.moocCoursesPath}',
      // ⚠ 真实服务端对课程详情页先给一个 302（带会话 token 再回跳）；
      // 不跟跳转就会拿到 0 字节 → 所有课都被判成「没有作业」（冒烟实测）。
      followRedirects: true,
      throttle: true,
    );
    final middleBody = _body(middle);
    ChaoxingHttpClient.ensureUsable(middle, middleBody);

    final query = chaoxingWorkEntryQuery(middleBody);
    if (query == null) {
      throw ChaoxingPageException(
        '课程 ${course.key} 的课程页里没有作业入口（页面 ${middleBody.length} B）'
        '——真课程页必然带 getAllWork 链接，抠不出说明这页不是业务页',
      );
    }

    // ⚠ query 原样拼进 URL（`enc`/`openc` 已是 URL 安全值）：走 `queryParameters`
    // 会被再编码一次，签名对不上会直接拿不到列表。
    final list = await _http.get(
      'https://${ChaoxingEndpoints.moocHost}'
      '${ChaoxingEndpoints.moocWorkListPath}?$query',
      jar: session.jar,
      referer:
          'https://${ChaoxingEndpoints.moocHost}${ChaoxingEndpoints.moocCourseMiddlePath}',
      followRedirects: true,
      throttle: true,
    );
    final html = _body(list);
    ChaoxingHttpClient.ensureUsable(list, html);

    if (chaoxingWorkPageIsEmpty(html)) return const [];
    final works = parseChaoxingWorks(
      html,
      courseId: course.courseId,
      courseName: course.name,
    );
    if (works.isEmpty) {
      throw ChaoxingPageException(
        '课程 ${course.key} 的作业页解析不出任何条目、也没写「暂无内容」'
        '（页面 ${html.length} B）——多半是取到了验证页',
      );
    }
    return works;
  }

  static String _body(Response<dynamic> response) =>
      response.data?.toString() ?? '';
}
