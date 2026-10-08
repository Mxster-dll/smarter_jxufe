/// `createAppDio` / GBK 解码器的**行为守卫** + 「Dio 只有一个构造入口」的**源码守卫**。
///
/// 起因（2026-10-08 架构审计）：全仓 23 处手写 `Dio(BaseOptions(...))`，其中 12 处
/// 近乎逐字相同（6 处 15s/30s + 6 处 12s/20s），GBK 解码器更是抄了三份（连 charset
/// 正则都各写一遍）。收敛后由本文件钉住「默认值是什么」和「不许再手写」。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';

/// 允许自己写 `BaseOptions(` 的文件 → 理由（**必须写清为什么不能套工厂**，
/// 只写包名等于没写）。
const Map<String, String> baseOptionsAllowList = <String, String>{
  'lib/features/ai/data/ai_providers.dart':
      'AI 客户端与校园站点抓取语义相反：没有 baseUrl、要 sendTimeout 60s + '
      'receiveTimeout 5min、且非 2xx 必须抛异常。套 createAppDio 得连传 5 个覆盖'
      '参数，比这段手写更难读。',
};

/// 扫 `lib/` 下所有**非注释行**里出现 `BaseOptions(` 的位置（`文件:行号`）。
///
/// 判据取 `BaseOptions(` 而不是 `Dio(`：调用方可能在两者之间夹注释，只匹配
/// `Dio(` 前缀会漏判。
List<String> baseOptionsSites() {
  final hits = <String>[];
  final dir = Directory('lib');
  if (!dir.existsSync()) return hits;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      if (lines[i].contains('BaseOptions(')) hits.add('$rel:${i + 1}');
    }
  }
  return hits;
}

