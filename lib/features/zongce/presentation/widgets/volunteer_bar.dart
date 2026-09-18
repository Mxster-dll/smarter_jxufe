/// 志愿服务时长进度条（表 18 档位分段）。
///
/// 用户 2026-09-18：「志愿服务也基本和基本分、评议分、加权/体测成绩一样显示，
/// 唯一不同的是，还要额外在下方显示一个进度条，并根据各级别分段」；
/// 同日二轮（改版）：「志愿时长进度条太粗；进度条颜色不对；提示文本太多，
/// 『（按表 18 档位换算）』『24 h · 已得 4 分 · 距 30 h 还差 6 h（可 +6 分）』
/// 都要去掉」→ 本组件**只剩条 + 档位刻度**：
/// - 高度收到 [zcVolunteerBarHeight]（6，与分数估计页的细条同档）；
/// - 颜色 = **主题红**（`colorScheme.primary`，与该行右侧胶囊、卡片强调色一致；
///   不再用劳育语义青绿 —— 那与同一行胶囊不同色，看着像两套东西）；
/// - **没有任何说明文案**（时长/得分/还差多少都不再印；数值看上方胶囊，
///   得分看卡头徽章），档位刻度只留门槛（`10h`）与分值（`1分`）两行小字。
///
/// 口径：一段 = 一个档位（等宽）——档位在小时轴上疏密悬殊（10/15/20/30/50/100），
/// 按小时线性铺会把前十小时挤在 1/10 的宽度里，看不出「到了哪一档」；等宽分段 +
/// 当前档内按小时填充，才是「按级别分段」的读法。
library;

import 'package:flutter/material.dart';

import '../../../../design/app_theme.dart';
import '../../domain/zc_rules.dart' show zcVolunteerTiers;

/// 进度条高度（细条，用户 2026-09-18 二轮：「太粗」→ 9 收到 6）。
const double zcVolunteerBarHeight = 6;

/// 段间缺口（比分数估计页的 2 稍窄，6 段时更整齐）。
const double zcVolunteerBarGap = 2;

class ZcVolunteerBar extends StatelessWidget {
  /// 本学年志愿时长（小时）。
  final double hours;

  /// 强调色；**null = 主题红**（唯一生产用法）。
  final Color? accent;

  /// 档位表（默认表 18；参数化只是为了测试能注入边界用例）。
  final List<(double, double)> tiers;

  const ZcVolunteerBar({
    super.key,
    required this.hours,
    this.accent,
    this.tiers = zcVolunteerTiers,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = this.accent ?? scheme.primary;
    // 升序：门槛低的档在左（表 18 原文是降序，进度条必须从左到右递增）。
    final asc = [...tiers]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ⚠ 必须 stretch：Row 默认 center 会给无子 ColoredBox 松高度约束 → 整条
        // 塌成 0 高（分数估计的占比条踩过同款）。
        SizedBox(
          height: zcVolunteerBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < asc.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == asc.length - 1 ? 0 : zcVolunteerBarGap,
                    ),
                    child: _Segment(
                      key: Key('zcVolunteerSeg-$i'),
                      fraction: _fractionOf(asc, i, hours),
                      accent: accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var i = 0; i < asc.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == asc.length - 1 ? 0 : zcVolunteerBarGap,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${_fmtHours(asc[i].$1)}h',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: _reached(asc, i, hours)
                              ? accent
                              : scheme.outline,
                          fontWeight: _reached(asc, i, hours)
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        '${_fmtPoints(asc[i].$2)}分',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          color: _reached(asc, i, hours)
                              ? accent
                              : scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 第 [i] 段的填充比例：已过档位 = 1，当前档 = 档内按小时线性，未到 = 0。
  static double _fractionOf(List<(double, double)> asc, int i, double hours) {
    final upper = asc[i].$1;
    if (hours >= upper - 0.001) return 1;
    final lower = i == 0 ? 0.0 : asc[i - 1].$1;
    if (hours <= lower) return 0;
    final span = upper - lower;
    if (span <= 0) return 0;
    return ((hours - lower) / span).clamp(0.0, 1.0);
  }

  /// 该档是否已达成（含恰好到线）。
  static bool _reached(List<(double, double)> asc, int i, double hours) =>
      hours >= asc[i].$1 - 0.001;

  static String _fmtHours(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _fmtPoints(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class _Segment extends StatelessWidget {
  final double fraction;
  final Color accent;

  const _Segment({super.key, required this.fraction, required this.accent});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.tint(context, accent, 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
