/// 设置页 —— 全局偏好的集中入口（首页右上角齿轮进入）。
///
/// 目前承载「我的校区」与「校历」两组偏好：校区一旦设置，电费绑定免手动选校区、
/// 学校地址与校区地图把该校区条目置顶；校历偏好控制月历「假/班」角标的画法与
/// 事件过滤口径（判定规则见 `domain/calendar_day_mark.dart`）。
/// 后续偏好项（通知等）一律收拢到本页，不再散落到各页的 feature-local 弹层。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

const _accent = FeaturePalette.campus;
const _calendarAccent = FeaturePalette.calendar;
const _widgetAccent = FeaturePalette.electricity;
const _libraryEduAccent = FeaturePalette.libraryEdu;
const _guidAccent = FeaturePalette.guidGuide;

/// 「不设置」在选择面板里的哨兵值。
///
/// 面板返回 `null` 表示用户取消（下滑关闭），要区分于「选择清空」，
/// 故清空走一个显式哨兵。
const _clearSentinel = '__clear__';

/// 设置页。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myCampusStoreProvider).campus;
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: [
          geCardTitle(context, text: '校区', accent: _accent),
          const SizedBox(height: 12),
          _MyCampusTile(
            mine: mine,
            onTap: () => _pickCampus(context, ref, mine),
          ),
          const SizedBox(height: 26),
          geCardTitle(context, text: '生效范围', accent: _accent),
          const SizedBox(height: 12),
          _EffectCard(mine: mine),
          const SizedBox(height: 26),
          geCardTitle(context, text: '校历', accent: _calendarAccent),
          const SizedBox(height: 12),
          const _CalendarDisplayCard(),
          const SizedBox(height: 26),
          geCardTitle(context, text: '入馆教育', accent: _libraryEduAccent),
          const SizedBox(height: 12),
          const _LibraryEduModeCard(),
          const SizedBox(height: 26),
          // 入口 2026-09-11 从首页宫格迁到设置页（用户裁定）。
          geCardTitle(context, text: '平台标识', accent: _guidAccent),
          const SizedBox(height: 12),
          const _PlatformGuidCard(),
          const SizedBox(height: 26),
          geCardTitle(context, text: '桌面小组件', accent: _widgetAccent),
          const SizedBox(height: 12),
          const _HomeWidgetCard(),
        ],
      ),
    );
  }

  /// 底部选择面板：4 个校区 + 不设置。
  Future<void> _pickCampus(
    BuildContext context,
    WidgetRef ref,
    MyCampus? current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                '我的校区',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in MyCampus.values)
              ListTile(
                leading: Icon(
                  c == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: c == current
                      ? _accent
                      : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
                title: Text(c.label),
                subtitle: c.supportsElectricity
                    ? null
                    : const Text(
                        '无宿舍电费服务，其余功能正常',
                        style: TextStyle(fontSize: 12),
                      ),
                onTap: () => Navigator.of(sheetContext).pop(c.name),
              ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.clear,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
              title: const Text('不设置'),
              enabled: current != null,
              onTap: () => Navigator.of(sheetContext).pop(_clearSentinel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return; // 用户取消
    await ref
        .read(myCampusStoreProvider)
        .save(picked == _clearSentinel ? null : MyCampus.fromName(picked));
  }
}

/// 「我的校区」选择入口卡。
class _MyCampusTile extends StatelessWidget {
  final MyCampus? mine;
  final VoidCallback onTap;

  const _MyCampusTile({required this.mine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: _accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '我的校区',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mine?.label ?? '未设置 · 点击选择',
                      style: TextStyle(
                        fontSize: 13,
                        color: mine == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「生效范围」说明卡：把设置后的三处影响讲清楚。
class _EffectCard extends StatelessWidget {
  final MyCampus? mine;

  const _EffectCard({required this.mine});

  @override
  Widget build(BuildContext context) {
    // 先落到局部变量：公开字段无法参与空提升（non-promo public field）。
    final mine = this.mine;
    final lines = <String>[
      if (mine == null) ...[
        '电费绑定：进入更换面板时自动预选该校区，仍可手动更改',
        '学校地址：该校区条目置顶',
        '校区地图：该校区相关地图置顶',
      ] else ...[
        mine.supportsElectricity
            ? '电费绑定：自动预选「${mine.shortLabel}」，仍可手动更改'
            : '电费绑定：青山园校区无宿舍电费服务，绑定需手动选校区',
        '学校地址：「${mine.label}」已置顶',
        mine.mapEntryNames.isEmpty
            ? '校区地图：无对应地图条目'
            : '校区地图：「${mine.mapEntryNames.join('、')}」已置顶',
      ],
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine == null ? '设置后将在三处生效：' : '当前已生效：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(fontSize: 13, height: 19 / 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 校历偏好卡：角标风格 + 军训角标 + 人群过滤。
///
/// 判定口径见 `lib/features/school_calendar/domain/calendar_day_mark.dart`；
/// 三项都只影响「显示」，不改动任何缓存数据。
class _CalendarDisplayCard extends ConsumerWidget {
  const _CalendarDisplayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(calendarPrefsStoreProvider).prefs;
    final store = ref.read(calendarPrefsStoreProvider);
    final viewer =
        ref.watch(calendarViewerProvider).valueOrNull ?? CalendarViewer.unknown;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SubLabel(
              icon: Icons.label_outline,
              title: '角标风格',
              subtitle: '月历上「假 / 班 / 运 / 考」等角标的画法',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final style in CalendarBadgeStyle.values)
                  ChoiceChip(
                    label: Text(
                      style.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: prefs.badgeStyle == style,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        store.save(prefs.copyWith(badgeStyle: style)),
                  ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.alwaysShowMilitary,
              onChanged: (v) =>
                  store.save(prefs.copyWith(alwaysShowMilitary: v)),
              title: const Text('非新生也显示军训', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                viewer.enrollYear != null
                    ? '当前学籍：${viewer.label} —— 军训只在入学年对应的学年显示'
                    : '未获取到学籍：军训只按「入学年 == 学年」判断（当前不显示）',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.filterByCategory,
              onChanged: (v) => store.save(prefs.copyWith(filterByCategory: v)),
              title: const Text('按我的培养层次过滤', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                viewer.hasInfo
                    ? '官方安排按「教职员工 / 本科生 / 研究生」分节，只显示本人相关的'
                          '运动会 / 考试等事件；放假与补课不受影响'
                    : '未获取到学籍，官方事件将全部显示',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '角标来自学校官方逐日安排（小程序校历，未配置 GUID 时用内置快照）；'
                    '教务校历的 workday/nonday 仅用于补寒暑假等学期外假期。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 入馆教育卡：公共 / 后门模式切换。
///
/// **唯一入口**（用户 2026-09-11 裁定：「公共模式的切换和后门模式,不应该显示在
/// 任何页面,只能显示在设置页」）。模式落盘在 Hive `tsgxsPrefs`，答题页 / 章节页
/// 读同一个控制器实例，改完立即生效。
class _LibraryEduModeCard extends ConsumerWidget {
  const _LibraryEduModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(tsgxsExamPrefsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SubLabel(
              icon: Icons.menu_book_outlined,
              title: '闯关答题模式',
              subtitle: '入馆教育章节页与答题页的作答方式（仅此处可切换）',
              accent: _libraryEduAccent,
            ),
            const SizedBox(height: 12),
            SegmentedButton<TsgxsAnswerMode>(
              segments: [
                for (final m in TsgxsAnswerMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(
                      m.label,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    icon: Icon(
                      m == TsgxsAnswerMode.normal
                          ? Icons.verified_user_outlined
                          : Icons.vpn_key_outlined,
                    ),
                  ),
              ],
              selected: {store.mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => store.save(s.first),
            ),
            const SizedBox(height: 12),
            for (final m in TsgxsAnswerMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m == store.mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: m == store.mode
                          ? _libraryEduAccent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${m.label}：${m.hint}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: m == store.mode
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '后门模式下章节页不显示线索卡片,进入答题时会自动补全线索;'
                    '「一键探底」逐题收集正确答案,若被判闯关失败会自动重新开考继续,'
                    '直到通过(最多 6 轮)。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 平台标识（GUID）卡：展示当前配置状态并进入获取向导。
///
/// 用户 2026-09-11 裁定：「首页宫格里的获取 GUID 应该放到设置里」——宫格磁贴已删，
/// 设置页是本入口的唯一位置（网费实时源 / 请假记录 / 校历官方安排都依赖该标识）。
class _PlatformGuidCard extends ConsumerWidget {
  const _PlatformGuidCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final guid = ref.watch(wxGuidProvider).valueOrNull;
    final configured = guid != null && guid.isNotEmpty;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SubLabel(
              icon: Icons.vpn_key_outlined,
              title: '微信平台标识（GUID）',
              subtitle: '网费实时源 / 请假记录 / 校历官方安排 都依赖它',
              accent: _guidAccent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: configured
                        ? Colors.green.withValues(alpha: 0.12)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    configured ? '已配置' : '未配置',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: configured
                          ? Colors.green.shade800
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    configured
                        ? '当前：${_maskGuid(guid)}'
                        : '未配置时相关功能自动回退离线 / 门户数据源',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GuidGuideScreen(),
                  ),
                ),
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: Text(configured ? '查看 / 更新' : '去获取'),
              ),
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GUID 由微信授权「智慧江财」下发，等同账号标识，一次获取长期有效；'
                    'App 内可一键抓取，也可从剪贴板或手动粘贴保存。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 只露出前 8 位，避免把账号级标识完整铺在界面上。
  String _maskGuid(String guid) =>
      guid.length <= 8 ? guid : '${guid.substring(0, 8)}…';
}

/// 卡片内的小节标题（图标 + 标题 + 说明）。
class _SubLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  const _SubLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = _calendarAccent,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 桌面小组件卡：一键把「数据一览 / 电费余额 / 课程加权」的八档尺寸固定到桌面。
///
/// 走系统 `AppWidgetManager.requestPinAppWidget`（API 26+）。**桌面分页归启动器管，
/// App 没有任何接口能命令桌面新建页面**：实测各渠道在「当前页放不下」时，小米 /
/// OPPO / vivo / 三星会自动新建一页放置，**华为 / honor 不会**，只提示「当前页面
/// 空间不足」（桌面自己弹的，App 拦不掉）。
///
/// 用户 2026-09-11 裁定：**不做任何「满页引导」**——取消确认框与桌面满页在代码里
/// 无法区分，自动弹层会误报，宁可不要。只保留「已在桌面」标记：尺寸 chip 上的 ✓
/// 与底部图例，由原生 `HomeWidgetBridge.pinnedCounts()`（`getAppWidgetIds` 计数）
/// 驱动，纯查询、无副作用。
class _HomeWidgetCard extends StatefulWidget {
  const _HomeWidgetCard();

  @override
  State<_HomeWidgetCard> createState() => _HomeWidgetCardState();
}

class _HomeWidgetCardState extends State<_HomeWidgetCard>
    with WidgetsBindingObserver {
  /// 与原生 `WidgetSize.tag` 一一对应（宽 × 高，单位 = 桌面格子）。
  static const _sizes = <String>[
    '2x1',
    '3x1',
    '4x1',
    '5x1',
    '2x2',
    '3x2',
    '4x2',
    '5x2',
  ];

  /// 「已在桌面」的绿（与其他模块的达标绿一致）。
  static const _placedColor = Color(0xFF2E7D32);

  /// 「指标:尺寸」→ 桌面上已放置的实例数（原生 `getAppWidgetIds`）。
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户去桌面加/删了小组件再回来 → 刷新「已在桌面」标记。
    if (state == AppLifecycleState.resumed) _loadCounts();
  }

  static IconData _icon(HomeWidgetMetric metric) => switch (metric) {
    HomeWidgetMetric.dashboard => Icons.dashboard_outlined,
    HomeWidgetMetric.electricity => Icons.bolt_outlined,
    HomeWidgetMetric.grades => Icons.school_outlined,
  };

  static Color _color(HomeWidgetMetric metric) => switch (metric) {
    HomeWidgetMetric.dashboard => FeaturePalette.dashboard,
    HomeWidgetMetric.electricity => FeaturePalette.electricity,
    HomeWidgetMetric.grades => FeaturePalette.grade,
  };

  Future<void> _loadCounts() async {
    final counts = await HomeWidgetBridge.pinnedCounts();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 5)),
      );
  }

  Future<void> _pin(HomeWidgetMetric metric, String size) async {
    final label = '${metric.defaultLabel} ${size.replaceAll('x', '×')}';
    final result = await HomeWidgetBridge.requestPinWidget(
      metric: metric,
      size: size,
    );
    if (!mounted) return;
    final text = !result.supported
        ? '当前桌面不支持一键添加，请长按应用图标 → 服务卡片，选「$label」'
        : result.requested
        ? '已请求添加「$label」，请在系统弹窗中确认'
        : '添加请求未生效，请长按应用图标 → 服务卡片手动添加「$label」';
    _snack(text);
    // 用户确认后 ✓ 标记要跟上：先延迟刷一次（确认框不暂停本页的情况），
    // 回前台时 didChangeAppLifecycleState 还会再刷一次。
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) _loadCounts();
    });
  }

  Widget _chip(HomeWidgetMetric metric, String size) {
    final placed = _counts[homeWidgetPinKey(metric, size)] ?? 0;
    return ActionChip(
      avatar: placed > 0
          ? const Icon(Icons.check_circle, size: 15, color: _placedColor)
          : null,
      label: Text(
        size.replaceAll('x', '×'),
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      tooltip: placed > 0 ? '已在桌面 $placed 个，再点会再加一个' : '点一下请求添加到桌面',
      onPressed: () => _pin(metric, size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placedTotal = _counts.values
        .where((c) => c > 0)
        .fold<int>(0, (sum, c) => sum + c);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SubLabel(
              icon: Icons.widgets_outlined,
              title: '添加到桌面',
              subtitle: '点尺寸即请求系统固定该小组件，已放置的尺寸带 ✓',
              accent: _widgetAccent,
            ),
            for (final metric in HomeWidgetMetric.values) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(_icon(metric), size: 15, color: _color(metric)),
                  const SizedBox(width: 6),
                  Text(
                    metric.defaultLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [for (final size in _sizes) _chip(metric, size)],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '共 8 档：2×1 / 3×1 / 4×1 / 5×1 是单行条（只放数值，最窄档自动改用短标题'
                    '与短数值），2×2 及以上带副文本；「数据一览」在小尺寸只显示前几项。'
                    '数据随 App 打开、手机解锁与后台任务刷新，点小组件直达对应页面。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
            if (placedTotal > 0) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 15, color: _placedColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '带 ✓ 的尺寸已经在桌面上，共 $placedTotal 个。',
                      style: const TextStyle(fontSize: 11.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
