/// `settings_cards.dart` 的「widgets」一组（2026-10-08 架构审计第三轮 · 按类拆文件）。
///
/// 拆分自 `settings_cards.dart`（2297 行 / 20 个 widget 类）：调用方**不用改** —— 桶文件
/// `export` 了本文件。共用顶层件（`settingsClearSentinel` / `SettingsSubLabel`）留在桶里，
/// 故这里反向 import 桶文件（Dart 允许互相 import，见 AGENTS.md §33.4.4 ②）。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/core/platform/app_settings.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/class_reminder_sync.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/class_reminder_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_start_reminder.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'settings_cards.dart';

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
class SettingsHomeWidgetCard extends StatefulWidget {
  const SettingsHomeWidgetCard({super.key});

  @override
  State<SettingsHomeWidgetCard> createState() => SettingsHomeWidgetCardState();
}

class SettingsHomeWidgetCardState extends State<SettingsHomeWidgetCard>
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

  /// 「已在桌面」的绿（与其他模块的达标绿一致）—— 现在随主题解析，
  /// 用 `AppColors.success(context)`（深色下自动提亮），不再是固定 const。

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

  static Color _color(BuildContext context, HomeWidgetMetric metric) =>
      switch (metric) {
        HomeWidgetMetric.dashboard => fp(context).dashboard,
        HomeWidgetMetric.electricity => fp(context).electricity,
        HomeWidgetMetric.grades => fp(context).grade,
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
          ? Icon(
              Icons.check_circle,
              size: 15,
              color: AppColors.success(context),
            )
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
            SettingsSubLabel(
              icon: Icons.widgets_outlined,
              title: '添加到桌面',
              subtitle: '点尺寸即请求系统固定该小组件，已放置的尺寸带 ✓',
              accent: fp(context).cardAccent,
            ),
            for (final metric in HomeWidgetMetric.values) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(_icon(metric), size: 15, color: _color(context, metric)),
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
                  Icon(Icons.check_circle, size: 15, color: AppColors.success(context)),
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

/// 「上课提醒」卡：上课前 X 分钟起的**常驻通知**（2026-09-22 立）。
///
/// 用户原话：「我希望在任何一节课上课前x分钟(x可设置，默认30）到上课前，移动端显示
/// 一个常驻通知，下节课的名称和教室」。
///
/// **唯一入口**（§3 铁律：新增用户偏好一律收拢到设置页，页面里不另开弹层）。
/// 偏好落 Hive `schedulePrefs` 的 `classReminder` 键（与课表显示偏好同一个 box、
/// 不同 key）；改完**立即重排系统通知**（`ClassReminderSync.syncNow(force: true)`），
/// 用户不必等下次回前台才生效。
///
/// 形态：Android 常驻通知（`ongoing`，上课那一刻由系统按 `timeoutAfter` 撤下）；
/// 桌面端不排（门控在 `ClassReminderSync` 里，按 `Platform.isAndroid`）。
///
/// ⚠ 2026-10-08 加「后台保护」引导（[SettingsClassReminderProtectHint]）：华为 / 荣耀 /
/// HarmonyOS 上**应用被从最近任务划掉后，系统不再为它排定闹钟**（华为官方支持文档
/// 「第三方闹钟类应用」一节），课前提醒因此完全不弹。系统级限制，代码绕不过去 ——
/// 只能把用户送到「应用启动管理」页去开自启动 / 关联启动 / 后台活动。
class SettingsClassReminderCard extends ConsumerStatefulWidget {
  const SettingsClassReminderCard({super.key});

  @override
  ConsumerState<SettingsClassReminderCard> createState() =>
      _SettingsClassReminderCardState();
}

class _SettingsClassReminderCardState
    extends ConsumerState<SettingsClassReminderCard> {
  /// 厂商名（`Build.MANUFACTURER`）；只用来说明文案要不要点名品牌。
  String? _manufacturer;
  bool _polledDevice = false;

  @override
  void initState() {
    super.initState();
    // 桌面端没有这套系统页 → 连问都不问（也不用 `Platform.isAndroid`：门控在桥里）。
    if (AppSettingsGuide.isSupported) unawaited(_loadDevice());
  }

  /// 问一次厂商名（原生桥，失败就保持 null → 文案走通用版）。
  Future<void> _loadDevice() async {
    if (_polledDevice) return;
    _polledDevice = true;
    final name = await AppSettingsGuide.manufacturer();
    if (!mounted || name == null) return;
    setState(() => _manufacturer = name);
  }

  /// 跳系统设置页并把结果告诉用户（失败也给手动步骤，不让按钮点了没反应）。
  Future<void> _openSystemSettings({required bool startup}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = startup
        ? await AppSettingsGuide.openBackgroundSettings()
        : await AppSettingsGuide.openBatterySettings();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('classReminderSnack'),
          duration: const Duration(seconds: 5),
          persist: false,
          content: Text(result.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(classReminderPrefsStoreProvider);
    final prefs = store.prefs;
    final accent = fp(context).cardAccent;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('classReminderSwitch'),
            value: prefs.enabled,
            onChanged: (next) => _setEnabled(context, ref, next),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            secondary: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.tint(context, accent, 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.alarm_on_outlined, color: accent, size: 22),
            ),
            title: const Text(
              '上课提醒',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '上课前起显示一条常驻通知：下节课的课程名与教室，上课时自动消失'
              '（Android；Windows 暂不支持常驻通知）',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.stroke(context)),
          // 关掉开关时「提前多久」整行置灰且点不动（值仍然保留，下次开回来还在）。
          Opacity(
            opacity: prefs.enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !prefs.enabled,
              child: ListTile(
                key: const Key('classReminderLeadRow'),
                contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                leading: Icon(
                  Icons.timer_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                title: const Text('提前多久提醒', style: TextStyle(fontSize: 14)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      classReminderLeadLabel(prefs.leadMinutes),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
                onTap: () => _pickLead(context, ref, prefs.leadMinutes),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('classReminderTest'),
                onPressed: () => _sendTest(context),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('发送测试提醒'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              '课表数据来自本地缓存（离线也有）；提醒预排未来一周，'
              '每次回到 App 会自动往后滚动。测试提醒会在 5 秒后出现、15 秒后自动消失。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          // 后台保护引导（仅 Android 原生侧有这套系统页；桌面端自动隐藏）。
          if (AppSettingsGuide.isSupported) ...[
            Divider(height: 1, thickness: 1, color: AppColors.stroke(context)),
            SettingsClassReminderProtectHint(
              manufacturer: _manufacturer,
              onOpenStartup: () => _openSystemSettings(startup: true),
              onOpenBattery: () => _openSystemSettings(startup: false),
            ),
          ],
        ],
      ),
    );
  }

  /// 开关：写偏好 → 立即重排（关掉时清空排期）→ 提示。
  Future<void> _setEnabled(BuildContext context, WidgetRef ref, bool next) async {
    final store = ref.read(classReminderPrefsStoreProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await store.save(store.prefs.copyWith(enabled: next));
    unawaited(ref.read(classReminderSyncProvider).syncNow(force: true));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('classReminderSnack'),
          duration: const Duration(seconds: 3),
          persist: false,
          content: Text(next ? '已开启上课提醒' : '已关闭上课提醒'),
        ),
      );
  }

  /// 测试提醒：当场排一条 5 秒后出现、15 秒后自动消失的常驻通知。
  ///
  /// 手机上没有「攒着等某节课」的耐心 —— 这个按钮让用户立刻看到通知长什么样、
  /// 以及「到点自动消失」是不是真的（2026-09-23 加）。
  Future<void> _sendTest(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await sendTestClassReminder();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('classReminderSnack'),
          duration: const Duration(seconds: 3),
          persist: false,
          content: Text(
            ok
                ? '已排一条测试提醒：5 秒后出现，15 秒后自动消失'
                : '测试提醒排期失败（通知被系统关闭或平台不支持）',
          ),
        ),
      );
  }

  /// 提前量：底部弹层选一个（5/10/15/20/30/45/60 分钟）。
  Future<void> _pickLead(BuildContext context, WidgetRef ref, int current) async {
    // messenger 在 await 之前取好（跨 await 用 context 会被
    // `use_build_context_synchronously` 判为隐患）。
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      // 7 个选项在小屏 / 横屏会超过半屏高度 → 可滚动（否则弹层内部溢出）。
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        key: const Key('classReminderLeadSheet'),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '提前多久提醒',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              for (final minutes in classReminderLeadOptions)
                ListTile(
                  key: Key('classReminderLead-$minutes'),
                  dense: true,
                  title: Text(classReminderLeadLabel(minutes)),
                  trailing: minutes == current
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: fp(sheetContext).cardAccent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(minutes),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;

    final store = ref.read(classReminderPrefsStoreProvider);
    await store.save(store.prefs.copyWith(leadMinutes: picked));
    // 提前量变了 → 每条提醒的触发时刻都变，立刻重排（幂等：内容一样就不动系统闹钟）。
    unawaited(ref.read(classReminderSyncProvider).syncNow(force: true));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('classReminderSnack'),
          duration: const Duration(seconds: 3),
          persist: false,
          content: Text('已改为${classReminderLeadLabel(picked)}提醒'),
        ),
      );
  }
}

