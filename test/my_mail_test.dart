import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/my_mail/data/datasources/my_mail_remote_datasource.dart';
import 'package:smarter_jxufe/features/my_mail/data/providers/my_mail_providers.dart';
import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart';
import 'package:smarter_jxufe/features/my_mail/presentation/my_mail_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart'
    show wxGuidProvider;

/// 记录请求并按脚本作答的 Dio 适配器（不打真实网络）。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://wxcourse.jxufe.cn'))
      ..httpClientAdapter = adapter;

const String _okBody =
    '{"code":1,"success":true,"message":null,'
    '"result":{"email":"2000000000@stu.jxufe.edu.cn","pwd":"zAacW6yCq4"}}';

void main() {
  group('StudentMailbox · 模型', () {
    test('掩码 = 星号数等于密码长度', () {
      expect(myMailMaskPassword('zAacW6yCq4'), '**********');
      expect(myMailMaskPassword(''), '');
      const box = StudentMailbox(
        email: '2000000000@stu.jxufe.edu.cn',
        password: 'zAacW6yCq4',
      );
      expect(box.maskedPassword, '**********');
      expect(box.isEmpty, isFalse);
      expect(StudentMailbox.empty.isEmpty, isTrue);
    });

    test('fromJson 兼容 pwd / password，缺字段与脏值不抛异常', () {
      expect(
        StudentMailbox.fromJson(const {
          'email': 'a@stu.jxufe.edu.cn',
          'pwd': 'p1',
        }).password,
        'p1',
      );
      expect(
        StudentMailbox.fromJson(const {
          'email': 'a@stu.jxufe.edu.cn',
          'password': 'p2',
        }).password,
        'p2',
      );
      final dirty = StudentMailbox.fromJson(const {'email': 12345});
      expect(dirty.email, '12345');
      expect(dirty.password, '');
      expect(StudentMailbox.fromJson(const {}).isEmpty, isTrue);
    });

    test('学生邮箱地址约定：<学号>@stu.jxufe.edu.cn', () {
      expect(myMailStudentAddress('2000000000'), '2000000000@stu.jxufe.edu.cn');
      expect(myMailStudentAddress(' 2000000000 '), '2000000000@stu.jxufe.edu.cn');
      expect(myMailStudentAddress(null), isNull);
      expect(myMailStudentAddress(''), isNull);
    });
  });

  group('MyMailRemoteDataSource · 解析', () {
    test('成功：取 email / pwd，并把 GUID 作为 username 查询参数', () async {
      final adapter = _FakeAdapter(_okBody);
      final ds = MyMailRemoteDataSource(_dioWith(adapter));

      final mailbox = await ds.fetchMailbox('GUID-1');

      expect(mailbox.email, '2000000000@stu.jxufe.edu.cn');
      expect(mailbox.password, 'zAacW6yCq4');
      expect(adapter.calls.single.path, MyMailRemoteDataSource.getPwdPath);
      expect(adapter.calls.single.queryParameters['username'], 'GUID-1');
    });

    test('失败：success=false 时抛出服务端 message', () async {
      final ds = MyMailRemoteDataSource(
        _dioWith(
          _FakeAdapter(
            '{"code":0,"success":false,"message":"账号不存在","result":null}',
          ),
        ),
      );
      await expectLater(
        ds.fetchMailbox('GUID-1'),
        throwsA(
          isA<MyMailApiException>().having(
            (e) => e.message,
            'message',
            contains('账号不存在'),
          ),
        ),
      );
    });

    test('异常：result 不是对象 / 缺邮箱地址', () async {
      final noResult = MyMailRemoteDataSource(
        _dioWith(_FakeAdapter('{"code":1,"success":true,"result":[]}')),
      );
      await expectLater(
        noResult.fetchMailbox('g'),
        throwsA(isA<MyMailApiException>()),
      );

      final noEmail = MyMailRemoteDataSource(
        _dioWith(
          _FakeAdapter('{"code":1,"success":true,"result":{"pwd":"x"}}'),
        ),
      );
      await expectLater(
        noEmail.fetchMailbox('g'),
        throwsA(
          isA<MyMailApiException>().having(
            (e) => e.message,
            'message',
            contains('缺少邮箱地址'),
          ),
        ),
      );
    });

    test('异常：非 JSON 响应 → 格式异常（不抛 Dio 的原始异常）', () async {
      final ds = MyMailRemoteDataSource(_dioWith(_FakeAdapter('<html>')));
      await expectLater(
        ds.fetchMailbox('g'),
        throwsA(
          isA<MyMailApiException>().having(
            (e) => e.message,
            'message',
            contains('格式异常'),
          ),
        ),
      );
    });
  });

  group('myMailboxProvider · 前置条件', () {
    test('未登录 → 提示先登录', () async {
      final container = ProviderContainer(
        overrides: [
          wxGuidProvider.overrideWith((ref) async => 'GUID-1'),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(myMailboxProvider.future),
        throwsA(
          isA<MyMailApiException>().having(
            (e) => e.message,
            'message',
            contains('请先登录'),
          ),
        ),
      );
    });

    test('未配置 GUID → kMyMailNeedGuid，且 myMailNeedsGuid 为真', () async {
      final container = ProviderContainer(
        overrides: [
          currentAccountProvider.overrideWith((ref) => '2000000000'),
          wxGuidProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      Object? caught;
      try {
        await container.read(myMailboxProvider.future);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<MyMailApiException>());
      expect((caught as MyMailApiException).message, kMyMailNeedGuid);
      expect(myMailNeedsGuid(caught), isTrue);
      expect(myMailNeedsGuid(const MyMailApiException('别的错误')), isFalse);
    });
  });

  group('MyMailScreen · 页面', () {
    Future<void> pump(
      WidgetTester tester, {
      required StudentMailbox mailbox,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myMailboxProvider.overrideWith((ref) async => mailbox),
          ],
          child: const MaterialApp(home: MyMailScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    const mailbox = StudentMailbox(
      email: '2000000000@stu.jxufe.edu.cn',
      password: 'zAacW6yCq4',
    );

    testWidgets('显示邮箱与掩码密码；点眼睛才明文', (tester) async {
      await pump(tester, mailbox: mailbox);

      expect(find.text('2000000000@stu.jxufe.edu.cn'), findsOneWidget);
      expect(find.text('**********'), findsOneWidget);
      expect(find.text('zAacW6yCq4'), findsNothing);

      await tester.tap(find.byKey(const Key('mymail_reveal')));
      await tester.pumpAndSettle();
      expect(find.text('zAacW6yCq4'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mymail_reveal')));
      await tester.pumpAndSettle();
      expect(find.text('**********'), findsOneWidget);
    });

    testWidgets('复制邮箱与复制初始密码都写入剪贴板（掩码状态下也能复制）', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pump(tester, mailbox: mailbox);

      await tester.tap(find.byKey(const Key('mymail_copy_email')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'Clipboard.setData');
      expect(calls.last.arguments['text'], mailbox.email);
      expect(find.text('已复制邮箱'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mymail_copy_password')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['text'], mailbox.password);
      expect(find.text('已复制初始密码'), findsOneWidget);
    });
  });
}
