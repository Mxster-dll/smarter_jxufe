/// 材料库的两个「挑一个」页面（2026-09-20 从 `materials_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原同文件私有件 `_MaterialTypePickerPage`（选材料类型，83 行）/ `_ActivityPickPage` + State
/// （选活动，213 行）+ 两个顶层小函数 `_dimLabel` / `_zcTypeIcon` —— 整体搬到本文件并改为公开名
/// （`_` 是库私有，跨文件即不可见）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/section_title.dart';

import 'package:smarter_jxufe/design/app_card.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';

String materialDimLabel(String dim) => switch (dim) {
  'z' => '智育',
  'd' => '德育',
  't' => '体育',
  'm' => '美育',
  'l' => '劳育',
  _ => '',
};

IconData materialTypeIcon(ZcTypeId id) => switch (id) {
  ZcTypeId.contest => Icons.emoji_events_outlined,
  ZcTypeId.paper => Icons.description_outlined,
  ZcTypeId.foreign => Icons.translate,
  ZcTypeId.startup => Icons.rocket_launch_outlined,
  ZcTypeId.honorP || ZcTypeId.honorG => Icons.workspace_premium_outlined,
  ZcTypeId.deed => Icons.favorite_outline,
  ZcTypeId.eduCon || ZcTypeId.eduPart => Icons.school_outlined,
  ZcTypeId.servicePost => Icons.groups_outlined,
  ZcTypeId.sportComp ||
  ZcTypeId.psych ||
  ZcTypeId.sportTeam => Icons.directions_run,
  ZcTypeId.artsComp || ZcTypeId.artAct => Icons.palette_outlined,
  ZcTypeId.media => Icons.campaign_outlined,
  ZcTypeId.social => Icons.handshake_outlined,
  ZcTypeId.laborAct => Icons.construction_outlined,
  ZcTypeId.dorm => Icons.home_outlined,
};

/// 第一级页：19 类活动（材料类型）按五育分组，点选返回 [ZcTypeId]。
class MaterialTypePickerPage extends StatelessWidget {
  const MaterialTypePickerPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('选择活动类型'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              '第一步 · 这份证明材料属于哪一类活动？',
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
          ),
          for (final dim in _dimOrder) ..._dimSection(context, dim),
        ],
      ),
    );
  }

  List<Widget> _dimSection(BuildContext context, String dim) {
    final scheme = Theme.of(context).colorScheme;
    final specs = [
      for (final s in zcTypeSpecs)
        if (s.dim == dim) s,
    ];
    if (specs.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(
          children: [
            appSectionTitle(
              context,
              text: '${materialDimLabel(dim)} · ${specs.length}',
            ),
          ],
        ),
      ),
      for (final s in specs)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: appCardShape(context),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.tint(context, scheme.primary, 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(materialTypeIcon(s.id), size: 19, color: scheme.primary),
            ),
            title: Text(
              s.label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              s.section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.outlineVariant,
            ),
            onTap: () => Navigator.of(context).pop(s.id),
          ),
        ),
    ];
  }
}

/// 第二级页：某类型的具体活动/档位候选；点选返回 [_PickOutcome]。
class ActivityPickPage extends StatefulWidget {
  final ZcTypeSpec spec;

  /// 选中候选（或「直接填写」传 `null`）后的处理，返回是否保存成功。
  /// 由本页调用而不是 `pop` 返回值：本页要**留在路由栈上**以便连续添加。
  final Future<bool> Function(ZcActivityItem? item) onPicked;

  const ActivityPickPage({required this.spec, required this.onPicked});

  @override
  State<ActivityPickPage> createState() => ActivityPickPageState();
}

class ActivityPickPageState extends State<ActivityPickPage> {
  late final List<ZcActivityItem> _all;
  final _searchCtrl = TextEditingController();
  String _q = '';

  ZcTypeSpec get _spec => widget.spec;
  bool get _isContest => _spec.id == ZcTypeId.contest;

  @override
  void initState() {
    super.initState();
    _all = zcActivityItems(_spec);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 搜索口径 = `zcActivityMatches`（去空白/标点/零宽 + 关键词/别名/复合赛事
  /// 子项，用户 2026-09-18：搜「大数据挑战赛」「华为ICT大赛」都要命中）。
  List<ZcActivityItem> _visible() => [
    for (final it in _all)
      if (zcActivityMatches(it, _q)) it,
  ];

  Future<void> _pick(ZcActivityItem it) async {
    final saved = await widget.onPicked(it);
    if (!mounted || !saved) return;
    // 保存成功 → 清空搜索、留在本页继续挑下一个（用户要求「停留在竞赛选择页」）。
    _searchCtrl.clear();
    setState(() => _q = '');
  }

  Future<void> _direct() => widget.onPicked(null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _visible();
    return Scaffold(
      appBar: AppBar(title: Text(_spec.label), centerTitle: false),
      body: Column(
        children: [
          if (_isContest)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: '搜索比赛名称，如 数学建模 / RoboMaster / CCPC',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kAppCardRadius),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text(
                    _isContest
                        ? '第二步 · 选择比赛（自动带回名称与类别，共 ${_all.length} 项）'
                        : '第二步 · 选择具体档位/名目（级别自动预选，可再改）',
                    style: TextStyle(fontSize: 12.5, color: scheme.outline),
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text(
                      '未找到匹配「$_q」的比赛，可直接在下方手动填写',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: scheme.outline),
                    ),
                  )
                else
                  ...(_isContest
                      ? _grouped(context, items)
                      : [for (final it in items) _candidateTile(context, it)]),
                const SizedBox(height: 12),
                _directCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 竞赛目录按 Ⅰ~Ⅳ 类分组（「其他」项不分组直排）。
  List<Widget> _grouped(BuildContext context, List<ZcActivityItem> items) {
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[];
    String? cur;
    for (final it in items) {
      if (it.other) {
        out.add(_candidateTile(context, it));
        continue;
      }
      if (it.group != null && it.group != cur) {
        cur = it.group;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: Text(
              cur!,
              style: TextStyle(
                fontSize: 12,
                color: scheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      out.add(_candidateTile(context, it));
    }
    return out;
  }

  Widget _candidateTile(BuildContext context, ZcActivityItem it) {
    final scheme = Theme.of(context).colorScheme;
    final icon = it.other
        ? Icons.edit_outlined
        : (_isContest ? Icons.emoji_events_outlined : Icons.tune);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: appCardShape(context),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tint(context, scheme.primary, 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: scheme.primary),
        ),
        title: Text(
          it.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: it.other
            ? Text(
                '手动填写名称（比赛类将自动识别类别）',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          size: 18,
          color: scheme.outlineVariant,
        ),
        onTap: () => _pick(it),
      ),
    );
  }

  Widget _directCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: appCardShape(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        onTap: _direct,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(Icons.create_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '直接填写（不选具体活动）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isContest ? '手动输入比赛名称，提交时将自动识别类别' : '手动填写名称与档位',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

const _dimOrder = ['z', 'd', 't', 'm', 'l'];