/// 「后台保护」引导（2026-10-08 加 · 课前提醒在华为 / 荣耀上不弹的根治步骤）。
///
/// 事实依据：华为官方支持文档「The alarm does not go off as scheduled」的
/// **第三方闹钟类应用**一节 —— 「If the app is not allowed to run in the background,
/// or is cleared from the background, it will not schedule an alarm.」，
/// 给的解法就是：① 设置里允许**自启动 / 关联启动 / 后台活动**；② 最近任务里
/// **下拉锁定**；③ 允许开机启动。第三方应用**没有任何 API 能自己开这些开关**，
/// 所以这里只做两件事：说清步骤 + 把用户送到那个设置页。
///
/// 纯展示组件（无状态、不碰 provider）：两个回调由卡片提供，文案随厂商名换一版
/// （华为 / 荣耀点名「应用启动管理」，其它品牌说通用说法）——**文案不参与控制流**，
/// 能不能跳过去由原生侧逐条 `resolveActivity` 决定。
class SettingsClassReminderProtectHint extends StatelessWidget {
  const SettingsClassReminderProtectHint({
    super.key,
    required this.manufacturer,
    required this.onOpenStartup,
    required this.onOpenBattery,
  });

  /// 厂商名（`Build.MANUFACTURER`），未取到时用通用文案。
  final String? manufacturer;

