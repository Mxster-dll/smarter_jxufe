/// 阅读学分「四部分进度」区（总成绩圆环 + 每个部分一张进度卡）。
///
/// 用户 2026-09-11 的三次裁定：
/// - 每个部分**只留一张进度卡**（经典阅读 / 普通阅读 / 入馆教育 / 信息素养），
///   入馆教育那张点进去 = 原「新生入馆教育」页（由页面注入
///   [ReadCreditProgressSection.onOpenLibraryEdu]）；**经典阅读那张点进去 =
///   畅想之星页**（[ReadCreditProgressSection.onOpenClassic]，用户 2026-09-15
///   裁定：「取消畅想之星的独立入口…删除目前点击蛟湖阅读-经典阅读的界面，而是
///   把点击后跳转的页面改成畅想之星」——原学分平台明细页不再从蛟湖阅读进入，
///   其数据源保留并归并到畅想之星页内）；其余两部分进平台明细表；
/// - 服务端数据一定晚于实际数据 → **一条进度条上叠两档**：灰色 = 实际数据，
///   红色 = 服务端数据，红条覆盖在灰条上（红条短于灰条 = 服务端还没追上实际进度）；
/// - 蛟湖阅读页要有**总成绩卡**：四段圆环（哪部分完成就亮起那一段）+ 是否获得学分的胶囊。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_progress.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_detail_screen.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/widgets/read_credit_ui.dart';

/// 四部分进度区（总成绩卡 + 每部分一张进度卡）。
class ReadCreditProgressSection extends ConsumerWidget {
  const ReadCreditProgressSection({
    super.key,
    this.onOpenLibraryEdu,
    this.onOpenClassic,
  });

  /// 「入馆教育」卡的点击目标（页面注入，避免本 feature 依赖入馆教育页）。
  final VoidCallback? onOpenLibraryEdu;

