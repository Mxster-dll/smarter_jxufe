/// 学习通接入用到的全部地址（唯一出处）。
///
/// ⚠ 不要在各数据源里各写一份字面量：`casServiceUrl` 的 service 是**超星统一认证网关**，
/// 写错一个字符就会得到「未认证授权的服务」（实测：图书馆域名 5 个变体全部被拒），
/// 守卫测试 `test/chaoxing_parser_test.dart` 的「端点与换证链守卫」组就盯着这几串。
library;

/// 学习通（超星）端点表。
class ChaoxingEndpoints {
  ChaoxingEndpoints._();

  /// 学校 CAS 登录入口。
  static const String casLogin = 'https://ssl.jxufe.edu.cn/cas/login';

  /// 超星统一认证网关的票据回调（= CAS 的 `service` 参数）。
  static const String casService =
      'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index';

  /// 传给 `AuthRepository.getServiceRedirectUrl` 的完整 CAS 入口。
  ///
  /// service 必须写**网关**那个（百分号编码后）—— 图书馆那条链路实测过：
  /// 目标业务域自己的域名不在学校 CAS 白名单里。
  static const String casServiceUrl =
      '$casLogin?service=https%3A%2F%2Funified-auth.chaoxing.com'
      '%2Flogin_auth%2Fcas%2Fjxufe%2Findex';

  /// 网关换证入口（`?refer=` 决定最终落点，**客户端可控**）。
  static const String gatewayInitPath = '/login_auth/jxufe/init';

  /// 网关的身份桥接接口（跳转页里 `jQuery.ajax` 打的那个）。
  static const String gatewayLoginPath = '/login_auth/cas/jxufe/login';

  /// 网关 host。
  static const String gatewayHost = 'unified-auth.chaoxing.com';

  /// 学习空间 host（会话最终归属域）。
  static const String spaceHost = 'i.chaoxing.com';

  /// 学习空间首页（登录链最后一跳落点；收件箱 token 就在这个页面里）。
  static const String spaceBase = 'https://i.chaoxing.com/base';

  /// 换证回跳目标（`firstReferer`，网关页会原样回显并跳过来）。
  ///
  /// ⚠ 与 `libsp` 的差别**只有这一处**：那边写图书馆的 `/find/sso/login/…`，
  /// 这边写学习空间根地址。
  static const String spaceRefer = 'https://i.chaoxing.com';

  /// 课程平台（学生端）host。
  static const String moocHost = 'mooc1.chaoxing.com';

  /// 课程清单（「学生端」）。
  static const String moocCoursesPath = '/visit/courses';

  /// 课程详情（作业 tab 的 `enc`/`openc` 从这里抠）。
  static const String moocCourseMiddlePath = '/visit/stucoursemiddle';

  /// 作业列表（HTML）。
  static const String moocWorkListPath = '/mooc-ans/work/getAllWork';

  /// 收件箱 host。
  static const String noticeHost = 'notice.chaoxing.com';

  /// 通知列表（**JSON**）。
  static const String noticeListPath = '/pc/notice/getNoticeList';

  /// 收件箱页面（`?s=<token>`，只用来做 Referer 与取 token 的锚点）。
  static const String noticeInboxPath = '/pc/notice/myNotice';

  /// 未读红点（`msg` 是布尔）。
  static const String noticeCountPath = '/base/getNoticeCount';

  /// 学习通 App 侧 host（签到 / 活动都在这边）。
  static const String signHost = 'mobilelearn.chaoxing.com';

  /// 签到活动清单 —— ⚠ **POST**（form：`courseId` / `classId` / `puid`）。
  ///
  /// 这是站方学生端活动页自己打的读取型接口（见 `util2.js` 的 `activeList`），
  /// 本模块仍然**只读**：只查清单，不提交任何签到（提交是 `pptSign/stuSignajax`，
  /// 本模块永不调用）。
  static const String signListPath = '/widget/pcpick/stu/activeList';

  /// 学生端活动首页（清单请求的 Referer；`?courseId=&jclassId=`）。
  static const String signPagePath = '/widget/pcpick/stu/index';

  /// 单个签到活动的详情页（GET，`?activeId=&classId=&courseId=`）——
  /// 「我的状态 + 签到时刻」**只有**这里给，故按需逐个取（1 请求 / 活动）。
  static const String signDetailPath = '/widget/sign/pcStuSignController/preSign';

  /// 学习通登录页 host（会话失效时被踢到这里）。
  static const String passportHost = 'passport2.chaoxing.com';

  /// 江西财经大学在超星侧的单位号（教学网 `fidflag`）。
  ///
  /// 当前链路（CAS 网关换证）**用不到**它 —— 留档：若将来要走教学网
  /// `passport2.chaoxing.com/login?fid=1412` 那条路，这里是唯一出处。
  static const String fid = '1412';
}
