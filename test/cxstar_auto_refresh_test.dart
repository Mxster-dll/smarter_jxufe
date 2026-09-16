/// 畅想之星「数据自动刷新」守卫（用户 2026-09-14 反馈）。
///
/// 原始反馈（verbatim）：「我发现不论是阅读界面右下角的时长还是总览卡片的时长，
/// 都无法自动刷新，前者必须重进阅读才刷新，后者必须点击重新获取令牌，然后才刷新
/// 数据，我希望不论是进入此页面，还是从别的页面点击返回到此页面，卡片里的数据都要
/// 刷新，然后阅读页的时长，则要每分钟更新1次」。
///
/// 三条守卫：
/// 1. `CxstarScreen` 在**首次进入 / 再次进入（有缓存）/ 从子页面返回 / 回前台**时
///    都会重取统计，且首次进入**不会**重复请求（`invalidateIfLoaded` 的「首次加载中跳过」）。
/// 2. **数据更新最小间隔 1 分钟**（用户 2026-09-14 追加：「数据更新设置一个最小间隔
///    （1min)」，并明确**仅限畅想之星**）：窗口起点 = 上次真的取到新数据的时刻，
///    窗口内上述**自动**刷新整组跳过；**手动下拉 / 会话变更 / 错误卡重试 / 结算补刷**
///    不受限制（见 `lib/features/cxstar/data/providers/cxstar_refresh_gate_provider.dart`）。
/// 3. `CxstarReaderScreen` 底部「今日已计 X 分」**每次心跳（60 秒）都刷新一次**
///    （此前每 5 次心跳才刷一次），并带「更新于 HH:mm」。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_reader_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_reader_providers.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_refresh_gate_provider.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_book_report.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_reader_screen.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_screen.dart';

/// 假业务数据源：只统计「页面真正取了几次数」。
class _CountingRemoteDataSource extends CxstarRemoteDataSource {
  _CountingRemoteDataSource() : super(Dio());

  /// 统计接口被调用的次数 = 统计卡的取数次数。
  int summaryCalls = 0;

  /// 「账号信息」调用次数 ≈ provider 被重算的次数（每次重算都会先取账号）。
  int userCalls = 0;

  int todayMinutes = 10;

  @override
  Future<String> ipLogin() async => 'fake-token';

  @override
  Future<CxstarUser> fetchUser(String token) async {
    userCalls++;
    return const CxstarUser(
      userId: 'u',
      userName: '2000000000',
      realName: '某同学',
      schoolName: '江西财经大学',
      schoolId: 'pinst-x',
    );
  }

  @override
  Future<CxstarReadSummary> fetchSummary(String token) async {
    summaryCalls++;
    return CxstarReadSummary(
      readCount: 3,
      finishCount: 1,
      readMinutes: 100 + todayMinutes,
      todayReadMinutes: todayMinutes,
      level: 1,
    );
  }

  @override
  Future<List<CxstarReadRecord>> fetchRecords(
    String token, {
    int page = 1,
  }) async => const [
    CxstarReadRecord(
      id: 'r1',
      bookId: 'book-1',
      title: '测试书',
      author: '某作者',
      readingTime: '2026/9/14 21:00:00',
    ),
  ];

  /// 逐书报告取数次数（记录行每次都只该取一次）。
  int reportCalls = 0;

  /// 报告形态开关：true = 已读完（带完成时间），false = 未读完。
  bool bookFinished = true;

  @override
  Future<CxstarBookReport?> fetchBookReport(String token, String bookId) async {
    reportCalls++;
    return CxstarBookReport(
      bookId: bookId,
      title: '测试书',
      startReadTime: '2026年09月14日',
      endReadTime: '2026年09月15日',
      finishReadTime: bookFinished ? '2026年09月09日' : '',
      readMinutes: 53,
      readDays: 2,
      readNo: 14,
      longestMinutes: 52,
      longestDate: '2026年09月14日',
      isFinish: bookFinished,
    );
  }
}

/// 宿主页：模拟 `jh_read_screen.dart` —— 畅想之星页是被 **push 上来**的（不是 home）。
///
/// 「从阅读器返回是否刷新」的 bug 只在真实结构里出现（home 直挂时守卫是通过的），
/// 所以这里必须复刻「本页是子路由」这一点。
class _HostPage extends StatelessWidget {
  const _HostPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const CxstarScreen())),
        child: const Text('打开畅想之星'),
      ),
    ),
  );
}

