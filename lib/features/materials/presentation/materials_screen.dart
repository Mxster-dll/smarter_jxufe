import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/section_title.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/materials/presentation/material_pick_pages.dart';
import 'package:smarter_jxufe/features/materials/presentation/widgets/material_edit_dialog.dart';
import 'package:smarter_jxufe/features/materials/domain/material_grouping.dart';
import 'package:smarter_jxufe/features/materials/presentation/material_tags.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/design/app_states.dart';

/// 材料库：独立于综测的证明文件档案（竞赛证书/奖状/评优证明等），
/// 作为综测计算的数据源之一（同 Hive box 'zongce' key 'materials'）。
///
/// 本页 watch zcMaterialsProvider；增删改保存后 invalidate 同一 provider，
/// 测算页（watch 同源）随即自动重算，无需手动同步。
class MaterialsScreen extends ConsumerStatefulWidget {
  const MaterialsScreen({super.key});

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  // ---------- 主体 ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: paneAppBar(context, title: const Text('材料库'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMaterial,
        icon: const Icon(Icons.add),
        label: const Text('添加材料'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matsAsync = ref.watch(zcMaterialsProvider);
    return matsAsync.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        title: '材料加载失败',
        error: e,
        retryIcon: false,
        onRetry: () => ref.invalidate(zcMaterialsProvider),
      ),
      data: (all) {
        // 材料**不分学年**（用户 2026-09-17：「所有的材料本身不分学年，只手动填入
        // 时间」）→ 全部材料一屏，不再按学年过滤/切换；综测侧也全量计入。
        final mats = all;
        if (mats.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
            children: [
              const SizedBox(height: 36),
              Icon(Icons.folder_open, size: 56, color: scheme.outlineVariant),
              const SizedBox(height: 16),
              const Text(
                '还没有证明材料',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '竞赛证书、奖状、评优证明等按类型录入留档，综合测评会自动读取计分，可附加证书照片作证明。\n材料不分学年，填好发生时间即可；综测会把全部材料计入。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.outline,
                  height: 1.6,
                ),
              ),
            ],
          );
        }
        // 分组口径 = **二级分类**（材料类型：学科竞赛获奖 / 论文 · 专利 / 外语水平…），
        // 不再按综测的「五育」分（用户 2026-09-18：「我希望材料库条目显示不要按综测
        // 分类，而是直接按二级分类分类，比如学科竞赛这样的」）。分组与组内排序的
        // 唯一实现 = `groupMaterialsByType`（lib/features/materials/domain/
        // material_grouping.dart），页面不再自己按 dim 分一遍。
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            for (final group in groupMaterialsByType(mats))
              ..._materialSection(context, group),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
              child: Text(
                '提示：证明材料仅在本档案中维护，不区分学年；综合测评会读取全部材料计分，'
                '分值口径与测评页计分明细一致。\n'
                '这里的竞赛获奖 / 专利 / 荣誉 / 论文会自动带入「推免成绩」与'
                '「竞赛奖励」的加分项（改这里，那两页当场跟着变）。',
                key: const Key('materialsAutoFillHint'),
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.outline,
                  height: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 一个二级分类分组 = 一行节标题（3px 竖条 + 类型名 + 条数）+ 该类型的材料行。
  ///
  /// 标题只写二级分类名（如「学科竞赛获奖」），**不再写「智育加分材料」这种综测口径**
  /// （用户 2026-09-18：「不要按综测分类，而是直接按二级分类分类」）；组内顺序由
  /// [groupMaterialsByType] 定（发生时间倒序），这里不再排序。
  List<Widget> _materialSection(BuildContext context, MaterialGroup group) {
    return [
      Padding(
        key: group.groupKey,
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: appSectionTitle(context, text: '${group.label} · ${group.count}'),
      ),
      for (final m in group.materials) _materialRow(context, m),
      const SizedBox(height: 4),
    ];
  }

  Widget _materialRow(BuildContext context, ZcMaterial m) {
    final scheme = Theme.of(context).colorScheme;
    final spec = m.spec;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: appCardShape(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        onTap: () => _editMaterial(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, scheme.primary, 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  materialTypeIcon(spec.id),
                  size: 19,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // 属性分色胶囊（用户 2026-09-18：「底部的国家级/省级、
                    // 一二三等奖 I/II/III/IV 类赛的颜色也不用那么浅，并且按不同
                    // 类别属性，要显示为不同色的胶囊」）。
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // ⚠ 行内**不再重复印类型名**：类型已经升级为分组标题
                        // （二级分类，用户 2026-09-18：「不要按综测分类，而是直接按
                        // 二级分类分类，比如学科竞赛这样的」）→ 每行再挂一枚同名的
                        // 中性墨蓝胶囊纯属重复。属性胶囊（类别 / 级别 / 奖项）照旧。
                        if (m.cat.isNotEmpty)
                          MaterialTag(
                            text: zcCatNames[m.cat] ?? '',
                            color: materialCategoryColor(m.cat),
                          ),
                        ...materialLevelTags(context, m),
                        if (m.dateIso.isNotEmpty)
                          Text(
                            m.dateIso,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (m.files.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.attach_file,
                                size: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 1),
                              Text(
                                '${m.files.length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 右侧：**不显示加分**（用户 2026-09-17：「材料页不显示加分」），
              // 改为显示该材料的备注（用户同日：「材料条目的右侧显示备注」）。
              // ⚠ 备注**不再限宽**（用户 2026-09-18：「材料库备注信息不要限制宽度」）
              // —— 原来套了 `maxWidth: 132`，稍长的备注定被截成「…」；现在用
              // `Flexible` 让它按需占位（左侧标题列是 `Expanded`，两边各分一半，
              // 短备注不会白占地方，长备注也不会被腰斩）。
              if (m.note.trim().isNotEmpty)
                Flexible(
                  child: Text(
                    m.note.trim(),
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    // 备注颜色与标题一致（用户 2026-09-18：「备注颜色不用那么浅，
                    // 颜色可以和标题一致」）——原来是 scheme.outline 的浅灰。
                    style: TextStyle(fontSize: 11, color: scheme.onSurface),
                  ),
                ),
              Icon(Icons.chevron_right, size: 18, color: scheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addMaterial() async {
    // 两级向导：先选活动类型，再选该类型下具体活动/档位，最后进表单补全。
    // **二级页留在路由栈上**、由它自己打开表单（用户 2026-09-17：「每添加完
    // 一个赛事后不要回到根页面，而是停留在竞赛选择页，以便连续添加」）——
    // 这样保存成功后就地留在候选页连续添加，也不会闪一下材料库根页。
    final type = await Navigator.of(context).push<ZcTypeId>(
      MaterialPageRoute(builder: (_) => const MaterialTypePickerPage()),
    );
    if (type == null || !mounted) return;
    final spec = zcTypeSpecOf[type]!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ActivityPickPage(
          spec: spec,
          onPicked: (item) => _openEditor(null, type: type, activity: item),
        ),
      ),
    );
  }

  void _editMaterial(ZcMaterial m) {
    _openEditor(m);
  }

  /// 打开材料表单；返回**是否保存成功**（向导据此决定是否留在二级页继续添加）。
  Future<bool> _openEditor(
    ZcMaterial? existing, {
    ZcTypeId? type,
    ZcActivityItem? activity,
  }) async {
    final store = await ref.read(zcStoreProvider.future);
    if (!mounted) return false;
    // 日期下限 = **入学年**（用户 2026-09-17：「学科竞赛日期选择器的年份范围应该
    // 最早是入学年份」）；学籍取不到时退回「今年 - 6」。
    int? enrollYear;
    try {
      enrollYear = (await ref.read(calendarViewerProvider.future)).enrollYear;
    } catch (_) {
      enrollYear = null;
    }
    if (!mounted) return false;
    final firstDate = DateTime(enrollYear ?? DateTime.now().year - 6, 1, 1);
    final result = await showDialog<MaterialEditResult>(
      context: context,
      builder: (_) => MaterialEditDialog(
        store: store,
        existing: existing,
        firstDate: firstDate,
        initialType: type,
        initialActivity: activity,
      ),
    );
    if (result == null || !mounted) return false;
    if (result is MaterialEditDelete) {
      final target = existing!;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除材料'),
          content: Text('确定删除「${target.displayName}」？附件文件将一并删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return false;
      try {
        final all = await store.loadMaterials();
        await store.deleteMaterial(all, target);
        if (!mounted) return false;
        ref.invalidate(zcMaterialsProvider);
      } catch (e) {
        if (!mounted) return false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
      return true;
    }
    final draft = (result as MaterialEditSave).draft;
    try {
      final all = await store.loadMaterials();
      if (existing == null) {
        final m = draft.toMaterial(id: const Uuid().v4());
        await store.saveMaterials([...all, m]);
      } else {
        final updated = draft.toMaterial(id: existing.id);
        await store.saveMaterials([
          for (final x in all)
            if (x.id == existing.id) updated else x,
        ]);
      }
      if (!mounted) return false;
      ref.invalidate(zcMaterialsProvider);
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      return false;
    }
    return true;
  }
}

// ===================================================================
// 材料编辑对话框
// ===================================================================

// ===================================================================
// 「添加材料」两级向导
// 第一级：活动类型（五育分组 19 类）；第二级：该类型下具体活动/档位候选。
// 候选文案如 "xxxx（例 aaaa\bbbb）" 由 zcActivityItems 预先扁平化并补
// 「其他 xxxx」兜底项；点选候选即回填 名称/类别/档位 进入编辑表单。
// ===================================================================

/// 一级页返回结果。
/// 二级页「选中候选 / 直接填写」都走 [onPicked] 回调（`null` = 直接填写），
/// 由材料库根页打开表单；二级页**不出栈**，保存后可就地继续添加。

/// 材料列表与类型选择分组顺序。

