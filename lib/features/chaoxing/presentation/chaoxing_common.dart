/// 学习通模块的共用小件（状态胶囊 / 作业行 / 通知行 / 课程行 / 区块卡）。
///
/// 口径：
/// - 卡片形状一律 `appCardShape(context)`（§16 全应用统一「综测评测结果卡」形态）；
/// - 区块标题一律 `geCardTitle`（3px 竖条 + 主题红）；
/// - 状态色是**语义色**（待做过期 = 警示红、待批阅 = 信息蓝、完成 = 灰），
///   不是装饰性强调色，因此不受「单色强调一律改主题红」约束。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 区块卡：`geCardTitle` + 内容，外面套统一卡片形态。
class ChaoxingSectionCard extends StatelessWidget {
  const ChaoxingSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.onSeeAll,
    this.seeAllLabel = '查看全部',
  });

  final String title;
  final List<Widget> children;

  /// 标题行右侧的小字/胶囊（如「12 条」）。
  final Widget? trailing;

  /// 非空时在卡片底部出一行「查看全部（N）」。
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(context, text: title, trailing: trailing),
            const SizedBox(height: 6),
            ...children,
            if (onSeeAll != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onSeeAll,
                  child: Text(seeAllLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 作业状态胶囊（待做 / 已过期 / 待批阅 / 已完成 N 分）。
class ChaoxingWorkStatusChip extends StatelessWidget {
  const ChaoxingWorkStatusChip({super.key, required this.work, required this.now});

  final ChaoxingWork work;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final overdue = work.isOverdueAt(now);
    final scheme = Theme.of(context).colorScheme;
    final Color fg;
    if (overdue) {
      fg = AppColors.critical(context);
    } else {
      switch (work.status) {
        case ChaoxingWorkStatus.todo:
          fg = scheme.primary;
        case ChaoxingWorkStatus.pendingReview:
          fg = AppColors.info(context);
        case ChaoxingWorkStatus.done:
        case ChaoxingWorkStatus.unknown:
          fg = AppColors.textMuted(context);
      }
    }
    final label = overdue ? '已过期' : chaoxingWorkStatusText(work);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(context, fg, 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// 一条作业（主页面与「全部作业」页共用）。
///
/// [onTap] 非空时整行可点（并出一枚右箭头提示），点开 = 作业详情弹窗
/// （`showChaoxingWorkDetail`）。
class ChaoxingWorkRow extends StatelessWidget {
  const ChaoxingWorkRow({
    super.key,
    required this.work,
    required this.now,
    this.showCourse = true,
    this.showStatusChip = true,
    this.onTap,
  });

  final ChaoxingWork work;
  final DateTime now;

  /// 是否在第二行显示课程名（按课分组时关掉，避免每行重复）。
  final bool showCourse;

  /// 已完成/待批阅在「待做」列表里也会出现时，用不到胶囊就关掉。
  final bool showStatusChip;

  /// 点击看详情（主页两个区块 / 全部作业页 / 课程页展开的作业行都传）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final overdue = work.isOverdueAt(now);
    final meta = <String>[
      if (showCourse) work.courseName,
      '截止 ${chaoxingDueText(work.dueAt)}',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _body(context, overdue, meta)),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMuted(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool overdue, String meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (showStatusChip) ...[
              const SizedBox(width: 8),
              ChaoxingWorkStatusChip(work: work, now: now),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              chaoxingCountdownText(work.dueAt, now),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: overdue
                    ? AppColors.critical(context)
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 作业详情弹窗（**唯一实现**：主页「待做作业 / 最近完成」两个区块、「全部作业」页、
/// 课程页展开的作业行共用）。
///
/// 口径：
/// - 时间一律给**绝对时刻**（`chaoxingMomentText`）—— 详情里「今天 08:05」没信息量；
/// - 「剩余」只对**待做**画（已完成/待批阅谈「已过期」是误导，与 `ChaoxingWork.isOverdueAt`
///   同一口径），过期时标红；
/// - 分数不单列 —— `chaoxingWorkStatusText` 已经给成 `已完成 90 分`；
/// - [courseName] 非空时优先用它（按课分组时调用方手上有更准的课程名）。
Future<void> showChaoxingWorkDetail(
  BuildContext context,
  ChaoxingWork work, {
  required DateTime now,
  String? courseName,
}) {
  final course = (courseName ?? work.courseName).trim();
  final overdue = work.isOverdueAt(now);
  final muted = TextStyle(fontSize: 12, color: AppColors.textMuted(context));
  final rows = <(String, String, TextStyle?)>[
    ('状态', chaoxingWorkStatusText(work), null),
    if (course.isNotEmpty) ('课程', course, null),
    ('开始时间', chaoxingMomentText(work.startAt), null),
    ('截止时间', chaoxingMomentText(work.dueAt), null),
    if (work.status.isOpen)
      (
        '剩余',
        chaoxingCountdownText(work.dueAt, now),
        TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: overdue
              ? AppColors.critical(context)
              : Theme.of(context).colorScheme.primary,
        ),
      ),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.assignment_outlined),
      title: Text(work.title.isEmpty ? '（无标题）' : work.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value, style) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 66, child: Text(label, style: muted)),
                      Expanded(
                        child: Text(
                          value,
                          style: style ?? const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 通知详情弹窗（**唯一实现**：主页「通知消息」区块与「全部通知」页共用）。
///
/// 正文是接口给的原始纯文本（含大量 `\r` 与空行），**保留段落、只 `trim()`** ——
/// 用 `chaoxingCleanText` 收拢空白会把整篇压成一行，读不了。
///
/// [courseName] 非空时多印一行「所属课程」；调用方用 `chaoxingCourseNameOf` 从快照查。
///
/// ⚠ 不提供「在学习通里打开」：`ChaoxingNotice.detailPath` 依赖学习通会话 Cookie，
/// 外链打开只会落到登录页（见 domain/chaoxing_notice.dart 的口径）。
Future<void> showChaoxingNoticeDetail(
  BuildContext context,
  ChaoxingNotice notice, {
  String? courseName,
}) {
  final sender = notice.sender.trim().isEmpty ? '学习通' : notice.sender;
  final time = chaoxingTimeText(notice.sentAt, DateTime.now());
  final body = notice.content.trim();
  final course = courseName?.trim() ?? '';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.campaign_outlined),
      title: Text(notice.title.isEmpty ? '（无标题）' : notice.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${notice.top ? '置顶 · ' : ''}$sender · $time',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted(context),
                ),
              ),
              if (course.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '所属课程：$course',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SelectableText(
                body.isEmpty ? '（这条通知没有正文，可能要在学习通里打开）' : body,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 一条通知。[onTap] 非空时整行可点（并出一枚右箭头提示），点开 = 详情弹窗。
class ChaoxingNoticeRow extends StatelessWidget {
  const ChaoxingNoticeRow({
    super.key,
    required this.notice,
    required this.now,
    this.snippetLength = 80,
    this.onTap,
  });

  final ChaoxingNotice notice;
  final DateTime now;
  final int snippetLength;

  /// 点击看详情（主页区块与「全部通知」页都传）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sender = notice.sender.trim().isEmpty ? '学习通' : notice.sender;
    final snippet = chaoxingNoticeSnippet(notice.content, max: snippetLength);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: notice.read
                      ? Colors.transparent
                      : AppColors.critical(context),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (notice.top) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tint(
                              context,
                              Theme.of(context).colorScheme.primary,
                              0.10,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '置顶',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          notice.title.isEmpty ? '（无标题）' : notice.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                notice.read ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$sender · ${chaoxingTimeText(notice.sentAt, now)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                  if (snippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMuted(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一门课程（课程列表与「全部课程」页共用）。
class ChaoxingCourseRow extends StatelessWidget {
  const ChaoxingCourseRow({
    super.key,
    required this.course,
    required this.workCount,
    required this.todoCount,
    this.note = '',
  });

  final ChaoxingCourse course;
  final int workCount;
  final int todoCount;

  /// 本轮取数状态说明（`chaoxingCourseScanNote`）；**空串 = 本轮正常扫过**。
  ///
  /// 有它才分得清「这门课真的没作业」与「这一轮还没扫到它」—— 后者不能说成
  /// 「无作业记录」（用户 2026-09-20：「我明明有一项线性代数的作业，为什么提示没有作业」）。
  final String note;

  @override
  Widget build(BuildContext context) {
    final term = course.termLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  workCount == 0
                      ? '无作业记录'
                      : '作业 $workCount 条${todoCount > 0 ? ' · 待做 $todoCount 条' : ''}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (term.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              term,
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted(context)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空态提示（居中一行灰字 + 图标）。
class ChaoxingEmptyHint extends StatelessWidget {
  const ChaoxingEmptyHint({super.key, required this.text, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMuted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 28, color: muted),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }
}
