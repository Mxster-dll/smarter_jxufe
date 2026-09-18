/// 学科竞赛页面的共享小件（分页条 / 状态胶囊 / 提示）。
///
/// 卡片形状与强调色一律走 `lib/design/app_card.dart`（§16 唯一口径），
/// 本文件不重复定义圆角与边框。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';

/// 分页条：官网列表是服务端分页，客户端只翻页、不做本地切片。
class CompetitionPagerBar extends StatelessWidget {
  final int page;
  final int totalPages;

  /// 是否正在加载（禁用按钮）。
  final bool busy;

  /// 翻页回调（页码从 1 开始）。
  final ValueChanged<int> onPage;

  const CompetitionPagerBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPage,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一页',
            icon: const Icon(Icons.chevron_left),
            onPressed: busy || page <= 1 ? null : () => onPage(page - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '第 $page / $totalPages 页',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: '下一页',
            icon: const Icon(Icons.chevron_right),
            onPressed: busy || page >= totalPages
                ? null
                : () => onPage(page + 1),
          ),
        ],
      ),
    );
  }
}

/// 申请类型胶囊（个人 / 团队）。
class CompetitionTypeChip extends StatelessWidget {
  final CompetitionType type;

  const CompetitionTypeChip({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final team = type == CompetitionType.team;
    final color = team
        ? AppColors.tone(context, const Color(0xFF6A1B9A))
        : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 审批状态胶囊（未审批 / 通过 / 不通过）。
class CompetitionStatusChip extends StatelessWidget {
  final String status;

  const CompetitionStatusChip({super.key, required this.status});

  /// 状态 → 颜色（未审批橙 / 通过绿 / 不通过红）。
  static Color colorOf(BuildContext context, String status) {
    if (status.contains('未') || status.contains('待')) {
      return AppColors.caution(context);
    }
    if (status.contains('不通过') || status.contains('未通过')) {
      return AppColors.critical(context);
    }
    return AppColors.success(context);
  }

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final color = colorOf(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 获奖等级胶囊（公示列表用）。
///
/// 等级文案 = `级别 · 奖项`（如 `省赛 · 二等奖`）；`loading` 时显示灰色占位
/// `…`（公示列表本身没有等级列，等级是逐行拉详情补上的，见
/// `competitionPublicityAwardProvider`）。
class CompetitionAwardChip extends StatelessWidget {
  final CompetitionAwardLevel award;

  /// 是否正在读取（显示占位，不闪空）。
  final bool loading;

  /// 是否没拿到（详情拉取失败 / 详情里没有奖项字段）→ 不显示。
  final bool unknown;

  const CompetitionAwardChip({
    super.key,
    this.award = CompetitionAwardLevel.empty,
    this.loading = false,
    this.unknown = false,
  });

  /// 赛别 → 颜色：国赛金 / 省赛蓝 / 校赛绿 / 其它主题色。
  static Color colorOf(BuildContext context, CompetitionAwardLevel award) {
    if (award.isNotEmpty && award.award.contains('未获奖')) {
      return Theme.of(context).colorScheme.outline;
    }
    final level = award.level;
    if (level.contains('国')) return fp(context).competition;
    if (level.contains('省')) return AppColors.info(context);
    if (level.contains('校')) return AppColors.success(context);
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    if (unknown) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = loading ? scheme.outline : colorOf(context, award);
    final text = loading ? '…' : award.label;
    if (text.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: loading ? '正在读取获奖等级' : '学生提交的奖项：$text',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.tint(context, color, 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 分值文案：整数不带小数（`3` → `3 分`、`1.5` → `1.5 分`、`0.1` → `0.1 分`）。
String competitionScoreText(double score) {
  final rounded = score.roundToDouble();
  if (score == rounded) return '${rounded.toInt()} 分';
  var text = score.toStringAsFixed(2);
  if (text.endsWith('0')) text = text.substring(0, text.length - 1);
  return '$text 分';
}

/// 申请条目右侧的**加分**胶囊。
///
/// 用户 2026-09-18 原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」。
/// 数据来自 `competitionApplyAwardProvider`（按行拉 `xd_detail.html`，见
/// [CompetitionApplyAward]）：
/// - 已评定（官网「个人得分」> 0 或已选定最终奖项）→ `3 分`，绿色；
/// - 未评定 → `预计 3 分`（申报奖项按该赛别标准算出的分值），模块色（琥珀金）；
/// - `loading` → 灰色 `…` 占位（不闪空、不跳版）；拉取失败 / 没有奖项 → 整块不显示，
///   不打断列表。
class CompetitionApplyAwardChip extends StatelessWidget {
  final CompetitionApplyAward award;

  /// 是否正在读取（显示占位）。
  final bool loading;

  /// 是否没拿到（详情拉取失败 / 结构变化）→ 不显示。
  final bool unknown;

  /// 点按看该赛别的分值标准（null = 不可点，仅展示）。
  final VoidCallback? onTap;

  const CompetitionApplyAwardChip({
    super.key,
    this.award = CompetitionApplyAward.empty,
    this.loading = false,
    this.unknown = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (unknown) return const SizedBox.shrink();
    if (loading) {
      return _AwardPill(
        color: Theme.of(context).colorScheme.outline,
        text: '…',
        tooltip: '正在读取这一项的加分',
      );
    }
    final score = award.score;
    if (!award.hasData || score == null) return const SizedBox.shrink();
    final scored = award.scored;
    return _AwardPill(
      color: scored ? AppColors.success(context) : fp(context).competition,
      text: scored
          ? competitionScoreText(score)
          : '预计 ${competitionScoreText(score)}',
      onTap: onTap,
      tooltip: scored
          ? '这一项已评定 ${competitionScoreText(score)}（点击查看该赛别分值标准）'
          : '按该赛别标准，这一项预计 ${competitionScoreText(score)}（点击查看分值标准）',
    );
  }
}

/// 加分胶囊的外观（与其它胶囊同形：10 圆角 + 同色 10% 底 + 35% 描边）。
///
/// 右侧自带 6px 间距 —— 胶囊在行里紧邻审批状态胶囊，间距随「有没有加分」一起出现。
class _AwardPill extends StatelessWidget {
  final Color color;
  final String text;
  final String tooltip;
  final VoidCallback? onTap;

  const _AwardPill({
    required this.color,
    required this.text,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: onTap == null
            ? body
            : InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: body,
              ),
      ),
    );
  }
}

/// 加分详情弹层（点加分胶囊）。
///
/// 内容 = 这一项的加分 + 你申报的奖项 + 最终获得奖项 / 个人得分 + **该赛别的分值标准**
/// （分值表 = 官网「最终获得奖项」下拉的全部选项，官网原文就在选项文案里）。
Future<void> showCompetitionApplyAwardSheet(
  BuildContext context, {
  required String gameName,
  required CompetitionApplyAward award,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _CompetitionApplyAwardSheet(gameName: gameName, award: award),
);

class _CompetitionApplyAwardSheet extends StatelessWidget {
  final String gameName;
  final CompetitionApplyAward award;

  const _CompetitionApplyAwardSheet({
    required this.gameName,
    required this.award,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = award.score;
    final accent = award.scored
        ? AppColors.success(context)
        : fp(context).competition;
    final tiers = award.tiers;
    final marked = competitionAwardKey(award.displayAward.award);
    final personal = award.personalScore;
    return SafeArea(
      key: const Key('competitionAwardSheet'),
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gameName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  score == null ? '—' : competitionScoreText(score),
                  key: const Key('competitionAwardSheetScore'),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    award.displayAward.isEmpty
                        ? (award.scored ? '已评定' : '未评定')
                        : '${award.displayAward.label}'
                              '${award.scored ? '' : ' · 未评定'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _AwardSheetLine(
              label: '你申报的奖项',
              value: award.submitted.isEmpty ? '—' : award.submitted.label,
              valueKey: const Key('competitionAwardSheetSubmitted'),
            ),
            _AwardSheetLine(
              label: '最终获得奖项',
              value: award.granted.isEmpty ? '待评定' : award.granted.label,
              valueKey: const Key('competitionAwardSheetGranted'),
            ),
            _AwardSheetLine(
              label: '个人得分',
              value: personal == null
                  ? '—'
                  : award.scored
                  ? competitionScoreText(personal)
                  : '${competitionScoreText(personal)}（待评定）',
              valueKey: const Key('competitionAwardSheetPersonal'),
            ),
            if (tiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: AppColors.hairline(context)),
              const SizedBox(height: 12),
              Text(
                '该赛别的分值标准',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              for (final tier in tiers)
                Padding(
                  key: Key('competitionAwardOption-${tier.label}'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tier.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: tier.label == marked
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: tier.label == marked
                                ? accent
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        competitionScoreText(tier.score),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: tier.label == marked
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: tier.label == marked
                              ? accent
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              '分值取自官网「最终获得奖项」下拉（该赛别标准）；评定后以「个人得分」为准。',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的一行「标签 + 值」。
class _AwardSheetLine extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;

  const _AwardSheetLine({
    required this.label,
    required this.value,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态占位（列表无数据 / 无搜索结果）。
class CompetitionEmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const CompetitionEmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 44, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 错误卡（含重试）。
class CompetitionErrorCard extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const CompetitionErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(kAppCardPadding),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 32),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部提示（统一 5 秒 + 先收上一条）。
void showCompetitionMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: action,
      ),
    );
}

/// 奖项下拉里的显示文案：`【国赛】一等奖 · 4 分`。
String competitionAwardLabel(CompetitionAward award, CompetitionGame game) {
  final score = award.score == award.score.roundToDouble()
      ? award.score.toStringAsFixed(0)
      : award.score.toStringAsFixed(1);
  return '${game.awardPrefix}${award.name} · $score 分';
}

/// 附件大小文案（表单里提示用）。
String competitionAttachmentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)}KB';
}
