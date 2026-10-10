import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/status_palette.dart';

/// 开屏光效的两支颜色（由 [SplashFlowLightStage] 从主题里取好再传给画笔，
/// 画笔本身不碰 `BuildContext`）。
@immutable
class SplashFlowLightTone {
  const SplashFlowLightTone({required this.shine, required this.glow});

  /// 掠光的本色（峰值处再乘 `SplashFlowLightPainter.peakAlpha`）。
  final Color shine;

  /// 楼体上那团呼吸辉光的本色。
  final Color glow;

  @override
  bool operator ==(Object other) =>
      other is SplashFlowLightTone &&
      other.shine == shine &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(shine, glow);
}

/// 开屏主视觉：**蛟桥图书馆插画 + 一道反复横掠的流光**。
///
/// 用户 2026-10-08 定稿（原话：「我希望就是在加载页面中心显示一个（图）片，
/// 上有流动光效动画」）—— 取代此前「主体建筑线条稿逐层生长」
/// （`splash_building_painter.dart` / `splash_building_stage.dart`，随本轮删除）。
///
/// ## 光效怎么做的（同一个 [AnimationController] 驱动）
/// 1. **掠光**（主效果）＝ 一道倾斜的窄亮带（平行四边形），横掠楼体。
/// 2. **辉光** ＝ 中心三笔同色径向渐变，随周期呼吸。
///
/// 两道光合在**一个图层**里画，再用**位图自己的 alpha** 收口 —— 图透明的地方
/// 一个字节都不留。这是用户 2026-10-08 口径「只让非透明部分闪」的实现，
/// 细节与踩坑见 [SplashFlowLightPainter] 的注释。
///
/// ## 节奏（刻意不是匀速循环）
/// 一个周期 2.6s：亮带在前 58% 从左侧屏外扫到右侧屏外，后 42% 是**留白**——
/// 建筑在全亮状态下停一拍再扫下一道。匀速连扫会像加载条，**停一拍才像光在流**。
///
/// ## 深浅色
/// 位图自带配色（石材米白 + 校红瓦），**不随主题反相**；只有辉光跟主题走
/// （`colorScheme.primary`），掠光本色 [StatusPalette.splashShine] 刻意恒定。
/// 所以深色页面下这是「一张明亮的画浮在深底上」—— 有意为之：
/// 开屏主视觉的价值就在这张图本身。
class SplashFlowLightStage extends StatefulWidget {
  const SplashFlowLightStage({
    super.key,
    this.imageWidth = 360,
    this.showTitle = true,
    this.period = const Duration(milliseconds: 2600),
  });

  /// 位图显示宽度（高度按 [aspectRatio] 联动）。
  ///
  /// 开屏页用 [responsiveWidth] 按可用空间算好再传进来。
  final double imageWidth;

  /// 位图宽高比（源图 1848×1336）。
  static const double aspectRatio = 1848 / 1336;

  /// 源图（透明底裁切，`design/蛟桥图书馆图片/svg导出_透明底_裁切.png` 的副本）。
  static const String imageAsset = 'assets/images/splash/library_shine.png';

  /// [responsiveWidth] 在「显示标题」时预留的竖向空间。
  ///
  /// = 标题两块（约 28 + 6 + 16）+ 与图之间的 20 间距 + 上下各一点余量。
  /// 是公开常量而不是内联字面量：守卫要拿它算「图高 + 预留装不装得进可用高度」，
  /// 内联的话改了这里、测试还按旧值断言（2026-10-08 改 96→104 时真被绊了一次）。
  static const double titleReserveHeight = 104;

  /// [responsiveWidth] 在不显示标题时预留的竖向空间（只留底边距）。
  static const double bodyReserveHeight = 32;

