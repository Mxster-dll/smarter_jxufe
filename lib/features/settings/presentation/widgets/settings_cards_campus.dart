/// `settings_cards.dart` 的「campus」一组（2026-10-08 架构审计第三轮 · 按类拆文件）。
///
/// 拆分自 `settings_cards.dart`（2297 行 / 20 个 widget 类）：调用方**不用改** —— 桶文件
/// `export` 了本文件。共用顶层件（`settingsClearSentinel` / `SettingsSubLabel`）留在桶里，
/// 故这里反向 import 桶文件（Dart 允许互相 import，见 AGENTS.md §33.4.4 ②）。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 「我的校区」选择入口卡。
///
/// 副标题讲清**这个值是谁给的**（用户 2026-09-20 要求校区设置接数据中心）：
/// - 手选过 → 以手选为准；数据中心那一份如果不一样，多一行提示（不自动改）；
/// - 从没设过 → 由数据中心的值自动补空（[MyCampusSource.center]）；
/// - 数据中心也取不到 → 「未设置 · 点击选择」，照旧手选（这就是「获取失败再手动设置」）。
class SettingsMyCampusTile extends StatelessWidget {
  final MyCampus? mine;
  final MyCampusSource? source;
  final MyCampus? center;
  final VoidCallback onTap;

  const SettingsMyCampusTile({
      super.key,
    
    required this.mine,
    required this.source,
    required this.center,
    required this.onTap,
  });

  /// 值来源的角标文案。
  ///
  /// 老存档（本功能之前设的）只写了 `campus` 一个键 → 没有来源标记；那时候的值
  /// 只可能是用户在设置页手选的，故照样标「手动设置」（别显示成一片空白）。
  String get _sourceBadge =>
      source == MyCampusSource.center ? '数据中心' : '手动设置';

