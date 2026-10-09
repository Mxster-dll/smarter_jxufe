/// 「窗口标题栏」设置卡（2026-10-09 立）—— 用户原话：
/// 「设置里可以调关于此标题栏的两项：① 交换左侧应用 logo 与右侧三键的位置，变成
/// 左侧三键，右侧 logo；② 允许选择 win 风格三键与 mac 风格」。
///
/// 归在设置页的**外观**节（紧挨主题卡）：它改的就是应用的外观；两项都即时生效
/// （`WindowBarPrefsStore` 是 `ChangeNotifier`，标题栏 `watch` 同一个实例）。
///
/// **非 Windows 平台整卡不画**（判据 = `windowTitleBarSupported(context)`）：
/// Android / iOS 没有窗口 chrome，Linux / macOS 还没实现原生侧 —— 那边标题栏
/// 根本不存在，摆两个改不动的开关只会让人以为是坏的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/window_title_bar.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards.dart';

/// 窗口标题栏两项设置。窗口里没有自绘标题栏时整卡不画。
class SettingsWindowBarCard extends ConsumerWidget {
  const SettingsWindowBarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!windowTitleBarSupported(context)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final accent = fp(context).cardAccent;
    final store = ref.watch(windowBarPrefsProvider);
    final buttonsOnLeft = store.buttonsOnLeft;
    return Card(
      elevation: 0,
      // 本节（外观）里它是第二张卡：自带 12 的上边距，非 Windows 整块 shrink 时不留空。
      margin: const EdgeInsets.only(top: 12),
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SettingsSubLabel(
              icon: Icons.web_asset_outlined,
              title: '窗口标题栏',
              subtitle: '系统标题栏已隐藏，顶部这条栏由应用自己画（Windows 桌面）',
              accent: accent,
            ),
          ),
          // ① 位置：logo 与三键互换。
          SwitchListTile(
            key: const Key('windowBarSwapSides'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            dense: true,
            value: store.swapSides,
            onChanged: (value) => store.saveSwapSides(value),
            title: const Text(
              '交换 logo 与三键的位置',
              style: TextStyle(fontSize: 13.5),
            ),
            subtitle: Text(
              buttonsOnLeft
                  ? '当前：三键在左、logo 在右'
                  : '当前：logo 在左、三键在右',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          const Divider(height: 1),
          // ② 风格：Windows / macOS。
          for (final style in WindowButtonsStyle.values)
            InkWell(
              key: Key('windowButtonsStyle-${style.name}'),
              onTap: () => store.saveStyle(style),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      style == store.style
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: style == store.style
                          ? accent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            windowButtonsStyleLabel(style),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            windowButtonsStyleDescription(style),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '标题栏支持拖动、双击最大化 / 还原、右键系统菜单、边缘缩放与贴靠'
              '（含 Win11 贴靠布局）；这些是系统行为，两种风格都有。',
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