  /// 主视觉宽度占**可用宽度**的比例 —— **移动端**。
  ///
  /// ⚠ 2026-10-10 用户口径：**「图片改用比例大小，而非固定大小」** ——
  /// 所以**没有**像素级的 min/max 夹取（曾经夹在 110~300，导致 900 与 1500 宽的
  /// 窗口算出同一个 300，看着像没适配）。现在只有比例，加上「高度」
  /// 与「两侧留边」两条防溢出约束 —— 宽度是多少，图就按比例跟着变。
  static const double widthRatioMobile = 0.41;

  /// 主视觉宽度占**可用宽度**的比例 —— **桌面 / PC**。
  ///
  /// ⚠ 用户 2026-10-10 追加：「**PC 端的比例要比移动端小**」。
  /// 桌面窗口本来就宽得多，同一个比例算出来的绝对尺寸会大得离谱
  /// （41% × 1920 = 787 逻辑像素，占掉小半个屏幕），而且桌面还有自绘标题栏
  /// 压掉 40 高。所以桌面单独给一个更小的比例。
  static const double widthRatioDesktop = 0.30;

  /// 按平台取比例。
  ///
  /// 判据用 `defaultTargetPlatform`（桌面 = Windows / macOS / Linux，其余算移动端），
  /// **不用** `Theme.platform` —— 后者要求有 `BuildContext`，而本函数是纯静态计算，
  /// 守卫直接调它做断言（测试里用 `debugDefaultTargetPlatformOverride` 切平台）。
  static double widthRatioFor(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => widthRatioDesktop,
    _ => widthRatioMobile,
  };

  /// 当前平台的宽度比例。
  static double get widthRatio => widthRatioFor(defaultTargetPlatform);

  /// 两侧至少留出的边距（防贴边 / 防溢出用的硬约束，不参与比例）。
  static const double sidePadding = 16;

  /// 一个流光周期的时长。
  final Duration period;

  /// 是否在插画下方显示应用名。
  final bool showTitle;

  /// 按可用空间算主视觉宽度。
  ///
  /// 口径（2026-10-10 定稿）：
  ///   1. `可用宽 × 当前平台比例`（移动 [widthRatioMobile] 0.41 / 桌面 [widthRatioDesktop] 0.30）；
  ///   2. 受**高度**约束：宽而矮的窗口（桌面把窗口拖扁）不能把图竖向撑爆 ——
  ///      高度预算 = 可用高 − [titleReserveHeight]（或 [bodyReserveHeight]），
  ///      再按 [aspectRatio] 反算成宽度；
  ///   3. 受**两侧留边**约束：最多 `可用宽 − 2×sidePadding`。
  ///
  /// 即「比例优先，只做防溢出」，**不做像素区间夹取**。实测（桌面比例 0.30）：
  ///   · 手机 390×844 → 160（41%）
  ///   · 小窗 900×650 → 270（30%）
  ///   · 大窗 1500×950 → 450（30%）
  static double responsiveWidth(
    double available, {
    double availableHeight = double.infinity,
    bool showTitle = true,
    TargetPlatform? platform,
  }) {
    final double reservedHeight = showTitle
        ? titleReserveHeight
        : bodyReserveHeight;
    double width = available * widthRatioFor(platform ?? defaultTargetPlatform);
    final double heightBudget = availableHeight - reservedHeight;
    if (heightBudget.isFinite) {
      width = math.min(width, heightBudget * aspectRatio);
    }
    // 留边是硬约束：宁可画得更小（极端情况下 0），也绝不贴边 / 溢出。
    return math.max(0, math.min(width, available - sidePadding * 2));
  }

  @override
  State<SplashFlowLightStage> createState() => _SplashFlowLightStageState();
}

