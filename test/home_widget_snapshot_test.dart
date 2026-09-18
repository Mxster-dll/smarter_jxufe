import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';

String hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

const _res = 'android/app/src/main/res';
const _values = '$_res/values';
const _night = '$_res/values-night';
const _kt = 'android/app/src/main/kotlin/com/example/smarter_jxufe/widget';

String read(String path) => File(path).readAsStringSync();

/// 尺寸档全集（宽 × 高，单位 = 桌面格子）—— 与原生 `WidgetSize.tag` 一致。
const _tags = <String>['2x1', '3x1', '4x1', '5x1', '2x2', '3x2', '4x2', '5x2'];

/// 每档的格子数 / 行数 / 是否有「更新于」页脚（仪表盘布局）。
const _dashGrid = <String, ({int cells, int rows, bool footer})>{
  '2x1': (cells: 2, rows: 1, footer: false),
  '3x1': (cells: 3, rows: 1, footer: false),
  '4x1': (cells: 4, rows: 1, footer: false),
  '5x1': (cells: 5, rows: 1, footer: false),
  '2x2': (cells: 4, rows: 2, footer: false),
  '3x2': (cells: 6, rows: 2, footer: false),
  '4x2': (cells: 6, rows: 2, footer: true),
  '5x2': (cells: 5, rows: 1, footer: true),
};

/// 资源名用单数（home_widget_grade_*），指标 key 是复数 grades。
String resName(HomeWidgetMetric metric) =>
    metric == HomeWidgetMetric.grades ? 'grade' : metric.key;

/// 从 colors.xml 里取某个颜色（返回 `#RRGGBB` / `#AARRGGBB` 原样大写）。
String colorOf(String xml, String name) {
  final match = RegExp(
    '<color name="$name">(#[0-9A-Fa-f]{6,8})</color>',
  ).firstMatch(xml);
  expect(match, isNotNull, reason: '$name 未在颜色资源里定义');
  return match!.group(1)!.toUpperCase();
}

List<String> colorNames(String xml) => [
  for (final m in RegExp(r'<color name="([^"]+)"').allMatches(xml)) m.group(1)!,
];