  /// 「打开启动管理 / 自启动设置」。
  final VoidCallback onOpenStartup;

  /// 「打开电池优化设置」。
  final VoidCallback onOpenBattery;

  /// 是不是华为 / 荣耀系（`HUAWEI` / `HONOR` / 鸿蒙）。
  bool get _isHuaweiStyle {
    final name = manufacturer?.toLowerCase() ?? '';
    return name.contains('huawei') || name.contains('honor');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fp(context).cardAccent;
    final title = _isHuaweiStyle
        ? '华为 / 荣耀：需要允许后台运行与自启动'
        : '收不到提醒？给应用开后台保护';
    final body = _isHuaweiStyle
        ? '鸿蒙 / EMUI 在你从最近任务划掉本应用后，会连它排好的闹钟一起停掉，'
              '提醒就不会弹。请：① 在下面的「应用启动管理」里关掉自动管理，'
              '打开自启动、关联启动、后台活动；② 在最近任务里把本应用**下拉**，'
              '出现锁图标即锁定成功。'
        : '部分系统在你从最近任务划掉本应用后，会连它排好的闹钟一起停掉，'
              '提醒就不会弹。请到系统设置里允许本应用自启动 / 后台运行，'
              '并把电池策略设为「不优化」。';
    return Padding(
      key: const Key('classReminderProtectHint'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 17, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: const Key('classReminderOpenStartup'),
                onPressed: onOpenStartup,
                icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                label: const Text('打开启动管理'),
              ),
              TextButton.icon(
                key: const Key('classReminderOpenBattery'),
                onPressed: onOpenBattery,
                icon: const Icon(Icons.battery_saver_outlined, size: 18),
                label: const Text('电池优化设置'),
              ),
            ],
          ),
          Text(
            '点上面两个按钮会跳转到系统设置页；找不到对应开关时，'
            '可手动进「设置 → 应用 → 应用启动管理」。',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
