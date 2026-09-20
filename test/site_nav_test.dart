/// 网站导航守卫（用户 2026-09-19 立项）。
///
/// 守四件事：
/// 1. **目录数据**（`domain/site_directory.dart`）：条数 / 分类分布 / URL 合法性 /
///    用户点名的 8 条原样在表里 / 只有 http 的站点没被「顺手统一成 https」/
///    实测的空壳与死站没被加回来；
/// 2. **筛选与分节纯函数**（`domain/campus_site.dart`）：搜索口径、收藏段恒在最前、
///    `favoritesOnly` 不重复列分类、筛选对收藏段同样生效；
/// 3. **收藏存储**（`data/site_favorites.dart`）：落盘 → 新实例读回、脏数据不炸、
///    外部写入（云同步恢复）能反映到内存；
/// 4. **页面**（`presentation/site_nav_screen.dart`）：搜索 / 筛选 / 星标 / 打开
///    走 `externalUrlOpenerProvider`（**一律系统浏览器**，用户明确否掉内嵌 WebView）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/site_nav/data/site_favorites.dart';
import 'package:smarter_jxufe/features/site_nav/domain/campus_site.dart';
import 'package:smarter_jxufe/features/site_nav/domain/site_directory.dart';
import 'package:smarter_jxufe/features/site_nav/presentation/site_nav_screen.dart';

/// 用户点名要的 8 条（名称 → 域名）。域名口径：用户给的是 `http://ehall.jxufe.edu.cn/`，
/// 目录里升级成 https（同一站点、同一域名，实测 https 可用），其余逐条一致。
const _userPicks = <String, String>{
  '教务处': 'jwc.jxufe.edu.cn',
  '学校官网': 'www.jxufe.edu.cn',
  '迎新网': 'hello.jxufe.edu.cn',
  '图书馆': 'lib.jxufe.edu.cn',
  '综合服务门户（智慧江财）': 'ehall.jxufe.edu.cn',
  '研究生院': 'grs.jxufe.edu.cn',
  '教学管理服务平台（选课）': 'xk.jxufe.cn',
  '软件与物联网工程学院': 'software.jxufe.edu.cn',
};

/// 实测**只有 http 可用**的域名（https 报 SQL 错误 / 握手失败 / 空壳模板）。
const _httpOnlyHosts = <String>[
  'xk.jxufe.cn',
  'hello.jxufe.edu.cn',
  'mail.jxufe.edu.cn',
  'st.jxufe.edu.cn',
  'sim.jxufe.edu.cn',
  'zcgl.jxufe.edu.cn',
  'pan.jxufe.cn',
  'bx.jxufe.cn',
  'ios.jxufe.edu.cn',
  'english.jxufe.edu.cn',
  'yjszs.jxufe.edu.cn',
  'ssp.jxufe.edu.cn',
  'lib.jxufe.cn',
  'beyondgdp.jxufe.edu.cn',
  'efdrc.jxufe.edu.cn',
  'kfzx.jxufe.edu.cn',
  'csyjzx.jxufe.edu.cn',
  'qyzx.jxufe.edu.cn',
  'cygz.jxufe.edu.cn',
  'xkxtzx.jxufe.edu.cn',
  'jrfxyjzx.jxufe.edu.cn',
  'fzjx.jxufe.edu.cn',
  'brri.jxufe.edu.cn',
  'bjgdyjy.jxufe.edu.cn',
  'ganzhou.jxufe.edu.cn',
];

/// 实测的**空壳 / 死站**（解析得到但只是学校通用模板，或 DNS 失败）—— 别再收录。
const _deadHosts = <String>[
  'mba.jxufe.edu.cn',
  'alumni.jxufe.edu.cn',
  'jjh.jxufe.edu.cn',
  'zs.jxufe.edu.cn',
  'epaper.jxufe.edu.cn',
  'jwc3.jxufe.edu.cn',
  'bwc.jxufe.edu.cn',
];

const _file = 'lib/features/site_nav/presentation/site_nav_screen.dart';
const _directoryFile = 'lib/features/site_nav/domain/site_directory.dart';
const _favoritesFile = 'lib/features/site_nav/data/site_favorites.dart';

CampusSite _byName(String name) =>
    campusSites.firstWhere((s) => s.name == name);

