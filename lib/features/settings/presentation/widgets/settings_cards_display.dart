/// `settings_cards.dart` 的「display」一组（2026-10-08 架构审计第三轮 · 按类拆文件）。
///
/// 拆分自 `settings_cards.dart`（2297 行 / 20 个 widget 类）：调用方**不用改** —— 桶文件
/// `export` 了本文件。共用顶层件（`settingsClearSentinel` / `SettingsSubLabel`）留在桶里，
/// 故这里反向 import 桶文件（Dart 允许互相 import，见 AGENTS.md §33.4.4 ②）。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/home/data/home_edit_mode.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_radius.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';

/// 「生效范围」说明卡：把设置后的三处影响讲清楚。
class SettingsEffectCard extends StatelessWidget {
  final MyCampus? mine;

  const SettingsEffectCard({
      super.key,
      required this.mine});

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
                        decoration: BoxDecoration(
                          color: fp(context).cardAccent,
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

/// 「主页布局」卡：宫格视图 / 左侧导航栏（用户 2026-09-15 裁定）。
///
/// 切换入口**只在这里**（不往顶栏加按钮），选择落 Hive `homePrefs`
/// （`HomeLayoutStore`，改动即时通知 → 主页无需重进即跟随）；
/// 手机端恒为宫格，判定集中在 `features/home/domain/home_layout.dart`。
/// 「外观」节：跟随系统 / 浅色 / 深色（用户 2026-09-16 拍板，默认跟随系统）。
///
/// - 选择存 Hive（`features/settings/data/theme_prefs.dart`），`MaterialApp.themeMode`
///   直接 `watch` 同一个 store → 点一下立即整树重建，中间没有「先闪一次旧值」的空窗。
/// - 深色配色 = **A 中性深灰** + 亮红强调（`lib/design/app_ladder.dart` /
///   `lib/design/app_theme.dart`），取值来自用户过目过的
///   `design_preview/dark_mode_preview.html`。
class SettingsAppearanceCard extends ConsumerWidget {
  const SettingsAppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(themeModeStoreProvider);
    final accent = fp(context).cardAccent;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final mode in ThemeMode.values)
            InkWell(
              key: Key('themeModeOption-${mode.name}'),
              onTap: () => store.save(mode),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      mode == store.mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: mode == store.mode
                          ? accent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            themeModeLabel(mode),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            themeModeDescription(mode),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              '深色外观为中性深灰底 + 亮红强调色，卡片、文字、分隔线会一并切换；'
              '首次安装默认跟随系统。',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsHomeLayoutCard extends ConsumerWidget {
  const SettingsHomeLayoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(homeLayoutStoreProvider);
    final gridStore = ref.watch(homeGridStoreProvider);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final value in HomeLayout.values)
            InkWell(
              key: Key('homeLayoutOption-${value.name}'),
              onTap: () => store.save(value),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      value == store.layout
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: value == store.layout
                          ? fp(context).cardAccent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.label,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              '侧栏视图只在电脑端生效（窗口宽度 ≥ '
              '${homeSidebarMinWidth.toInt()}px）；手机端始终是宫格视图。',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          // 卡片形态（用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，
          // 然后都是在设置了可选的。可以都不显示为卡片样式」+「要阴影」）。
          // 四档 = 两块区域「选 / 不选」的全部组合；默认「都不显示」，
          // 与改造前逐像素一致（见 `HomeCardStyle` 与 `lib/design/card_frame.dart`）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '卡片样式',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '把侧栏 / 内容区框成浮起的圆角卡片（带阴影），与窗口边缘留一道缝；'
              '只在侧栏视图（电脑端）下可见。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final value in HomeCardStyle.values)
            InkWell(
              key: Key('homeCardOption-${value.name}'),
              onTap: () => store.saveCardStyle(value),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      value == store.cardStyle
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: value == store.cardStyle
                          ? fp(context).cardAccent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.label,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          // 卡片间距（用户 2026-10-09 三轮原话：「我希望卡片与卡片之间的距离为 2a、
          // 卡片与窗口之间（卡片与标题栏之间的距离不受此限制）的距离为 a；
          // 然后 a 可以通过设置调」）。滑杆按 `kCardGapStops` 吸附，落盘整数文本。
          _cardGapRow(context, scheme, store),
          const Divider(height: 1),
          // 宫格聚合（用户 2026-09-21 需求）：拖动说明 + 恢复默认布局。
          // 拖动/合并发生在**主页宫格**上，这里只放口径说明与兜底按钮
          // （用户 2026-09-11 裁定「偏好入口一律收在设置页」）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '宫格聚合',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '长按功能本身（图标 / 文字那一块）只拖动这一个功能；长按卡片其余部分'
                  '（功能四周的空白与格与格之间的缝）拖动整张卡片。'
                  '拖到另一张卡片的边缘（最外侧约三分之一）'
                  '松手即合并成一张卡片，拖到卡片中间不会合并、而是把压到的卡片挤开让位。'
                  '聚合卡片可以是不规则形状，互补的形状能相互嵌合。'
                  '下面打开「编辑模式」后回到主页：卡片里出现分割线，点分割线断开这一处，'
                  '退出时仍然连着的会自动接回去；该模式下拖动不必长按（按下即可拖，'
                  '也可以点一下拿起、再点一下放下），点空白处可把拿起的卡片放下。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // 编辑模式开关（用户 2026-09-21 十三轮原话：「我希望标题栏不显示编辑模式按钮和
                // 重置按钮，这两个都放到设置里」）—— 原来这枚剪刀按钮在主页顶栏，位置太显眼、
                // 也容易误触；开关本身是跨页面的一次性状态，见 [homeEditModeProvider]。
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '编辑模式',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Switch(
                      key: const Key('homeEditModeSwitch'),
                      value: ref.watch(homeEditModeProvider),
                      onChanged: (next) => _setEditMode(context, ref, next),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _gridSummary(gridStore),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('homeGridReset'),
                      // 先退出编辑模式再重置：那些「断开」是临时状态，退出时会结算落盘
                      // （见 §17.10），留着会让「恢复默认布局」看起来没生效。
                      onPressed: () {
                        _setEditMode(context, ref, false);
                        unawaited(gridStore.reset());
                      },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('恢复默认布局'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「卡片间距」那一行（滑杆 + 当前派生量）。只在**有卡片**时才有意义，所以
  /// 「都不显示」时压暗并禁用（不是藏起来：藏了用户会以为这功能不存在）。
  Widget _cardGapRow(
    BuildContext context,
    ColorScheme scheme,
    HomeLayoutStore store,
  ) {
    final enabled = store.cardStyle.anyCard;
    final gap = cardGapMetricsOf(store.cardGap);
    final label = TextStyle(
      fontSize: 12.5,
      height: 1.3,
      color: enabled ? scheme.onSurfaceVariant : scheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '卡片间距',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? scheme.onSurface : scheme.outline,
                  ),
                ),
              ),
              Text(
                '卡片之间 ${_num(gap.between)} · 距窗口 ${_num(gap.edge)}',
                key: const Key('homeCardGapSummary'),
                style: label,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '设定值 a = ${_num(store.cardGap)}：卡片与卡片之间、卡片与窗口左 / 右 / 底边'
            '的距离都是 a（与标题栏之间不留缝，不受此限）。',
            style: label,
          ),
          Slider(
            key: const Key('homeCardGapSlider'),
            value: store.cardGap,
            min: kCardGapMin,
            max: kCardGapMax,
            // **每 1 像素一档**（用户 2026-10-09 十四轮：「我希望卡片间距可以调整的最小
            // 步长应该是 1，现在是 2」）。`divisions` = 22 **段** → 23 个刻度
            // （2, 3, …, 24，每段正好 1），与 `kCardGapStops`（2..24 全部整数，23 格）
            // 同口径；`snapCardGap` 在现行档位表下是恒等映射，留着当"落盘值必在允许
            // 集合内"的保险。
            // ⚠ **别只改这里不改 `kCardGapStops`**：上一版的 bug 就是"滑杆每格 1、
            // 档位表却很稀"，拖到 5 被吸附回 4/6，看起来像步长 2。
            divisions: (kCardGapMax - kCardGapMin).round(),
            label: _num(store.cardGap),
            onChanged: enabled
                ? (next) => unawaited(store.saveCardGap(snapCardGap(next)))
                : null,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('a 越小越紧凑', style: label),
              const Spacer(),
              TextButton(
                key: const Key('homeCardGapReset'),
                onPressed: enabled
                    ? () => unawaited(store.saveCardGap(kCardGapDefault))
                    : null,
                child: const Text('恢复默认'),
              ),
            ],
          ),
          const Divider(height: 20),
          // 卡片圆角：用户 2026-10-09 十五轮「我希望卡片圆角大小也是可控的」。
          Row(
            children: [
              Expanded(
                child: Text(
                  '卡片圆角',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? scheme.onSurface : scheme.outline,
                  ),
                ),
              ),
              Text(
                '${_num(store.cardRadius)} px',
                key: const Key('homeCardRadiusSummary'),
                style: label,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '区域卡片的圆角大小；0 = 直角（纯色块 + 投影）。'
            '只影响侧栏 / 内容区这两张区域卡片，不影响页面里的小卡。',
            style: label,
          ),
          Slider(
            key: const Key('homeCardRadiusSlider'),
            value: store.cardRadius,
            min: kCardRadiusMin,
            max: kCardRadiusMax,
            // 每 1 像素一档：`divisions` 是**段数**（28 段 → 29 个刻度 0..28），
            // 与 `kCardRadiusStops`（0..28 每个整数，29 格）同口径 ——
            // 与间距那条同一教训（十四轮），别让两处口径不一致。
            divisions: (kCardRadiusMax - kCardRadiusMin).round(),
            label: _num(store.cardRadius),
            onChanged: enabled
                ? (next) => unawaited(store.saveCardRadius(snapCardRadius(next)))
                : null,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('0 = 直角，越大越圆', style: label),
              const Spacer(),
              TextButton(
                key: const Key('homeCardRadiusReset'),
                onPressed: enabled
                    ? () => unawaited(store.saveCardRadius(kCardRadiusDefault))
                    : null,
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 去掉小数的整数写法（档位都是整数，`6.0` 读起来别扭）。
  String _num(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  /// 拨「编辑模式」开关（原主页顶栏的剪刀按钮）。
  ///
  /// 提示给在**这里**：用户拨开关时人在设置页，而模式生效在主页 —— 不说明一句，
  /// 回到主页前完全看不到反馈（宫格此时多半还在屏幕外）。
  void _setEditMode(BuildContext context, WidgetRef ref, bool next) {
    ref.read(homeEditModeProvider.notifier).state = next;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('homeGridEditHint'),
          duration: const Duration(seconds: 4),
          content: Text(
            next
                ? '编辑模式已打开：回到主页，卡片里会出现分割线（点分割线断开 / 接回），'
                      '拖动也不必长按'
                : '已退出编辑模式：真的分成两块的才保留',
          ),
        ),
      );
  }

  /// 聚合布局现状（给用户一句「现在是什么状态」）。
  String _gridSummary(HomeGridStore store) {
    final layout = store.layout;
    if (layout == null) return '当前为默认布局（未自定义）。';
    final groups = layout.groupCount;
    return '已自定义：${layout.tiles.length} 张卡片'
        '${groups > 0 ? '，其中 $groups 张是聚合卡片' : ''}。';
  }
}
