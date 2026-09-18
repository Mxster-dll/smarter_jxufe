import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/transcript_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/transcript_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/transcript_report.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/transcript_sheet.dart';
import 'package:smarter_jxufe/features/my_mail/data/datasources/my_mail_remote_datasource.dart';
import 'package:smarter_jxufe/features/my_mail/data/providers/my_mail_providers.dart';
import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart';

/// 记录请求（含 form 原文）并按脚本作答的 Dio 适配器。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  final List<RequestOptions> calls = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      bodies.add(utf8.decode(bytes, allowMalformed: true));
    }
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

/// 只覆写业务方法的假数据源（不打网络）。
class _FakeTranscriptDs extends TranscriptRemoteDataSource {
  _FakeTranscriptDs() : super(Dio());

  final List<({String enc, String email, String courseId})> sent = [];
  Object? failWith;

  @override
  Future<String> sendTranscript({
    required String enc,
    required String email,
    required String courseId,
  }) async {
    if (failWith != null) throw failWith!;
    sent.add((enc: enc, email: email, courseId: courseId));
    return '成绩单已发送至 $email，请查收。';
  }
}

void main() {
  group('transcriptReportTypes · 服务端 message 解析', () {
    test(',1 → 主修中/英两项', () {
      final types = transcriptReportTypes(',1');
      expect(types.map((t) => t.courseId).toList(), ['1', '11']);
      expect(types.first.label, '主修成绩单（中）');
      expect(types.last.label, '主修成绩单（英）');
    });

    test(',1,2 → 主修两项 + 辅修两项（服务端顺序）', () {
      expect(
        transcriptReportTypes(',1,2').map((t) => t.courseId).toList(),
        ['1', '11', '2', '22'],
      );
    });

    test('空 / 无有效标记 / 未知标记 → 空列表', () {
      expect(transcriptReportTypes(null), isEmpty);
      expect(transcriptReportTypes(''), isEmpty);
      expect(transcriptReportTypes(','), isEmpty);
      expect(transcriptReportTypes(',3,9'), isEmpty);
    });

    test('重复标记只出一次；缺前导逗号也能解析', () {
      expect(
        transcriptReportTypes(',1,1').map((t) => t.courseId).toList(),
        ['1', '11'],
      );
      expect(
        transcriptReportTypes('1,2').map((t) => t.courseId).toList(),
        ['1', '11', '2', '22'],
      );
    });
  });

  group('transcriptEmailValid', () {
    test('与 H5 同款正则', () {
      expect(transcriptEmailValid('2000000000@stu.jxufe.edu.cn'), isTrue);
      expect(transcriptEmailValid(' a_b.c-d@qq.com '), isTrue);
      expect(transcriptEmailValid(''), isFalse);
      expect(transcriptEmailValid('a@b'), isFalse);
      expect(transcriptEmailValid('a@@b.com'), isFalse);
      expect(transcriptEmailValid('中文@qq.com'), isFalse);
    });
  });

  group('TranscriptRemoteDataSource · 请求口径', () {
    test('换加密账号：appid=1741570971384 + GUID', () async {
      final adapter = _FakeAdapter(
        '{"code":200,"success":true,"result":{"username":"AAAAAAAAAAAAAAAAAAAAAA=="}}',
      );
      final ds = TranscriptRemoteDataSource(_dioWith(adapter));

      expect(await ds.fetchEncUserId('GUID-1'), 'AAAAAAAAAAAAAAAAAAAAAA==');
      expect(adapter.calls.single.path, TranscriptRemoteDataSource.checkAppAuthUrl);
      expect(adapter.calls.single.queryParameters['appid'], '1741570971384');
      expect(adapter.calls.single.queryParameters['platformUsername'], 'GUID-1');
    });

    test('换账号失败（code=401）→ 抛错', () async {
      final ds = TranscriptRemoteDataSource(
        _dioWith(_FakeAdapter('{"code":401,"message":"没有访问权限"}')),
      );
      await expectLater(
        ds.fetchEncUserId('g'),
        throwsA(
          isA<TranscriptApiException>().having(
            (e) => e.message,
            'message',
            contains('没有访问权限'),
          ),
        ),
      );
    });

    test('查报表类型：status=true 解析 message', () async {
      final adapter = _FakeAdapter('{"message":",1","status":true}');
      final ds = TranscriptRemoteDataSource(_dioWith(adapter));

      final types = await ds.fetchReportTypes('enc==');
      expect(types.map((t) => t.courseId).toList(), ['1', '11']);
      expect(
        adapter.calls.single.path,
        '${TranscriptRemoteDataSource.layuiBasePath}/score/verifySecondMajor',
      );
      expect(adapter.bodies.single, contains('userId=enc%3D%3D'));
    });

    test('查报表类型失败（status=false）→ 抛服务端 message', () async {
      final ds = TranscriptRemoteDataSource(
        _dioWith(_FakeAdapter('{"message":"学号不存在","status":false}')),
      );
      await expectLater(
        ds.fetchReportTypes('e'),
        throwsA(
          isA<TranscriptApiException>().having(
            (e) => e.message,
            'message',
            contains('学号不存在'),
          ),
        ),
      );
    });

    test('发送成绩单：form 里 enc 的 + 与 = 必须百分号编码（H5 encodeURIComponent 口径）', () async {
      final adapter = _FakeAdapter('{"message":"发送成功，请查收邮箱","status":true}');
      final ds = TranscriptRemoteDataSource(_dioWith(adapter));

      final message = await ds.sendTranscript(
        enc: 'AAAAAAAAAAAAAAAAAAAAAA==',
        email: '2000000000@stu.jxufe.edu.cn',
        courseId: '1',
      );

      expect(message, '发送成功，请查收邮箱');
      expect(
        adapter.calls.single.path,
        '${TranscriptRemoteDataSource.layuiBasePath}/score/bkscj',
      );
      final body = adapter.bodies.single;
      expect(body, contains('userId=AAAAAAAAAAAAAAAAAAAAAA%3D%3D'));
      expect(body, contains('courseId=1'));
      expect(
        body,
        contains('email=2000000000%40stu.jxufe.edu.cn'),
      );
    });

    test('发送失败（status=false）→ 抛服务端 message', () async {
      final ds = TranscriptRemoteDataSource(
        _dioWith(_FakeAdapter('{"message":"邮箱格式错误","status":false}')),
      );
      await expectLater(
        ds.sendTranscript(enc: 'e', email: 'a@b.com', courseId: '1'),
        throwsA(
          isA<TranscriptApiException>().having(
            (e) => e.message,
            'message',
            '邮箱格式错误',
          ),
        ),
      );
    });
  });

  group('transcriptDefaultEmailProvider · 预填口径', () {
    test('优先用邮箱接口给的权威地址', () async {
      final container = ProviderContainer(
        overrides: [
          myMailboxProvider.overrideWith(
            (ref) async => const StudentMailbox(
              email: '2000000000@stu.jxufe.edu.cn',
              password: 'x',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(transcriptDefaultEmailProvider.future),
        '2000000000@stu.jxufe.edu.cn',
      );
    });

    test('邮箱接口不可用 → 回退登录账号（= 学号）+ 同一域，不用学籍 serialNo', () async {
      final container = ProviderContainer(
        overrides: [
          myMailboxProvider.overrideWith(
            (ref) async => throw const MyMailApiException('未配置 GUID'),
          ),
          currentAccountProvider.overrideWith((ref) => '2000000000'),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(transcriptDefaultEmailProvider.future),
        '2000000000@stu.jxufe.edu.cn',
      );
    });

    test('账号也取不到 → null（不预填）', () async {
      final container = ProviderContainer(
        overrides: [
          myMailboxProvider.overrideWith(
            (ref) async => throw const MyMailApiException('请先登录'),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(transcriptDefaultEmailProvider.future), isNull);
    });
  });

  group('TranscriptSheet · 弹层', () {
    Future<_FakeTranscriptDs> pump(
      WidgetTester tester, {
      String? defaultEmail = '2000000000@stu.jxufe.edu.cn',
      Object? typesError,
    }) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ds = _FakeTranscriptDs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transcriptEncUserIdProvider.overrideWith((ref) async => 'enc=='),
            transcriptDefaultEmailProvider.overrideWith(
              (ref) async => defaultEmail,
            ),
            transcriptRemoteDataSourceProvider.overrideWithValue(ds),
            if (typesError != null)
              transcriptReportTypesProvider.overrideWith(
                (ref) async => throw typesError,
              )
            else
              transcriptReportTypesProvider.overrideWith(
                (ref) async => transcriptReportTypes(',1'),
              ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TranscriptSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ds;
    }

    testWidgets('预填学生邮箱 + 报表类型下拉默认第一项', (tester) async {
      await pump(tester);

      expect(find.text('本科生成绩单'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('transcript_email')),
      );
      expect(field.controller?.text, '2000000000@stu.jxufe.edu.cn');
      expect(find.text('主修成绩单（中）'), findsOneWidget);
    });

    testWidgets('发送 → 带上 enc / 邮箱 / courseId，并显示服务端提示', (tester) async {
      final ds = await pump(tester);

      await tester.tap(find.byKey(const Key('transcript_send')));
      await tester.pumpAndSettle();

      expect(ds.sent.single.enc, 'enc==');
      expect(ds.sent.single.email, '2000000000@stu.jxufe.edu.cn');
      expect(ds.sent.single.courseId, '1');
      // 弹层内状态行与 SnackBar 都会显示服务端提示（两处同文案）。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('transcript_status')))
            .data,
        '成绩单已发送至 2000000000@stu.jxufe.edu.cn，请查收。',
      );
      expect(
        find.text('成绩单已发送至 2000000000@stu.jxufe.edu.cn，请查收。'),
        findsWidgets,
      );
    });

    testWidgets('邮箱为空 → 拦下并提示，不发请求', (tester) async {
      final ds = await pump(tester, defaultEmail: null);

      await tester.tap(find.byKey(const Key('transcript_send')));
      await tester.pumpAndSettle();

      expect(ds.sent, isEmpty);
      expect(find.text('邮箱不能为空。'), findsOneWidget);
    });

    testWidgets('邮箱格式错 → 拦下并提示', (tester) async {
      final ds = await pump(tester, defaultEmail: null);

      await tester.enterText(
        find.byKey(const Key('transcript_email')),
        'not-an-email',
      );
      await tester.tap(find.byKey(const Key('transcript_send')));
      await tester.pumpAndSettle();

      expect(ds.sent, isEmpty);
      expect(find.text('请输入正确的邮箱地址。'), findsOneWidget);
    });

    testWidgets('服务端报错 → 段内显示该消息', (tester) async {
      final ds = await pump(tester);
      ds.failWith = const TranscriptApiException('学号未关联教务账号');

      await tester.tap(find.byKey(const Key('transcript_send')));
      await tester.pumpAndSettle();

      expect(find.text('学号未关联教务账号'), findsOneWidget);
    });

    testWidgets('报表类型拉取失败 → 显示错误与重试', (tester) async {
      await pump(tester, typesError: const TranscriptApiException('未配置微信平台标识（GUID），无法申请成绩单'));

      expect(
        find.text('未配置微信平台标识（GUID），无法申请成绩单'),
        findsOneWidget,
      );
      expect(find.text('重试'), findsOneWidget);
      expect(find.byKey(const Key('transcript_send')), findsOneWidget);
    });
  });
}