void main() {
  late Directory hiveDir;

  // Hive 只 init 一次（整个文件共用一个临时目录）；每个测试前清库 → 用例之间隔离。
  //
  // ⚠ **必须在真实异步区里就把 box 打开**（照 `test/theme_dark_test.dart:72-79` 的实测口径）：
  // `Hive.openBox` 对同一个 box 名是「单飞」的 —— 第一次打开若发生在 `testWidgets` 的
  // 假异步区（页面里 `siteFavoritesProvider` 的 `unawaited(ensureLoaded())` 就会这么干），
  // 那个 future 永远不会完成，之后**任何**一次 `openBox('siteNavPrefs')` 都会一直等它
  // → widget 测试挂到 `pumpAndSettle` 上限才报 "did not complete"。
  // 预先打开后，假异步区里的 `openBox` 走「已打开」短路，不再碰真实 I/O。
  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('site_nav_hive');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(siteNavPrefsBoxName);
  });

  tearDownAll(() {
    // ⚠ **刻意不碰 Hive**（照 `test/aa_test.dart:134` 与 `test/theme_dark_test.dart:83` 的
    // 实测教训）：本文件末尾是 widget 测试，假异步区里留下的在途操作永远不会完成 →
    // 收尾调 `Hive.deleteFromDisk()` / `Hive.close()` 会**永不返回**（实测整份测试
    // 卡在 `(tearDownAll)` 12 分钟超时）。临时目录交给系统回收。
  });

  group('目录数据', () {
    test('共 137 条，五个分类都有货', () {
      // 29 学院与学部 / 37 职能部门 / 22 服务系统 / 38 科研机构 / 11 其他站点。
      // 增删站点请同步本测试与 `site_directory.dart` 头注释。
      expect(campusSites.length, 137, reason: '目录条数变了，请同步本测试与 AGENTS.md');
      final counts = <CampusSiteCategory, int>{};
      for (final s in campusSites) {
        counts[s.category] = (counts[s.category] ?? 0) + 1;
      }
      expect(counts[CampusSiteCategory.college], 29);
      expect(counts[CampusSiteCategory.department], 37);
      expect(counts[CampusSiteCategory.service], 22);
      expect(counts[CampusSiteCategory.research], 38);
      expect(counts[CampusSiteCategory.other], 11);
      expect(counts.keys.toSet().length, CampusSiteCategory.values.length);
    });

    test('每条 URL 合法、无空白中文、且不重复', () {
      final seen = <String>{};
      for (final s in campusSites) {
        expect(s.name.trim(), s.name, reason: '站点名首尾有空白：${s.name}');
        expect(s.name, isNotEmpty);
        expect(
          RegExp(r'^https?://').hasMatch(s.url),
          isTrue,
          reason: '${s.name} 的 URL 必须以 http:// 或 https:// 开头',
        );
        expect(s.url.trim(), s.url, reason: '${s.name} 的 URL 首尾有空白');
        expect(
          RegExp(r'[\u4e00-\u9fa5\s]').hasMatch(s.url),
          isFalse,
          reason: '${s.name} 的 URL 里有中文或空白',
        );
        expect(
          Uri.tryParse(s.url)?.host,
          isNotEmpty,
          reason: '${s.name} 的 URL 解析不出主机名',
        );
        expect(
          s.host,
          isNotEmpty,
          reason: '${s.name} 的 host 为空（campusSiteHost 兜底失效）',
        );
        expect(seen.add(s.url), isTrue, reason: '${s.name} 的 URL 与前面的条目重复');
      }
    });

    test('站点名唯一（搜索与收藏的锚点）', () {
      final names = campusSites.map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('用户点名的 8 条都在，域名与用户给的一致', () {
      for (final entry in _userPicks.entries) {
        expect(
          _byName(entry.key).host,
          entry.value,
          reason: '用户点名要的「${entry.key}」丢了或换了域名',
        );
      }
    });

    test('只有 http 的站点没被「顺手统一成 https」', () {
      for (final s in campusSites) {
        if (!_httpOnlyHosts.contains(s.host)) continue;
        expect(
          s.url.startsWith('http://'),
          isTrue,
          reason: '${s.name}（${s.host}）实测只有 http 可用，https 是空壳 / 报错页',
        );
      }
    });

    test('实测的空壳与死站没有混回来', () {
      for (final s in campusSites) {
        expect(
          _deadHosts,
          isNot(contains(s.host)),
          reason: '${s.name}（${s.host}）实测是空壳模板 / DNS 失败，别加回目录',
        );
      }
      // 保卫处走 jczzw；图书馆主站与「图书资源门户」是两个不同站点，都保留。
      expect(_byName('保卫工作部（处）、人武部').host, 'jczzw.jxufe.edu.cn');
      expect(_byName('图书馆').host, 'lib.jxufe.edu.cn');
      expect(_byName('图书馆 · 图书资源门户').host, 'lib.jxufe.cn');
    });

    test('常用 16 条，用户点名的 8 条都在其中', () {
      final hot = campusSites.where((s) => s.hot).map((s) => s.name).toSet();
      expect(hot.length, 16);
      for (final name in _userPicks.keys) {
        expect(hot, contains(name), reason: '「$name」是用户点名的，应在常用里');
      }
    });

    test('改名后的学院用的是现名与现存域名', () {
      // 旧名单（国际经贸 / 人文 / 艺术 / 信息管理 / 统计 / 财税与公共管理）已不存在。
      const renamed = <String, String>{
        '国际经济与政治学院': 'gmxy.jxufe.edu.cn',
        '社会与人文学院': 'rwxynew.jxufe.edu.cn',
        '设计与艺术学院': 'art.jxufe.edu.cn',
        '信息管理与数学学院': 'sim.jxufe.edu.cn',
        '统计与数据科学学院': 'stat.jxufe.edu.cn',
        '财政税务学院': 'csxy.jxufe.edu.cn',
        '公共管理学院': 'ggxy.jxufe.edu.cn',
        '计算机与人工智能学院': 'cai.jxufe.edu.cn',
        '虚拟现实（VR）现代产业学院': 'vr.jxufe.edu.cn',
      };
      renamed.forEach((name, host) {
        expect(_byName(name).host, host, reason: name);
      });
      final names = campusSites.map((s) => s.name).toSet();
      for (final old in const [
        '国际经贸学院',
        '人文学院',
        '艺术学院',
        '信息管理学院',
        '统计学院',
        '财税与公共管理学院',
        '旅游与城市管理学院',
      ]) {
        expect(names, isNot(contains(old)), reason: '「$old」是旧名，官网已不存在');
      }
    });

    test('三个易混入口是三条独立记录', () {
      expect(_byName('综合服务门户（智慧江财）').host, 'ehall.jxufe.edu.cn');
      expect(_byName('网上办事大厅').host, 'onestop.jxufe.edu.cn');
      expect(_byName('统一身份认证').host, 'ssl.jxufe.edu.cn');
    });
  });

  group('筛选与分节', () {
    test('搜索命中名称 / 域名 / 备注，忽略大小写与空白', () {
      expect(campusSiteMatches(_byName('教务处'), '教务'), isTrue);
      expect(campusSiteMatches(_byName('教务处'), 'JWC'), isTrue);
      expect(campusSiteMatches(_byName('教务处'), ' jwc '), isTrue);
      expect(campusSiteMatches(_byName('图书馆'), 'lib'), isTrue);
      expect(campusSiteMatches(_byName('社会与人文学院'), '人文'), isTrue);
      expect(campusSiteMatches(_byName('信息管理与数学学院'), '仅 http'), isTrue);
      expect(campusSiteMatches(_byName('教务处'), '图书馆'), isFalse);
      expect(campusSiteMatches(_byName('教务处'), ''), isTrue);
      expect(campusSiteMatches(_byName('教务处'), '   '), isTrue);
    });

    test('分类 / 常用 / 收藏 / 搜索可叠加（与关系）', () {
      final favs = {_byName('教务处').key, _byName('图书馆').key};
      final services = filterCampusSites(
        campusSites,
        category: CampusSiteCategory.service,
      );
      expect(services.length, 22);
      expect(
        services.every((s) => s.category == CampusSiteCategory.service),
        isTrue,
      );
      expect(filterCampusSites(campusSites, hotOnly: true).length, 16);
      expect(
        filterCampusSites(
          campusSites,
          favoritesOnly: true,
          favorites: favs,
        ).map((s) => s.name).toList(),
        ['教务处', '图书馆'], // 段内顺序 = 目录顺序
      );
      expect(
        filterCampusSites(
          campusSites,
          category: CampusSiteCategory.service,
          favoritesOnly: true,
          favorites: favs,
        ).map((s) => s.name).toList(),
        ['图书馆'],
      );
      expect(
        filterCampusSites(campusSites, query: '教务').map((s) => s.name),
        containsAll(<String>['教务处', '教务管理系统']),
      );
    });

    test('收藏段恒在最前，且收藏项在分类段里也出现（置顶 ≠ 移出目录）', () {
      final favs = {_byName('图书馆').key};
      final sections = campusSiteSections(all: campusSites, favorites: favs);
      expect(sections.first.key, 'fav');
      expect(sections.first.title, '我的收藏');
      expect(sections.first.favorites, isTrue);
      expect(sections.first.sites.map((s) => s.name).toList(), ['图书馆']);
      expect(
        sections.skip(1).map((s) => s.key).toList(),
        CampusSiteCategory.values.map((c) => c.name).toList(),
        reason: '分类段顺序必须 = 枚举顺序',
      );
      for (final s in sections) {
        expect(s.sites, isNotEmpty, reason: '空节不许占位：${s.key}');
      }
      expect(
        sections
            .firstWhere((s) => s.key == CampusSiteCategory.service.name)
            .sites
            .map((s) => s.name),
        contains('图书馆'),
      );
    });

    test('无收藏时不出收藏段', () {
      final sections = campusSiteSections(all: campusSites);
      expect(sections.map((s) => s.key), isNot(contains('fav')));
      expect(sections.length, CampusSiteCategory.values.length);
    });

    test('favoritesOnly 只出收藏段（不把同一批站点再列一遍）', () {
      final favs = {_byName('图书馆').key, _byName('教务处').key};
      final sections = campusSiteSections(
        all: campusSites,
        favorites: favs,
        favoritesOnly: true,
      );
      expect(sections.length, 1);
      expect(sections.single.key, 'fav');
      expect(sections.single.sites.length, 2);
      expect(
        campusSiteSections(
          all: campusSites,
          favoritesOnly: true,
        ),
        isEmpty,
        reason: '没收藏时必须整页空（页面给「还没有收藏」的提示）',
      );
    });

    test('筛选对收藏段同样生效（不会冒出被筛掉的站点）', () {
      final favs = {_byName('图书馆').key, _byName('教务处').key};
      final searched = campusSiteSections(
        all: campusSites,
        favorites: favs,
        query: '图书',
      );
      expect(searched.first.key, 'fav');
      expect(searched.first.sites.map((s) => s.name).toList(), ['图书馆']);
      expect(searched.map((s) => s.key).toList(), ['fav', 'service']);

      final hot = campusSiteSections(
        all: campusSites,
        favorites: favs,
        hotOnly: true,
      );
      expect(hot.first.sites.map((s) => s.name).toList(), ['教务处', '图书馆']);
    });
  });

  group('收藏存储', () {
    setUp(() async {
      await Hive.deleteFromDisk();
      // `deleteFromDisk` 会把 box 一起关掉 → **再预开一次**，否则后面的
      // widget 测试又会在假异步区里碰真实 I/O（见 `setUpAll` 上方那段）。
      await Hive.openBox<String>(siteNavPrefsBoxName);
    });

    test('toggle 落盘 → 新实例读回', () async {
      final store = SiteFavoritesStore();
      await store.ensureLoaded();
      expect(store.length, 0);
      await store.toggle('https://jwc.jxufe.edu.cn/');
      expect(store.contains('https://jwc.jxufe.edu.cn/'), isTrue);
      expect(store.length, 1);

      final reopened = SiteFavoritesStore();
      await reopened.ensureLoaded();
      expect(reopened.keys, {'https://jwc.jxufe.edu.cn/'});
    });

    test('取消收藏后 key 被删掉（盘上不留空数组）', () async {
      final store = SiteFavoritesStore();
      await store.ensureLoaded();
      await store.toggle('https://jwc.jxufe.edu.cn/');
      await store.toggle('https://jwc.jxufe.edu.cn/');
      expect(store.length, 0);
      final box = await Hive.openBox<String>(siteNavPrefsBoxName);
      expect(box.get(siteNavFavoritesKey), isNull);
    });

    test('脏数据不炸：非 JSON / 非数组 / 混进非字符串项一律忽略', () async {
      expect(siteFavoritesFromJson(null), isEmpty);
      expect(siteFavoritesFromJson(''), isEmpty);
      expect(siteFavoritesFromJson('这不是 JSON'), isEmpty);
      expect(siteFavoritesFromJson('{"a":1}'), isEmpty);

      final box = await Hive.openBox<String>(siteNavPrefsBoxName);
      await box.put(
        siteNavFavoritesKey,
        jsonEncode(['https://a/', 42, null, '', 'https://b/']),
      );
      final store = SiteFavoritesStore();
      await store.ensureLoaded();
      expect(store.keys, {'https://a/', 'https://b/'});
    });

    test('外部写入（云同步「从云端恢复」）会反映到内存', () async {
      final store = SiteFavoritesStore();
      await store.ensureLoaded();
      expect(store.length, 0);
      var notified = 0;
      store.addListener(() => notified++);

      final box = await Hive.openBox<String>(siteNavPrefsBoxName);
      await box.put(siteNavFavoritesKey, siteFavoritesToJson(['https://x/']));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.keys, {'https://x/'}, reason: 'BoxReloadWatcher 没绑上 → 恢复报成功但界面不动');
      expect(notified, greaterThan(0));
    });

    test('存储不可用也不抛（Hive 打开失败 → 仅本次会话生效）', () async {
      final store = SiteFavoritesStore();
      await store.ensureLoaded();
      await store.clear();
      expect(store.length, 0);
    });
  });

  group('页面', () {
    late List<String> opened;
    late List<String> clipboard;

    Widget app({SiteFavoritesStore? favorites}) => ProviderScope(
      overrides: [
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri.toString());
          return true;
        }),
        if (favorites != null)
          siteFavoritesProvider.overrideWith((ref) => favorites),
      ],
      child: MaterialApp(theme: appLightTheme, home: const SiteNavScreen()),
    );

    setUp(() {
      opened = <String>[];
      clipboard = <String>[];
    });

    testWidgets('渲染：搜索框 + 分类胶囊 + 分组标题 + 站点行', (tester) async {
      await tester.pumpWidget(app());
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('共 137 个站点 · 已收藏 0 个'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('siteSection-college')),
        findsOneWidget,
      );
      expect(find.text('经济学院'), findsOneWidget);
    });

    testWidgets('搜索 jwc 只命中教务处，点行用系统浏览器打开', (tester) async {
      await tester.pumpWidget(app());
      await tester.enterText(find.byType(TextField), 'jwc');
      await tester.pumpAndSettle();

      expect(find.text('共 137 个站点 · 命中 1 个'), findsOneWidget);
      expect(find.text('教务处'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('siteSection-college')),
        findsNothing,
        reason: '空节不占位',
      );

      await tester.tap(find.text('教务处'));
      await tester.pumpAndSettle();
      expect(opened, ['https://jwc.jxufe.edu.cn/']);
    });

    testWidgets('打开失败时给「可能需要校园网」的提示', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalUrlOpenerProvider.overrideWithValue((uri) async => false),
          ],
          child: MaterialApp(
            theme: appLightTheme,
            home: const SiteNavScreen(),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'jwc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('教务处'));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法打开 jwc.jxufe.edu.cn'), findsOneWidget);
    });

    testWidgets('点星标 → 置顶出现「我的收藏」段，再点取消', (tester) async {
      // box 已在 `setUpAll` 里预开 → 这里的 `ensureLoaded()` 命中「已打开」短路，
      // 不会挂在假异步区（⚠ 别改用 `tester.runAsync` 建 store：那样 `_loading` 是
      // 真实异步区里完成的 future，假异步区 `await` 它**永远不恢复**，实测点星标没有任何反应）。
      final favorites = SiteFavoritesStore();
      await favorites.ensureLoaded();
      await tester.pumpWidget(app(favorites: favorites));
      // ⚠ 搜索词用域名而不是「图书馆」：后者会同时命中「图书馆 · 图书资源门户」。
      await tester.enterText(find.byType(TextField), 'lib.jxufe.edu.cn');
      await tester.pumpAndSettle();
      expect(find.text('图书馆'), findsOneWidget);

      expect(find.byKey(const ValueKey('siteSection-fav')), findsNothing);
      await tester.tap(find.byTooltip('收藏'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('siteSection-fav')), findsOneWidget);
      expect(favorites.contains('https://lib.jxufe.edu.cn/'), isTrue);
      // 收藏段与分类段各有一行（置顶是快捷区，不是把站点搬走），
      // 两行的星标都已点亮 → 取消收藏要点第一颗。
      expect(find.byTooltip('取消收藏'), findsNWidgets(2));

      await tester.tap(find.byTooltip('取消收藏').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('siteSection-fav')), findsNothing);
      expect(favorites.length, 0);
    });

    testWidgets('点复制把 URL 写进剪贴板并提示', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              clipboard.add(args['text']! as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(app());
      await tester.enterText(find.byType(TextField), 'jwc');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('复制链接'));
      await tester.pumpAndSettle();

      expect(clipboard, ['https://jwc.jxufe.edu.cn/']);
      expect(find.textContaining('已复制链接'), findsOneWidget);
    });

    testWidgets('点「服务系统」胶囊只出服务系统段，点「全部」还原', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('服务系统').first);
      await tester.pumpAndSettle();

      expect(find.text('共 137 个站点 · 命中 22 个'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('siteSection-service')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('siteSection-college')), findsNothing);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('共 137 个站点 · 已收藏 0 个'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('siteSection-college')),
        findsOneWidget,
      );
    });

    testWidgets('空收藏时点「我的收藏」给提示而不是空白页', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏 · 点行尾的星标即可收藏'), findsOneWidget);
    });

    testWidgets('站点行用的是全应用卡片契约（圆角 12 + hairline 边；浅色/深色同款）', (
      tester,
    ) async {
      // 用户 2026-09-20：「『规章制度』和『网站导航』中的卡片样式与其他页面不同」
      // —— 本页从前自己拼了 `radius 9 + BorderSide(color: scheme.outline)`。
      for (final theme in <ThemeData>[appLightTheme, appDarkTheme]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              externalUrlOpenerProvider.overrideWithValue((uri) async => true),
            ],
            child: MaterialApp(theme: theme, home: const SiteNavScreen()),
          ),
        );
        // 用搜索把行拉进视口（ListView 懒构建，靠后的分组不会渲染）。
        await tester.enterText(find.byType(TextField), 'jwc');
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SiteNavScreen));
        final tile = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('教务处'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          tile.shape,
          appCardShape(context),
          reason: '瓦片形状必须逐值等于 appCardShape(context)（圆角 12 + hairline 描边）',
        );
        expect(
          tile.color,
          appCardColor(context),
          reason: '瓦片底色必须等于 appCardColor(context)（浅色纯白 / 深色 #1A1A1A）',
        );
      }
    });
  });

  group('源码守卫', () {
    test('一律用系统浏览器：页面走 provider，不得引入内嵌 WebView', () {
      final source = File(_file).readAsStringSync();
      expect(source.contains('externalUrlOpenerProvider'), isTrue);
      expect(
        RegExp(r'^\s*import .*in_app_web', multiLine: true).hasMatch(source),
        isFalse,
        reason: '用户 2026-09-19 明确否掉手机内嵌 WebView（文档注释里点名该文件是可以的）',
      );
      expect(source.contains('InAppWebScreen'), isFalse);
      expect(source.contains('inAppWebViewSupportedProvider'), isFalse);
      expect(
        source.contains('launchUrl('),
        isFalse,
        reason: '打开外链必须走 externalUrlOpenerProvider（测试才能断言 URL）',
      );
    });

    test('页面里不写死站点 URL（唯一出处 = 目录表）', () {
      final source = File(_file).readAsStringSync();
      expect(
        RegExp(r'https?://').hasMatch(source),
        isFalse,
        reason: '页面里不许出现 URL 字面量，全部来自 campusSites',
      );
      expect(source.contains('site_directory.dart'), isTrue);
      final directory = File(_directoryFile).readAsStringSync();
      expect(directory.contains('news-list-xysz.html'), isTrue, reason: '权威来源要留在注释里');
    });

    test('收藏走 Hive 单 key + BoxReloadWatcher（不新增文件存储）', () {
      final source = File(_favoritesFile).readAsStringSync();
      expect(source.contains("const siteNavPrefsBoxName = 'siteNavPrefs'"), isTrue);
      expect(source.contains('bindBoxReload'), isTrue);
      expect(source.contains('jsonEncode'), isTrue);
    });

    test('站点行卡片走卡片契约（不自己拼圆角 + 描边）', () {
      final source = File(_file).readAsStringSync();
      expect(source.contains('shape: appCardShape(context)'), isTrue);
      expect(source.contains('color: appCardColor(context)'), isTrue);
      expect(
        source.contains('BorderSide(color: scheme.outline)'),
        isFalse,
        reason: '卡片描边唯一出处 = appCardBorderSide（scheme.outline 实线比契约深一档，'
            '用户 2026-09-20 当场指出这一页卡片与别页不同）',
      );
    });

    test('首页目录已挂「网站导航」，色板已登记 siteNav', () {
      final catalog = File(
        'lib/features/home/presentation/home_service_catalog.dart',
      ).readAsStringSync();
      expect(catalog.contains("'网站导航'"), isTrue);
      expect(catalog.contains('SiteNavScreen()'), isTrue);
      expect(catalog.contains('f.siteNav'), isTrue);
      final palette = File('lib/design/feature_palette.dart').readAsStringSync();
      expect(palette.contains('siteNav'), isTrue);
      expect(palette.contains('Color get siteNav'), isTrue);
    });
  });
}
