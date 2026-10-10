// 开屏流光（蛟桥图书馆插画 + 流动光效）的守卫。
//
// 这组用例钉住四件事：
//   1. 资源真的在 `pubspec.yaml` 覆盖范围内、且宽高比与源图（1848×1336）一致；
//   2. 亮带**真的在动**、且会在有限的周期内扫完并留白（不匀速连扫、不空转）；
//   3. 三层绘制都在「图已解码 / 图未解码」两种状态下可画（不抛异常）；
//   4. 尺寸自适应不会算到溢出（宽高两重约束 + 上下限）。
//
// 上一版开屏是「主体建筑线条稿逐层生长」（splash_building_painter.dart /
// splash_building_stage.dart），用户 2026-10-08 裁定换成这一版，那两个文件
// 与它们那组几何守卫（原 splash_building_test.dart）一并删除 —— 想找回线条稿
// 口径请看 assets/images/splash/ 下留下的 SVG + geometry.json。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/splash/presentation/splash_flow_light_stage.dart';

/// 造一张真位图当开屏插画：左半边不透明（模拟建筑），右半边全透明（模拟透明底）。
Future<ui.Image> _fakeBuilding({int width = 40, int height = 30}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xFFEEE7DE),
  );
  return recorder.endRecording().toImage(width, height);
}

Future<ImageInfo> _fakeInfo() async => ImageInfo(image: await _fakeBuilding());

/// 一张**完全不透明**的位图。
///
/// 用来做「反向保险」：光效必须真的落在不透明处 —— 否则「透明处不许亮」
/// 那条守卫可以靠「什么都不画」假绿过去。
Future<ImageInfo> _opaqueInfo({int width = 40, int height = 30}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF6E6E6E),
  );
  return ImageInfo(image: await recorder.endRecording().toImage(width, height));
}

Future<void> _pumpStage(
  WidgetTester tester, {
  Duration period = const Duration(milliseconds: 1000),
  double width = 300,
  bool showTitle = true,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ThemeData(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SplashFlowLightStage(
            period: period,
            imageWidth: width,
            showTitle: showTitle,
          ),
        ),
      ),
    ),
  );
}

SplashFlowLightPainter _painterOf(WidgetTester tester) {
  for (final p in tester.widgetList<CustomPaint>(
    _insideStage(find.byType(CustomPaint)),
  )) {
    final painter = p.painter;
    if (painter is SplashFlowLightPainter) return painter;
  }
  fail('未找到 SplashFlowLightPainter（开屏流光没有挂上）');
}

/// 把查找范围收进 [SplashFlowLightStage] 子树。
///
/// ⚠ `MaterialApp` / `Scaffold` 自己也会挂 `FadeTransition`（路由转场）与
/// `CustomPaint`，全局 `find.byType` 会一次命中多个（实测 `Bad state: Too many
/// elements`），所以凡是要 `.single` / `getSize` 的查找一律先收范围。
Finder _insideStage(Finder of) =>
    find.descendant(of: find.byType(SplashFlowLightStage), matching: of);

/// 直接驱动画笔（不经过 widget），用来在可控的 progress 上验几何。
void _paintAt(
  double progress, {
  required ImageInfo info,
  Size size = const Size(300, 217),
  SplashFlowLightTone? tone,
}) {
  final recorder = ui.PictureRecorder();
  SplashFlowLightPainter(
    progress: progress,
    image: info,
    tone:
        tone ??
        const SplashFlowLightTone(
          shine: StatusPalette.splashShine,
          glow: Color(0xFFC3282E),
        ),
  ).paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

/// 把笔画到真位图上，取若干像素的 R 通道**相对底色的增量**。
///
/// [background] 传页面底（浅色 `0xFFFFFF` / 深色 `0x121212`），光效是加色，
/// 于是「角落比底色亮多少」就是这几笔在角落的总贡献。
Future<Map<String, int>> _cornerDelta(
  ImageInfo info, {
  required double progress,
  required int background,
  Size size = const Size(300, 217),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = Color(background));
  SplashFlowLightPainter(
    progress: progress,
    image: info,
    tone: const SplashFlowLightTone(
      shine: StatusPalette.splashShine,
      glow: Color(0xFFC3282E),
    ),
  ).paint(canvas, size);

  final picture = recorder.endRecording();
  final rendered = await picture.toImage(
    size.width.round(),
    size.height.round(),
  );
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  final int w = size.width.round();
  final int base = background == 0xFFFFFF ? 0xFF : 0x12;
  int delta(int x, int y) => bytes!.getUint8((y * w + x) * 4) - base;
  final Map<String, int> out = <String, int>{
    'leftTop': delta(2, 2),
    'rightTop': delta(w - 3, 2),
    'leftBottom': delta(2, size.height.round() - 3),
  };
  rendered.dispose();
  picture.dispose();
  return out;
}

/// 真素材解码结果（守卫要用「用户实际看到的那张图」量）。
Future<ImageInfo> _realInfo({int decodeWidth = 480}) async {
  final data = await rootBundle.load(SplashFlowLightStage.imageAsset);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(),
    targetWidth: decodeWidth,
  );
  return ImageInfo(image: (await codec.getNextFrame()).image);
}