  /// 「经典阅读」卡的点击目标（页面注入：畅想之星页）。
  ///
  /// 为 null 时回退到学分平台明细页（保底，正常路径由蛟湖阅读页注入）。
  final VoidCallback? onOpenClassic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readCreditProgressProvider);
    return async.when(
      loading: () => readCreditCard(
        context,
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在统计四部分进度…', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      error: (error, _) => _errorCard(context, ref, '$error'),
      data: (bundle) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _creditCard(context, ref, bundle),
          const SizedBox(height: 12),
          for (final part in bundle.creditParts) ...[
            ReadCreditPartCard(part: part, onTap: _tapFor(context, part)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  VoidCallback? _tapFor(BuildContext context, ReadCreditPartProgress part) {
    if (part.kind == ReadCreditKind.libraryEdu) {
      return onOpenLibraryEdu;
    }
    // 经典阅读 → 畅想之星页（该页内已含学分平台侧明细，用户 2026-09-15 裁定）。
    if (part.kind == ReadCreditKind.classic && onOpenClassic != null) {
      return onOpenClassic;
    }
    if (!part.kind.hasDetail) return null;
    return () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadCreditDetailScreen(kind: part.kind),
      ),
    );
  }

  /// 总成绩卡：四段圆环（完成即亮起）+ 学分胶囊 + 四部分图例 + 口径说明。
  Widget _creditCard(
    BuildContext context,
    WidgetRef ref,
    ReadCreditProgressBundle bundle,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final parts = bundle.creditParts;
    final granted = bundle.creditGranted;
    final creditLabel = bundle.creditText.isEmpty
        ? (granted ? '获得学分' : '未获得学分')
        : bundle.creditText;
    final culture = bundle.partOf(ReadCreditKind.culture);
    return readCreditCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CreditRing(
                done: [for (final part in parts) readCreditPartCompleted(part)],
                completed: bundle.completedCount,
                total: parts.length,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '阅读学分',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: granted
                                ? AppColors.successFill(context)
                                : AppColors.cautionFill(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            creditLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: granted
                                  ? AppColors.success(context)
                                  : AppColors.caution(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '共 1 分 · 四部分全部完成后由图书馆出具证明',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final part in parts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _legendRow(context, part),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (culture != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  readCreditKindIcon(ReadCreditKind.culture),
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '蛟湖文化活动（不属四部分，服务端单独标记）',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                readCreditChip(
                  culture.remoteMet == true
                      ? '通过'
                      : (culture.remoteMet == false ? '未通过' : '未提供'),
                  readCreditMetColors(
                    context,
                    culture.remoteMet,
                    unknownIsGrey: false,
                  ).bg,
                  readCreditMetColors(
                    context,
                    culture.remoteMet,
                    unknownIsGrey: false,
                  ).fg,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '进度条：浅红 = 实际数据（App 实时：入馆教育闯关、数据中心借阅、'
                  '平台明细实时统计），深红 = 服务端数据（学分查询页汇总，只在 5 月与'
                  '11 月更新）。红条覆盖在浅红条上——红条较短，就是服务端还没追上你的'
                  '实际进度；服务端若已标记该项完成，红条直接拉满。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: () {
                  ref.invalidate(readCreditProgressProvider);
                  ref.invalidate(readCreditScoreProvider);
                },
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(BuildContext context, ReadCreditPartProgress part) {
    final scheme = Theme.of(context).colorScheme;
    final done = readCreditPartCompleted(part);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          // 图例圆点与圆环同色口径：完成 = 红色（主题红），未完成 = 灰。
          decoration: BoxDecoration(
            color: done ? scheme.primary : scheme.outlineVariant,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            part.kind.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              color: done ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          done ? '已完成' : '未完成',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: done ? AppColors.success(context) : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _errorCard(BuildContext context, WidgetRef ref, String message) {
    final scheme = Theme.of(context).colorScheme;
    return readCreditCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              const Text(
                '阅读学分读取失败',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(readCreditProgressProvider),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 四段圆环：完成的段亮红色（用户裁定：颜色为红色），段之间留明显间隙；
/// 未完成段留灰底。
class _CreditRing extends StatelessWidget {
  const _CreditRing({
    required this.done,
    required this.completed,
    required this.total,
  });

  static const double size = 120;

  final List<bool> done;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CreditRingPainter(
          done: done,
          activeColor: scheme.primary,
          baseColor: scheme.outlineVariant,
          strokeWidth: 12,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$completed/$total',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '部分已完成',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditRingPainter extends CustomPainter {
  _CreditRingPainter({
    required this.done,
    required this.activeColor,
    required this.baseColor,
    required this.strokeWidth,
  });

  final List<bool> done;
  final Color activeColor;
  final Color baseColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (done.isEmpty) return;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    // 段间明显间隙：四段各占 90°，去掉 22° 缝隙（用户要求「明显间隙」）。
    const gap = 0.38;
    final step = 2 * math.pi / done.length;
    final sweep = step - gap;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = baseColor;
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = activeColor;
    for (var i = 0; i < done.length; i++) {
      // 从 12 点方向顺时针排布。
      final start = -math.pi / 2 + i * step + gap / 2;
      canvas.drawArc(rect, start, sweep, false, basePaint);
      if (done[i]) {
        canvas.drawArc(rect, start, sweep, false, activePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_CreditRingPainter oldDelegate) =>
      oldDelegate.baseColor != baseColor ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      !_sameDone(oldDelegate.done, done);

  bool _sameDone(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 单个部分的进度卡（蛟湖阅读页与入馆教育页共用）。
class ReadCreditPartCard extends StatelessWidget {
  const ReadCreditPartCard({
    super.key,
    required this.part,
    this.onTap,
    this.titleOverride,
    this.compact = false,
  });

  final ReadCreditPartProgress part;
  final VoidCallback? onTap;

  /// 卡片标题（默认取 [ReadCreditPartProgress.kind] 的平台名称）。
  final String? titleOverride;

  /// 紧凑模式：省掉两条脚注（用于嵌入到别的页面时的窄场景）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actual = readCreditMetColors(context, part.actualMet);
    final server = readCreditMetColors(context, part.remoteMet);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              readCreditIconBox(
                context,
                readCreditKindIcon(part.kind),
                readCreditPartColor(context, part.kind),
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleOverride ?? part.kind.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      part.requirementText,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              readCreditChip(
                part.actualMet == true
                    ? '实际 已达标'
                    : (part.actualMet == false ? '实际 未达标' : '实际 无数据'),
                actual.bg,
                actual.fg,
              ),
              readCreditChip(
                part.remoteMet == true
                    ? '服务端 通过'
                    : (part.remoteMet == false ? '服务端 未通过' : '服务端 未提供'),
                server.bg,
                server.fg,
              ),
            ],
          ),
          for (final bar in part.bars) ...[
            const SizedBox(height: 12),
            _barBlock(context, bar, serverPassed: part.remoteMet),
          ],
          if (part.lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in part.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          if (!compact) ...[
            const SizedBox(height: 8),
            _footnote(
              context,
              Icons.cloud_outlined,
              scheme.onSurfaceVariant,
              '服务端：${part.remoteStatusText}',
            ),
            if (part.actualSourceNote != null) ...[
              const SizedBox(height: 4),
              _footnote(
                context,
                Icons.bolt_outlined,
                readCreditAccent(context),
                part.actualSourceNote!,
              ),
            ],
          ],
        ],
      ),
    );
    if (onTap == null) return readCreditCard(context, child: body);
    return readCreditCard(
      context,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: body,
      ),
    );
  }

  Widget _footnote(
    BuildContext context,
    IconData icon,
    Color color,
    String text,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 11.5, height: 1.5, color: color),
        ),
      ),
    ],
  );

  /// 一条进度条上叠两档：浅红 = 实际（先画），深红 = 服务端（覆盖其上）。
  ///
  /// 服务端已标记该项完成（[serverPassed]）时，**红条直接拉满**（用户裁定——
  /// 服务端认可即视为满分，不再受它的计数口径限制）。
  Widget _barBlock(
    BuildContext context,
    ReadCreditProgressBar bar, {
    required bool? serverPassed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final actualColor = readCreditActualBarColor(context);
    final serverColor = readCreditServerBarColor(context);
    final serverRatio = serverPassed == true ? 1.0 : bar.remoteRatio;
    final serverText = serverPassed == true
        ? '服务端 已完成'
        : (bar.remoteText == null ? null : '服务端 ${bar.remoteText}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bar.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '实际 ${bar.actualText}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (serverText != null) ...[
              const SizedBox(width: 10),
              Text(
                serverText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: serverColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Container(
                    height: 8,
                    width: width,
                    color: scheme.surfaceContainerHighest,
                  ),
                  // 浅红：实际数据。
                  Container(
                    height: 8,
                    width: width * bar.actualRatio,
                    color: actualColor,
                  ),
                  // 深红：服务端数据，覆盖在浅红条之上。
                  if (serverRatio != null)
                    Container(
                      height: 8,
                      width: width * serverRatio,
                      color: serverColor,
                    ),
                ],
              );
            },
          ),
        ),
        if (bar.actualNote != null) ...[
          const SizedBox(height: 3),
          Text(
            bar.actualNote!,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
