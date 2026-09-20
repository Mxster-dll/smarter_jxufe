/// 学习通解析器与端点守卫。
///
/// fixture 全部是 2026-09-19 从学习通网页端抓下来的**原样结构**
/// （`test/fixtures/chaoxing_*.html|json`），已脱敏：courseId/classId/workId/enc/openc
/// 换成同形态假值、人名换张三李四。**收件箱 token 与会话 Cookie 属凭据，
/// 一律不入库**（fixture 里是同形态假值）。
///
/// 换解析口径前先让本文件全绿。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_course_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_notice_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_work_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('课程清单解析（/visit/courses）', () {
    final courses = parseChaoxingCourses(fixture('chaoxing_courses.html'));

    test('4 门课，三个标识齐全，占位项被跳过', () {
      expect(courses.length, 4);
      expect(courses.first.courseId, '100000001');
      expect(courses.first.classId, '200000001');
      expect(courses.first.cpi, '900000001');
      expect(courses.map((c) => c.key).toSet().length, 4);
    });

    test('★ 课程名取 a.courseName（不是前面那个空的封面锚点）', () {
      // 页面里每门课有两个指向 stucoursemiddle 的 <a>：封面在前且为空。
      // 只按 href 扫会把课程名写成 courseId —— 这条就是它的回归守卫。
      expect(courses.first.name, '261学期 计算机组成原理');
      expect(courses.first.displayName, '计算机组成原理');
      expect(courses.first.termLabel, '261学期');
    });

    test('NBSP 收成普通空格；无学期前缀的课原样保留', () {
      expect(courses.first.name.contains('\u00a0'), isFalse);
      expect(courses[2].name, '253程序设计实训');
      expect(courses[2].termLabel, '');
      expect(courses[2].displayName, '253程序设计实训');
    });

    test('空页 / 脏页 / 非 HTML 一律空表，不抛', () {
      expect(parseChaoxingCourses(''), isEmpty);
      expect(parseChaoxingCourses('<html></html>'), isEmpty);
      expect(parseChaoxingCourses('<<<not html'), isEmpty);
    });
  });

  group('作业入口 query（从课程详情页抠 enc/openc）', () {
    final html = fixture('chaoxing_course_middle.html');

    test('★ 挑带 enc + openc 的那条，不要 status / pageNum 变体', () {
      final q = chaoxingWorkEntryQuery(html);
      expect(q, isNotNull);
      expect(q, contains('classId=200000001'));
      expect(q, contains('courseId=100000001'));
      expect(q, contains('enc='));
      expect(q, contains('openc='));
      expect(q, isNot(contains('status=')));
      expect(q, isNot(contains('pageNum=')));
    });

    test('认不出返回 null（不发出残 query）', () {
      expect(chaoxingWorkEntryQuery('<html></html>'), isNull);
      expect(chaoxingWorkEntryQuery(''), isNull);
    });
  });

  group('作业页解析（/mooc-ans/work/getAllWork）', () {
    final html = fixture('chaoxing_work_list.html');
    final works = parseChaoxingWorks(
      html,
      courseId: '100000002',
      courseName: '261学期 线性代数(工)',
    );

    test('3 条，时间与状态字段齐全', () {
      expect(works.length, 3);
      expect(works.first.workId, '55739815');
      expect(works.first.title, '9月20日24:00前提交作业');
      expect(works.first.startAt, DateTime(2026, 9, 17, 14, 28));
      expect(works.first.dueAt, DateTime(2026, 9, 20, 23, 59));
      expect(works.first.status, ChaoxingWorkStatus.todo);
      expect(works.first.score, isNull);
      // 课程信息由调用方回填（作业页自己不重复课程名）
      expect(works.first.courseId, '100000002');
      expect(works.first.courseName, '261学期 线性代数(工)');
    });

    test('三档状态都认；已完成带分数', () {
      expect(works[1].status, ChaoxingWorkStatus.pendingReview);
      expect(works[1].title, '课程设计评阅表提交');
      expect(works[2].status, ChaoxingWorkStatus.done);
      expect(works[2].title, '第三次实验');
      expect(works[2].score, 90);
    });

    test('过期只对「待做」成立', () {
      expect(works.first.isOverdueAt(DateTime(2026, 9, 19)), isFalse);
      expect(works.first.isOverdueAt(DateTime(2026, 9, 21)), isTrue);
      // 已完成的不算过期（页面上的旧作业不该天天飘红）
      expect(works[2].isOverdueAt(DateTime(2030, 1, 1)), isFalse);
    });

    test('空课页 → 空列表，且判空函数认得它', () {
      final empty = fixture('chaoxing_work_empty.html');
      expect(
        parseChaoxingWorks(empty, courseId: '1', courseName: '体育3'),
        isEmpty,
      );
      expect(chaoxingWorkPageIsEmpty(empty), isTrue);
      expect(chaoxingWorkPageIsEmpty(html), isFalse);
      expect(chaoxingWorkPageIsEmpty(''), isFalse);
    });

    test('空页 / 无条目页不抛', () {
      expect(parseChaoxingWorks('', courseId: '1', courseName: 'x'), isEmpty);
      expect(
        parseChaoxingWorks('<html><body><li></li></body></html>',
            courseId: '1', courseName: 'x'),
        isEmpty,
      );
    });

    test('状态认不出 → unknown（不当成待做）', () {
      const html = '<ul><li><div class="titTxt">'
          '<a class="inspectTask" data="9" title="怪作业"></a>'
          '<span class="pt5"><span class="fl">作业状态：</span><strong> 审核中 </strong></span>'
          '</div></li></ul>';
      final list = parseChaoxingWorks(html, courseId: '1', courseName: 'x');
      expect(list.single.status, ChaoxingWorkStatus.unknown);
      expect(list.single.status.isOpen, isFalse);
    });
  });

  group('通知解析（getNoticeList / getNoticeCount）', () {
    final json = jsonDecode(fixture('chaoxing_notices.json'));
    final notices = parseChaoxingNotices(json);

    test('收件箱 token 从学习空间首页抠出来（登录链最后一跳）', () {
      expect(
        chaoxingNoticeToken(fixture('chaoxing_space_base.html')),
        '0123456789abcdef0123456789abcdef',
      );
      expect(chaoxingNoticeToken('<html></html>'), isNull);
      expect(chaoxingNoticeToken(''), isNull);
    });

    test('4 条；字段名是 createrName / isread（不是 senderName）', () {
      expect(notices.length, 4);
      expect(notices.first.title, '261学前测通知及注意事项');
      expect(notices.first.sender, '张三');
      expect(notices.first.sentAt, DateTime(2026, 9, 17, 20, 18, 37));
      expect(notices.first.read, isTrue);
      expect(notices.first.courseId, '100000001');
    });

    test('未读 / 置顶 / 数字与布尔两种写法都认', () {
      expect(notices[1].read, isFalse);
      expect(notices[1].top, isTrue);
      expect(notices[2].read, isFalse, reason: 'isread 是字符串 "0"');
      expect(notices[3].read, isTrue, reason: 'isread 是布尔 true');
    });

    test('uuid 缺失回落 idCode；idCode 缺失回落 uuid', () {
      expect(notices[2].id, 'CD6071288347CC4DC1A0E2EEC441CCCC');
      expect(notices[3].id, r'$CACG$dddddddd-1111-2222-3333-444444444444');
    });

    test('时间为空回落 completeTime', () {
      expect(notices[2].sentAt, DateTime(2026, 9, 14, 9, 47, 2));
    });

    test('非课程通知的 tag 解析不出 courseId', () {
      expect(notices[3].courseId, '');
    });

    test('未读数接口的 msg 是布尔，不是条数', () {
      expect(chaoxingNoticeHasNew({'status': true, 'msg': false}), isFalse);
      expect(chaoxingNoticeHasNew({'status': true, 'msg': true}), isTrue);
      expect(chaoxingNoticeHasNew({'status': true, 'msg': 0}), isFalse);
      expect(chaoxingNoticeHasNew(null), isFalse);
      expect(chaoxingNoticeHasNew('oops'), isFalse);
    });

    test('脏 JSON 不抛（整条丢，不整表失败）', () {
      expect(parseChaoxingNotices(null), isEmpty);
      expect(parseChaoxingNotices({'notices': {'list': 'oops'}}), isEmpty);
      expect(parseChaoxingNotices({'notices': {'list': [1, 'x', null]}}), isEmpty);
    });
  });

  group('端点与换证链守卫', () {
    test('CAS service 必须是超星统一认证网关那个', () {
      expect(ChaoxingEndpoints.casServiceUrl, startsWith(ChaoxingEndpoints.casLogin));
      expect(
        ChaoxingEndpoints.casServiceUrl,
        contains(
          'https%3A%2F%2Funified-auth.chaoxing.com'
          '%2Flogin_auth%2Fcas%2Fjxufe%2Findex',
        ),
        reason: 'service 写错会得到「未认证授权的服务」（图书馆域名实测 5 个变体全被拒）',
      );
    });

    test('换证回跳 = 学习空间（与图书馆链路的唯一差别）', () {
      expect(ChaoxingEndpoints.spaceRefer, 'https://i.chaoxing.com');
      expect(ChaoxingEndpoints.spaceBase, 'https://i.chaoxing.com/base');
      expect(ChaoxingEndpoints.gatewayLoginPath, '/login_auth/cas/jxufe/login');
      expect(ChaoxingEndpoints.fid, '1412', reason: '江财在超星侧的单位号（留档）');
    });

    test('网关桥接参数：标识符要回代到 var 声明', () {
      final params = ChaoxingAuthRemoteDataSource.parseGatewayBridgeParams(
        fixture('chaoxing_gateway_page.html'),
      );
      expect(params['data'], '0123456789abcdef0123456789abcdef');
      expect(params['time'], '1789753140082');
      expect(params['enc'], 'AABBCCDDEEFF00112233445566778899');
      expect(params['displayName'], '张三');
      expect(params['userRole'], '3');
    });

    test('认不出桥接块 → 空表（调用方据此报「页面可能已改版」）', () {
      expect(
        ChaoxingAuthRemoteDataSource.parseGatewayBridgeParams('<html></html>'),
        isEmpty,
      );
    });
  });
}
