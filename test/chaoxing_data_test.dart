/// 学习通数据层守卫：Cookie 罐 / 快照派生 / 刷新闸门 / 换证链 + 全量取数（假 HTTP）。
///
/// 最后一个 group 是**端到端**的：真数据源 + 真解析器 + 真 Cookie 罐，只有 HTTP 与
/// 「换票」两处是假的 —— 这样解析口径、Cookie 归属、并发编排、缓存写入一次全测到。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_cookie_jar.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_gate.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_repository.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_store.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_mooc_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_notice_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_sign_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Cookie 罐：按域匹配（学习通 passport 是 Domain=.chaoxing.com 的域级 Cookie）', () {
    test('域级 Cookie 覆盖业务子域，host-only 不外泄', () {
      final jar = SessionCookieJar();
      jar.absorb(Uri.parse('https://i.chaoxing.com/'), [
        'UID=abc; Path=/; Domain=.chaoxing.com',
        'jrose=xyz; Path=/',
      ]);
      expect(jar.headerFor('mooc1.chaoxing.com'), contains('UID=abc'));
      expect(jar.headerFor('notice.chaoxing.com'), contains('UID=abc'));
      expect(jar.headerFor('mooc1.chaoxing.com'), isNot(contains('jrose')));
      expect(jar.headerFor('i.chaoxing.com'), contains('jrose'));
      expect(jar.hasPassport, isTrue);
    });

    test('★ 网关域（host-only）的 Cookie 不进业务域 —— libsp 踩过的混发坑', () {
      final jar = SessionCookieJar();
      jar.absorb(
        Uri.parse('https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'),
        ['JSESSIONID=gw; Path=/', 'firstReferer=x; Path=/', 'route=gw; Path=/'],
      );
      expect(jar.headerFor('unified-auth.chaoxing.com'), contains('JSESSIONID=gw'));
      expect(jar.headerFor('mooc1.chaoxing.com'), isEmpty);
      expect(jar.hasPassport, isFalse, reason: '只有网关 Cookie 时不算登录成功');
    });

    test('标签边界：chaoxing.com 不命中 xchaoxing.com', () {
      final jar = SessionCookieJar();
      jar.absorb(Uri.parse('https://i.chaoxing.com/'), [
        'UID=abc; Domain=chaoxing.com',
      ]);
      expect(jar.headerFor('evilxchaoxing.com'), isEmpty);
      expect(jar.headerFor('i.chaoxing.com'), contains('UID=abc'));
    });

    test('同名时更具体的域赢（host-only > 域级），与浏览器一致', () {
      final jar = SessionCookieJar();
      jar.absorb(Uri.parse('https://unified-auth.chaoxing.com/'), ['route=a; Path=/']);
      jar.absorb(Uri.parse('https://i.chaoxing.com/'), [
        'route=b; Path=/; Domain=.chaoxing.com',
      ]);
      expect(jar.headerFor('unified-auth.chaoxing.com'), contains('route=a'));
      expect(jar.headerFor('mooc1.chaoxing.com'), contains('route=b'));
    });

    test('★ passport 认三件套 UID / _uid / p_auth_token，且只认业务域上的', () {
      for (final name in const ['UID', '_uid', 'p_auth_token']) {
        final jar = SessionCookieJar();
        jar.absorb(Uri.parse('https://i.chaoxing.com/'), [
          '$name=v; Path=/; Domain=.chaoxing.com',
        ]);
        expect(jar.hasPassport, isTrue, reason: '$name 应算已登录');
      }
      final gatewayOnly = SessionCookieJar();
      gatewayOnly.absorb(
        Uri.parse('https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'),
        ['UID=gw; Path=/'],
      );
      expect(
        gatewayOnly.hasPassport,
        isFalse,
        reason: '网关域 host-only 的 UID 不算登录（票还没换完）',
      );
    });

    test('namesOf 只报名字（诊断用，值不外泄）；toJson/fromJson 往返', () {
      final jar = SessionCookieJar();
      jar.absorb(Uri.parse('https://i.chaoxing.com/'), ['UID=secret; Domain=.chaoxing.com']);
      expect(jar.namesOf()['chaoxing.com'], ['UID']);
      expect(jar.toString().contains('secret'), isFalse);

      final restored = SessionCookieJar.fromJson(jsonDecode(jsonEncode(jar.toJson())));
      expect(restored.headerFor('mooc1.chaoxing.com'), contains('UID=secret'));
      expect(SessionCookieJar.fromJson(null).isEmpty, isTrue);
      expect(SessionCookieJar.fromJson({'chaoxing.com': 'oops'}).isEmpty, isTrue);
    });
  });

  group('快照派生与文案', () {
    final course = const ChaoxingCourse(
      courseId: '1',
      classId: '11',
      cpi: '9',
      name: '261学期 线性代数(工)',
    );
    final works = [
      ChaoxingWork(
        workId: 'a',
        title: '待做晚',
        courseId: '1',
        courseName: course.name,
        dueAt: DateTime(2026, 9, 25, 23, 59),
        status: ChaoxingWorkStatus.todo,
      ),
      ChaoxingWork(
        workId: 'b',
        title: '待做早',
        courseId: '1',
        courseName: course.name,
        dueAt: DateTime(2026, 9, 20, 23, 59),
        status: ChaoxingWorkStatus.todo,
      ),
      ChaoxingWork(
        workId: 'c',
        title: '待批阅',
        courseId: '1',
        courseName: course.name,
        dueAt: DateTime(2026, 9, 1),
        status: ChaoxingWorkStatus.pendingReview,
      ),
      ChaoxingWork(
        workId: 'd',
        title: '已完成',
        courseId: '1',
        courseName: course.name,
        dueAt: DateTime(2026, 9, 10),
        status: ChaoxingWorkStatus.done,
        score: 90,
      ),
      ChaoxingWork(
        workId: 'e',
        title: '状态未知',
        courseId: '1',
        courseName: course.name,
        status: ChaoxingWorkStatus.unknown,
      ),
    ];
    final snapshot = ChaoxingSnapshot(
      courses: [course],
      works: works,
      notices: [
        ChaoxingNotice(
          id: 'n1',
          title: '未读',
          content: 'x',
          sender: '张三',
          sentAt: DateTime(2026, 9, 17, 20, 18, 37),
        ),
        ChaoxingNotice(
          id: 'n2',
          title: '已读',
          content: 'y',
          sender: '学习通知',
          read: true,
          top: true,
        ),
      ],
      fetchedAt: DateTime(2026, 9, 19, 10),
    );

    test('待做按截止升序在前；已完成倒序；unknown 不混进待做', () {
      expect(snapshot.openWorks.map((w) => w.title).toList(), ['待做早', '待做晚']);
      expect(snapshot.todoCount, 2);
      expect(snapshot.finishedWorks.map((w) => w.title).toList(), ['已完成']);
      expect(snapshot.unreadNoticeCount, 1);
      expect(snapshot.isEmpty, isFalse);
    });

    test('toJson / fromJson 往返（脏数据只丢那一条）', () {
      final back = ChaoxingSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );
      expect(back.courses.length, 1);
      expect(back.works.length, 5);
      expect(back.notices.length, 2);
      expect(back.fetchedAt, snapshot.fetchedAt);
      expect(back.works.first.dueAt, DateTime(2026, 9, 25, 23, 59));
      expect(back.notices[1].top, isTrue);

      final dirty = ChaoxingSnapshot.fromJson({
        'courses': ['oops', 1],
        'works': 'nope',
        'notices': null,
        'failedCourseKeys': [1, 'x'],
      });
      expect(dirty.courses, isEmpty);
      expect(dirty.works, isEmpty);
      expect(dirty.notices, isEmpty);
      expect(dirty.failedCourseKeys, ['1', 'x']);
    });

    test('按课程聚合作业（认不出归属的条目丢掉）', () {
      final grouped = chaoxingWorksByCourse(
        ChaoxingSnapshot(
          courses: [course],
          works: [
            ...works,
            ChaoxingWork(
              workId: 'ghost',
              title: '课程已消失',
              courseId: '404',
              courseName: '?',
              status: ChaoxingWorkStatus.todo,
            ),
          ],
        ),
      );
      expect(grouped[course.key]!.length, 5);
    });

    test('倒计时文案四档 + 过期', () {
      final now = DateTime(2026, 9, 19, 12);
      expect(chaoxingCountdownText(null, now), '无截止时间');
      expect(chaoxingCountdownText(DateTime(2026, 9, 19, 23, 59), now), '今天 23:59 截止');
      expect(chaoxingCountdownText(DateTime(2026, 9, 20, 23, 59), now), '明天 23:59 截止');
      expect(chaoxingCountdownText(DateTime(2026, 9, 21, 12), now), '还剩 2 天');
      expect(chaoxingCountdownText(DateTime(2026, 9, 19, 11), now), '已过期 1 小时');
      expect(
        chaoxingCountdownText(DateTime(2026, 10, 5, 8), now),
        '10月5日 08:00 截止',
      );
    });

    test('通知时间：今天 / 昨天 / 今年 / 跨年', () {
      final now = DateTime(2026, 9, 19, 12);
      expect(chaoxingTimeText(DateTime(2026, 9, 19, 8, 5), now), '今天 08:05');
      expect(chaoxingTimeText(DateTime(2026, 9, 18, 8, 5), now), '昨天 08:05');
      expect(chaoxingTimeText(DateTime(2026, 3, 1, 8, 5), now), '3月1日 08:05');
      expect(chaoxingTimeText(DateTime(2025, 3, 1, 8, 5), now), '2025年3月1日');
      expect(chaoxingTimeText(null, now), '—');
    });

    test('详情弹窗的绝对时刻（与列表的相对口语分工）', () {
      expect(chaoxingMomentText(DateTime(2026, 9, 20, 23, 59)), '2026-09-20 23:59');
      expect(chaoxingMomentText(DateTime(2026, 1, 2, 8, 5)), '2026-01-02 08:05');
      expect(chaoxingMomentText(null), '—', reason: '开始时间经常缺失');
    });

    test('状态文案：已完成带分数、未知单列', () {
      expect(chaoxingWorkStatusText(works[3]), '已完成 90 分');
      expect(chaoxingWorkStatusText(works[0]), '待做');
      expect(chaoxingWorkStatusText(works[4]), '状态未知');
    });

    test('通知摘要收拢空白并截断', () {
      expect(chaoxingNoticeSnippet('a\r\n  b   c'), 'a b c');
      expect(chaoxingNoticeSnippet('x' * 100, max: 10).endsWith('…'), isTrue);
    });

    test('按 courseId 查课程名：查不到给空串（详情里不回显裸 id）', () {
      final snap = ChaoxingSnapshot(courses: [course], works: const []);
      expect(chaoxingCourseNameOf(snap, course.courseId), course.name);
      expect(chaoxingCourseNameOf(snap, '404'), '');
      expect(chaoxingCourseNameOf(snap, ''), '', reason: '非课程类通知的 courseId 是空串');
      expect(chaoxingCourseNameOf(null, course.courseId), '', reason: '首帧快照还没到');
    });
  });

  group('刷新闸门（1 分钟窗口，时钟可注入）', () {
    test('窗口起点 = 上一次真的取到新数据的时刻', () {
      var now = DateTime(2026, 9, 19, 10);
      final gate = ChaoxingRefreshGate(now: () => now);
      expect(gate.allowsAutoRefresh, isTrue, reason: '从没取过数 → 允许');
      gate.markUpdated();
      expect(gate.allowsAutoRefresh, isFalse);
      expect(gate.remaining.inSeconds, 60);
      now = now.add(const Duration(seconds: 59));
      expect(gate.allowsAutoRefresh, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(gate.allowsAutoRefresh, isTrue);
      expect(gate.remaining, Duration.zero);
    });

    test('常量就是用户口径的 1 分钟', () {
      expect(chaoxingMinRefreshInterval, const Duration(minutes: 1));
    });
  });

  group('业务请求的跳转口径（真机 302 回归 · 2026-09-19 冒烟实测）', () {
    ChaoxingHttpClient client(_RouteAdapter adapter) => ChaoxingHttpClient(
      Dio(
        BaseOptions(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      )..httpClientAdapter = adapter,
    );

    ChaoxingSession session() => ChaoxingSession(jar: SessionCookieJar());

    const course = ChaoxingCourse(
      courseId: '100000001',
      classId: '200000001',
      cpi: '900000001',
      name: '261学期 计算机组成原理',
    );

    test('★ 课程详情先给 302 → 必须跟到真页面，否则作业恒为 0 条', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle') && !url.contains('w='),
          body: '',
          status: 302,
          location:
              'https://mooc1.chaoxing.com/visit/stucoursemiddle'
              '?courseid=100000001&clazzid=200000001&w=tok',
        ),
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_work_list.html'),
          contentType: 'text/html; charset=utf-8',
        ),
      ]);
      final works = await ChaoxingMoocRemoteDataSource(
        client(adapter),
      ).worksOf(session(), course);
      expect(works.length, 3, reason: '不跟 302 的话这里是 0');
      expect(
        adapter.calls.any((c) => c.uri.toString().contains('w=tok')),
        isTrue,
        reason: '确实跟到了带会话 token 的那一跳',
      );
    });

    test('默认不跟跳转（换证链要自己逐跳判定）', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('/anything'),
          body: '',
          status: 302,
          location: 'https://mooc1.chaoxing.com/next',
        ),
      ]);
      final r = await client(
        adapter,
      ).get('https://mooc1.chaoxing.com/anything');
      expect(r.statusCode, 302);
      expect(adapter.calls.length, 1, reason: '默认只发一跳');
    });

    test('★ 被踢回登录页的 302 不跟 —— 原样返回，交给 ensureAlive 判失效', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: '',
          status: 302,
          location: 'https://passport2.chaoxing.com/login?refer=x',
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(
          client(adapter),
        ).worksOf(session(), course),
        throwsA(isA<ChaoxingSessionExpiredException>()),
      );
      expect(adapter.calls.length, 1, reason: '登录页 302 不该被跟出去');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 用户 2026-09-19 报「作业、课程有时刷新会刷新没」→ 根因就是下面这一组：
  // 请求过密时超星回 `202` + 4527 B 的验证码挑战页（正文无课程锚点 / 无 getAllWork
  // 入口 / 无「暂无内容」），首版把这种页面一律当成**空结果**，于是
  //   ① 那些课的作业静默消失；
  //   ② `refresh()` 又把残缺快照无条件写进缓存 → 连旧数据也保不住。
  // 实测触发口径：稳态 1 请求/秒 → 0 次；突发 8/16 并发 → 0 次；24 并发 → 24/24 全中；
  // 触发后 ≥ 60 秒不恢复（所以**不能靠重试**，只能判失败 + 保留旧数据 + 冷却）。
  // ────────────────────────────────────────────────────────────────────────
  group('★ 风控挑战页与「可信空」口径（用户 2026-09-19：「作业、课程有时刷新会刷新没」）', () {
    ChaoxingHttpClient client(_RouteAdapter adapter) => ChaoxingHttpClient(
      Dio(
        BaseOptions(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      )..httpClientAdapter = adapter,
      minRequestInterval: Duration.zero, // 单测不必真等限速
    );

    ChaoxingSession session() => ChaoxingSession(jar: SessionCookieJar());

    const course = ChaoxingCourse(
      courseId: '100000001',
      classId: '200000001',
      cpi: '900000001',
      name: '261学期 计算机组成原理',
    );

    test('挑战页识别：202 状态码，以及 200 但正文带验证码文案', () {
      expect(
        ChaoxingHttpClient.challengeStatus,
        202,
        reason: '实测就是 202（不是 200/403）',
      );
      expect(
        ChaoxingHttpClient.isChallengePage(
          Response<dynamic>(requestOptions: RequestOptions(), statusCode: 202),
          '',
        ),
        isTrue,
      );
      expect(
        ChaoxingHttpClient.isChallengePage(
          Response<dynamic>(requestOptions: RequestOptions(), statusCode: 200),
          fixture('chaoxing_challenge.html'),
        ),
        isTrue,
        reason: '防它哪天改回 200 —— 正文特征也算数',
      );
      expect(
        ChaoxingHttpClient.isChallengePage(
          Response<dynamic>(requestOptions: RequestOptions(), statusCode: 200),
          fixture('chaoxing_work_empty.html'),
        ),
        isFalse,
        reason: '真业务页不能被误判',
      );
    });

    test('★ 课程页是 202 挑战页 → 抛「风控」，而不是「这门课没作业」', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_challenge.html'),
          status: 202,
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).worksOf(session(), course),
        throwsA(isA<ChaoxingChallengedException>()),
      );
    });

    test('★ 200 但课程页是挑战页 → 同样抛风控', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_challenge.html'),
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).worksOf(session(), course),
        throwsA(isA<ChaoxingChallengedException>()),
      );
    });

    test('★ 课程页 200 却抠不出作业入口 → 抛「页面不对」，绝不返回空列表', () async {
      // 这条就是本 bug 的第一层根因：真课程页的 getAllWork 命中数恒为 1（实测 35/35），
      // 抠不出必然是没拿到业务页 —— 返回空列表 = 这门课的作业静默消失。
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: '<html><head><title>空业务页</title></head><body></body></html>',
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).worksOf(session(), course),
        throwsA(isA<ChaoxingPageException>()),
      );
    });

    test('作业页是挑战页 → 抛风控（中间页正常也不例外）', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_challenge.html'),
          status: 202,
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).worksOf(session(), course),
        throwsA(isA<ChaoxingChallengedException>()),
      );
    });

    test('★ 作业页解析 0 条且没写「暂无内容」→ 抛页面异常（不静默空）', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: '<html><body><div class="ulDiv"><ul></ul></div></body></html>',
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).worksOf(session(), course),
        throwsA(isA<ChaoxingPageException>()),
      );
    });

    test('真·空课（页面写「暂无内容」）→ 仍然是空列表，不能误判成失败', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_work_empty.html'),
        ),
      ]);
      final works = await ChaoxingMoocRemoteDataSource(
        client(adapter),
      ).worksOf(session(), course);
      expect(works, isEmpty, reason: '22/35 门课属于这一档，必须保持正常空态');
    });

    test('★ 课程清单解析 0 门 → 抛页面异常（不让整页连课程一起空）', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('visit/courses'),
          body: '<html><head><title>学生端</title></head><body></body></html>',
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).courses(session()),
        throwsA(isA<ChaoxingPageException>()),
      );
    });

    test('★ 课程清单是挑战页 → 抛风控', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_challenge.html'),
          status: 202,
        ),
      ]);
      await expectLater(
        ChaoxingMoocRemoteDataSource(client(adapter)).courses(session()),
        throwsA(isA<ChaoxingChallengedException>()),
      );
    });

    test('课程清单正常 → 4 门（对照组，证明上面几例不是「一律抛」）', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_courses.html'),
        ),
      ]);
      final courses = await ChaoxingMoocRemoteDataSource(
        client(adapter),
      ).courses(session());
      expect(courses.length, 4);
    });

    test('限速器：业务请求之间按 minRequestInterval 排队（并发也共用同一条队列）', () async {
      // 用可注入的时钟不行（等待是真的 Future.delayed），这里直接验「两次业务请求
      // 的发出时刻差 ≥ 间隔」，取小间隔以免拖慢测试。
      final stamps = <DateTime>[];
      final adapter = _RouteAdapter([
        _Route((url) => url.contains('visit/courses'), body: fixture('chaoxing_courses.html')),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
        minRequestInterval: const Duration(milliseconds: 120),
      );
      for (var i = 0; i < 3; i++) {
        await http.get('https://mooc1.chaoxing.com/visit/courses', throttle: true);
        stamps.add(DateTime.now());
      }
      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i].difference(stamps[i - 1]).inMilliseconds,
          greaterThanOrEqualTo(110),
          reason: '第 ${i + 1} 次业务请求被排队了（间隔 120ms）',
        );
      }
    });

    test('★ 限速器在并发下依然成立 —— 4 条 lane 不许同时发', () async {
      // 首版是「读上次时刻 → 睡够 → 写时刻」，4 条 lane 会读到同一个 last、
      // 算出同一个 wait、**一起醒来一起发** → 实测退化成 4 请求/间隔
      // （冒烟里 64 个请求只花 4.3 秒，风控照样触发）。现在改成原子预定下一格。
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_courses.html'),
        ),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
        minRequestInterval: const Duration(milliseconds: 80),
      );
      final sw = Stopwatch()..start();
      await Future.wait([
        for (var i = 0; i < 4; i++)
          http.get('https://mooc1.chaoxing.com/visit/courses', throttle: true),
      ]);
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(230),
        reason: '4 个请求按 80ms 排队 → 最后一个要到 240ms 才发得出去',
      );
    });

    test('换证链不排队（throttle 默认关）—— 免得每跳都白等', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('/login_auth/'),
          body: '<html></html>',
        ),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
        minRequestInterval: const Duration(seconds: 5),
      );
      final sw = Stopwatch()..start();
      await http.get('https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: '不该等 5 秒');
    });
  });

  group('换证链 + 全量取数（假 HTTP）', () {
    late Directory tmp;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('chaoxing_test');
      Hive.init(tmp.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('★ 零密码走完全链：4 门课 / 3 条作业 / 4 条通知，并落缓存', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('getNoticeCount'),
          body: '{"status":true,"msg":false}',
          contentType: Headers.jsonContentType,
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/index?ticket='),
          body: fixture('chaoxing_gateway_page.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/login'),
          body: '{"cxuser":{},"status":true}',
          contentType: Headers.jsonContentType,
          setCookie: ['UID=uid-value; Path=/; Domain=.chaoxing.com'],
        ),
        _Route(
          (url) => url.startsWith('https://i.chaoxing.com?data='),
          body: '',
          status: 302,
          location: 'https://i.chaoxing.com/base?t=1',
        ),
        _Route(
          (url) => url.contains('i.chaoxing.com/base'),
          body: fixture('chaoxing_space_base.html'),
          contentType: 'text/html; charset=utf-8',
          setCookie: ['jrose=1; Path=/', 'spaceFid=1412; Path=/'],
        ),
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_courses.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        // 课程详情页：**按课**给 —— 线性代数那门课的页里，作业入口带的是它自己的
        // enc/openc（100000002）；其余三门给通用页（100000001）。
        // ⚠ 若对所有课返回同一张页，四门课的作业入口 URL 会完全相同，
        // 「只有一门课有作业」就表达不出来（首跑踩过）。
        _Route(
          (url) => url.contains('stucoursemiddle') && url.contains('courseid=100000002'),
          body: fixture('chaoxing_course_middle_lin.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        // 只有线性代数（100000002）有作业，其余三门是空课页。
        _Route(
          (url) => url.contains('work/getAllWork') && url.contains('courseId=100000002'),
          body: fixture('chaoxing_work_list.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_work_empty.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        // 签到清单（**POST** `widget/pcpick/stu/activeList`）：1 请求/课；
        // 假适配器只按 URL 分发，四门课拿到同一份（4 条签到）。
        _Route(
          (url) => url.contains('pcpick/stu/activeList'),
          body: fixture('chaoxing_sign_list.json'),
          contentType: Headers.jsonContentType,
        ),
        // 我的状态：**按需**逐活动取（1 请求/活动）。
        _Route(
          (url) => url.contains('pcStuSignController/preSign'),
          body: fixture('chaoxing_sign_detail.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('notice/getNoticeList'),
          body: fixture('chaoxing_notices.json'),
          contentType: Headers.jsonContentType,
        ),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
      );
      var ticketCalls = 0;
      final repo = ChaoxingRepository(
        auth: ChaoxingAuthRemoteDataSource(http),
        mooc: ChaoxingMoocRemoteDataSource(http),
        notice: ChaoxingNoticeRemoteDataSource(http),
        sign: ChaoxingSignRemoteDataSource(http),
        fetchTicket: (casUrl) async {
          ticketCalls += 1;
          expect(casUrl, ChaoxingEndpoints.casServiceUrl);
          return Right(
            'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'
            '?ticket=ST-fake',
          );
        },
        store: ChaoxingStore(await Hive.openBox<String>('chaoxing_test_full')),
        concurrency: 2,
      );

      final progress = <ChaoxingProgress>[];
      final snapshot = await repo.refresh(onProgress: progress.add);

      expect(ticketCalls, 1, reason: '一次刷新只换一次票');
      expect(snapshot.courses.length, 4);
      expect(snapshot.works.length, 3, reason: '只有线性代数那门课有作业');
      expect(snapshot.notices.length, 4);
      expect(snapshot.noticesAvailable, isTrue);
      expect(snapshot.failedCourseKeys, isEmpty);
      expect(snapshot.todoCount, 1);
      expect(snapshot.unreadNoticeCount, 2);
      expect(snapshot.fetchedAt, isNotNull);
      expect(snapshot.works.first.courseName, '261学期 线性代数(工)');

      // 签到：4 门课各 1 个请求 → 每门 4 条（fixture 里 3 条已结束 + 1 条进行中）
      expect(snapshot.signs.length, 16, reason: '4 门课 × 4 条');
      expect(snapshot.failedSignCourseKeys, isEmpty);
      expect(snapshot.signsOfCourse('100000001').length, 4);
      expect(
        adapter.calls
            .where((c) => c.uri.toString().contains('pcpick/stu/activeList'))
            .length,
        4,
        reason: '签到清单是**每门课 1 个请求**',
      );
      expect(
        adapter.calls
            .firstWhere((c) => c.uri.toString().contains('activeList'))
            .data
            .toString(),
        contains('courseId'),
        reason: '清单是 POST form（courseId / classId / puid）',
      );
      expect(
        snapshot.unknownSignStatusCount,
        16,
        reason: '清单接口不给我的状态 → 全部「未查」（**不是**未签）',
      );

      // 进度：会话 → 课程 → 作业（逐门）→ 完成
      expect(progress.first.phase, ChaoxingPhase.session);
      expect(
        progress.where((p) => p.phase == ChaoxingPhase.works).last.done,
        4,
        reason: '4 门课各回调一次',
      );

      // 缓存写进去了（下次进页面先显示它）
      final cached = await repo.cached();
      expect(cached, isNotNull);
      expect(cached!.courses.length, 4);
      expect(cached.works.length, 3);

      // Cookie 归属：passport 是 Domain=.chaoxing.com 的域级 Cookie → 业务域都拿得到；
      // 而 `i.chaoxing.com` 自己那枚 host-only 的 jrose 不外泄给任何别的域。
      expect(adapter.cookieOf('mooc1.chaoxing.com'), contains('UID=uid-value'));
      expect(adapter.cookieOf('mooc1.chaoxing.com'), isNot(contains('jrose')));
      expect(adapter.cookieOf('notice.chaoxing.com'), contains('UID=uid-value'));
      expect(adapter.cookieOf('notice.chaoxing.com'), isNot(contains('jrose')));

      // 但发给**它自己的**域时要带上：jrose 是换证最后一跳（`/base`）才下发的，
      // 所以断言必须发生在「那一跳之后」—— 换一次新会话，随后打红点接口
      // （`i.chaoxing.com/base/getNoticeCount`）时它必须在头上。
      final freshSession = await ChaoxingAuthRemoteDataSource(http).establishSession(
        'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'
        '?ticket=ST-fake',
      );
      expect(await ChaoxingNoticeRemoteDataSource(http).hasNew(freshSession), isFalse);
      expect(adapter.cookieOf('i.chaoxing.com'), contains('jrose'));
      expect(adapter.cookieOf('i.chaoxing.com'), contains('UID=uid-value'));
    });

    test('★ 只扫当下学期（用户 2026-09-20 定 A+B 的 A）：往期课一个请求都不发', () async {
      // 作业是学习通里唯一没有统一接口的数据（逐课 2 请求），35 门全扫 = 70 个请求
      // 必然撞风控（≈60/窗口）。所以真正的解法是**缩小范围**：只扫当下学期。
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('getNoticeCount'),
          body: '{"status":true,"msg":false}',
          contentType: Headers.jsonContentType,
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/index?ticket='),
          body: fixture('chaoxing_gateway_page.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/login'),
          body: '{"status":true}',
          contentType: Headers.jsonContentType,
          setCookie: ['UID=uid-value; Domain=.chaoxing.com'],
        ),
        _Route(
          (url) => url.startsWith('https://i.chaoxing.com?data='),
          body: '',
          status: 302,
          location: 'https://i.chaoxing.com/base?t=1',
        ),
        _Route(
          (url) => url.contains('i.chaoxing.com/base'),
          body: fixture('chaoxing_space_base.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        // 5 门课：261 学期 1 门 + 252/251 学期各 1 门（往期）+ 无学期前缀 2 门。
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_courses_terms.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('stucoursemiddle') && url.contains('courseid=100000002'),
          body: fixture('chaoxing_course_middle_lin.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('work/getAllWork') && url.contains('courseId=100000002'),
          body: fixture('chaoxing_work_list.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_work_empty.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('notice/getNoticeList'),
          body: fixture('chaoxing_notices.json'),
          contentType: Headers.jsonContentType,
        ),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
        minRequestInterval: Duration.zero,
      );
      Future<ChaoxingRepository> build(String termCode, String box) async =>
          ChaoxingRepository(
            auth: ChaoxingAuthRemoteDataSource(http),
            mooc: ChaoxingMoocRemoteDataSource(http),
            notice: ChaoxingNoticeRemoteDataSource(http),
            sign: ChaoxingSignRemoteDataSource(http),
            fetchTicket: (_) async => const Right(
              'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'
              '?ticket=ST-fake',
            ),
            store: ChaoxingStore(await Hive.openBox<String>(box)),
            concurrency: 1,
            currentTermCode: termCode,
          );

      List<String> scannedCourses() => [
        for (final c in adapter.calls)
          if (c.uri.toString().contains('stucoursemiddle')) c.uri.toString(),
      ];

      final repo = await build('261', 'chaoxing_test_terms');
      final snapshot = await repo.refresh();

      expect(snapshot.courses.length, 5, reason: '课程清单本身永远是全量');
      expect(snapshot.skippedCourseKeys, [
        '100000006/200000006',
        '100000007/200000007',
      ], reason: '非当下学期 → 有意不扫，如实记下来');
      expect(snapshot.pendingCourseKeys, isEmpty,
          reason: '窗口（20）装得下 3 个目标 → 没有「本轮没跑到」的课');
      expect(snapshot.works.length, 3, reason: '线性代数的作业照常扫到');

      final first = scannedCourses();
      expect(first.length, 3, reason: '261 学期 1 门 + 无前缀 2 门，一门课 1 个中间页请求');
      expect(first.where((u) => u.contains('courseid=100000006')), isEmpty);
      expect(first.where((u) => u.contains('courseid=100000007')), isEmpty);

      // 窗口装得下 → **游标推回 0**：第二轮仍是同样那 3 门（不再「两轮才凑齐」）。
      await repo.refresh(previous: snapshot);
      final second = scannedCourses().sublist(3);
      expect(second.length, 3);
      expect(second.where((u) => u.contains('courseid=100000002')).length, 1);
      expect(second.where((u) => u.contains('courseid=100000006')), isEmpty);

      // 对照：学期码为空（判不出当下学期）→ 不筛，5 门全扫（旧行为，别把功能变成不扫）。
      final all = await build('', 'chaoxing_test_terms_all');
      final allSnapshot = await all.refresh();
      expect(scannedCourses().sublist(6).length, 5);
      expect(allSnapshot.skippedCourseKeys, isEmpty);
    });

    test('★ 会话失效 → 只重换一次票再重试', () async {
      final adapter = _RouteAdapter([
        _Route(
          (url) => url.contains('getNoticeCount'),
          body: '{"status":true,"msg":false}',
          contentType: Headers.jsonContentType,
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/index?ticket='),
          body: fixture('chaoxing_gateway_page.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('login_auth/cas/jxufe/login'),
          body: '{"status":true}',
          contentType: Headers.jsonContentType,
          setCookie: ['UID=uid-value; Domain=.chaoxing.com'],
        ),
        _Route(
          (url) => url.startsWith('https://i.chaoxing.com?data='),
          body: '',
          status: 302,
          location: 'https://i.chaoxing.com/base?t=1',
        ),
        _Route(
          (url) => url.contains('i.chaoxing.com/base'),
          body: fixture('chaoxing_space_base.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        // 第一次拉课程被踢回登录页，重换票后正常。
        _Route(
          (url) => url.contains('visit/courses'),
          body: fixture('chaoxing_courses.html'),
          expireOnceOnFirstHit: true,
        ),
        _Route(
          (url) => url.contains('stucoursemiddle'),
          body: fixture('chaoxing_course_middle.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('work/getAllWork'),
          body: fixture('chaoxing_work_empty.html'),
          contentType: 'text/html; charset=utf-8',
        ),
        _Route(
          (url) => url.contains('notice/getNoticeList'),
          body: fixture('chaoxing_notices.json'),
          contentType: Headers.jsonContentType,
        ),
      ]);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
      );
      var ticketCalls = 0;
      final repo = ChaoxingRepository(
        auth: ChaoxingAuthRemoteDataSource(http),
        mooc: ChaoxingMoocRemoteDataSource(http),
        notice: ChaoxingNoticeRemoteDataSource(http),
        sign: ChaoxingSignRemoteDataSource(http),
        fetchTicket: (_) async {
          ticketCalls += 1;
          return Right(
            'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'
            '?ticket=ST-fake',
          );
        },
        store: ChaoxingStore(await Hive.openBox<String>('chaoxing_test_expire')),
        concurrency: 1,
      );

      final snapshot = await repo.refresh();
      expect(ticketCalls, 2, reason: '失效只重换一次');
      expect(snapshot.courses.length, 4);
    });

    test('换票失败 → 抛带原因的会话异常', () async {
      final http = ChaoxingHttpClient(
        Dio(BaseOptions(followRedirects: false, validateStatus: (_) => true))
          ..httpClientAdapter = _RouteAdapter(const []),
      );
      final repo = ChaoxingRepository(
        auth: ChaoxingAuthRemoteDataSource(http),
        mooc: ChaoxingMoocRemoteDataSource(http),
        notice: ChaoxingNoticeRemoteDataSource(http),
        sign: ChaoxingSignRemoteDataSource(http),
        fetchTicket: (_) async => Left(UnknownFailure('尚未授权，无法获取平台会话')),
        store: ChaoxingStore(await Hive.openBox<String>('chaoxing_test_noticket')),
      );
      await expectLater(
        repo.refresh(),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('统一认证换票失败'),
          ),
        ),
      );
    });

    /// 共用装配：同一条假链路，只有「第几轮开始变样」不同。
    ({ChaoxingRepository repo, _RouteAdapter adapter, ChaoxingStore store})
    buildRepo({
      required String box,
      required List<_Route> routes,
      required DateTime Function() now,
      int scanWindow = 20,
    }) {
      final adapter = _RouteAdapter(routes);
      final http = ChaoxingHttpClient(
        Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )..httpClientAdapter = adapter,
        minRequestInterval: Duration.zero,
      );
      final store = ChaoxingStore(Hive.box<String>(box));
      return (
        repo: ChaoxingRepository(
          auth: ChaoxingAuthRemoteDataSource(http),
          mooc: ChaoxingMoocRemoteDataSource(http),
          notice: ChaoxingNoticeRemoteDataSource(http),
          sign: ChaoxingSignRemoteDataSource(http),
          fetchTicket: (_) async => Right(
            'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index'
            '?ticket=ST-fake',
          ),
          store: store,
          concurrency: 1,
          scanWindow: scanWindow,
          now: now,
        ),
        adapter: adapter,
        store: store,
      );
    }

    /// 一条完整的假链路（课程 4 门 / 线性代数有作业 / 通知 4 条）。
    List<_Route> baseRoutes({
      _Route? linMiddle,
      _Route? linWorkList,
      _Route? noticeList,
    }) => [
      _Route(
        (url) => url.contains('login_auth/cas/jxufe/index?ticket='),
        body: fixture('chaoxing_gateway_page.html'),
      ),
      _Route(
        (url) => url.contains('login_auth/cas/jxufe/login'),
        body: '{"status":true}',
        contentType: Headers.jsonContentType,
        setCookie: ['UID=uid-value; Domain=.chaoxing.com'],
      ),
      _Route(
        (url) => url.startsWith('https://i.chaoxing.com?data='),
        body: '',
        status: 302,
        location: 'https://i.chaoxing.com/base?t=1',
      ),
      _Route(
        (url) => url.contains('i.chaoxing.com/base'),
        body: fixture('chaoxing_space_base.html'),
      ),
      _Route(
        (url) => url.contains('visit/courses'),
        body: fixture('chaoxing_courses.html'),
      ),
      linMiddle ??
          _Route(
            (url) =>
                url.contains('stucoursemiddle') && url.contains('courseid=100000002'),
            body: fixture('chaoxing_course_middle_lin.html'),
          ),
      _Route(
        (url) => url.contains('stucoursemiddle'),
        body: fixture('chaoxing_course_middle.html'),
      ),
      linWorkList ??
          _Route(
            (url) =>
                url.contains('work/getAllWork') && url.contains('courseId=100000002'),
            body: fixture('chaoxing_work_list.html'),
          ),
      _Route(
        (url) => url.contains('work/getAllWork'),
        body: fixture('chaoxing_work_empty.html'),
      ),
      noticeList ??
          _Route(
            (url) => url.contains('notice/getNoticeList'),
            body: fixture('chaoxing_notices.json'),
            contentType: Headers.jsonContentType,
          ),
    ];

    test('★ 风控截断 → 已扫到的照算、没扫到的沿用旧数据，界面上如实标注', () async {
      var clock = DateTime(2026, 9, 19, 22);
      await Hive.openBox<String>('chaoxing_test_challenge');
      final built = buildRepo(
        box: 'chaoxing_test_challenge',
        now: () => clock,
        routes: baseRoutes(
          // 线性代数的课程页：**第二轮**开始变 202 挑战页（第一轮正常，否则没数据可丢）
          linMiddle: _Route(
            (url) =>
                url.contains('stucoursemiddle') && url.contains('courseid=100000002'),
            body: fixture('chaoxing_course_middle_lin.html'),
            switchFromHit: 2,
            laterBody: fixture('chaoxing_challenge.html'),
            laterStatus: 202,
          ),
        ),
      );

      // 第一轮：一切正常 → 落盘 4 门课 / 3 条作业 / 4 条通知
      final first = await built.repo.refresh();
      expect(first.courses.length, 4);
      expect(first.works.length, 3);
      expect(first.throttled, isFalse);
      expect((await built.repo.cached())!.works.length, 3);

      // 第二轮：课程页被风控 → **不再整次作废**，而是保留已扫结果 + 旧数据兜底
      final second = await built.repo.refresh(previous: first);
      expect(second.throttled, isTrue, reason: '界面据此提示「学习通限流」');
      expect(
        second.failedCourseKeys,
        contains('100000002/200000002'),
        reason: '撞墙的那门课如实记失败',
      );
      expect(
        second.works.length,
        3,
        reason: '★ 用户的 bug：刷新后作业不许凭空消失（失败课沿用旧作业）',
      );
      expect(second.courses.length, 4, reason: '课程更不能没');

      // 缓存同样不丢数据（旧快照的作业被原样搬过来了，落盘是安全的）
      final cached = await built.repo.cached();
      expect(cached!.courses.length, 4);
      expect(cached.works.length, 3);
      expect(cached.notices.length, 4);
      expect(cached.throttled, isTrue);

      // 进入冷却，且冷却期内**一个请求都不发**（重打只会延长风控窗口）
      expect(built.repo.challengeCooldownLeft, isNotNull);
      final frozen = built.adapter.calls.length;
      await expectLater(
        built.repo.refresh(previous: second),
        throwsA(
          isA<ChaoxingChallengedException>().having(
            (e) => '$e',
            'message',
            contains('冷却期'),
          ),
        ),
      );
      expect(
        built.adapter.calls.length,
        frozen,
        reason: '冷却期内不得再发请求（实测风控窗口 ≥ 60 秒）',
      );

      // 手动 force 可以越过冷却（用户明确要求就让他试）——
      // ⚠ 越过后**不再抛错**：撞风控只是那一门课记失败、其余沿用旧数据（本轮设计如此），
      // 所以断言的是「真的发了请求 + 结果仍然不丢数据」。
      final forced = await built.repo.refresh(previous: second, force: true);
      expect(built.adapter.calls.length, greaterThan(frozen));
      expect(forced.works.length, 3, reason: '强制重试也不许把数据刷没');
      expect(forced.throttled, isTrue);
      expect(built.repo.challengeCooldownLeft, isNotNull, reason: '又撞一次 → 冷却重新计时');

      // 冷却到期后自动刷新恢复放行
      clock = clock.add(ChaoxingRepository.challengeCooldown + const Duration(seconds: 1));
      expect(built.repo.challengeCooldownLeft, isNull);
    });

    test('★ 分批轮转：每轮只扫窗口内的课，其余沿用旧数据并记 pending', () async {
      // 为什么必须轮转：实测风控的触发量是**累计请求数**（2 请求/秒匀速扫 35 门课，
      // 仍在第 31 门 ≈62 个请求处整段变成验证码页）→ 一次全扫 70 个请求必然撞墙。
      final clock = DateTime(2026, 9, 19, 22);
      await Hive.openBox<String>('chaoxing_test_rotate');
      final built = buildRepo(
        box: 'chaoxing_test_rotate',
        now: () => clock,
        // 4 门课，窗口 2 → 两轮覆盖一轮
        scanWindow: 2,
        routes: baseRoutes(),
      );

      // 第一轮：只扫课程 1-2（线性代数在里面）→ 拿到 3 条作业；课程 3-4 待补齐
      final first = await built.repo.refresh();
      expect(first.pendingCourseKeys.length, 2, reason: '窗口外的 2 门课记 pending');
      expect(first.failedCourseKeys, isEmpty, reason: 'pending 不是 failed');
      expect(first.works.length, 3);

      // 第二轮：从游标接着扫课程 3-4（这两门都没作业）→ 第一轮的作业**不能消失**
      final second = await built.repo.refresh(previous: first);
      expect(
        second.works.length,
        3,
        reason: '★ 本轮没扫到的课沿用旧作业，不是清空',
      );
      expect(second.pendingCourseKeys.length, 2, reason: '这轮轮到的是 1-2');

      // 第三轮：游标绕回课程 1-2 → 仍然 3 条（线性代数被重新扫到）
      final third = await built.repo.refresh(previous: second);
      expect(third.works.length, 3);
      expect(third.courses.length, 4);
    });

    test('★ 本轮扫过且确认「暂无内容」的课 → 采信空结果（可信空压过旧数据）', () async {
      final clock = DateTime(2026, 9, 19, 22);
      await Hive.openBox<String>('chaoxing_test_trusted_empty');
      final built = buildRepo(
        box: 'chaoxing_test_trusted_empty',
        now: () => clock,
        routes: baseRoutes(
          // 第二轮的线性代数作业页：明确写着「暂无内容」（老师删了 / 收回了作业）
          linWorkList: _Route(
            (url) =>
                url.contains('work/getAllWork') && url.contains('courseId=100000002'),
            body: fixture('chaoxing_work_list.html'),
            switchFromHit: 2,
            laterBody: fixture('chaoxing_work_empty.html'),
          ),
        ),
      );

      final first = await built.repo.refresh();
      expect(first.works.length, 3);

      final second = await built.repo.refresh(previous: first);
      expect(
        second.works,
        isEmpty,
        reason: '扫过 + 页面写「暂无内容」= 可信空，此时才允许丢掉旧作业',
      );
      expect(second.failedCourseKeys, isEmpty, reason: '这不是失败');
    });

    test('★ 通知取数失败 → 沿用旧通知（不是「没有通知」），且只降级可用性', () async {
      final clock = DateTime(2026, 9, 19, 22);
      await Hive.openBox<String>('chaoxing_test_notice_keep');
      final built = buildRepo(
        box: 'chaoxing_test_notice_keep',
        now: () => clock,
        routes: baseRoutes(
          // 第二轮起通知接口吐非 JSON（接口抖动）——作业扫描仍然成功
          noticeList: _Route(
            (url) => url.contains('notice/getNoticeList'),
            body: fixture('chaoxing_notices.json'),
            contentType: Headers.jsonContentType,
            switchFromHit: 2,
            laterBody: '<html>接口抖了</html>',
            laterContentType: 'text/html; charset=utf-8',
          ),
        ),
      );

      final first = await built.repo.refresh();
      expect(first.notices.length, 4);

      final second = await built.repo.refresh(previous: first);
      expect(second.notices.length, 4, reason: '取不到 ≠ 没有：旧通知必须留下');
      expect(second.noticesAvailable, isFalse, reason: '但可用性要如实降级');
      expect(second.works.length, 3, reason: '作业不受影响');
      expect((await built.repo.cached())!.notices.length, 4);
    });

    test('★ 单课页面结构变化（非风控）→ 逐课容错：旧作业保留 + 记失败 + 仍然落盘', () async {
      final clock = DateTime(2026, 9, 19, 22);
      await Hive.openBox<String>('chaoxing_test_pagefail');
      final built = buildRepo(
        box: 'chaoxing_test_pagefail',
        now: () => clock,
        routes: baseRoutes(
          // 第二轮起：线性代数的课程页变成「没有作业入口」的空白业务页
          linMiddle: _Route(
            (url) =>
                url.contains('stucoursemiddle') && url.contains('courseid=100000002'),
            body: fixture('chaoxing_course_middle_lin.html'),
            switchFromHit: 2,
            laterBody: '<html><body>空白</body></html>',
          ),
        ),
      );

      final first = await built.repo.refresh();
      expect(first.works.length, 3);

      final second = await built.repo.refresh(previous: first);
      expect(
        second.failedCourseKeys,
        contains('100000002/200000002'),
        reason: '如实记失败（概览卡会显示「N 门课扫描失败」）',
      );
      expect(second.works.length, 3, reason: '失败课的旧作业沿用，不是消失');
      expect((await built.repo.cached())!.works.length, 3, reason: '这种情形仍然可以落盘');
    });
  });

  group(
    '★ 控制器：单飞 + previous 兜底（用户 2026-09-20：「我明明有一项线性代数的作业，'
    '为什么提示没有作业」）',
    () {
      test('★ 并发 refresh 只跑一次全扫（两次全扫会双双撞风控、还会互相覆盖快照）', () async {
        final repo = _FakeRepository();
        final gate = Completer<void>();
        repo.gate = gate;
        final container = ProviderContainer(
          overrides: [chaoxingRepositoryProvider.overrideWith((ref) async => repo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(chaoxingControllerProvider.notifier);
        final first = controller.refresh();
        final second = controller.refresh();
        expect(identical(first, second), isTrue, reason: '第二次必须复用同一个 Future');
        gate.complete();
        await Future.wait([first, second]);
        expect(repo.refreshCalls, 1, reason: '一次全扫 ≈40 个请求，绝不允许两份并发');
      });

      test('★ 首帧刷新（build 还没读完缓存）也要把磁盘缓存当 previous', () async {
        final cached = ChaoxingSnapshot(
          courses: const [_linCourse],
          works: [_linWork],
          fetchedAt: DateTime(2026, 9, 19, 21),
        );
        // 让 `cached()` 挂起（**只是慢，不是返回 null**）→ 制造出「build 还在读缓存」
        // 这个真实瞬间；两个调用者谁先谁后都能拿到同一份缓存，断言因此是确定性的。
        final repo = _FakeRepository(cachedSnapshot: cached, holdCached: true);
        final container = ProviderContainer(
          overrides: [chaoxingRepositoryProvider.overrideWith((ref) async => repo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(chaoxingControllerProvider.notifier);
        // 不等 build 完成就刷新 —— 页面首帧的 post-frame 自动刷新就是这么触发的。
        final inflight = controller.refresh();
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          container.read(chaoxingControllerProvider).valueOrNull,
          isNull,
          reason: '此刻 build 还没读完缓存 → 内存里没有可用的 previous（这就是竞态现场）',
        );

        repo.releaseCached();
        await inflight;
        expect(repo.refreshCalls, 1);
        expect(
          repo.lastPrevious,
          isNotNull,
          reason: 'previous=null 就是「本轮没扫到的课连旧作业一起丢」的根因',
        );
        expect(repo.lastPrevious!.works.length, 1, reason: '缓存里那条作业必须带上');
      });

      test('★ 文案三档：未扫到 / 扫描失败 / 正常 —— 前两档绝不说成「无作业记录」', () {
        const key = '100000002/200000002';
        final pending = ChaoxingSnapshot(
          courses: const [_linCourse],
          pendingCourseKeys: const [key],
        );
        expect(pending.isCoursePending(key), isTrue);
        expect(pending.isCourseFailed(key), isFalse);
        expect(pending.unscannedCourseCount, 1);
        expect(chaoxingCourseScanNote(pending, key), contains('未扫到'));

        final failed = pending.copyWith(
          pendingCourseKeys: const [],
          failedCourseKeys: const [key],
        );
        expect(failed.isCoursePending(key), isFalse);
        expect(chaoxingCourseScanNote(failed, key), contains('扫描失败'));
        expect(failed.unscannedCourseCount, 1);

        // 两档的作业数都是「沿用上次」，界面必须靠这句话区分，不能只看条数。
        expect(
          chaoxingCourseScanNote(const ChaoxingSnapshot(), key),
          isEmpty,
          reason: '正常扫过（哪怕真的没作业）不挂任何备注',
        );
        expect(ChaoxingSnapshot.empty.unscannedCourseCount, 0);
      });
    },
  );
}

const _linCourse = ChaoxingCourse(
  courseId: '100000002',
  classId: '200000002',
  cpi: '900000001',
  name: '261学期 线性代数(工)',
);

final _linWork = ChaoxingWork(
  workId: '55739815',
  title: '9月20日24:00前提交作业',
  courseId: _linCourse.courseId,
  courseName: _linCourse.name,
  dueAt: DateTime(2026, 9, 20, 23, 59),
  status: ChaoxingWorkStatus.todo,
);

/// 假仓库：只实现控制器用到的那几个成员（`store` 被读到就是测试写错了）。
class _FakeRepository implements ChaoxingRepository {
  _FakeRepository({this.cachedSnapshot, this.holdCached = false});

  /// `cached()` 返回的「磁盘缓存」。
  final ChaoxingSnapshot? cachedSnapshot;

  /// true = `cached()` 一律挂起，直到 [releaseCached] —— 用来造出
  /// 「build 还没读完缓存，首帧刷新已经发出去了」这个真实竞态（**确定性**：
  /// 谁先调用都只是被延迟，不会被喂成 null）。
  final bool holdCached;

  /// 非空时 `refresh()` 会等它（造并发场景）。
  Completer<void>? gate;

  Completer<void>? _cachedGate;

  ChaoxingSnapshot? lastPrevious;
  int refreshCalls = 0;
  int cachedCalls = 0;

  /// 放行所有挂起的 `cached()`。
  void releaseCached() {
    final g = _cachedGate ??= Completer<void>();
    if (!g.isCompleted) g.complete();
  }

  @override
  Future<ChaoxingSnapshot?> cached() async {
    cachedCalls++;
    if (holdCached) {
      await (_cachedGate ??= Completer<void>()).future;
    }
    return cachedSnapshot;
  }

  @override
  Future<ChaoxingSnapshot> refresh({
    ChaoxingSnapshot? previous,
    void Function(ChaoxingProgress progress)? onProgress,
    bool force = false,
  }) async {
    refreshCalls++;
    lastPrevious = previous;
    await gate?.future;
    return const ChaoxingSnapshot();
  }

  @override
  Future<List<ChaoxingNotice>?> fetchNoticesOnly() async => null;

  /// 签到：控制器「点开才查状态」用的（1 请求/活动）。
  @override
  Future<ChaoxingSnapshot> refreshSignDetail(
    ChaoxingSnapshot current,
    ChaoxingSign sign,
  ) async {
    signDetailCalls++;
    return current.copyWith(
      signs: [
        for (final s in current.signs)
          if (s.key == sign.key)
            s.copyWith(status: ChaoxingSignStatus.signed, statusLoaded: true)
          else
            s,
      ],
    );
  }

  /// 签到：手动全量更新（清单 + 状态）。
  @override
  Future<ChaoxingSnapshot> refreshSignsFull(
    ChaoxingSnapshot current, {
    bool allCourses = false,
    void Function(ChaoxingProgress progress)? onProgress,
  }) async {
    signFullCalls++;
    signFullAllCourses = allCourses;
    return current;
  }

  int signDetailCalls = 0;
  int signFullCalls = 0;
  bool? signFullAllCourses;

  @override
  bool get hasSession => false;

  @override
  void invalidateSession() {}

  @override
  Duration? get challengeCooldownLeft => null;

  @override
  int get concurrency => 1;

  @override
  int get scanWindow => 1;

  @override
  String get currentTermCode => '261';

  @override
  ChaoxingStore get store => throw UnimplementedError('测试不碰缓存落盘');
}

/// 一条假路由。
class _Route {
  const _Route(
    this.match, {
    required this.body,
    this.status = 200,
    this.contentType = 'text/html; charset=utf-8',
    this.setCookie,
    this.location,
    this.expireOnceOnFirstHit = false,
    this.switchFromHit,
    this.laterBody,
    this.laterStatus,
    this.laterContentType,
  });

  /// URL 里包含它就命中。
  final bool Function(String url) match;

  final String body;
  final int status;
  final String contentType;
  final List<String>? setCookie;
  final String? location;

  /// true = **第一次**命中时回「被踢回登录页」的 302（会话失效重试用例）。
  final bool expireOnceOnFirstHit;

  /// 从**第 n 次**命中起改用 [laterBody] / [laterStatus] / [laterContentType]。
  ///
  /// 模拟「第一轮好好的、第二轮开始变样」——风控挑战页与接口抖动都是这么出现的，
  /// 也是「刷新有时会刷没」能复现的关键（第一轮必须有数据可丢）。
  final int? switchFromHit;
  final String? laterBody;
  final int? laterStatus;
  final String? laterContentType;
}

/// 记录请求并按 URL 分发的假适配器（仓库既有口径：每个测试文件内私有）。
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  final List<_Route> routes;
  final List<RequestOptions> calls = <RequestOptions>[];

  /// 已经「失效过一次」的路由下标（`expireOnceOnFirstHit` 用）。
  final Set<int> _expired = <int>{};

  /// 每条路由被命中过几次（`switchFromHit` 用）。
  final Map<int, int> _hits = <int, int>{};

  /// 某个 host 最近一次请求实际带上的 Cookie 头（断言 Cookie 归属用）。
  String cookieOf(String host) {
    for (final call in calls.reversed) {
      if (call.uri.host == host) {
        return call.headers['Cookie']?.toString() ?? '';
      }
    }
    return '';
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      if (!route.match(url)) continue;
      if (route.expireOnceOnFirstHit && _expired.add(i)) {
        return ResponseBody.fromString('', 302, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          'location': ['https://passport2.chaoxing.com/login?refer=x'],
        });
      }
      final hits = (_hits[i] = (_hits[i] ?? 0) + 1);
      final switchAt = route.switchFromHit;
      final later = switchAt != null && hits >= switchAt;
      final status = later ? (route.laterStatus ?? route.status) : route.status;
      final body = later ? (route.laterBody ?? route.body) : route.body;
      final location = route.location;
      final contentType = later
          ? (route.laterContentType ?? route.contentType)
          : route.contentType;
      return ResponseBody.fromString(
        status >= 300 && status < 400 ? '' : body,
        status,
        headers: {
          Headers.contentTypeHeader: [contentType],
          if (route.setCookie != null) 'set-cookie': route.setCookie!,
          if (location != null) 'location': [location],
        },
      );
    }
    return ResponseBody.fromString('not routed: $url', 404, headers: {
      Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}