void main() {
  group('HomeWidgetSnapshot · 序列化', () {
    HomeWidgetSnapshot sample() => HomeWidgetSnapshot(
      metric: HomeWidgetMetric.electricity,
      label: '电费余额',
      value: '12.5',
      unit: 'kWh',
      sub1: '房间 05602',
      sub2: '更新于 09-11 02:30',
      state: HomeWidgetState.ok,
      message: '',
      updatedAt: 1789000000000,
      accent: '#F9A825',
    );

    test('encode → decode 往返不丢字段', () {
      final decoded = HomeWidgetSnapshot.decode(sample().encode());
      expect(decoded, isNotNull);
      expect(decoded!.metric, HomeWidgetMetric.electricity);
      expect(decoded.value, '12.5');
      expect(decoded.unit, 'kWh');
      expect(decoded.sub1, '房间 05602');
      expect(decoded.state, HomeWidgetState.ok);
      expect(decoded.updatedAt, 1789000000000);
      expect(decoded.accent, '#F9A825');
    });

    test('空 / 损坏 / 未知指标一律返回 null（原生按兜底渲染）', () {
      expect(HomeWidgetSnapshot.decode(null), isNull);
      expect(HomeWidgetSnapshot.decode(''), isNull);
      expect(HomeWidgetSnapshot.decode('{不是 json'), isNull);
      expect(HomeWidgetSnapshot.decode('[]'), isNull);
      expect(HomeWidgetSnapshot.decode('{"metric":"unknown"}'), isNull);
    });

    test('字段缺失走默认值，state 未知视为 error', () {
      final decoded = HomeWidgetSnapshot.decode('{"metric":"grades"}');
      expect(decoded, isNotNull);
      expect(decoded!.label, HomeWidgetMetric.grades.defaultLabel);
      expect(decoded.value, '');
      expect(decoded.unit, '');
      expect(decoded.state, HomeWidgetState.error);
      expect(decoded.accent, '#9E9E9E');
      expect(decoded.cells, isEmpty);
    });

    test('metric / state 的 key 与原生约定一致', () {
      expect(HomeWidgetMetric.dashboard.key, 'dashboard');
      expect(HomeWidgetMetric.electricity.key, 'electricity');
      expect(HomeWidgetMetric.grades.key, 'grades');
      expect(HomeWidgetState.ok.key, 'ok');
      expect(HomeWidgetState.empty.key, 'empty');
      expect(HomeWidgetState.error.key, 'error');
    });

    test('更新时间文案为「更新于 MM-DD HH:mm」', () {
      expect(
        HomeWidgetSnapshot.updatedLabel(DateTime(2026, 9, 11, 2, 5)),
        '更新于 09-11 02:05',
      );
    });
  });

  group('HomeWidgetSnapshot · 仪表盘格子（cells）', () {
    HomeWidgetSnapshot dashboard(List<HomeWidgetCell> cells) =>
        HomeWidgetSnapshot(
          metric: HomeWidgetMetric.dashboard,
          label: '数据一览',
          value: '',
          unit: '',
          sub1: '',
          sub2: '更新于 09-11 09:00',
          state: HomeWidgetState.ok,
          message: '',
          updatedAt: 1789000000000,
          accent: '#C3282E',
          cells: cells,
        );

    test('cells 往返不丢格，顺序保持', () {
      final decoded = HomeWidgetSnapshot.decode(
        dashboard(const [
          HomeWidgetCell(label: '电费', value: '120.9'),
          HomeWidgetCell(label: '网费', value: '12.50'),
          HomeWidgetCell(label: '加权', value: '91.86'),
          HomeWidgetCell(label: '志愿', value: '24h'),
          HomeWidgetCell(label: '今日', value: '3 节'),
        ]).encode(),
      );
      expect(decoded, isNotNull);
      expect(decoded!.metric, HomeWidgetMetric.dashboard);
      expect(decoded.cells.length, 5);
      expect(decoded.cells.map((c) => c.label).toList(), [
        '电费',
        '网费',
        '加权',
        '志愿',
        '今日',
      ]);
      expect(decoded.cells.first.value, '120.9');
      expect(decoded.cells.last.value, '3 节');
    });

    test('cells 容错：非列表 → 空；空格 / 非 Map 格被丢弃', () {
      expect(HomeWidgetSnapshot.cellsFromJson(null), isEmpty);
      expect(HomeWidgetSnapshot.cellsFromJson('电费'), isEmpty);
      expect(
        HomeWidgetSnapshot.cellsFromJson([
          {'label': '电费', 'value': '120.9'},
          {'label': '', 'value': ''},
          'oops',
          {'value': '3 节'},
        ]).length,
        2,
      );
    });

    test('HomeWidgetCell 值相等（漂移守卫依赖它比较历史快照）', () {
      expect(
        const HomeWidgetCell(label: '电费', value: '120.9'),
        const HomeWidgetCell(label: '电费', value: '120.9'),
      );
      expect(
        const HomeWidgetCell(label: '电费', value: '120.9'),
        isNot(const HomeWidgetCell(label: '电费', value: '120.8')),
      );
    });
  });

  group('品牌色漂移守卫（Dart 调色板 ↔ 原生颜色资源）', () {
    /// 小组件配色是原生资源（图标矢量图也引用 @color），一旦调色板改了色值，
    /// 这里会立刻失败，提醒同步 `values/colors.xml`。
    test('三个指标点缀色 == FeaturePalette', () {
      final colors = read('$_values/colors.xml');
      expect(
        colorOf(colors, 'home_widget_accent_electricity'),
        hex(FeaturePalette.electricity),
      );
      expect(
        colorOf(colors, 'home_widget_accent_grade'),
        hex(FeaturePalette.grade),
      );
      expect(
        colorOf(colors, 'home_widget_accent_dashboard'),
        hex(FeaturePalette.dashboard),
      );
    });

    test('图标矢量图引用颜色资源（深色模式才能自动提亮）', () {
      for (final metric in HomeWidgetMetric.values) {
        final res = resName(metric);
        final xml = read('$_res/drawable/home_widget_ic_$res.xml');
        expect(
          xml.contains('android:fillColor="@color/home_widget_accent_$res"'),
          isTrue,
          reason: 'home_widget_ic_$res.xml 必须引用 @color 而不是写死色值',
        );
      }
    });

    test('所有指标的 key 在原生 provider 映射表中都存在', () {
      final bridge = read('$_kt/HomeWidgetBridge.kt');
      for (final metric in HomeWidgetMetric.values) {
        expect(
          bridge.contains('"${metric.key}" to listOf(') ||
              bridge.contains('METRIC_DASHBOARD to listOf('),
          isTrue,
          reason: 'HomeWidgetBridge.kt 缺少指标 ${metric.key} 的 provider 映射',
        );
      }
    });
  });

  group('深色模式守卫（values-night）', () {
    test('夜间配色覆盖浅色全部键，且都为合法色值', () {
      final light = read('$_values/colors.xml');
      final night = read('$_night/colors.xml');
      final lightNames = colorNames(light);
      expect(lightNames, isNotEmpty);
      for (final name in lightNames) {
        expect(
          night.contains('<color name="$name">'),
          isTrue,
          reason: 'values-night/colors.xml 缺少 $name —— 深色模式下该处会退回浅色值',
        );
        expect(
          RegExp(r'#[0-9A-Fa-f]{6,8}').hasMatch(colorOf(night, name)),
          isTrue,
        );
      }
    });

    test('卡片底色 / 描边 / 正文色在夜间必须换值', () {
      final light = read('$_values/colors.xml');
      final night = read('$_night/colors.xml');
      for (final name in [
        'home_widget_bg',
        'home_widget_stroke',
        'home_widget_text_primary',
      ]) {
        expect(
          colorOf(light, name),
          isNot(colorOf(night, name)),
          reason: '$name 夜间必须换值，否则深色桌面上白底黑字',
        );
      }
      // 夜间底色必须比正文暗（简单可读性检查：亮度比较）
      expect(
        _luminance(colorOf(night, 'home_widget_bg')),
        lessThan(_luminance(colorOf(night, 'home_widget_text_primary'))),
      );
    });

    test('三个点缀色在夜间提亮（深底可读）', () {
      final light = read('$_values/colors.xml');
      final night = read('$_night/colors.xml');
      for (final name in [
        'home_widget_accent_electricity',
        'home_widget_accent_grade',
        'home_widget_accent_dashboard',
      ]) {
        expect(colorOf(light, name), isNot(colorOf(night, name)));
        expect(
          _luminance(colorOf(night, name)),
          greaterThan(_luminance(colorOf(light, name))),
          reason: '$name 夜间应更亮，才能在深色底上可读',
        );
      }
    });

    test('布局只用 RemoteViews 白名单内的组件（禁止 <View> / <Space>）', () {
      // RemoteViews 在宿主进程 inflate 时只认白名单类（AOSP RemoteViews.sInflaterFilter）。
      // 用了 <View>（哪怕只是当分隔线 / 弹簧）会得到：
      //   Binary XML file line #N: Error inflating class android.view.View
      // 实测由 debug 启动自检抓到（12 个单行档全灭），故在此设守卫。
      const whitelist = <String>{
        'LinearLayout',
        'FrameLayout',
        'RelativeLayout',
        'GridLayout',
        'TextView',
        'ImageView',
        'Button',
        'ImageButton',
        'Chronometer',
        'ProgressBar',
        'AnalogClock',
        'ViewFlipper',
        'AdapterViewFlipper',
      };
      final files = Directory('$_res/layout')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('home_widget'));
      expect(files, isNotEmpty);
      for (final file in files) {
        // 注释里写着 `dash_cell<i>` 这类说明，先剥掉注释再扫标签。
        final xml = file.readAsStringSync().replaceAll(
          RegExp(r'<!--.*?-->', dotAll: true),
          '',
        );
        for (final m in RegExp(r'<([A-Za-z][\w.]*)').allMatches(xml)) {
          final cls = m.group(1)!;
          if (cls.startsWith('?') || cls == 'shape' || cls == 'vector') {
            continue;
          }
          expect(
            whitelist.contains(cls.split('.').last),
            isTrue,
            reason:
                '${file.path} 使用了 <$cls> —— RemoteViews 不允许（白名单外无法 inflate）',
          );
        }
      }
    });

    test('布局与 drawable 不写死颜色（全部走 @color 资源）', () {
      final files = [
        ...Directory('$_res/layout').listSync().whereType<File>(),
        ...Directory('$_res/drawable').listSync().whereType<File>(),
      ].where((f) => f.path.contains('home_widget'));
      expect(files, isNotEmpty);
      final hardcoded = RegExp(
        r'android:(textColor|background|fillColor|color)="#[0-9A-Fa-f]{3,8}"',
      );
      for (final file in files) {
        final hits = hardcoded.allMatches(file.readAsStringSync());
        expect(
          hits,
          isEmpty,
          reason: '${file.path} 写死了颜色 —— 深色模式会失效，请改用 @color 资源',
        );
      }
    });
  });

  group('尺寸档漂移守卫（3 指标 × ${_tags.length} 档 = 24 个 provider）', () {
    test('原生 provider 映射表声明了 指标数 × 8 档 个 provider', () {
      final bridge = read('$_kt/HomeWidgetBridge.kt');
      expect(
        'to WidgetSize.X'.allMatches(bridge).length,
        HomeWidgetMetric.values.length * _tags.length,
        reason:
            '每个指标都应有 8 档尺寸的 provider（2×1 / 3×1 / 4×1 / 5×1 / 2×2 / 3×2 / 4×2 / 5×2）',
      );
      // 24 个具体类都得存在（AppWidgetProvider 必须有无参构造 → 不能靠枚举复用）
      for (final metric in HomeWidgetMetric.values) {
        final prefix =
            '${resName(metric)[0].toUpperCase()}${resName(metric).substring(1)}Widget';
        final kt = read('$_kt/MetricWidgetProviders.kt');
        for (final tag in _tags) {
          expect(
            kt.contains('class $prefix$tag : MetricWidgetProvider()'),
            isTrue,
            reason: '缺少 provider 类 $prefix$tag',
          );
        }
      }
    });

    test('每档尺寸都有元数据文件，且指向对应布局', () {
      for (final metric in HomeWidgetMetric.values) {
        final res = resName(metric);
        for (final tag in _tags) {
          final info = File('$_res/xml/home_widget_${res}_${tag}_info.xml');
          expect(info.existsSync(), isTrue, reason: '缺少 $res 的 $tag 档元数据');
          final xml = info.readAsStringSync();
          final layout = res == 'dashboard'
              ? 'home_widget_dashboard_$tag'
              : 'home_widget_metric_$tag';
          expect(
            xml.contains('@layout/$layout'),
            isTrue,
            reason: '$tag 档元数据必须指向 $layout',
          );
          expect(
            File('$_res/layout/$layout.xml').existsSync(),
            isTrue,
            reason: '缺少 $tag 档布局 $layout.xml',
          );
          expect(
            xml.contains(
              'android:description="@string/home_widget_${res}_${tag}_desc"',
            ),
            isTrue,
          );
          expect(
            xml.contains(
              'android:minHeight="${int.parse(tag.split('x')[1]) * 70 - 30}dp"',
            ),
            isTrue,
          );
        }
      }
    });

    test('格数换算与 targetCell 声明一致（cells*70-30，与元数据公式同源）', () {
      for (final metric in HomeWidgetMetric.values) {
        final res = resName(metric);
        for (final tag in _tags) {
          final parts = tag.split('x');
          final w = int.parse(parts[0]);
          final h = int.parse(parts[1]);
          final xml = read('$_res/xml/home_widget_${res}_${tag}_info.xml');
          expect(
            xml.contains('android:minWidth="${w * 70 - 30}dp"'),
            isTrue,
            reason: '$tag 档宽度应为 ${w * 70 - 30}dp',
          );
          expect(xml.contains('android:minHeight="${h * 70 - 30}dp"'), isTrue);
          expect(xml.contains('android:targetCellWidth="$w"'), isTrue);
          expect(xml.contains('android:targetCellHeight="$h"'), isTrue);
        }
      }
    });

    test('单值卡每档布局都有约定的 6 个 id（渲染器不分支取 id）', () {
      for (final tag in _tags) {
        final xml = read('$_res/layout/home_widget_metric_$tag.xml');
        for (final id in [
          'widget_root',
          'widget_icon',
          'widget_label',
          'widget_value',
          'widget_unit',
          'widget_sub1',
          'widget_sub2',
        ]) {
          expect(
            xml.contains('@+id/$id"'),
            isTrue,
            reason: 'home_widget_metric_$tag.xml 缺少 @+id/$id',
          );
        }
      }
    });

    test('1×2 已彻底退役（布局 / 元数据 / 清单都不再引用）', () {
      final files = [
        ...Directory('$_res/layout').listSync().whereType<File>(),
        ...Directory('$_res/xml').listSync().whereType<File>(),
        File('android/app/src/main/AndroidManifest.xml'),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync().contains('1x2') || file.path.contains('1x2'),
          isFalse,
          reason: '${file.path} 仍在引用已退役的 1×2 档',
        );
      }
    });
  });

  group('仪表盘小组件守卫（数据一览）', () {
    test('每档的格子 / 行 / 页脚与 WidgetSize 声明一致', () {
      for (final entry in _dashGrid.entries) {
        final tag = entry.key;
        final spec = entry.value;
        final xml = read('$_res/layout/home_widget_dashboard_$tag.xml');
        for (var i = 1; i <= spec.cells; i++) {
          expect(
            xml.contains('@+id/dash_cell$i"'),
            isTrue,
            reason: '$tag 缺 dash_cell$i',
          );
          expect(xml.contains('@+id/dash_cell${i}_label"'), isTrue);
          expect(xml.contains('@+id/dash_cell${i}_value"'), isTrue);
        }
        expect(
          xml.contains('@+id/dash_cell${spec.cells + 1}"'),
          isFalse,
          reason: '$tag 多出了第 ${spec.cells + 1} 格（原生只按 dashCells 取值）',
        );
        for (var r = 1; r <= spec.rows; r++) {
          expect(
            xml.contains('@+id/dash_row$r"'),
            isTrue,
            reason: '$tag 缺 dash_row$r',
          );
        }
        expect(xml.contains('@+id/dash_row${spec.rows + 1}"'), isFalse);
        expect(
          xml.contains('@+id/dash_message"'),
          isTrue,
          reason: '$tag 缺整卡空态 dash_message',
        );
        expect(
          xml.contains('@+id/dash_footer"'),
          spec.footer,
          reason: '$tag 的页脚存在性与声明不一致（渲染器只在声明有页脚时才碰它）',
        );
      }
    });

    test('原生 WidgetSize 的 dashCells / dashRows / dashFooter 与布局一致', () {
      final kt = read('$_kt/MetricWidgetProviders.kt');
      final re = RegExp(
        r'R\.layout\.home_widget_dashboard_(\w+),\s*'
        r'showSub1 = (\w+), showSub2 = (\w+), dashCells = (\d+), dashRows = (\d+), '
        r'dashFooter = (\w+),',
      );
      final found = <String, ({int cells, int rows, bool footer})>{};
      for (final m in re.allMatches(kt)) {
        found[m.group(1)!] = (
          cells: int.parse(m.group(4)!),
          rows: int.parse(m.group(5)!),
          footer: m.group(6) == 'true',
        );
      }
      expect(found.keys.toSet(), _tags.toSet(), reason: '八档都要声明仪表盘布局');
      for (final entry in _dashGrid.entries) {
        final declared = found[entry.key];
        expect(declared, isNotNull, reason: '${entry.key} 未声明');
        expect(
          declared!.cells,
          entry.value.cells,
          reason: '${entry.key} dashCells 漂移',
        );
        expect(
          declared.rows,
          entry.value.rows,
          reason: '${entry.key} dashRows 漂移',
        );
        expect(
          declared.footer,
          entry.value.footer,
          reason: '${entry.key} dashFooter 漂移',
        );
      }
    });

    test('渲染器按 ids 前缀取值（与布局命名约定绑定）', () {
      final renderer = read('$_kt/MetricWidgetRenderer.kt');
      for (final fragment in [
        r'"dash_cell${i}_label"',
        r'"dash_cell${i}_value"',
        r'"dash_cell$i"',
        r'"dash_row$row"',
        'R.id.dash_message',
        'R.id.dash_footer',
        'METRIC_DASHBOARD',
      ]) {
        expect(
          renderer.contains(fragment),
          isTrue,
          reason: '渲染器缺少 $fragment（布局 id 约定会漂移）',
        );
      }
    });

    test('数据一览的口径与首页面板同源（电费 / 校园网 / 加权 / 志愿 / 今日）', () {
      final sync = read('lib/features/home_widget/data/home_widget_sync.dart');
      for (final label in ["'电费'", "'校园网'", "'加权'", "'志愿'", "'今日'"]) {
        expect(sync.contains('add($label'), isTrue, reason: '仪表盘缺少 $label 格');
      }
      for (final provider in [
        'dashboardElectricityProvider',
        'netFeeSummaryProvider',
        'weightedGradeRankingProvider(1)',
        'dashboardVolunteerHoursProvider',
        'dashboardTodayCoursesProvider',
      ]) {
        expect(
          sync.contains(provider),
          isTrue,
          reason: '仪表盘应复用首页面板的 $provider（避免两处口径打架）',
        );
      }
    });
  });

  group('后台刷新入口点守卫（root library 约定）', () {
    const entryPoint = 'homeWidgetBackgroundMain';

    test('入口点定义在 root library（lib/main.dart）—— 否则引擎解析不到', () {
      final main = read('lib/main.dart');
      expect(
        main.contains('Future<void> $entryPoint()'),
        isTrue,
        reason:
            '命名入口点必须定义在 root library：DartEntrypoint 不指定 libraryUri 时，'
            'Flutter 只在 lib/main.dart 里查找（曾定义在子库 → 引擎报 '
            '"Could not resolve main entrypoint function." → 后台刷新静默失效）',
      );
    });

    test('原生 JobService 的入口点常量与 Dart 侧一致', () {
      final service = read('$_kt/WidgetRefreshJobService.kt');
      expect(service.contains('ENTRY_POINT = "$entryPoint"'), isTrue);
      expect(service.contains('FlutterEngineGroup'), isTrue);
      // Flutter 3.38 的嵌入层已移除回调句柄 API，必须用命名入口点。
      expect(service.contains('DartExecutor.DartEntrypoint'), isTrue);
    });

    test('后台刷新会合并更新仪表盘（不能只刷电费 / 成绩）', () {
      final bg = read(
        'lib/features/home_widget/data/home_widget_background.dart',
      );
      expect(bg.contains('_refreshDashboard('), isTrue);
      expect(bg.contains('HomeWidgetCell('), isTrue);
      // 后台 isolate 不碰 Hive：依赖本地缓存的格子只能沿用上次快照
      expect(bg.contains('prev['), isTrue);
    });
  });

  group('桌面「已在桌面」标记（pinnedCounts · 华为不自动新建页面）', () {
    test('pinKey 两端格式一致（Dart homeWidgetPinKey ↔ 原生 pinKey）', () {
      expect(
        homeWidgetPinKey(HomeWidgetMetric.electricity, '5x2'),
        'electricity:5x2',
      );
      expect(homeWidgetPinKey(HomeWidgetMetric.grades, '2x1'), 'grades:2x1');
      expect(
        homeWidgetPinKey(HomeWidgetMetric.dashboard, '2x2'),
        'dashboard:2x2',
      );
      final kt = read('$_kt/HomeWidgetBridge.kt');
      expect(
        kt.contains('metric + ":" + size.tag'),
        isTrue,
        reason:
            '原生 pinKey 必须保持显式拼接（守卫按这段原文匹配）：键格式一旦漂移，'
            '设置页的「已在桌面」徽章与落地检测会全部查不到',
      );
    });

    test('原生提供 pinnedCounts（getAppWidgetIds 计数），Dart 桥有对应调用', () {
      final kt = read('$_kt/HomeWidgetBridge.kt');
      expect(kt.contains('"pinnedCounts" ->'), isTrue);
      expect(kt.contains('manager.getAppWidgetIds('), isTrue);
      final bridge = read(
        'lib/features/home_widget/data/home_widget_bridge.dart',
      );
      expect(
        bridge.contains(
          "invokeMethod<Map<Object?, Object?>>('pinnedCounts')",
        ),
        isTrue,
      );
      expect(
        bridge.contains('static Future<Map<String, int>> pinnedCounts()'),
        isTrue,
      );
    });

    test('设置页用 pinnedCounts 画「已在桌面」标记，且刻意不做满页引导', () {
      final settings = read(
        'lib/features/settings/presentation/settings_screen.dart',
      );
      // 徽章与图例的数据全都来自原生「已绑定实例数」
      expect(settings.contains('HomeWidgetBridge.pinnedCounts()'), isTrue);
      expect(settings.contains('homeWidgetPinKey(metric, size)'), isTrue);
      expect(settings.contains('带 ✓ 的尺寸已经在桌面上'), isTrue);
      // 用户去桌面加/删小组件再回来要刷新标记
      expect(settings.contains('didChangeAppLifecycleState'), isTrue);
      // 用户 2026-09-11 裁定：不做满页引导 —— 取消确认框与桌面满页在代码里
      // 无法区分，自动弹层必然误报，宁可不要（华为也不触发 pin 的成功回调）。
      expect(
        settings.contains('_WidgetPinGuideSheet'),
        isFalse,
        reason: '满页引导已按用户要求移除，别再以任何形式加回来',
      );
      expect(settings.contains('桌面放不下'), isFalse);
    });
  });
}

/// 相对亮度（sRGB 近似，够用来判断「深底 vs 亮字」）。
double _luminance(String hexColor) {
  final hex = hexColor.replaceFirst('#', '');
  final rgb = hex.length == 8 ? hex.substring(2) : hex;
  final r = int.parse(rgb.substring(0, 2), radix: 16);
  final g = int.parse(rgb.substring(2, 4), radix: 16);
  final b = int.parse(rgb.substring(4, 6), radix: 16);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}