class _SplashFlowLightStageState extends State<SplashFlowLightStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  /// 已解码的位图；首帧尚未解码完时为 null（那时只画标题，不画光效）。
  ImageInfo? _image;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant SplashFlowLightStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      // 换周期 = 换 `duration` 再重新 `repeat()`，动画**立刻按新速度**走。
      //
      // ⚠ 实测口径（别照直觉改，2026-10-08 探针实测）：`repeat()` **不会把 value 归零**
      // —— 它是把当前值当相位锚点重排 `_RepeatingSimulation`。所以换周期后的首帧仍会
      // 短暂显示上一个周期的进度（0.7 → 0.7），下一帧起就完全按新 `duration` 推进。
      // 开屏页从不改 period（只有设置页预览那种用法会），这个一帧的交错不必强行抹平；
      // 真要「重头播」得显式 `..value = 0` 或 `forward(from: 0)`。
      _controller
        ..duration = widget.period
        ..repeat();
    }
    // 宽度变了 → 解码目标跟着变，重新取一张，避免放大后发虚。
    if (oldWidget.imageWidth != widget.imageWidth) _resolveImage();
  }

  /// 按显示宽度取图。
  ///
  /// ⚠ 不直接用 `Image.asset` 全解：源图 1848×1336 解出来约 9.9 MB 像素，
  /// 而开屏最多画到 520 逻辑像素宽 —— 按 1.6 倍留出高 DPI 余量即可。
  void _resolveImage() {
    final provider = ResizeImage(
      const AssetImage(SplashFlowLightStage.imageAsset),
      width: (widget.imageWidth * 1.6).round(),
    );
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!mounted) {
          info.dispose();
          return;
        }
        final previous = _image;
        setState(() => _image = info);
        previous?.dispose();
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        // 图取不到就退化成「只有标题」的开屏 —— 开屏页不该因为一张图白屏。
        assert(() {
          debugPrint('开屏插画加载失败：$error');
          return true;
        }());
      },
    );
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = widget.imageWidth;
    final tone = SplashFlowLightTone(
      shine: StatusPalette.splashShine,
      glow: scheme.primary,
    );

    // 标题比流光晚一拍浮现（周期后 70%）。
    final titleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => SizedBox(
              width: width,
              height: width / SplashFlowLightStage.aspectRatio,
              child: CustomPaint(
                painter: SplashFlowLightPainter(
                  progress: _controller.value,
                  image: _image,
                  tone: tone,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeTransition(
          opacity: titleFade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showTitle)
                Text(
                  '智慧er江财',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                '江西财经大学校园服务',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 流光画笔：位图 + 掠光 + 辉光（两道光都裁在剪影内）。
///
/// ## ⚠ 三条「不许」—— 都踩过，记在这里免得再走一遍
///
/// **① 不能用 `srcIn` 做剪影遮罩。** 曾经的做法是「`saveLayer` 里先画图，
/// 再用 `srcIn` 把渐变裁进剪影」。`srcIn` 的语义是「用源的 alpha **替换**目标」，
/// 于是**渐变透明的地方（亮带两侧、辉光半径之外）会把建筑整块擦掉** ——
/// 建筑只剩一道幽灵轮廓，辉光强时更会整幅糊成白雾（实测产物
/// `A_image_shine.png` / `C_image_both.png`）。要收口请用 `dstIn`（乘 alpha）。
///
/// **② 不能只靠 `plus` 加色。** 加色是**不看目标**的：源色无条件加到画布上，
/// 于是图**透明的地方**（透明底 + 四角）照样被照亮 —— 用户 2026-10-08 原话
/// 「我希望不是整个图都在闪光，因为是透明图，我希望只是非透明部分闪」。
///
/// **③ 也不能只靠 `screen`。** 滤色 `result = src + dst − src·dst` 在 alpha 上
/// 是**相乘**关系，目标透明（预乘色为 0）时结果恒为 0 —— 比 `plus` 好，
/// **但它只管「目标 alpha=0」，管不住「源该不该出现在这儿」**：
/// 亮带有半幅图宽还带渐隐尾、辉光是一张铺满画布的径向渐变，它们的边缘
/// **必然扫过透明区**。实测：只剩 `screen` 时深色底左上角在 t=0.2 被提亮
/// **18 色阶**、t=0.1 被提亮 34 个。最终口径见 [_paintLight] 的「先裁后合」。
class SplashFlowLightPainter extends CustomPainter {
  const SplashFlowLightPainter({
    required this.progress,
    required this.image,
    required this.tone,
  });

  /// 0 → 1 循环。**不是**亮带位置 —— 位置由 [bandPosition] 换算。
  final double progress;

  /// 已解码的建筑位图；为 null 时不画任何东西（图还没解码完的第一帧）。
  final ImageInfo? image;

  final SplashFlowLightTone tone;

  /// 掠光峰值处的不透明度（图层内 `screen` 的加色量）。
  ///
  /// ⚠ 这个值必须给得**高**（2026-10-08 实测教训）：石材面本身就接近白
  /// （实测 R≈229/255），而 `screen` 只能把像素往 255 推 —— 可用余量只有 26 个
  /// 色阶。峰 alpha 给 0.32 时楼体上只亮 **+1~6 色阶**，肉眼完全看不出「光在流」
  /// （行扫描实测：留白段 229，亮带正中 235）。
  /// 给到 0.85 才能让扫过处真的接近过曝成一道亮痕 —— 那才是「反光扫过石材」。
  /// 别按「这是个淡淡的亮带」的直觉往下调，那会直接调成看不见。
  static const double peakAlpha = 0.85;

  /// 亮带宽度占整幅图宽的比例。
  static const double bandWidth = 0.5;

  /// 亮带的倾斜量（顶边相对底边右移的比例，占整幅图宽）。
  ///
  /// 竖直扫会像进度条，斜扫才像玻璃 / 石材上的反光；0.15 在 520 宽的图上约 78 像素，
  /// 斜得看得出来又不至于像「一道斜杠」。
  static const double bandSkew = 0.15;

  /// 亮带走完全程所占的周期比例；剩下的时间是留白（见类注释「节奏」）。
  static const double sweepPortion = 0.58;

  /// 辉光呼吸的峰值 alpha（按最外那笔算；另两笔再乘 0.55 / 0.40）。
  static const double glowPeakAlpha = 0.20;

  /// 亮带的归一化位置：`-0.30` = 连**倾斜的角**都在图左侧之外，
  /// `1.30` = 连最靠右的角都在图右侧之外。（0 = 图左边界，1 = 图右边界。）
  ///
  /// ⚠ 行程端点必须比「`-bandWidth/2`」再多让出 [bandSkew]（2026-10-08 实测踩过）：
  /// 带子是斜的，**顶边比中心右移 `bandSkew/2`**。若只让到 `-0.25`，那么
  /// 中心走到 `-0.1476`（t≈0.1）时左上角就是 `-0.1476 - 0.25 + 0.075 = +0.0274`
  /// —— 已经**探进画面**，那一丝最淡的光尾会扫过左上角的空白
  /// （实测深色底左上角被提亮 34 个色阶，而真正的空白应当纹丝不动）。
  /// 放宽一个 [bandSkew] 之后，起步与收尾都保证「整条带子含角都在图外」。
  ///
  /// [progress] 超过 [sweepPortion] 后**钉在 `1.25 + bandSkew`**（屏外），
  /// 于是那段时间里图上没有任何亮带 —— 这就是「停一拍」。
  static double bandPosition(double progress) {
    const double start = -0.25 - bandSkew;
    const double end = 1.25 + bandSkew;
    final double phase = progress / sweepPortion;
    if (phase >= 1) return end;
    // 缓入缓出：起手不突兀、收尾不戛然而止。
    return start + (end - start) * Curves.easeInOutSine.transform(phase);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final info = image;
    if (info == null || size.width <= 0 || size.height <= 0) return;

    // 顺序即图层：建筑 → 两道光效（整体裁在剪影内）。
    //
    // ⚠ **没有地面影**：曾有一笔椭圆影让插画「落在地上」，但它必然画在页面底上
    // （图透明处也要有影才像影子），与用户「只让非透明部分闪」的口径冲突，
    // 2026-10-08 已删。想加回来必须先想清楚这条口径怎么共存。
    final Rect rect = Offset.zero & size;
    _paintImage(canvas, info, rect);
    _paintLight(canvas, size, info, rect);
  }

  /// 两道光效（辉光 + 掠光）画进一个图层，用位图 alpha 收口后再 [BlendMode.screen]
  /// 合成回画布。
  ///
  /// ⚠ 这是「只让非透明部分闪」的**唯一可靠实现**（用户 2026-10-08 口径）：
  /// `BlendMode.screen` 只保证「目标 alpha=0 时不动它」，**管不住形状** ——
  /// 亮带有半幅图宽、还带渐隐尾，它的边缘必然会扫过透明区；辉光更是一张
  /// 铺满画布的径向渐变。实测：只剩 screen 时，深色底左上角在 t=0.2 被提亮
  /// **18 个色阶**、t=0.1 被提亮 34 个（那还是修掉 `GradientRotation` 之后）。
  ///
  /// 做法 = 「**先裁后合**」：
  ///   ① `saveLayer` 开一个**透明**图层（默认 srcOver）；
  ///   ② 图层内画两道光（`screen`，保住「提亮而不是覆盖」的观感）；
  ///   ③ `dstIn` + 位图 alpha 把「图透明处」从图层里删掉；
  ///   ④ 弹层时用 `screen` 合成回画布 —— **screen 不碰 alpha**，所以裁好的
  ///      「空白全透明」在合成后依然是空白全透明。
  ///
  /// ⚠ 上一版在这里多铺了一层不透明白（想用 dstIn 把 alpha 抬满再乘），
  /// 那是错的：`dstIn` 是**乘** alpha，铺白之后 alpha 恒为 1，乘完只剩位图 alpha，
  /// 光本身的强弱被抹平 —— 实测楼体上几乎看不到亮带。别再加那层白。
  void _paintLight(Canvas canvas, Size size, ImageInfo info, Rect rect) {
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.screen);
    _paintGlow(canvas, size);
    _paintShine(canvas, size);
    _maskToImage(canvas, info, rect);
    canvas.restore();
  }

  /// 把当前图层按位图 alpha 收口：`dstIn` × 位图 alpha，图透明处一律归零。
  ///
  /// ⚠ 不用 `srcIn` 直接画位图：它的 RGB 会覆盖图层颜色通道，空白处会残留
  /// `RGBA(1,0,0,2)` 这种「alpha 归零但颜色带红」的像素。
  void _maskToImage(Canvas canvas, ImageInfo info, Rect rect) {
    canvas.drawImageRect(
      info.image,
      Rect.fromLTWH(
        0,
        0,
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      ),
      rect,
      Paint()
        ..filterQuality = FilterQuality.none
        ..blendMode = BlendMode.dstIn,
    );
  }

  void _paintImage(Canvas canvas, ImageInfo info, Rect rect) {
    canvas.drawImageRect(
      info.image,
      Rect.fromLTWH(
        0,
        0,
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      ),
      rect,
      // ⚠ 插值滤波器必须是 `none`，不能用 `medium`/`high`（2026-10-08 实测）：
      // 源图是一张**大片透明底**的插画，双三次类滤波（medium = Mitchell）会在
      // 「完全不透明」与「完全透明」的边界上过冲，把大片 alpha=0 的区域滤成
      // `RGBA(1,0,0,2)` 这种「几乎全透明但有色」的像素；本页把源图放大到
      // 300~520 逻辑像素宽（×7.5 上下）之后，这些像素被摊开成肉眼可见的**灰蒙层**
      // —— 正好违背用户「只让非透明部分闪」的要求（实测白底四角从 255 掉到 1）。
      //
      // 用 `none` 的代价是缩小时有轻微锯齿；但 `decodeWidth = 显示宽 × 1.6`
      // 已经把缩放比压在 1.6 倍以内，且画面是矢量感的扁平插画（边缘本来就硬），
      // 锯齿不可见 —— 而「透明处必须真的透明」是硬要求。
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// 斜向亮带：位置由 [bandPosition] 给，倾斜由 [bandSkew] 直接**做成平行四边形**，
  /// 而不是给渐变加 `GradientRotation`。
  ///
  /// ⚠ 为什么不用 `GradientRotation`（2026-10-08 实测踩过）：`GradientRotation` 绕
  /// **rect 中心**旋转，一个 `(-260, 0, 260, 376)` 的细长竖带转过 π/7 之后，
  /// 四角横向甩到 `-328.7 … +68.7` —— 于是「亮带已经扫出图外」的留白段里，
  /// 它**又横着探回画面**，把左上角照亮（实测角落像素 18 → 104）。
  /// 几何自己倾斜就完全没有这个副作用：带子始终是那个平行四边形，扫出去就是扫出去了。
  ///
  /// 画进 [_paintLight] 的图层里并用 [BlendMode.screen]：提亮而不是覆盖，
  /// 带子两端渐隐到 0 —— `screen(x, 0) = x`，所以渐隐处等于没画。
  /// 「不许它落在空白上」由图层收口负责（见 [_paintLight]），不靠混合模式。
  void _paintShine(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double left = (bandPosition(progress) - bandWidth / 2) * w;
    final double bandW = bandWidth * w;
    final double skew = bandSkew * w;
    // 上下各多出 `skew` 的高度：倾斜会让顶边右移、底边左移，多出来的部分正好补上。
    final Rect area = Rect.fromLTRB(left, -skew, left + bandW, h + skew);

    final Color base = tone.shine;
    final shader = LinearGradient(
      colors: [
        base.withValues(alpha: 0),
        base.withValues(alpha: peakAlpha * 0.45),
        base.withValues(alpha: peakAlpha),
        base.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.42, 0.62, 1.0],
    ).createShader(area);

    // 平行四边形：上边右移 skew/2，下边左移 skew/2（即整条带子斜着立着）。
    final Path band = Path()
      ..moveTo(left + skew / 2, -skew)
      ..lineTo(left + bandW + skew / 2, -skew)
      ..lineTo(left + bandW - skew / 2, h + skew)
      ..lineTo(left - skew / 2, h + skew)
      ..close();

    canvas.drawPath(
      band,
      Paint()
        // `screen`：透明处不发光、建筑上正常提亮（口径见类注释 ②）。
        ..blendMode = BlendMode.screen
        ..shader = shader,
    );
  }

  /// 中心辉光：随周期呼吸（一个周期一次明暗），叠在楼体上做「亮部呼吸」。
  ///
  /// 这里只管画；「裁进剪影」由 [_paintLight] 的图层收口统一负责
  /// （口径与实测见该方法的注释）。
  void _paintGlow(Canvas canvas, Size size) {
    // 1 → 0 → 1：亮带扫过图心时辉光最盛，留白段里慢慢收。
    final double breath = 0.5 + 0.5 * math.cos(progress * 2 * math.pi);
    final double alpha = glowPeakAlpha * breath;
    if (alpha <= 0.001) return;

    final Rect rect = Offset.zero & size;
    final Offset center = Alignment.center.withinRect(rect);
    final double radius = size.width * 0.62;

    void halo({
      required double peak,
      required double stop,
      required double blur,
    }) {
      canvas.drawRect(
        rect,
        Paint()
          // `screen`：提亮而不是覆盖，保住「中间亮边缘薄」的形状。
          ..blendMode = BlendMode.screen
          ..maskFilter = blur <= 0
              ? null
              : MaskFilter.blur(BlurStyle.normal, blur)
          ..shader = RadialGradient(
            radius: stop,
            colors: [
              tone.glow.withValues(alpha: peak),
              tone.glow.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    halo(peak: alpha, stop: 0.55, blur: size.width * 0.035);
    halo(peak: alpha * 0.55, stop: 0.35, blur: size.width * 0.012);
    halo(peak: alpha * 0.40, stop: 0.16, blur: size.width * 0.008);
  }

  @override
  bool shouldRepaint(SplashFlowLightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.image != image ||
      oldDelegate.tone != tone;
}