  /// 校区名下面那一行小字。
  String get _subtitle {
    final mine = this.mine;
    final hint = center;
    if (mine == null) {
      return hint == null ? '未设置 · 点击选择' : '正在采用数据中心的值…';
    }
    final head = '${mine.label} · $_sourceBadge';
    if (hint != null && hint != mine) {
      return '$head（数据中心显示：${hint.label}）';
    }
    return head;
  }

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
                  color: AppColors.tint(context, fp(context).cardAccent, 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.place_outlined,
                  color: fp(context).cardAccent,
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
                      _subtitle,
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

/// 默认教学楼选择弹层：**先选校区、再选楼房**（楼房码只在所属校区内才有意义）。
///
/// 预选口径 = ① 已存的默认教学楼（校区 + 楼房原样回填）；② 否则「我的校区」按名匹配
/// （`matchPublicQueryOption`，与 `classroom_free_screen.dart` 的
/// `_applyCampusDefault` 同口径）；③ 都拿不到就留空，绝不猜。
/// ⚠ 「**拿到值才落闸**」：`myCampusStoreProvider` 是异步加载的，首帧还没值就置位会让
/// 「我的校区」永远匹配不上（照 `classroom_free_screen.dart:158-167`）。
class SettingsBuildingPickerSheet extends ConsumerStatefulWidget {
  const SettingsBuildingPickerSheet({super.key});

  @override
  ConsumerState<SettingsBuildingPickerSheet> createState() =>
      SettingsBuildingPickerSheetState();
}

class SettingsBuildingPickerSheetState extends ConsumerState<SettingsBuildingPickerSheet> {
  /// 当前选中的校区码 / 楼房码（`''` = 未选）。
  String _campus = '';
  String _building = '';

  /// 是否已做过一次预选 —— `build` 每帧都会跑，重复预选会冲掉用户刚做的选择。
  bool _defaultsApplied = false;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMuted(context);
    final store = ref.watch(publicQueryPrefsStoreProvider);
    final campuses = ref.watch(publicQueryCampusesProvider).valueOrNull ?? [];
    if (!_defaultsApplied && _campus.isEmpty && campuses.isNotEmpty) {
      final saved = store.defaultBuilding;
      if (saved != null &&
          saved.campusCode.isNotEmpty &&
          campuses.any((c) => c.code == saved.campusCode)) {
        _defaultsApplied = true;
        _campus = saved.campusCode;
        _building = saved.buildingCode;
      } else {
        final myCampus = ref.read(myCampusStoreProvider).campus?.label ?? '';
        if (myCampus.isNotEmpty) {
          _defaultsApplied = true;
          final matched = matchPublicQueryOption(campuses, myCampus);
          if (matched != null) _campus = matched.code;
        }
      }
    }
    final buildingsAsync = _campus.isEmpty
        ? null
        : ref.watch(publicQueryBuildingsProvider(_campus));
    final buildings = buildingsAsync?.valueOrNull ?? [];
    // 只认列表里真有的码 —— `DropdownButton.value` 必须是某个 item，否则直接断言。
    final selected = buildings.any((b) => b.code == _building) ? _building : '';
    final buildingHint = buildingsAsync == null
        ? '请先选择校区'
        : (buildingsAsync.hasError ? '楼房列表加载失败' : '请选择楼房');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '默认教学楼',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _row(
              context,
              icon: Icons.location_city_outlined,
              label: '校区',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('settingsBuildingCampusPicker'),
                  isExpanded: true,
                  value: _campus.isEmpty ? null : _campus,
                  hint: Text(
                    '请选择校区',
                    style: TextStyle(fontSize: 13.5, color: muted),
                  ),
                  items: [
                    for (final c in campuses)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text(c.displayName),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _campus = v ?? '';
                    _building = '';
                  }),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _row(
              context,
              icon: Icons.apartment_outlined,
              label: '楼房',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('settingsBuildingPicker'),
                  isExpanded: true,
                  value: selected.isEmpty ? null : selected,
                  hint: Text(
                    buildingHint,
                    style: TextStyle(fontSize: 13.5, color: muted),
                  ),
                  items: [
                    for (final b in buildings)
                      DropdownMenuItem(
                        value: b.code,
                        child: Text(b.displayName),
                      ),
                  ],
                  onChanged: (v) => setState(() => _building = v ?? ''),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '「找空闲教室」打开时会自动选中这栋楼；若它不在当前校区，就不预选。',
              style: TextStyle(fontSize: 12, height: 1.5, color: muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  key: const Key('settingsBuildingClear'),
                  onPressed: store.defaultBuilding == null
                      ? null
                      : _clearSelection,
                  child: const Text('清除'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('settingsBuildingSave'),
                  onPressed: selected.isEmpty ? null : _saveSelection,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 弹层里的一行：图标 + 定宽标签 + 控件（与 `classroom_free_screen.dart` 的 `_row`
  /// 同款，两处保持一种观感）。
  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) => Row(
    children: [
      Icon(icon, size: 17, color: AppColors.textMuted(context)),
      const SizedBox(width: 8),
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted(context)),
        ),
      ),
      Expanded(child: child),
    ],
  );

  /// 保存默认教学楼（校区名 / 楼房名一并落库 —— 找空闲教室只认 code，名字是给人看的）。
  Future<void> _saveSelection() async {
    final campuses = ref.read(publicQueryCampusesProvider).valueOrNull ?? [];
    final buildings =
        ref.read(publicQueryBuildingsProvider(_campus)).valueOrNull ?? [];
    var campusName = '';
    for (final c in campuses) {
      if (c.code == _campus) campusName = c.displayName;
    }
    var buildingName = '';
    for (final b in buildings) {
      if (b.code == _building) buildingName = b.displayName;
    }
    await ref.read(publicQueryPrefsStoreProvider).saveBuilding(
      PublicQueryBuilding(
        campusCode: _campus,
        campusName: campusName,
        buildingCode: _building,
        buildingName: buildingName,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 清除默认教学楼（`saveBuilding(null)`）—— 之后「找空闲教室」回到「我的校区」口径。
  Future<void> _clearSelection() async {
    await ref.read(publicQueryPrefsStoreProvider).saveBuilding(null);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
