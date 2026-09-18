/// 服务宫格（主页宫格视图）。
///
/// 用户 2026-09-15 裁定（第 2 条）：「电脑端宫格视图下，每个卡片要一样宽高，
/// 提示文本不足 1 行也显示为 2 行高，超过 2 行的显示省略号、只保留两行」。
///
/// 落地口径：
/// - **等高** = 每个磁贴外面套 `SizedBox(height: …)`，高度由 [cardHeight] /
///   [compactCardHeight] 固定算出来（不靠 `IntrinsicHeight` 猜内容）；
/// - **副标题恒占 2 行** = `SizedBox(height: subtitleLineHeight * 2)` 里放
///   `maxLines: 2` 的 `Text`（1 行的文案照样占满 2 行高，磁贴因此对得齐）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 服务宫格。
class HomeServiceGrid extends StatelessWidget {
  final List<HomeServiceEntry> entries;

  const HomeServiceGrid({super.key, required this.entries});

  /// 窄屏断点（手机竖屏）：小于它走紧凑磁贴（图标在上、只留标题）。
  static const double compactBreakpoint = 620;

  /// 宽屏磁贴最小宽度（列数 = 可用宽度能摆几个这样的磁贴）。
  static const double minCard = 208;

  /// 磁贴间距（横竖同值）。
  static const double gap = 12;

  /// 紧凑磁贴的目标宽度（等价 `SliverGridDelegateWithMaxCrossAxisExtent` 语义）。
  static const double compactExtent = 108;

  /// 副标题单行高度（与 `TextStyle.height` 口径一致：12 × 16/12）。
  static const double subtitleLineHeight = 16;

  /// 标题单行高度（15 × 20/15）。
  static const double titleLineHeight = 20;

  /// 宽屏磁贴高度 = 内边距 16×2 + 标题 20 + 间距 2 + 副标题 2 行 32（= 86）+
  /// 2px 余量（字体度量取整，实测 2 行正好 32）。
  static const double cardHeight = 88;

  /// 紧凑磁贴高度 = 内边距 14×2 + 图标 42 + 间距 8 + 标题 16（= 94）。
  static const double compactCardHeight = 94;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        final maxWidth = constraints.maxWidth;
        var cols = 0;
        double width = 0;
        if (isCompact) {
          cols = ((maxWidth + gap) / (compactExtent + gap)).ceil();
          if (cols < 2) cols = 2;
          width = (maxWidth - gap * (cols - 1)) / cols;
        } else {
          cols = (maxWidth + gap) ~/ (minCard + gap);
          if (cols < 1) cols = 1;
          if (cols > 6) cols = 6;
          width = (maxWidth - gap * (cols - 1)) / cols;
        }
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in entries)
              SizedBox(
                width: width,
                height: isCompact ? compactCardHeight : cardHeight,
                child: _HomeTile(item: item, compact: isCompact),
              ),
          ],
        );
      },
    );
  }
}

/// 单个服务磁贴（定宽等高；[compact] = 手机端紧凑形态）。
class _HomeTile extends StatelessWidget {
  final HomeServiceEntry item;
  final bool compact;

  const _HomeTile({required this.item, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = item.accent;
    // 副标题被截到 2 行时，悬停（手机长按）用 tooltip 看全文。
    return Tooltip(
      message: item.subtitle,
      child: Material(
        key: Key('homeTile-${item.title}'),
        color: Theme.of(context).cardTheme.color,
        shape: appCardShape(context),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.onTap,
          hoverColor: accent.withValues(alpha: 0.05),
          child: compact
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.tint(context, accent, 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, color: accent, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 16 / 13,
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.tint(context, accent, 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 20 / 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // 副标题恒占 2 行高（不足 1 行也照样占满）。
                            SizedBox(
                              key: Key('homeSubtitleBox-${item.title}'),
                              height: HomeServiceGrid.subtitleLineHeight * 2,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 16 / 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
