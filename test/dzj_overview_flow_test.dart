/// 数据中心首屏取数流程（会话预检 / 并发 / 会话失效语义 / 页面先上屏）· 守卫。
///
/// 2026-10-01 立。由来是一轮真机实测：dzj 的 SESSION 落在 Hive 里且
/// **不看 TTL**（`dzj_auth_local_datasource.dart` 的 `getSession` 命中即用，
/// `getUpdatedAt` 无人调用），实测那份会话已躺了 **472 小时**。后果链：
/// 首屏 19 并发 + 5 个身份文本**全部**回 `code=50002` 白打一轮，仓库才靠
/// 「全都空」的启发式猜出会话失效、换会话**整批重打** —— 冷连接实测
/// **6568ms**，而同一批紧接着再跑只要 **537ms**。期间界面只有一枚转圈，
/// 用户完全看不出在等什么。
///
/// 本文件钉住四件事（对应那轮改造的四个落点）：
/// 1. **预检**：会话已死时先换会话、再打那一批（不是打完 24 个才知道）；
/// 2. **并发**：身份文本 5 条 / 校内关系 5 维 / 助学金 2 条同时飞（不是串行链）；
/// 3. **语义**：`50002` → `DzjSessionExpiredException` 冒出去（不被 `_guard`
///    吞成 null），而普通业务失败仍然照旧吞成 null（单卡容错不许退化）；
/// 4. **先上屏**：概览还没回来时，只依赖自己 provider 的卡已经画出来了。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/data_center/data/data_center_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_crypto.dart';
import 'package:smarter_jxufe/features/data_center/data/dzj_auth_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';

/// 会话盐（Base64 的 `salt`）—— 测试里自己发的，不是任何真实凭证。
const String _salt = 'c2FsdA==';

const String _account = '2202500001';

/// 真机实测的会话失效回包（错误码与文案逐字照抄，见 `_isSessionInvalid`）。
const String _sessionDeadJson =
    '{"success":false,"errorCode":"50002",'
    '"errorMessage":"当前用户登录信息已失效，请重新登录"}';

const Map<String, List<String>> _jsonHeaders = {
  Headers.contentTypeHeader: ['application/json; charset=utf-8'],
};

// ---- 测试替身 ----

/// 脚本化 Dio 适配器：记账 + 量并发度，不打网络。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  /// 收到的请求（按到达顺序）。
  final List<RequestOptions> requests = [];

  /// 同时在飞的请求数（峰值）—— 并发的判据。
  int inFlight = 0;
  int maxInFlight = 0;

  Iterable<String> get paths => requests.map((r) => r.uri.path);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      return await respond(options);
    } finally {
      inFlight--;
    }
  }
}

/// 会话仓库替身：按脚本换会话，并记账换了几次。
///
/// 只实现 [DzjAuthRepository] 的三个公开方法 —— 真身要 Hive box + 统一认证，
/// 本文件验的是「仓库在什么时候决定换会话」，不是换取本身。
class _FakeAuthRepo implements DzjAuthRepository {
  _FakeAuthRepo({this.onRefresh});

  /// 换会话时的副作用（用来把"服务端会话已复活"这个状态翻过去）。
  final void Function()? onRefresh;

  int refreshCount = 0;
  int clearCount = 0;

  @override
  Future<DzjSession> getSession(String account, {bool forceRefresh = false}) async {
    return const DzjSession(session: 'SESSION-1', fixedSalt: _salt);
  }

  @override
  Future<DzjSession> refreshSession(String account) async {
    refreshCount++;
    onRefresh?.call();
    return const DzjSession(session: 'SESSION-2', fixedSalt: _salt);
  }

  @override
  Future<void> clearSession(String account) async {
    clearCount++;
  }
}

Dio _dio(HttpClientAdapter adapter) => Dio(
  BaseOptions(
    baseUrl: 'https://dzj.jxufe.edu.cn',
    validateStatus: (status) => true,
  ),
)..httpClientAdapter = adapter;

/// 请求体明文 —— [_ScriptedAdapter] 靠它认出「这是哪个组件 / 哪个指标位」。
///
/// `_postComponent` 把 body 加密成 `ts:nonce:base64`；这里用会话盐解回来
/// （[DzjCrypto] 是对称的），于是断言能写到「哪个 componentId、哪个 index」这一层。
Map<String, dynamic> _bodyOf(RequestOptions o, {String salt = _salt}) {
  final raw = o.data;
  if (raw is! String) return const <String, dynamic>{};
  final decoded = jsonDecode(DzjCrypto.decrypt(raw, salt));
  return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
}