/// 一帧渲染结果里，「透明区」与「楼体上」各采样点的**相对底色增量**。
typedef RealProbe = ({Map<String, int> transparent, Map<String, int> opaque});

/// 用真素材画一帧，然后分别在**透明区**与**楼体上**取点量增量。
///
/// 采样点按实图选（1848×1336 的裁切图：左右上角是透明底，底边是楼体基座）：
///   · 透明区：左上 / 右上 / 顶部中央偏左 —— 后两个会自动跳过不透明的点；
///   · 楼体上：屋檐、塔楼中部、基座。
/// 判据由调用方给（透明区 ≈ 0，楼体上 > 0）。
Future<RealProbe> _probeRealImage(
  ImageInfo info, {
  required double progress,
  required int background,
  Size size = const Size(300, 217),
}) async {
  // 先记下源图在这些点上的 alpha，用来把「透明区」与「楼体上」分开。
  final int sw = info.image.width;
  final int sh = info.image.height;
  final srcBytes = await info.image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  int srcAlpha(double u, double v) {
    final x = (u * (sw - 1)).round().clamp(0, sw - 1);
    final y = (v * (sh - 1)).round().clamp(0, sh - 1);
    return srcBytes!.getUint8((y * sw + x) * 4 + 3);
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = Color(background));
  SplashFlowLightPainter(
    progress: progress,
    image: info,
    tone: const SplashFlowLightTone(
      shine: StatusPalette.splashShine,
      glow: Color(0xFFC3282E),
    ),
  ).paint(canvas, size);

  final picture = recorder.endRecording();
  final rendered = await picture.toImage(
    size.width.round(),
    size.height.round(),
  );
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  final int w = size.width.round();
  final int h = size.height.round();
  final int base = background == 0xFFFFFF ? 0xFF : 0x12;
  int deltaAt(double u, double v) {
    final x = (u * (w - 1)).round().clamp(0, w - 1);
    final y = (v * (h - 1)).round().clamp(0, h - 1);
    return bytes!.getUint8((y * w + x) * 4) - base;
  }

  const Map<String, Offset> candidates = <String, Offset>{
    // 透明底（实图四角与上部两翼之间都是空的）
    '左上角': Offset(0.02, 0.02),
    '右上角': Offset(0.98, 0.02),
    '顶部中偏左': Offset(0.25, 0.02),
    '顶部中偏右': Offset(0.75, 0.02),
    // 楼体（塔楼 / 裙楼 / 基座，实图上是实心的）
    '塔楼中部': Offset(0.5, 0.35),
    '塔楼下部': Offset(0.45, 0.55),
    '裙楼左翼': Offset(0.2, 0.7),
    '裙楼右翼': Offset(0.8, 0.7),
    '基座': Offset(0.5, 0.93),
  };
  final transparent = <String, int>{};
  final opaque = <String, int>{};
  for (final entry in candidates.entries) {
    final int a = srcAlpha(entry.value.dx, entry.value.dy);
    // alpha ≤ 8 才算「透明底」，避免把抗锯齿边缘算进来。
    if (a <= 8) {
      transparent[entry.key] = deltaAt(entry.value.dx, entry.value.dy);
    } else {
      opaque[entry.key] = deltaAt(entry.value.dx, entry.value.dy);
    }
  }

  rendered.dispose();
  picture.dispose();
  return (transparent: transparent, opaque: opaque);
}

