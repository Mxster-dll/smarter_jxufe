import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 校历页：按「学年 × 学段」展示教务公开校历。
///
/// 数据来自 jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp（免登录），
/// 每个学段返回数月月历（周一起始 + 教学周次列）+ 备注（学期/假期起止）。
class SchoolCalendarScreen extends ConsumerStatefulWidget {
  const SchoolCalendarScreen({super.key});

  @override
  ConsumerState<SchoolCalendarScreen> createState() =>
      _SchoolCalendarScreenState();
}

class _SchoolCalendarScreenState extends ConsumerState<SchoolCalendarScreen> {
  late int _xn;
  late int _xq;

  @override
  void initState() {
    super.initState();
    final term = currentSchoolTerm(DateTime.now());
    _xn = term.xn;
    _xq = term.xq;
  }

  ({int xn, int xq}) get _term => (xn: _xn, xq: _xq);

  @override
  Widget build(BuildContext context) {
    final calendarAsync = ref.watch(schoolCalendarProvider(_term));
    // 小程序源学期安排（实时优先 / 内置兜底）。
    final wxArrangements = ref.watch(wxArrangementsProvider);
    final guid = ref.watch(wxGuidProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('校历')),
      body: Column(
        children: [
          _buildTermSwitcher(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(schoolCalendarProvider(_term));
                await ref.read(schoolCalendarProvider(_term).future);
                ref.invalidate(wxArrangementsProvider);
                await ref.read(wxArrangementsProvider.future);
              },
              child: calendarAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => _buildError(context, error),
                data: (calendar) => _buildCalendar(
                  context,
                  calendar,
                  wxArrangements,
                  guid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 学年 / 学段切换 ----------

  Widget _buildTermSwitcher(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一学年',
                onPressed: () => setState(() => _xn -= 1),
              ),
              Text(
                xnDisplayName(_xn),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一学年',
                onPressed: () => setState(() => _xn += 1),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final xq in const [0, 1, 2]) ...[
                ChoiceChip(
                  label: Text(xqShortName(xq)),
                  selected: _xq == xq,
                  onSelected: (_) => setState(() => _xq = xq),
                  showCheckmark: false,
                  selectedColor: scheme.primary.withValues(alpha: 0.10),
                  labelStyle: TextStyle(
                    color: _xq == xq ? scheme.primary : null,
                    fontWeight:
                        _xq == xq ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color: _xq == xq
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant,
                  ),
                ),
                if (xq != 2) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 错误 / 空状态 ----------

  Widget _buildError(BuildContext context, Object error) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Color(0xFFD9534F)),
            const SizedBox(height: 12),
            Text(
              '校历加载失败',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(schoolCalendarProvider(_term));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 校历主体 ----------

  Widget _buildCalendar(
    BuildContext context,
    SchoolCalendar calendar,
    AsyncValue<List<WxSemesterArrangement>> wxArrangements,
    String? guid,
  ) {
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _buildKeyDatesCard(context, calendar),
        const SizedBox(height: 10),
        _buildOfficialCard(context, wxArrangements, guid),
        const SizedBox(height: 10),
        for (final month in calendar.months) ...[
          _MonthCard(month: month, now: now),
          const SizedBox(height: 10),
        ],
        if (calendar.notes.isNotEmpty)
          _buildNotesCard(context, calendar.notes),
      ],
    );
  }

  /// 备注里的「学期开始/结束、假期开始/结束」等日期行。
  Widget _buildKeyDatesCard(BuildContext context, SchoolCalendar calendar) {
    final dateRows = <({String label, String value})>[];
    final extras = <String>[];
    for (final line in calendar.notes) {
      final idx = line.indexOf('：');
      if (idx <= 0) {
        extras.add(line);
        continue;
      }
      final label = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        dateRows.add((label: label, value: value));
      } else {
        extras.add(line);
      }
    }
    if (dateRows.isEmpty && extras.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final row in dateRows) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(Icons.event_outlined,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Text(
                  row.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ),
              Text(
                row.value,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    for (final extra in extras) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            extra,
            style: textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
      );
    }

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.date_range_outlined, title: '关键日期'),
          const SizedBox(height: 4),
          ...widgets,
        ],
      ),
    );
  }

  // ---------- 小程序源「官方安排」卡 ----------

  /// 所选 (xn, xq) 对应学期的小程序校历官方安排（放假/补课/考试/军训等）。
  ///
  /// 数据源：小程序校历接口需平台 GUID（仅微信授权可得）；配置了 GUID 走实时，
  /// 否则用内置离线快照（抓取于 2026-09，新学年数据请更新快照）。
  Widget _buildOfficialCard(
    BuildContext context,
    AsyncValue<List<WxSemesterArrangement>> wxArrangements,
    String? guid,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final live = guid != null && guid.trim().isNotEmpty;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.event_note_outlined,
                  title: '官方安排',
                ),
              ),
              Tooltip(
                message: live ? '实时（智慧江财）' : '内置数据（2026-09 快照）',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showSourceDialog(context, guid),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          live ? Icons.cloud_done_outlined : Icons.archive_outlined,
                          size: 15,
                          color: scheme.primary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          live ? '实时' : '内置',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 18),
                tooltip: '数据源设置',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showSourceDialog(context, guid),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._officialBody(context, wxArrangements, guid),
        ],
      ),
    );
  }

  List<Widget> _officialBody(
    BuildContext context,
    AsyncValue<List<WxSemesterArrangement>> wxArrangements,
    String? guid,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return wxArrangements.when(
      loading: () => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('加载学期安排…', style: textTheme.bodySmall),
            ],
          ),
        ),
      ],
      error: (e, _) => [
        Text('学期安排加载失败：$e', style: textTheme.bodySmall),
      ],
      data: (all) {
        final arrangement = WxcalRepository.findByTerm(
          all,
          xn: _xn,
          xq: _xq,
        );
        if (arrangement == null) {
          final note = _xq == 2
              ? '暑期段小程序校历无对应数据'
              : '所选学段暂无官方安排数据';
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(note, style: textTheme.bodySmall),
            ),
          ];
        }
        switch (arrangement.style) {
          case WxArrangementStyle.paragraph:
            return _paragraphBody(context, arrangement);
          case WxArrangementStyle.empty:
            return [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('该学期无文字安排', style: textTheme.bodySmall),
              ),
            ];
          case WxArrangementStyle.lines:
          case WxArrangementStyle.table:
            final events = [...arrangement.events]
              ..sort((a, b) => a.from.compareTo(b.from));
            return [
              for (final e in events) _buildEventRow(context, e),
            ];
        }
      },
    );
  }

  /// 文字版（paragraph）学期：原文段落折叠展示，点击弹出全文。
  List<Widget> _paragraphBody(BuildContext context, WxSemesterArrangement a) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '该学年校历以文字通知发布',
          style: textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ),
      for (final para in a.notes)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _showParagraphDialog(context, a, para),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              para,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _showParagraphDialog(context, a, a.notes.join('\n')),
          icon: const Icon(Icons.open_in_full, size: 15),
          label: const Text('查看全文'),
          style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
            visualDensity: VisualDensity.compact,
            textStyle: textTheme.bodySmall,
          ),
        ),
      ),
    ];
  }

  void _showParagraphDialog(
      BuildContext context, WxSemesterArrangement a, String para) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${xnDisplayName(a.xn)}${xqDisplayName(a.xq)}官方安排',
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Text(
              para,
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(height: 1.7),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 数据源说明 / 设置弹窗（填平台 GUID 后走实时）。
  void _showSourceDialog(BuildContext context, String? current) {
    final controller = TextEditingController(text: current ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('校历数据源'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '官方安排 = 小程序「智慧江财-校历」的学期逐日安排'
                  '（放假 / 补课 / 运动会 / 期中 / 军训等）。\n'
                  '该校历接口需平台用户标识（GUID，仅微信授权可得），'
                  '因此未配置时使用内置快照；填入你自己的 GUID 后每次打开'
                  '自动实时拉取最新学期，无需等待快照更新。',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.6, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '智慧江财平台 GUID',
                    hintText: '如 00000000-0000-4000-8000-000000000000',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '留空并保存 = 回到内置快照。GUID 等同账号标识，请勿泄露。',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final value = controller.text.trim();
              final box = await ref
                  .read(wxPlatformBoxProvider.future);
              if (value.isEmpty) {
                await box.delete('guid');
              } else {
                await box.put('guid', value);
              }
              ref.invalidate(wxGuidProvider);
              ref.invalidate(wxArrangementsProvider);
              if (ctx.mounted) Navigator.of(ctx).pop();
              _toast(value.isEmpty ? '已使用内置快照' : '已启用实时数据源');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  /// 单条官方安排行：icon + 日期区间 + 说明（+ 分节类别徽标）。
  Widget _buildEventRow(BuildContext context, WxCalEvent e) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cat = e.category;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_eventIcon(e.text), size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.rangeText,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.text,
                        style: textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
                if (cat != null && cat.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 0.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: scheme.primary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 事件图标：按文字关键词选 icon（遵循界面图标优先偏好）。
  IconData _eventIcon(String text) {
    if (text.contains('放假') ||
        text.contains('假期') ||
        text.contains('寒假') ||
        text.contains('暑假') ||
        text.contains('元旦') ||
        text.contains('春节')) {
      return Icons.beach_access_outlined;
    }
    if (text.contains('考试') ||
        text.contains('复习') ||
        text.contains('校考') ||
        text.contains('补考')) {
      return Icons.assignment_outlined;
    }
    if (text.contains('军训')) return Icons.military_tech_outlined;
    if (text.contains('运动会')) return Icons.emoji_events_outlined;
    if (text.contains('报到') || text.contains('注册')) {
      return Icons.how_to_reg_outlined;
    }
    if (text.contains('上课') ||
        text.contains('开课') ||
        text.contains('课程结束') ||
        text.contains('补课') ||
        text.contains('上班')) {
      return Icons.school_outlined;
    }
    return Icons.event_outlined;
  }

  Widget _buildNotesCard(BuildContext context, List<String> notes) {
    final textTheme = Theme.of(context).textTheme;
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.notes_outlined, title: '备注'),
          const SizedBox(height: 6),
          for (final line in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                style: textTheme.bodySmall?.copyWith(
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个月的月历卡。
class _MonthCard extends StatelessWidget {
  final CalendarMonth month;
  final DateTime now;

  const _MonthCard({required this.month, required this.now});

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.calendar_month_outlined,
            title: '${month.year}年${month.month}月',
          ),
          const SizedBox(height: 8),
          // 周几表头（周次列占位）。
          _buildRow(
            leading: const SizedBox(width: 38),
            cells: List.generate(
              7,
              (i) => _dayCell(
                context,
                text: const ['一', '二', '三', '四', '五', '六', '日'][i],
                isHeader: true,
                isWeekend: i >= 5,
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          for (final row in month.rows) _buildWeekRow(context, row),
        ],
      ),
    );
  }

  Widget _buildWeekRow(BuildContext context, CalendarWeekRow row) {
    final scheme = Theme.of(context).colorScheme;
    final weekNo = row.weekNo?.trim() ?? '';
    return _buildRow(
      leading: Container(
        width: 38,
        alignment: Alignment.center,
        child: weekNo.isEmpty
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '第$weekNo周',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
      ),
      cells: List.generate(
        7,
        (i) {
          final day = i < row.days.length ? row.days[i] : null;
          final isToday = day != null &&
              isCurrentMonth &&
              day == now.day &&
              month.year == now.year &&
              month.month == now.month;
          return _dayCell(
            context,
            text: day == null ? '' : '$day',
            isToday: isToday,
            isWeekend: i >= 5,
            bold: day != null && i < 5,
          );
        },
      ),
    );
  }

  bool get isCurrentMonth {
    return month.year == now.year && month.month == now.month;
  }

  Widget _buildRow({
    required Widget leading,
    required List<Widget> cells,
  }) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          leading,
          for (final cell in cells)
            Expanded(
              child: SizedBox(
                height: 32,
                child: Center(child: cell),
              ),
            ),
        ],
      ),
    );
  }

  /// 单格内容（表头/日期数字/今天高亮）。
  Widget _dayCell(
    BuildContext context, {
    required String text,
    bool isHeader = false,
    bool isWeekend = false,
    bool isToday = false,
    bool bold = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (isHeader) {
      return Text(
        text,
        style: textTheme.bodySmall?.copyWith(
          color: isWeekend ? Colors.grey.shade400 : Colors.grey.shade600,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (text.isEmpty) return const SizedBox.shrink();
    final color = isWeekend ? Colors.grey.shade400 : Colors.black87;
    final dayStyle = textTheme.bodySmall?.copyWith(
      color: isToday ? Colors.white : color,
      fontWeight: bold || isToday ? FontWeight.w600 : FontWeight.w400,
    );
    if (isToday) {
      return Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: Text(text, style: dayStyle),
      );
    }
    return Text(text, style: dayStyle);
  }
}

/// 区块标题：左侧 3px 主色竖条 + 小图标 + 标题文字。
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 5),
        Text(
          title,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

/// 通用白卡：白色圆角 8 + 细描边。
class _WhiteCard extends StatelessWidget {
  final Widget child;

  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: child,
    );
  }
}