/// 最小宿主：只挂 [PageAutoRefresher]，单独守卫「从子页面返回 → `didPopNext`」这条通用机制。
///
/// 畅想之星页改成确定性 `await push` 后自己不再订阅路由，所以这条机制必须单独测。
class _RefresherHost extends StatefulWidget {
  const _RefresherHost({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  State<_RefresherHost> createState() => _RefresherHostState();
}

class _RefresherHostState extends State<_RefresherHost> {
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: widget.onRefresh,
  );

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoRefresh.subscribeRoute(context);
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('主页')));
}

/// 假阅读数据源：不取正文（避免在单测里加载 pdfium）。
class _FakeReaderDataSource extends CxstarReaderRemoteDataSource {
  _FakeReaderDataSource() : super(Dio());

  @override
  Future<CxstarReadSession> fetchSession({
    required String token,
    required String bookId,
    required String pinst,
    int page = 1,
  }) async => const CxstarReadSession(
    title: '测试书',
    page: 1,
    totalPage: 5,
    trialPage: 1,
    logId: 'log-1',
    watermark: '',
    isbuy: true,
  );

  @override
  Future<Uint8List> fetchPagePdf({
    required String token,
    required String bookId,
    required String pinst,
    required int pageNo,
  }) async => throw const CxstarApiException('单测不取正文');

  @override
  Future<int?> fetchProgress({
    required String token,
    required String bookId,
  }) async => 1;

  @override
  Future<void> postProgress({
    required String token,
    required String bookId,
    required int page,
    String logId = '',
    int paragraph = 0,
    int charIndex = 0,
    int percent = 0,
  }) async {}
}

/// 可控时钟：1 分钟节流窗口在 widget 测试里推不动（`DateTime.now()` 是真实时间）。
class _FakeClock {
  DateTime now = DateTime(2026, 9, 14, 21, 0);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('畅想之星总览页：进入 / 返回 / 回前台自动刷新', () {
    late _CountingRemoteDataSource remote;
    late GlobalKey<NavigatorState> navKey;
    late _FakeClock clock;
    late CxstarRefreshGate gate;

    Widget app(Widget home) => ProviderScope(
      overrides: [
        // 不配账号、不配手工令牌 → 走 IP 免密兜底，省掉 Hive 与 CAS 依赖。
        currentAccountProvider.overrideWith((ref) => ''),
        cxstarPersonalTokenProvider.overrideWith((ref) async => null),
        cxstarRemoteDataSourceProvider.overrideWithValue(remote),
        // ⚠ 闸门实例必须在 app() 之外创建：ProviderScope 重建时若换成新实例，
        // 节流窗口会被清空，测的就不是真实行为了。
        cxstarRefreshGateProvider.overrideWithValue(gate),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [appRouteObserver],
        home: home,
      ),
    );

    setUp(() {
      remote = _CountingRemoteDataSource();
      navKey = GlobalKey<NavigatorState>();
      clock = _FakeClock();
      gate = CxstarRefreshGate(clock: clock.call);
    });

    testWidgets('首次进入只取一次数（不重复请求）', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(remote.userCalls, 1, reason: '首次进入 build 已发起请求，不该再发一次');
      expect(find.byKey(const Key('cxstar_read_count')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('再次进入：1 分钟窗口内不重复取数，超过窗口必须重取', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1);

      // 卸载页面再进入：ProviderScope 容器保留 → provider 命中缓存。
      // 用户 2026-09-14：「数据更新设置一个最小间隔（1min)」→ 窗口内不再重复请求。
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(remote.userCalls, 1, reason: '距上次更新不足 1 分钟，不该再取一次');

      // 过了最小间隔 → 必须重取（不能一直吃缓存）。
      clock.advance(const Duration(minutes: 1, seconds: 1));
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(remote.userCalls, 2, reason: '超过 1 分钟必须刷新，不能用上次缓存');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('从子页面返回：窗口内不重复取数，结算补刷照常取到新值', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1);

      // 点 AppBar 的书架图标 —— 这是本页自己的子页面通路（`_openChild` + await push）。
      await tester.tap(find.byTooltip('书架 · 找书'));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1, reason: '进子页不该触发刷新');

      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('cxstar_read_count')), findsOneWidget);
      expect(remote.userCalls, 1, reason: '距上次更新不足 1 分钟：返回瞬间那次被窗口挡下');

      // 但结算补刷不受窗口限制 → 10 秒后照样取到新值（用户「返回后要刷新」的要求不丢）。
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(remote.userCalls, 2, reason: '结算补刷（force）必须放行');

      // 走完剩下的补刷时刻表，避免测试结束时留下未完成的定时器。
      await tester.pump(const Duration(seconds: 250));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('手动下拉刷新不受 1 分钟窗口限制', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1);

      // 直接调 RefreshIndicator 的 onRefresh（手势下拉在测试里易抖动，这里测的是口径）。
      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator).first,
      );
      await indicator.onRefresh();
      await tester.pumpAndSettle();