void main() {
  group('createAppDio 默认值 = 校园站点抓取口径', () {
    test('12s / 20s、自己跟重定向、任何状态码都算成功、无 baseUrl = 空串', () {
      final dio = createAppDio();

      expect(dio.options.baseUrl, '');
      expect(dio.options.connectTimeout, const Duration(seconds: 12));
      expect(dio.options.receiveTimeout, const Duration(seconds: 20));
      expect(dio.options.sendTimeout, isNull);
      expect(dio.options.followRedirects, isTrue);
      for (final status in <int>[200, 204, 301, 404, 500]) {
        expect(
          dio.options.validateStatus(status),
          isTrue,
          reason: '$status 在校园站点口径里也算「拿到了响应」',
        );
      }
    });

    test('rejectNon2xxStatus = Dio 自己的默认判据（给要严格语义的站点）', () {
      expect(rejectNon2xxStatus(200), isTrue);
      expect(rejectNon2xxStatus(299), isTrue);
      expect(rejectNon2xxStatus(300), isFalse);
      expect(rejectNon2xxStatus(404), isFalse);
      expect(rejectNon2xxStatus(500), isFalse);
      expect(rejectNon2xxStatus(null), isFalse);
    });

    test('userAgent 排在 headers 最前，其余按调用方给的顺序', () {
      final dio = createAppDio(
        userAgent: 'UA/1.0',
        headers: <String, String>{
          'Referer': 'https://example.edu.cn/',
          'Accept': '*/*',
        },
      );

      expect(dio.options.headers.keys.toList(), <String>[
        'User-Agent',
        'Referer',
        'Accept',
      ]);
      expect(dio.options.headers['User-Agent'], 'UA/1.0');
    });

    test('不给 userAgent 就不写这个头（不要塞空串污染请求）', () {
      expect(
        createAppDio().options.headers.containsKey('User-Agent'),
        isFalse,
      );
      expect(
        createAppDio(userAgent: '').options.headers.containsKey('User-Agent'),
        isFalse,
      );
    });

    test('少数派一律显式传参：超时 / 重定向 / 判据 / responseType 都能覆盖', () {
      final dio = createAppDio(
        baseUrl: 'https://strict.example.cn',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 60),
        followRedirects: false,
        validateStatus: rejectNon2xxStatus,
        responseType: ResponseType.bytes,
      );

      expect(dio.options.baseUrl, 'https://strict.example.cn');
      expect(dio.options.connectTimeout, const Duration(seconds: 30));
      expect(dio.options.receiveTimeout, const Duration(minutes: 5));
      expect(dio.options.sendTimeout, const Duration(seconds: 60));
      expect(dio.options.followRedirects, isFalse);
      expect(dio.options.validateStatus(404), isFalse);
      expect(dio.options.responseType, ResponseType.bytes);
    });
  });

  group('gbkAwareResponseDecoder（教务一族的刚需）', () {
    ResponseBody body(Map<String, List<String>> headers) =>
        ResponseBody(Stream<Uint8List>.empty(), 200, headers: headers);

    // 「成绩」的 GBK 字节 = B3 C9 BC A8；UTF-8 字节 = E6 88 90 E7 BB A9。
    const gbkChengJi = <int>[0xB3, 0xC9, 0xBC, 0xA8];
    const utf8ChengJi = <int>[0xE6, 0x88, 0x90, 0xE7, 0xBB, 0xA9];

    test('charset=gbk → 按 GBK 解', () {
      final decode = gbkAwareResponseDecoder();
      expect(
        decode(
          gbkChengJi,
          RequestOptions(),
          body(<String, List<String>>{
            'Content-Type': <String>['text/html; charset=gbk'],
          }),
        ),
        '成绩',
      );
    });

    test('gb2312 / 大写 / 前后空白 / 带引号 都能认出来', () {
      final decode = gbkAwareResponseDecoder();
      for (final header in <String>[
        'text/html; Charset=GB2312 ',
        'text/html; charset=GBK',
        'text/html; charset="gbk"',
        "text/html; charset='gbk'",
      ]) {
        expect(
          decode(
            gbkChengJi,
            RequestOptions(),
            body(<String, List<String>>{
              'Content-Type': <String>[header],
            }),
          ),
          '成绩',
          reason: header,
        );
      }
    });

    test('没有 charset → 走 UTF-8', () {
      final decode = gbkAwareResponseDecoder();
      expect(
        decode(
          utf8ChengJi,
          RequestOptions(),
          body(<String, List<String>>{
            'Content-Type': <String>['application/json'],
          }),
        ),
        '成绩',
      );
    });

    test('allowMalformed=false（默认）：坏 UTF-8 字节抛异常', () {
      final decode = gbkAwareResponseDecoder();
      expect(
        () => decode(
          const <int>[0xFF, 0xFE],
          RequestOptions(),
          body(const <String, List<String>>{}),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('allowMalformed=true：坏字节留替换字符，不判失败（后台小组件口径）', () {
      final decode = gbkAwareResponseDecoder(allowMalformed: true);
      final text =
          decode(
                const <int>[0xFF, 0xFE],
                RequestOptions(),
                body(const <String, List<String>>{}),
              )
              as String;
      expect(text.contains('\uFFFD'), isTrue);
    });

    test('extractCharset 的边界', () {
      expect(extractCharset(null), '');
      expect(extractCharset('text/html'), '');
      expect(extractCharset('text/html; charset=UTF-8'), 'utf-8');
      expect(extractCharset('text/html; charset="gbk"'), 'gbk');
      expect(extractCharset('charset=gbk; boundary=x'), 'gbk');
    });
  });

  group('源码守卫：Dio 只有一个构造入口', () {
    test('lib/ 下除白名单外不再手写 BaseOptions(', () {
      final offenders = baseOptionsSites()
          .where((hit) {
            final file = hit.substring(0, hit.lastIndexOf(':'));
            return file != 'lib/core/network/dio_factory.dart' &&
                !baseOptionsAllowList.containsKey(file);
          })
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '这些地方又手写了 Dio(BaseOptions(...))：请改走 '
            'createAppDio()（lib/core/network/dio_factory.dart）；'
            '确实不能套的，加进本文件 baseOptionsAllowList 并写明理由。',
      );
    });

    test('白名单每一条都写了理由（不是空壳）', () {
      for (final entry in baseOptionsAllowList.entries) {
        expect(
          entry.value.trim().length,
          greaterThan(20),
          reason: '${entry.key} 的理由太短，等于没写',
        );
      }
    });

    test('白名单不许陈旧：列的包必须真的还在手写', () {
      for (final file in baseOptionsAllowList.keys) {
        expect(
          File(file).existsSync(),
          isTrue,
          reason: '$file 不存在了，从白名单里删掉',
        );
        expect(
          baseOptionsSites().any((hit) => hit.startsWith('$file:')),
          isTrue,
          reason: '$file 已经不手写 BaseOptions 了，从白名单里删掉（棘轮只许减）',
        );
      }
    });

    test('工厂自己也只写一处（别在工厂里再套一层）', () {
      final inFactory = baseOptionsSites()
          .where((hit) => hit.startsWith('lib/core/network/dio_factory.dart:'))
          .length;
      expect(inFactory, 1);
    });
  });
}
