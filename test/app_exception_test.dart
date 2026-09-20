/// 异常体系的行为守卫（2026-09-20 · 架构审查后收敛）。
///
/// 收敛前全仓 29 个站点异常**各自 `implements Exception`**、各自重复一份
/// `final String message;` + `String toString() => message;`，彼此**没有公共类型** ——
/// 界面层想按类型分支（「这是会话失效，给重新登录入口」）根本做不到。
///
/// 现在：`AppException`（全族基类）+ `SessionExpiredException`（会话失效标记）。
/// 静态唯一性守卫在 `test/core_conventions_test.dart`，**这一份管行为**：
/// 每个成员真的落在族里、`toString()` 真的等于 `message`、不该进族的真的没进。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/data/qr_login_exception.dart';

void main() {
  group('会话失效族：9 个成员都在 SessionExpiredException 里', () {
    /// 名 → 实例（默认文案构造，不带任何参数）。
    final members = <String, AppException>{
      'JwSessionExpiredException': const JwSessionExpiredException(),
      'TgcExpiredException': TgcExpiredException(),
      'ChaoxingSessionExpiredException': ChaoxingSessionExpiredException('学习通会话过期'),
      'SspSessionExpiredException': SspSessionExpiredException(),
      'DzjSessionExpiredException': DzjSessionExpiredException(),
      'TsgxsSessionExpiredException': TsgxsSessionExpiredException(),
      'ReadCreditSessionExpiredException': ReadCreditSessionExpiredException(),
      'LibspSessionExpiredException': LibspSessionExpiredException(),
      'SelectionSessionExpired': const SelectionSessionExpired(),
    };

    test('每个成员 isA<SessionExpiredException> 且 isA<AppException>', () {
      expect(members, hasLength(9), reason: '族成员清单变了？同步 lib/core/errors/app_exception.dart 文档');
      members.forEach((name, e) {
        expect(e, isA<SessionExpiredException>(), reason: name);
        expect(e, isA<AppException>(), reason: name);
      });
    });

    test('契约：toString() 恒等于 message，且文案非空', () {
      members.forEach((name, e) {
        expect(e.message, isNotEmpty, reason: name);
        expect(e.toString(), e.message, reason: '$name 的 toString 必须等于 message');
      });
    });

    test('按类型分支管用（不必碰文案）', () {
      // 界面层的正确用法：`if (e is SessionExpiredException) 给重新登录入口`。
      final Object e = const JwSessionExpiredException();
      expect(e is SessionExpiredException, isTrue);
      expect(e is AppException, isTrue);
    });

    test('默认文案没被搬家（历史用户可见文案原样）', () {
      expect(const JwSessionExpiredException().message, '凭证已失效，请重新登录！');
      expect(TgcExpiredException().message, 'TGC 已过期，需要重新登录');
      expect(const SelectionSessionExpired().message, '选课会话已失效');
    });
  });

  group('不该进「会话失效」族的（换票没用）', () {
    test('学习通被风控 / 入馆教育未解锁 / 会话建立失败：都是 AppException，但不是会话失效', () {
      final others = <String, AppException>{
        'ChaoxingChallengedException': ChaoxingChallengedException('风控'),
        'ChaoxingPageException': ChaoxingPageException('结构变了'),
        'ChaoxingSessionException': ChaoxingSessionException('会话建立失败'),
        'TsgxsAccessDeniedException': const TsgxsAccessDeniedException('未解锁'),
        'CxstarSessionException': CxstarSessionException(),
      };
      others.forEach((name, e) {
        expect(e, isA<AppException>(), reason: name);
        expect(
          e,
          isNot(isA<SessionExpiredException>()),
          reason: '$name 换票没用（要等冷却 / 是业务状态），混进族里会让界面给错建议',
        );
      });
    });
  });

  group('特殊形态：附加字段与 const 构造都保住了', () {
    test('TgcExpiredException 仍带 responseBody，且不再把类名拼进用户文案', () {
      final e = TgcExpiredException('http://cas/login');
      expect(e.responseBody, 'http://cas/login');
      expect(e.toString(), 'TGC 已过期，需要重新登录');
      expect(e.toString(), isNot(contains('TgcExpiredException')));
    });

    test('ElectricityApiException 两参（code + message）', () {
      const e = ElectricityApiException(404, '未绑定该房间');
      expect(e.code, 404);
      expect(e.message, '未绑定该房间');
      expect(e.toString(), '未绑定该房间');
    });

    test('NetworkServiceException 仍是 const + 具名 needGuid', () {
      const e = NetworkServiceException('需要平台标识', needGuid: true);
      expect(e.needGuid, isTrue);
      expect(e.message, '需要平台标识');
    });

    test('ChaoxingSessionExpiredException 既是 ChaoxingSessionException 又在失效族里', () {
      final e = ChaoxingSessionExpiredException('x');
      expect(e, isA<ChaoxingSessionException>(), reason: '仓库里按父类 catch 的地方不许漏');
      expect(e, isA<SessionExpiredException>());
    });
  });

  group('「异常 → 上屏文案」唯一出口 friendlyErrorText', () {
    test('typed 异常直接取 message（不带任何前缀）', () {
      expect(friendlyErrorText(const JwSessionExpiredException()), '凭证已失效，请重新登录！');
      expect(friendlyErrorText(const QrLoginException('验证码发送失败')), '验证码发送失败');
      expect(friendlyErrorText(ChaoxingChallengedException('学习通限流')), '学习通限流');
    });

    test('历史 `throw Exception(…)` 剥掉 Dart 自带前缀（这正是它存在的理由）', () {
      // `Exception('x').toString()` == 'Exception: x' —— 直接 `'失败：$e'` 会把英文打给用户。
      expect(Exception('会话失效').toString(), 'Exception: 会话失效');
      expect(friendlyErrorText(Exception('会话失效')), '会话失效');
    });

    test('不是 Exception 前缀的照原样返回（别顺手剥 StateError 之类）', () {
      expect(friendlyErrorText('裸字符串'), '裸字符串');
      expect(friendlyErrorText(StateError('x')), startsWith('Bad state:'));
    });
  });

  group('Failure（Either 侧）不遮蔽基类字段', () {
    test('子类 message 经基类静态类型仍取得到', () {
      const Failure f = UnknownFailure('未知错误');
      expect(f.message, '未知错误');
      const Failure g = NetworkFailure();
      expect(g.message, isNull);
      expect(const ServerFailure('服务异常').message, '服务异常');
      expect(const InvalidCredentialsFailure('密码错').message, '密码错');
    });
  });
}