ResponseBody _ok([Object? data]) => ResponseBody.fromString(
  jsonEncode({'success': true, 'errorCode': '10000', 'data': data}),
  200,
  headers: _jsonHeaders,
);

ResponseBody _dead() =>
    ResponseBody.fromString(_sessionDeadJson, 200, headers: _jsonHeaders);

/// 业务失败（**不是**会话失效）：真机实测的「分数数据量不能大于500」。
ResponseBody _businessError() => ResponseBody.fromString(
  jsonEncode({
    'success': false,
    'errorCode': '50000',
    'errorMessage': '分数数据量不能大于500',
  }),
  200,
  headers: _jsonHeaders,
);

/// 一个成功回包的"内容"：按 path / componentId 给形状，其余给空表。
///
/// 空表**不算成功**（大多数卡片会解析成 null），这是有意的：只想让断言关心的
/// 那几个字段有值，别的走"这一张卡没取到"的正常分支。
Object? _payloadFor(RequestOptions o) {
  final body = _bodyOf(o);
  switch (o.uri.path) {
    case '/api/page/manageTreeByVersion':
      return {'tree': <Object?>[]};
    case '/api/app/component/tsa/getWeekClass':
      return {'weekClass': <Object?>[]};
    case '/api/app/component/tsa/getTodayZc':
      return {'weeks': <Object?>[]};
  }
  switch (body['componentId']) {
    case 'u:97019a44a735':
      return {'username': '同学甲'};
    case 'u:6e8a5f94005d':
      return {'userid': _account};
    case 'u:a56e2d07cc33':
      return {'ssdw': '示例学院'};
    case 'u:ee1581a17fe0':
      return {'bzrxm': '教师甲'};
    case 'u:3acfa51c6b45':
      return {'bzrsjh': '13800000001'};
    case 'u:9206d2e048b4':
      return {'pm': 88.5};
    case 'u:fcd2d17a9131':
      return {'sj': 42};
  }
  return const <String, Object?>{};
}

/// 让 `n` 个请求同时在飞才算通过：第 n 个进入时放闸，之前一律挂住。
///
/// 串行实现会在每一跳各等一次 [timeout]（并让 `maxInFlight` 停在 1 附近）——
/// 断言照样红，只是慢几百毫秒。
Future<ResponseBody> _gateAt(
  _ScriptedAdapter adapter,
  Completer<void> gate,
  int n,
  ResponseBody Function() body, {
  Duration timeout = const Duration(milliseconds: 500),
}) async {
  if (adapter.inFlight >= n) gate.complete();
  await gate.future.timeout(timeout, onTimeout: () {});
  return body();
}