void main() {
  group('素材与比例', () {
    test('资源路径落在 pubspec 登记的 assets/images/splash/ 之下', () {
      expect(
        SplashFlowLightStage.imageAsset,
        startsWith('assets/images/splash/'),
        reason: 'pubspec 只登记了目录，路径必须落在该目录下才会被打进包',
      );
    });

    test('宽高比 = 源图 1848×1336', () {
      expect(SplashFlowLightStage.aspectRatio, closeTo(1848 / 1336, 1e-9));
      expect(
        SplashFlowLightStage.aspectRatio,
        greaterThan(1.0),
        reason: '源图是横构图',
      );
    });

    test('资产目录里真的有这张图', () async {
      final data = await rootBundle.load(SplashFlowLightStage.imageAsset);
      expect(data.lengthInBytes, greaterThan(1024));
      // PNG 魔数：确认不是被 LFS / 占位符替换成了文本。
      expect(
        data.buffer.asUint8List(0, 8),
        equals(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        reason: '开屏插画必须是真 PNG（透明底裁切）',
      );
    });
  });

  group('流光几何（亮带位置）', () {
    // bandPosition 的口径：`-0.25 - skew` = 含倾斜的角都在图左侧之外，
    // `1.25 + skew` = 含角都在右侧之外（0 = 图左边界，1 = 图右边界）。
    test('起点在图左之外、扫过图面、终点在右之外', () {
      expect(
        SplashFlowLightPainter.bandPosition(0),
        closeTo(-0.25 - SplashFlowLightPainter.bandSkew, 1e-9),
      );
      expect(
        SplashFlowLightPainter.bandPosition(
          SplashFlowLightPainter.sweepPortion / 2,
        ),
        closeTo(0.5, 0.01),
        reason:
            '扫程过半时亮带应落在图心附近。'
            '⚠ 刻意**不是** 1e-9 级精度：缓动用的 `Curves.easeInOutSine` 中点实测为 '
            '`0.50278319…`（偏 +0.28%），该曲线本来就微不对称，'
            '这点偏移在 520 逻辑像素上只有约 1 像素，肉眼不可见。',
      );
      expect(
        SplashFlowLightPainter.bandPosition(
          SplashFlowLightPainter.sweepPortion,
        ),
        closeTo(1.25 + SplashFlowLightPainter.bandSkew, 1e-9),
      );
    });

    test('扫程内单调推进（不回跳、不抖动）', () {
      double previous = SplashFlowLightPainter.bandPosition(0);
      for (
        double t = 0.02;
        t <= SplashFlowLightPainter.sweepPortion;
        t += 0.02
      ) {
        final current = SplashFlowLightPainter.bandPosition(t);
        expect(current, greaterThan(previous), reason: 't=$t 处亮带倒退了');
        previous = current;
      }
    });

    test('扫程尽头到周期结束是**留白**：亮带整条停在图外', () {
      for (
        double t = SplashFlowLightPainter.sweepPortion;
        t <= 1.0;
        t += 0.05
      ) {
        final band = SplashFlowLightPainter.bandPosition(t);
        expect(band, closeTo(1.25 + SplashFlowLightPainter.bandSkew, 1e-9));
        expect(
          band -
              SplashFlowLightPainter.bandWidth / 2 -
              SplashFlowLightPainter.bandSkew / 2,
          greaterThanOrEqualTo(1.0),
          reason: '留白段亮带最靠左的边也必须已越过图右边界（t=$t）',
        );
      }
    });

    test('★ 起步与收尾时，整条带子（含倾斜的角）都在图外', () {
      // ⚠ 回归守卫，两条历史教训都在这一条里：
      //   ① 早先用 `GradientRotation` 倾斜 → 绕 rect 中心旋转，细长带子的角会
      //      甩回画面（实测把左上角照亮到 104/255）；
      //   ② 改成几何倾斜后仍不够：只让到 `-bandWidth/2` 时，t≈0.1 处
      //      **左上角算到 +0.0274**，最淡的光尾会扫过左上角空白
      //      （实测深色底 +34 色阶）。所以端点必须再让出 bandSkew。
      double leftMost(double t) =>
          SplashFlowLightPainter.bandPosition(t) -
          SplashFlowLightPainter.bandWidth / 2 -
          SplashFlowLightPainter.bandSkew / 2;
      double rightMost(double t) =>
          SplashFlowLightPainter.bandPosition(t) +
          SplashFlowLightPainter.bandWidth / 2 +
          SplashFlowLightPainter.bandSkew / 2;

      // 起步：最靠左的边（底边）不得探进画面
      expect(
        leftMost(0),
        lessThanOrEqualTo(0.0),
        reason: 'bandPosition(0) 时整条带子必须完全在图左边界之外',
      );
      // 收尾：最靠右的边（顶边）不得探进画面
      expect(
        rightMost(SplashFlowLightPainter.sweepPortion),
        greaterThanOrEqualTo(1.0),
        reason: '扫程结束时整条带子必须完全在图右边界之外',
      );
      // ⚠ 关键的一条：扫程**前段**（带子刚起步那几帧）也不许有任何角探进来 ——
      // 这正是 t≈0.1 漏光的那一档。
      for (double t = 0.0; t <= 0.08; t += 0.01) {
        expect(
          leftMost(t),
          lessThanOrEqualTo(0.0),
          reason: 't=$t 时左上角已探进画面（历史 bug：深色底左上角被提亮 34 色阶）',
        );
      }
    });

    test('亮带斜率是「斜扫」而不是「竖扫」', () {
      expect(SplashFlowLightPainter.bandSkew, greaterThan(0.05));
      expect(
        SplashFlowLightPainter.bandSkew,
        lessThan(SplashFlowLightPainter.bandWidth / 2),
        reason: '倾斜量不该大到把带子扭成一道斜杠',
      );
    });

    test('亮带不会在图里停住不动超过一个周期（进度必须真的推进）', () {
      final samples = <double>[
        for (double t = 0; t <= SplashFlowLightPainter.sweepPortion; t += 0.1)
          SplashFlowLightPainter.bandPosition(t),
      ];
      expect(samples.toSet().length, samples.length, reason: '采样点应两两不同');
    });
  });

  group('绘制（图已解码）', () {
    late ImageInfo info;

    setUpAll(() async {
      info = await _fakeInfo();
    });

    tearDownAll(() => info.dispose());

    test('整个周期都能画出来，不抛异常', () {
      for (double t = 0; t <= 1.0; t += 0.05) {
        _paintAt(t, info: info);
      }
      expect(true, isTrue);
    });

    test('极小的画布也能画（不出现 NaN / 除零）', () {
      _paintAt(0.3, info: info, size: const Size(1, 1));
      _paintAt(0.3, info: info, size: const Size(0.5, 0.4));
    });

    test('零尺寸直接早退（布局尚未定尺时不会炸）', () {
      _paintAt(0.5, info: info, size: Size.zero);
    });

    test('★ 图透明的地方一个色阶都不许变（像素级回归 · 用户口径）', () async {
      // 用户 2026-10-08 原话：「我希望不是整个图都在闪光，因为是透明图，
      // 我希望只是非透明部分闪」—— 这条就是那个口径的守卫。
      //
      // ⚠ 用**真素材**量，不用合成图：合成图看不出真实透明边的行为
      // （探针实测合成全透明图会引入与真图无关的杂音）。
      // 采样点取自实图：四角是透明底，四角往内一点或底边是楼体本身。
      //
      // 它同时守两个踩过的坑：
      //   ① 亮带曾用 `GradientRotation` 倾斜 → 绕 rect 中心旋转，带子「扫出画面」
      //      之后四角横着甩回画面，左上角被照亮到 104/255（底色 18）；
      //   ② 光效曾用 `BlendMode.plus` 加色 —— 加色**不看目标**，图透明的地方照样亮。
      //      现在走 `BlendMode.screen`（滤色）：目标 alpha=0 → 结果恒为 0。
      final real = await _realInfo();
      addTearDown(real.dispose);

      for (final int background in <int>[0xFFFFFF, 0x121212]) {
        for (final double t in <double>[0.0, 0.1, 0.2, 0.3, 0.5, 0.58, 0.8]) {
          final probe = await _probeRealImage(
            real,
            progress: t,
            background: background,
          );
          for (final entry in probe.transparent.entries) {
            expect(
              entry.value,
              lessThanOrEqualTo(1),
              reason:
                  '底色 #${background.toRadixString(16)} 的透明区 ${entry.key} '
                  '在 t=$t 变了 ${entry.value} 个色阶 —— 图透明的地方不该有任何光',
            );
          }
        }
      }
    });

    test('★ 楼体必须真的被照亮（别把光效修没了）', () async {
      // 上一条的反向保险：如果谁把混合模式改成「什么都不画」，上一条会假绿。
      //
      // ⚠ 必须在**深色底**上量：楼体是浅色的（石材米白），而 `screen` 只会提亮
      // —— 浅色底（白）上它相对底色本来就是负增量（实测 -70），读数会看不出光。
      // 深色底下 `screen` 的提亮才是正数。
      final real = await _realInfo();
      addTearDown(real.dispose);

      final probe = await _probeRealImage(
        real,
        progress: 0.3,
        background: 0x121212,
      );
      expect(probe.opaque, isNotEmpty, reason: '采样点里必须有落在楼体上的');
      for (final entry in probe.opaque.entries) {
        expect(
          entry.value,
          greaterThan(0),
          reason: '深色底下 ${entry.key}（t=0.3 亮带扫过）应被照亮',
        );
      }
    });

    test('★ 图不透明的地方必须被照亮（别把光效修没了）', () async {
      // 上一条的反向保险：如果谁把混合模式改成「什么都不画」，上一条会假绿。
      final filled = await _opaqueInfo();
      addTearDown(filled.dispose);

      final atPeak = await _cornerDelta(
        filled,
        progress: 0.5,
        background: 0x121212,
      );
      for (final String corner in atPeak.keys) {
        expect(
          atPeak[corner]!,
          greaterThan(0),
          reason: '不透明的 $corner 在扫程过半（亮带正好在图心）时应被照亮',
        );
      }
    });

    test('shouldRepaint 只在输入真的变了时才重画', () {
      const tone = SplashFlowLightTone(
        shine: StatusPalette.splashShine,
        glow: Color(0xFFC3282E),
      );
      SplashFlowLightPainter at(double progress) =>
          SplashFlowLightPainter(progress: progress, image: info, tone: tone);

      expect(at(0.2).shouldRepaint(at(0.2)), isFalse);
      expect(at(0.2).shouldRepaint(at(0.3)), isTrue);
      expect(
        at(0.2).shouldRepaint(
          SplashFlowLightPainter(
            progress: 0.2,
            image: info,
            tone: const SplashFlowLightTone(
              shine: Color(0xFFFFFFFF),
              glow: Color(0xFFC3282E),
            ),
          ),
        ),
        isTrue,
        reason: '换色必须重画（深浅色切换）',
      );
    });
  });

  group('绘制（图还没解码完）', () {
    test('image 为 null 时直接早退：不画任何东西，也不抛异常', () {
      final recorder = ui.PictureRecorder();
      const SplashFlowLightPainter(
        progress: 0.4,
        image: null,
        tone: SplashFlowLightTone(
          shine: StatusPalette.splashShine,
          glow: Color(0xFFC3282E),
        ),
      ).paint(Canvas(recorder), const Size(300, 217));
      recorder.endRecording().dispose();
    });

    test('空位图（1×1 全透明）也能画：底色不参与 srcIn 裁剪时不会炸', () {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = const Color(0x00000000),
      );
      final image = recorder.endRecording().toImageSync(1, 1);
      final info = ImageInfo(image: image);
      for (double t = 0; t <= 1.0; t += 0.25) {
        _paintAt(t, info: info);
      }
      info.dispose();
    });
  });

  group('尺寸自适应（2026-10-10 = 纯比例 + PC 比例更小）', () {
    test('★ 宽度就是可用宽 × 比例，没有像素封顶', () {
      // 用户 2026-10-10 口径：「图片改用比例大小，而非固定大小」。
      // 之前夹在 110~300，900 与 1500 宽的窗口会算出同一个 300 —— 那不叫比例。
      for (final double w in <double>[
        320,
        390,
        768,
        900,
        1280,
        1500,
        1920,
        2560,
      ]) {
        for (final TargetPlatform p in <TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        ]) {
          final width = SplashFlowLightStage.responsiveWidth(
            w,
            availableHeight: w * 0.7,
            platform: p,
          );
          expect(
            width,
            closeTo(w * SplashFlowLightStage.widthRatioFor(p), 0.001),
            reason:
                '$p 可用宽 $w 时应得到 ${w * SplashFlowLightStage.widthRatioFor(p)}，'
                '不该被任何固定值截断',
          );
        }
      }
    });

    test('★ PC 端的比例必须比移动端小（用户 2026-10-10 要求）', () {
      expect(
        SplashFlowLightStage.widthRatioDesktop,
        lessThan(SplashFlowLightStage.widthRatioMobile),
      );
      // 三个桌面平台都算 PC
      for (final TargetPlatform p in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          SplashFlowLightStage.widthRatioFor(p),
          SplashFlowLightStage.widthRatioDesktop,
          reason: '$p 应判为桌面',
        );
      }
      // 移动端两个平台都算移动
      for (final TargetPlatform p in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          SplashFlowLightStage.widthRatioFor(p),
          SplashFlowLightStage.widthRatioMobile,
          reason: '$p 应判为移动端',
        );
      }
      // 同一个窗口宽度下，PC 的图必须更小
      double wOn(TargetPlatform p) => SplashFlowLightStage.responsiveWidth(
        1200,
        availableHeight: 800,
        platform: p,
      );
      expect(
        wOn(TargetPlatform.windows),
        lessThan(wOn(TargetPlatform.android)),
        reason: '同样 1200 宽的可用空间，PC 的主视觉必须比移动端小',
      );
    });

    test('默认取当前平台（不传 platform 时用 defaultTargetPlatform）', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final onWin = SplashFlowLightStage.responsiveWidth(
        1200,
        availableHeight: 800,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final onAndroid = SplashFlowLightStage.responsiveWidth(
        1200,
        availableHeight: 800,
      );
      expect(onWin, lessThan(onAndroid));
      expect(
        onWin,
        closeTo(1200 * SplashFlowLightStage.widthRatioDesktop, 0.001),
      );
      expect(
        onAndroid,
        closeTo(1200 * SplashFlowLightStage.widthRatioMobile, 0.001),
      );
    });

    test('★ 更宽的窗口必须得到更大的图（比例的意义）', () {
      double widthAt(double w, TargetPlatform p) =>
          SplashFlowLightStage.responsiveWidth(
            w,
            availableHeight: w * 0.7,
            platform: p,
          );
      // 这条就是「900 与 1500 一样大」那个坑的回归守卫。
      expect(
        widthAt(1500, TargetPlatform.windows),
        greaterThan(widthAt(900, TargetPlatform.windows)),
      );
      expect(
        widthAt(900, TargetPlatform.windows),
        greaterThan(widthAt(390, TargetPlatform.windows)),
      );
      // 两倍宽 → 两倍图
      expect(
        widthAt(1800, TargetPlatform.windows) /
            widthAt(900, TargetPlatform.windows),
        closeTo(2, 0.001),
      );
    });

    test('手机宽度 → 屏宽的 41%', () {
      expect(
        SplashFlowLightStage.responsiveWidth(390, availableHeight: 844),
        closeTo(390 * SplashFlowLightStage.widthRatio, 0.001),
      );
    });

    test('窄得离谱也要给两侧留边（不贴屏幕边）', () {
      const double w = 120;
      final width = SplashFlowLightStage.responsiveWidth(
        w,
        availableHeight: 800,
      );
      expect(width, lessThanOrEqualTo(w - 32));
    });

    test('矮窗口由高度反算（宽而扁时图不竖向溢出）', () {
      // 高 300、显示标题 → 预算 = 300 − titleReserveHeight，宽 = 预算 × 比例。
      final width = SplashFlowLightStage.responsiveWidth(
        1920,
        availableHeight: 300,
        showTitle: true,
      );
      final budget = 300 - SplashFlowLightStage.titleReserveHeight;
      expect(width, closeTo(budget * SplashFlowLightStage.aspectRatio, 0.001));
      expect(
        width / SplashFlowLightStage.aspectRatio +
            SplashFlowLightStage.titleReserveHeight,
        lessThanOrEqualTo(300.5),
        reason: '图高 + 标题预留必须装得进可用高度',
      );
    });

    test('不显示标题时高度预算更宽松（同一窗口下能画得更大）', () {
      expect(
        SplashFlowLightStage.bodyReserveHeight,
        lessThan(SplashFlowLightStage.titleReserveHeight),
        reason: '不显示标题时必须少留空间，否则高度预算白扣',
      );
      const double h = 300;
      final withTitle = SplashFlowLightStage.responsiveWidth(
        1920,
        availableHeight: h,
        showTitle: true,
      );
      final withoutTitle = SplashFlowLightStage.responsiveWidth(
        1920,
        availableHeight: h,
        showTitle: false,
      );
      expect(withoutTitle, greaterThanOrEqualTo(withTitle));
    });

    test('极窄窗口：比例值本身就够小，留边约束兜底', () {
      // 120 宽：0.41×120 = 49.2，小于留边上限 120−32=88 ⇒ **49.2**（比例说了算）
      expect(
        SplashFlowLightStage.responsiveWidth(120, availableHeight: 200),
        closeTo(120 * SplashFlowLightStage.widthRatio, 0.001),
        reason: '纯比例口径下，极窄窗口也按比例缩，不再有像素下限把它抬回去。',
      );
      // 留边仍是硬约束：可用宽再小也只给 `可用宽 − 2×sidePadding`
      expect(
        SplashFlowLightStage.responsiveWidth(30, availableHeight: 200),
        lessThanOrEqualTo(30),
        reason: '装不下时让位给边距，绝不溢出。',
      );
      expect(
        SplashFlowLightStage.responsiveWidth(600, availableHeight: 40),
        greaterThanOrEqualTo(0),
        reason: '高度极扁时不再硬托底，但也不该算出 NaN / 负数',
      );
    });

    test('任何输入都给出有限、非负、且不超过可用宽度的值', () {
      for (final double w in <double>[0, 50, 320, 414, 1024, 3840]) {
        for (final double h in <double>[0, 120, 640, 2160]) {
          final width = SplashFlowLightStage.responsiveWidth(
            w,
            availableHeight: h,
          );
          expect(width.isFinite, isTrue, reason: 'w=$w h=$h 算出了非有限值');
          expect(width, greaterThanOrEqualTo(0), reason: 'w=$w h=$h 算出了负值');
          expect(width, lessThanOrEqualTo(w), reason: 'w=$w h=$h 超出了可用宽度');
          // 只做防溢出，不做像素封顶：宽度绝不该超过比例值
          expect(
            width,
            lessThanOrEqualTo(w * SplashFlowLightStage.widthRatio + 0.001),
            reason: 'w=$w h=$h 超过了比例值（说明又被夹取了）',
          );
        }
      }
    });
  });

  group('动画驱动（widget 层）', () {
    testWidgets('挂载即开始播放，进度单调推进并循环', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 1000));
      await tester.pump();
      final first = _painterOf(tester).progress;
      expect(first, lessThan(0.3), reason: '首帧应几乎为 0');

      await tester.pump(const Duration(milliseconds: 300));
      final mid = _painterOf(tester).progress;
      expect(mid, greaterThan(first));

      await tester.pump(const Duration(milliseconds: 300));
      expect(_painterOf(tester).progress, greaterThan(mid));
    });

    testWidgets('一个周期后回到起点（循环，不是播完就停）', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(_painterOf(tester).progress, lessThan(0.3));
      // 再走一圈仍然在动
      await tester.pump(const Duration(milliseconds: 400));
      expect(_painterOf(tester).progress, greaterThan(0.3));
    });

    testWidgets('一直挂着不抛异常（长开屏也不炸）', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 400));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('画布尺寸按传入宽度与原图比例联动', (tester) async {
      await _pumpStage(tester, width: 200);
      final paints = _insideStage(find.byType(CustomPaint));
      expect(paints, findsOneWidget, reason: '开屏只该有一块自绘画布');
      final size = tester.getSize(paints);
      expect(size.width, closeTo(200, 0.5));
      expect(size.height, closeTo(200 / SplashFlowLightStage.aspectRatio, 0.5));
    });

    testWidgets('改周期立刻按新速度走（设置页预览那种用法）', (tester) async {
      // ⚠ 不断言「归零」：实测 `AnimationController.repeat()` **不重置 value**
      // （把当前值当相位锚点重排 simulation），所以改周期后首帧仍是旧进度。
      // 用户真正要的是「速度当场变」，那就量**推进速率**。
      await _pumpStage(tester, period: const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 300));
      final fastStart = _painterOf(tester).progress;
      await tester.pump(const Duration(milliseconds: 100));
      final fastDelta = _painterOf(tester).progress - fastStart;
      expect(
        fastDelta,
        closeTo(0.1, 0.02),
        reason: '1000ms 周期下 100ms 应推进约 1/10 个周期',
      );

      await _pumpStage(tester, period: const Duration(milliseconds: 6000));
      await tester.pump();
      final slowStart = _painterOf(tester).progress;
      await tester.pump(const Duration(milliseconds: 100));
      final slowDelta = _painterOf(tester).progress - slowStart;
      expect(slowDelta, lessThan(fastDelta / 2), reason: '换成 6 倍周期后必须明显变慢');
      expect(slowDelta, closeTo(100 / 6000, 0.01));
    });

    testWidgets('扫程内进度单调推进（一个周期内不回跳）', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 1000));
      await tester.pump();
      double previous = _painterOf(tester).progress;
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final current = _painterOf(tester).progress;
        expect(current, greaterThan(previous), reason: '第 $i 步进度倒退了');
        expect(current, lessThan(1.0), reason: '8×100ms 仍在第一个周期之内');
        previous = current;
      }
    });

    testWidgets('图取不到时退化成「只有标题」，不白屏也不崩', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SplashFlowLightStage(
                period: Duration(milliseconds: 400),
                imageWidth: 200,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      // widget 测试的 rootBundle 拿不到真资产 → 走 onError 分支，
      // 此时仍应有应用名与副标题，且没有未捕获异常。
      expect(find.text('智慧er江财'), findsOneWidget);
      expect(find.text('江西财经大学校园服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('标题', () {
    testWidgets('默认显示应用名 + 副标题', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('智慧er江财'), findsOneWidget);
      expect(find.text('江西财经大学校园服务'), findsOneWidget);
    });

    testWidgets('showTitle: false 时只留插画', (tester) async {
      await _pumpStage(
        tester,
        period: const Duration(milliseconds: 300),
        showTitle: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('智慧er江财'), findsNothing);
      // 副标题仍在（它是「校园服务」的说明，不属于应用名）
      expect(find.text('江西财经大学校园服务'), findsOneWidget);
    });

    testWidgets('标题是淡入的（首帧不透明度接近 0）', (tester) async {
      await _pumpStage(tester, period: const Duration(milliseconds: 2000));
      await tester.pump();
      final fade = _insideStage(find.byType(FadeTransition));
      expect(fade, findsOneWidget, reason: '标题那层淡入只该有一处');
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(0.2));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        greaterThan(0.9),
      );
    });
  });

  group('深色主题', () {
    testWidgets('深色下用主题色绘制，不抛异常', (tester) async {
      await _pumpStage(
        tester,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final painter = _painterOf(tester);
      // 掠光刻意**不随主题反相**（位图本身是彩色、不反相），
      // 只有辉光 / 地面影跟主题走。
      expect(painter.tone.shine, StatusPalette.splashShine);
      expect(painter.tone.glow, isNot(painter.tone.shine));
      expect(tester.takeException(), isNull);
    });
  });
}