      expect(remote.userCalls, 2, reason: '用户主动下拉 = 显式刷新，必须立刻取数');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('PageAutoRefresher：didPopNext 通用机制守卫', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [appRouteObserver],
          home: _RefresherHost(onRefresh: () => count++),
        ),
      );
      await tester.pumpAndSettle();
      expect(count, 1, reason: '首帧后刷新一次');

      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('子页'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(count, 1, reason: '进子页不刷新');

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(count, 2, reason: '返回必须触发 RouteAware.didPopNext');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('App 回到前台：窗口内不重复取数，超过窗口才重取', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(remote.userCalls, 1, reason: '切后台不刷新');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1, reason: '距上次更新不足 1 分钟：窗口内不重复取数');

      clock.advance(const Duration(minutes: 1, seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.userCalls, 2, reason: '超过 1 分钟回前台必须自动刷新');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('畅想之星页：不显示账号卡片（用户 2026-09-14 裁定）', () {
    late _CountingRemoteDataSource remote;
    late GlobalKey<NavigatorState> navKey;

    Widget app(Widget home) => ProviderScope(
      overrides: [
        currentAccountProvider.overrideWith((ref) => ''),
        cxstarPersonalTokenProvider.overrideWith((ref) async => null),
        cxstarRemoteDataSourceProvider.overrideWithValue(remote),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [appRouteObserver],
        home: home,
      ),
    );

    setUp(() {
      remote = _CountingRemoteDataSource();
      navKey = GlobalKey<NavigatorState>();
    });

    testWidgets('页面上没有账号卡片，只留一行公用账号提醒', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('使用统一身份认证登录'),
        findsNothing,
        reason: '数据来源卡（账号 + 三个按钮）已整体撤出页面',
      );
      expect(find.text('手工令牌'), findsNothing);
      expect(
        find.textContaining('校园网公用账号'),
        findsOneWidget,
        reason: '落到全校汇总口径时必须提示，不能静默当成个人进度',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('「阅读记录」下方不再有操作提示文字（用户 2026-09-14 裁定）', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('点书名即可'),
        findsNothing,
        reason: '用户要求删掉「点书名即可在 App 内在线阅读…」这句提示',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('区块顺序：书架在阅读记录**上方**（用户 2026-09-14 要求）', (tester) async {
      // 放大视口，保证两段标题都在同一次布局里（ListView 只构建可见范围）。
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      final shelf = tester.getTopLeft(find.text('找书 · 书架')).dy;
      final records = tester.getTopLeft(find.text('阅读记录')).dy;
      expect(shelf, lessThan(records), reason: '书架卡要在阅读记录上方');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('账号卡片内容收进右上角「阅读会话」弹窗', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('阅读会话'));
      await tester.pumpAndSettle();

      expect(find.text('阅读会话'), findsOneWidget);
      expect(find.text('使用统一身份认证登录'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('使用统一身份认证登录'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('阅读记录：逐书时长与完成时间（用户 2026-09-15 提问）', () {
    late _CountingRemoteDataSource remote;

    Widget app(Widget home) => ProviderScope(
      overrides: [
        currentAccountProvider.overrideWith((ref) => ''),
        cxstarPersonalTokenProvider.overrideWith((ref) async => null),
        cxstarRemoteDataSourceProvider.overrideWithValue(remote),
        // 逐书报告与阅读器同用个人会话（公用账号是全校聚合，不给逐书口径）。
        cxstarReaderContextProvider.overrideWith(
          (ref) async => const CxstarReaderContext(token: 't', pinst: 'pinst-x'),
        ),
      ],
      child: MaterialApp(navigatorObservers: [appRouteObserver], home: home),
    );

    setUp(() {
      remote = _CountingRemoteDataSource();
    });

    testWidgets('记录行直接显示累计时长 + 阅读天数/次数 + 完成时间', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      expect(remote.reportCalls, 1, reason: '每行只该取一次逐书报告');
      final line = find.textContaining('累计 53 分');
      expect(line, findsOneWidget, reason: '逐书时长要直接显示在阅读记录里');
      final text = tester.widget<Text>(line).data ?? '';
      expect(text, contains('阅读 2 天'));
      expect(text, contains('14 次'));
      expect(text, contains('完成于 2026年09月09日'), reason: '读完的书必须给出完成时间');
      expect(find.text('已读完'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('未读完的书显示「未读完」，不冒充已读完', (tester) async {
      remote.bookFinished = false;
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      final text =
          tester.widget<Text>(find.textContaining('累计 53 分')).data ?? '';
      expect(text, contains('未读完'));
      expect(text, isNot(contains('完成于')));
      expect(find.text('阅读中'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('点「阅读报告」弹窗给出逐书全量统计（含分钟精度说明）', (tester) async {
      await tester.pumpWidget(app(const CxstarScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('阅读报告'));
      await tester.pumpAndSettle();

      expect(find.text('累计阅读'), findsOneWidget);
      expect(find.text('53 分'), findsOneWidget);
      expect(find.text('2 天'), findsOneWidget);
      expect(find.text('14 次'), findsOneWidget);
      expect(find.text('2026年09月09日'), findsOneWidget);
      expect(find.textContaining('精度为分钟'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('阅读器底部时长：每分钟随心跳刷新', () {
    late _CountingRemoteDataSource remote;
    late _FakeReaderDataSource reader;

    setUp(() {
      remote = _CountingRemoteDataSource();
      reader = _FakeReaderDataSource();
    });

    Future<void> pumpReader(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cxstarReaderContextProvider.overrideWith(
              (ref) async => const CxstarReaderContext(token: 't', pinst: 'p'),
            ),
            cxstarReaderDataSourceProvider.overrideWithValue(reader),
            cxstarRemoteDataSourceProvider.overrideWithValue(remote),
          ],
          child: const MaterialApp(
            home: CxstarReaderScreen(bookId: 'book-1', title: '测试书'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('每 60 秒心跳刷新一次「今日已计」，并显示更新时刻', (tester) async {
      await pumpReader(tester);

      expect(find.textContaining('今日已计 10 分'), findsOneWidget);
      expect(find.textContaining('更新'), findsOneWidget);
      final callsAfterBoot = remote.summaryCalls;

      // 一次心跳（60 秒）后必须刷新（此前是每 5 次心跳 = 5 分钟才刷一次）。
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      await tester.pump();
      expect(
        remote.summaryCalls,
        greaterThan(callsAfterBoot),
        reason: '每次心跳都应刷新统计',
      );

      remote.todayMinutes = 11;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('今日已计 11 分'), findsOneWidget);

      remote.todayMinutes = 12;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('今日已计 12 分'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('真实流程镜像：宿主 → 畅想之星（子路由）→ 阅读器 → 返回', () {
    late _CountingRemoteDataSource remote;
    late _FakeReaderDataSource reader;
    late GlobalKey<NavigatorState> navKey;
    late _FakeClock clock;
    late CxstarRefreshGate gate;

    setUp(() {
      remote = _CountingRemoteDataSource();
      reader = _FakeReaderDataSource();
      navKey = GlobalKey<NavigatorState>();
      clock = _FakeClock();
      gate = CxstarRefreshGate(clock: clock.call);
    });

    testWidgets('从阅读器返回：窗口内不重取，结算补刷照常取到新值', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAccountProvider.overrideWith((ref) => ''),
            cxstarPersonalTokenProvider.overrideWith((ref) async => null),
            cxstarRemoteDataSourceProvider.overrideWithValue(remote),
            cxstarReaderContextProvider.overrideWith(
              (ref) async => const CxstarReaderContext(token: 't', pinst: 'p'),
            ),
            cxstarReaderDataSourceProvider.overrideWithValue(reader),
            cxstarRefreshGateProvider.overrideWithValue(gate),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [appRouteObserver],
            home: const _HostPage(),
          ),
        ),
      );

      // ① 进入畅想之星（被 push 的子路由）
      await tester.tap(find.text('打开畅想之星'));
      await tester.pumpAndSettle();
      expect(remote.userCalls, 1, reason: '进入页面取一次');

      // ② 点书名进阅读器
      await tester.tap(find.text('测试书'));
      await tester.pumpAndSettle();
      expect(find.byType(CxstarReaderScreen), findsOneWidget);

      // ③ 返回：距上次更新不足 1 分钟 → 立即那次被窗口挡下（用户 2026-09-14 追加的
      //    「数据更新最小间隔 1 分钟」）；结算补刷不受限，10 秒后照样取到新值。
      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        remote.userCalls,
        1,
        reason: '窗口内的自动刷新不重复取数（返回瞬间那次被挡）',
      );

      // ④ 结算补刷：平台批量结算，返回后按 10s / 45s / 150s 再各取一次（force，不受窗口限制）
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(remote.userCalls, 2, reason: '返回 10 秒后应补刷一次（等平台结算）');

      await tester.pump(const Duration(seconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        remote.userCalls,
        4,
        reason: '45 秒 / 150 秒两次补刷也要发生',
      );

      await tester.pumpWidget(const SizedBox());
    });
  });
}