void main() {
  group('① 会话预检（首屏不再白打一整轮）', () {
    test('会话已死：先换会话、再打那一批 —— 共 1 + 19 + 5 个请求，不重打', () async {
      var dead = true;
      final adapter = _ScriptedAdapter(
        (o) async => dead ? _dead() : _ok(_payloadFor(o)),
      );
      final auth = _FakeAuthRepo(onRefresh: () => dead = false);
      final repo = DataCenterRepository(
        authRepository: auth,
        remoteDataSource: DzjApiRemoteDataSource(_dio(adapter)),
      );

      final overview = await repo.fetchOverview(_account);

      expect(auth.refreshCount, 1, reason: '死会话只换一次');
      expect(
        adapter.requests.first.uri.path,
        '/api/page/manageTreeByVersion',
        reason: '第一个请求必须是那枚轻量预检',
      );
      expect(
        adapter.requests.length,
        25,
        reason: '1 预检 + 19 概览 + 5 身份文本；从前是 24 白打 + 换会话 + 24 重打',
      );
      expect(overview.username, '同学甲');
      expect(overview.userid, _account);
      expect(overview.weightedScore, 88.5);
    });

    test('会话活着：不多打一个请求（预检就是那一个）', () async {
      final adapter = _ScriptedAdapter((o) async => _ok(_payloadFor(o)));
      final auth = _FakeAuthRepo();
      final repo = DataCenterRepository(
        authRepository: auth,
        remoteDataSource: DzjApiRemoteDataSource(_dio(adapter)),
      );

      final overview = await repo.fetchOverview(_account);

      expect(auth.refreshCount, 0, reason: '活着就不该换会话');
      expect(adapter.requests.length, 25);
      expect(adapter.requests.first.uri.path, '/api/page/manageTreeByVersion');
      expect(overview.username, '同学甲');
    });

    test('预检漏网（预检过后服务端才判过期）→ 换会话重来一次，且只重来一次', () async {
      var revived = false;
      final adapter = _ScriptedAdapter((o) async {
        if (o.uri.path == '/api/page/manageTreeByVersion') {
          return _ok(_payloadFor(o)); // 预检放行
        }
        return revived ? _ok(_payloadFor(o)) : _dead();
      });
      final auth = _FakeAuthRepo(onRefresh: () => revived = true);
      final repo = DataCenterRepository(
        authRepository: auth,
        remoteDataSource: DzjApiRemoteDataSource(_dio(adapter)),
      );

      final overview = await repo.fetchOverview(_account);

      expect(auth.refreshCount, 1);
      // 1 预检 + 19（全 50002，Future.wait 立刻抛，身份文本没发）+ 19 + 5
      expect(adapter.requests.length, 44);
      expect(overview.username, '同学甲');
    });

    test('两次都失效 → 抛会话失效（界面据此给「重新登录」，不是干转）', () async {
      final adapter = _ScriptedAdapter((o) async => _dead());
      final auth = _FakeAuthRepo();
      final repo = DataCenterRepository(
        authRepository: auth,
        remoteDataSource: DzjApiRemoteDataSource(_dio(adapter)),
      );

      await expectLater(
        repo.fetchOverview(_account),
        throwsA(isA<DzjSessionExpiredException>()),
      );
      expect(auth.refreshCount, 2, reason: '预检后一次 + 批次失败后一次，到此为止');
      expect(adapter.requests.length, 39, reason: '1 预检 + 19 + 19；不许无限重试');
    });

    test('probeSession：网络异常不算会话失效（回 true，免得白换一次会话）', () async {
      final adapter = _ScriptedAdapter(
        (o) async => throw DioException(
          requestOptions: o,
          message: '网络抖动',
          type: DioExceptionType.connectionError,
        ),
      );
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      expect(
        await ds.probeSession(
          const DzjSession(session: 'SESSION-1', fixedSalt: _salt),
        ),
        isTrue,
      );
    });
  });

  group('② 串行链改并发', () {
    const session = DzjSession(session: 'SESSION-1', fixedSalt: _salt);

    test('身份文本：5 条同时飞（从前是 5 次串行 await）', () async {
      final gate = Completer<void>();
      late _ScriptedAdapter adapter;
      adapter = _ScriptedAdapter(
        (o) => _gateAt(adapter, gate, 5, () => _ok(_payloadFor(o))),
      );
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      final identity = await ds.fetchIdentityTexts(session);

      expect(adapter.maxInFlight, 5);
      expect(adapter.requests.length, 5);
      expect(identity['username'], '同学甲');
      expect(identity['userid'], _account);
      expect(identity, hasLength(5));
    });

    test('校内关系五维：5 条同时飞，index 0..4 各一路', () async {
      final gate = Completer<void>();
      late _ScriptedAdapter adapter;
      adapter = _ScriptedAdapter(
        (o) => _gateAt(adapter, gate, 5, () => _ok({'sj': 7})),
      );
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      final counts = await ds.fetchPeerCounts(session);

      expect(adapter.maxInFlight, 5);
      expect(adapter.requests.length, 5);
      expect(
        {
          for (final r in adapter.requests)
            _bodyOf(r)['index'],
        },
        {0, 1, 2, 3, 4},
        reason: '五维靠 index 区分，并发不许把指标位搞乱',
      );
      for (final r in adapter.requests) {
        expect(_bodyOf(r)['componentId'], 'u:fcd2d17a9131');
      }
      expect(counts, {
        'grade': 7,
        'class': 7,
        'major': 7,
        'dorm': 7,
        'college': 7,
      });
    });

    test('助学金 / 勤工助学：2 条同时飞（从前是两次串行 await）', () async {
      final gate = Completer<void>();
      late _ScriptedAdapter adapter;
      adapter = _ScriptedAdapter(
        (o) => _gateAt(adapter, gate, 2, () => _ok(_payloadFor(o))),
      );
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      await ds.fetchAidRecords(session);

      expect(adapter.maxInFlight, 2);
      expect(adapter.requests.length, 2);
    });
  });

  group('③ 会话失效的语义（不再静默吞成 null）', () {
    const session = DzjSession(session: 'SESSION-1', fixedSalt: _salt);

    test('50002 → DzjSessionExpiredException 冒出去', () async {
      final adapter = _ScriptedAdapter((o) async => _dead());
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      await expectLater(
        ds.fetchWeightedScore(session),
        throwsA(isA<DzjSessionExpiredException>()),
      );
      await expectLater(
        ds.fetchPeerCounts(session),
        throwsA(isA<DzjSessionExpiredException>()),
      );
    });

    test('业务失败（50000）仍然回 null —— 单卡容错不许退化', () async {
      final adapter = _ScriptedAdapter((o) async => _businessError());
      final ds = DzjApiRemoteDataSource(_dio(adapter));

      expect(await ds.fetchWeightedScore(session), isNull);
      expect(await ds.fetchPeerCounts(session), isNull);
    });

    test('校内关系：单维失败记 -1（"这格没有数据"），全失败才回 null', () async {
      final partial = _ScriptedAdapter((o) async {
        final index = _bodyOf(o)['index'];
        return index == 4 ? _businessError() : _ok({'sj': 7});
      });
      final counts = await DzjApiRemoteDataSource(
        _dio(partial),
      ).fetchPeerCounts(session);
      expect(counts, {
        'grade': 7,
        'class': 7,
        'major': 7,
        'dorm': 7,
        'college': -1,
      });

      final allFail = _ScriptedAdapter((o) async => _businessError());
      expect(
        await DzjApiRemoteDataSource(_dio(allFail)).fetchPeerCounts(session),
        isNull,
        reason: '五维全失败 = 整卡失败，仓库据此换会话重来',
      );
    });
  });

  group('④ 页面先上屏（整页不再被一个 Future 挡住）', () {
    /// 概览**永不完成**：模拟"首屏那一批还在飞"的那 6.5 秒。
    final neverOverview = Completer<DataCenterOverview>();

    Future<void> pump(WidgetTester tester, {required Object? overviewError}) async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAccountProvider.overrideWith((ref) => _account),
            dataCenterOverviewProvider.overrideWith((ref) async {
              if (overviewError != null) throw overviewError;
              return await neverOverview.future;
            }),
            dzjPageTreeProvider.overrideWith(
              (ref) async => const DzjPageTree(
                roots: [],
                subPages: [DzjPageNode(pageKey: 'p1', title: '指导教师')],
              ),
            ),
            dzjPeerCountsProvider.overrideWith((ref) async => const <String, int>{}),
            dzjRelatedCountsProvider.overrideWith(
              (ref) async => const <String, int>{},
            ),
            dzjExtraProvider.overrideWith((ref) async => DzjExtraInfo.empty),
            dzjGradeCollegeCountProvider.overrideWith((ref) async => 0),
          ],
          child: const MaterialApp(home: DataCenterScreen()),
        ),
      );
      // ⚠ 不能用 pumpAndSettle：骨架里有转圈（无限动画），settle 不下来。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('概览还在飞：子页面清单卡已经画出来，概览那几张给骨架', (tester) async {
      await pump(tester, overviewError: null);

      // 只依赖自己 provider 的卡：立刻可见（从前它要等概览那批回来才开始发请求）
      expect(find.text('指导教师'), findsOneWidget);
      expect(find.text('共 1 个子页面'), findsOneWidget);
      // 等概览的卡：骨架（标题在、值未到），不是空白、也不是假 0
      expect(find.text('学籍概要'), findsOneWidget);
      expect(find.text('正在读取学籍 / 学业 / 消费 / 图书…'), findsOneWidget);
      expect(find.text('学业情况'), findsOneWidget);
      expect(find.text('0'), findsNothing, reason: '骨架不许拿默认 0 冒充数据');
    });

    testWidgets('概览失败：顶部一张错误卡 + 独立卡照常；会话失效给「重新登录」', (tester) async {
      await pump(tester, overviewError: DzjSessionExpiredException());

      expect(find.text('登录已过期'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.byKey(const Key('dzjOverviewRetry')), findsOneWidget);
      // 会话死了，独立卡也还画着自己的内容（不整页白屏）
      expect(find.text('指导教师'), findsOneWidget);
    });

    testWidgets('概览失败但不是会话问题：给「重试」而不是「重新登录」', (tester) async {
      await pump(tester, overviewError: const _PlainFailure());

      expect(find.text('数据中心加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('重新登录'), findsNothing);
    });
  });
  group('⑤ 源码守卫：别退回旧写法', () {
    /// 读源码（与 `core_conventions_test.dart` 同一口径：cwd = 包根）。
    String sourceOf(String path) => File(path).readAsStringSync();

    /// 去掉注释行再断言 —— 守卫别被"自己文档里的反面示例"绊倒
    /// （`core_conventions_test.dart` 的 `_codeHits` 就是干这个的；
    /// 本页注释里正写着「从前这里是 `overviewAsync.when(…`」）。
    String codeOf(String src) => src
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    /// `lib/features/data_center/presentation/` 下**全部** dart 的并集（含 `widgets/`）。
    ///
    /// ⚠ 2026-10-08 拆分后必须这样读：屏幕文件 1389 行 → 122 行，骨架 / 错误卡等
    /// 搬到了 `widgets/data_center_common.dart`（`_skeletonCard` → `dcSkeletonCard`）。
    /// 只钉单个文件的话，每次拆分都会把这条守卫打红，而它要守的是
    /// 「整页不被一个 Future 挡住」这个**行为**，与件放在哪个文件无关。
    String dataCenterFamilySource() {
      final files = Directory('lib/features/data_center/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return files.map((f) => f.readAsStringSync()).join('\n');
    }

    test('数据中心页不许再拿 `overviewAsync.when(` 挡住整页', () {
      final src = codeOf(dataCenterFamilySource());
      expect(
        src.contains('overviewAsync.when('),
        isFalse,
        reason: '那就是"整页被一个 Future 挡住"的原样写法：'
            '子页面清单 / 补充模块 / 校内关系 / 相关人员都要等概览那批回来才开始取数',
      );
      expect(src.contains('dcSkeletonCard('), isTrue, reason: '概览没到要给骨架');
      expect(
        src.contains('AppLoadingState('),
        isTrue,
        reason: '加载态走三态组件（design/app_states.dart），别自己拼 Center + 转圈',
      );
    });

    test('数据中心：卡片标题行只许有一份实现（`dcCardHeader`）', () {
      final files = Directory('lib/features/data_center/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      var inside = 0;
      var outside = 0;
      final signature = RegExp(
        r'TextStyle\(\s*fontSize: 14,\s*fontWeight: FontWeight\.bold\s*\)',
      );
      for (final f in files) {
        final n = signature.allMatches(codeOf(f.readAsStringSync())).length;
        if (f.path.endsWith('data_center_common.dart')) {
          inside += n;
        } else {
          outside += n;
        }
      }
      expect(inside, 1, reason: '`dcCardHeader` 是卡片标题行（图标 18 + 14 w700）的唯一实现');
      expect(
        outside,
        0,
        reason: '用户 2026-10-09：「所有的卡片统一样式」—— 卡里别自己拼标题行，走 dcCardHeader',
      );
    });

    test('成绩页的分母只许看 `dzjPeerCountsProvider`（不许 watch 整个概览）', () {
      final src = codeOf(
        sourceOf('lib/features/ims/grades/presentation/grades_screen.dart'),
      );
      expect(src.contains('dzjPeerCountsProvider'), isTrue);
      expect(
        src.contains('dataCenterOverviewProvider'),
        isFalse,
        reason: '打开成绩页会连带打数据中心首屏那 19 个请求，只为两个分母',
      );
    });

    test('首屏批次 / 换会话：预检在前、串行链不许复活', () {
      final repo = sourceOf(
        'lib/features/data_center/data/data_center_repository.dart',
      );
      expect(repo.contains('probeSession('), isTrue, reason: '死会话要先探后打');
      expect(
        repo.contains('api.fetchPeerCounts('),
        isFalse,
        reason: '校内关系五维已拆去 dzjPeerCountsProvider，别塞回首屏',
      );

      // ⚠ 数据源已拆成 4 个文件（2026-10-08 第二阶段：`dzj_api_support` + cards/peers/pages
      //    三个 extension）→ 读**整族并集**，与上面 presentation 那条同一手法；
      //    只钉 `dzj_api_remote_datasource.dart` 的话，每次拆分都会把这条守卫打红。
      final ds = Directory('lib/features/data_center/data/datasource')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final dsSource = ds.map((f) => f.readAsStringSync()).join('\n');
      // 三处串行链（身份文本 5 / 五维 5 / 助学金 2）都必须是 Future.wait
      expect(
        'for (final entry in fields.entries)'.allMatches(dsSource),
        isEmpty,
        reason: '身份文本别退回逐条 await',
      );
      expect(dsSource.contains('_peerCountOf('), isTrue);
    });
  });
}

/// 非会话类失败（用来验错误卡的分支）。
class _PlainFailure implements Exception {
  const _PlainFailure();

  @override
  String toString() => '示例失败';
}
