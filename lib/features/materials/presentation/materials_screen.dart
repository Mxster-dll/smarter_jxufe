import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/materials/domain/material_grouping.dart';
import 'package:smarter_jxufe/features/materials/presentation/material_tags.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/shared/widgets/grid_date_picker.dart';

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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '材料加载失败：$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(zcMaterialsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return [
      Padding(
        key: group.groupKey,
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${group.label} · ${group.count}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        side: BorderSide(color: AppColors.hairline(context, 0.6)),
      ),
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
                  _zcTypeIcon(spec.id),
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
      MaterialPageRoute(builder: (_) => const _MaterialTypePickerPage()),
    );
    if (type == null || !mounted) return;
    final spec = zcTypeSpecOf[type]!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ActivityPickPage(
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
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _MaterialEditDialog(
        store: store,
        existing: existing,
        firstDate: firstDate,
        initialType: type,
        initialActivity: activity,
      ),
    );
    if (result == null || !mounted) return false;
    if (result is _EditDelete) {
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
    final draft = (result as _EditSave).draft;
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

/// 对话框结果。
sealed class _EditResult {}

class _EditSave extends _EditResult {
  final _MaterialDraft draft;
  _EditSave(this.draft);
}

class _EditDelete extends _EditResult {}

/// 编辑过程中的草稿（可来回改类型不丢数据）。
class _MaterialDraft {
  ZcTypeId typeId;
  String name;
  String dateIso;
  String org;
  String cat;
  int level;
  int opt;
  double qty;

  /// 手填得分（外语等 `manualScore` 类型；用户 2026-09-17 裁定）。
  double? manualScore;
  List<String> files;
  String note;
  bool catAuto;

  _MaterialDraft({
    required this.typeId,
    this.name = '',
    this.dateIso = '',
    this.org = '',
    this.cat = '',
    this.level = 0,
    this.opt = 0,
    this.qty = 0,
    this.manualScore,
    this.files = const [],
    this.note = '',
    this.catAuto = false,
  });

  factory _MaterialDraft.from(ZcMaterial m) => _MaterialDraft(
    typeId: m.typeId,
    name: m.name,
    dateIso: m.dateIso,
    org: m.org,
    cat: m.cat,
    level: m.level,
    opt: m.opt,
    qty: m.qty,
    manualScore: m.manualScore,
    files: m.files,
    note: m.note,
    catAuto: m.cat.isNotEmpty,
  );

  ZcMaterial toMaterial({String? id}) => ZcMaterial(
    id: id ?? '',
    typeId: typeId,
    name: name.trim(),
    dateIso: dateIso,
    org: org.trim(),
    cat: cat,
    level: level,
    opt: opt,
    qty: qty,
    manualScore: manualScore,
    files: files,
    note: note.trim(),
  );
}

class _MaterialEditDialog extends StatefulWidget {
  final ZcStore store;
  final ZcMaterial? existing;

  /// 日期可选范围下限（= 入学年 1 月 1 日）。
  final DateTime firstDate;

  /// 向导已选类型（新增时非 null → 表头改只读显示，不再弹 19 类型下拉）。
  final ZcTypeId? initialType;

  /// 向导二级页选中的具体活动（预填 name/级别/类别）。
  final ZcActivityItem? initialActivity;

  const _MaterialEditDialog({
    required this.store,
    required this.existing,
    required this.firstDate,
    this.initialType,
    this.initialActivity,
  });

  @override
  State<_MaterialEditDialog> createState() => _MaterialEditDialogState();
}

class _MaterialEditDialogState extends State<_MaterialEditDialog> {
  late _MaterialDraft _d;
  final _nameCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _scoreCtrl = TextEditingController();
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _d = _MaterialDraft.from(existing);
    } else {
      _d = _MaterialDraft(typeId: widget.initialType ?? zcTypeSpecs.first.id);
      final a = widget.initialActivity;
      if (a != null) {
        _d.name = a.namePrefill ?? '';
        if (a.levelIdx != null) _d.level = a.levelIdx!;
        if (a.cat != null) {
          _d.cat = a.cat!;
          _d.catAuto = true;
        }
      }
    }
    _nameCtrl.text = _d.name;
    _orgCtrl.text = _d.org;
    _noteCtrl.text = _d.note;
    _qtyCtrl.text = _d.qty == 0 ? '' : _d.qty.round().toString();
    final ms = _d.manualScore;
    _scoreCtrl.text = ms == null
        ? ''
        : (ms == ms.roundToDouble() ? ms.round().toString() : '$ms');
    if (_d.dateIso.isNotEmpty) {
      _date = DateTime.tryParse(_d.dateIso);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orgCtrl.dispose();
    _noteCtrl.dispose();
    _qtyCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  ZcTypeSpec get _spec => zcTypeSpecOf[_d.typeId]!;

  int _clampI(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

  void _setType(ZcTypeId id) {
    setState(() {
      _d.typeId = id;
      _d.level = 0;
      _d.opt = 0;
      _d.qty = 0;
      _d.cat = '';
      _d.catAuto = false;
    });
  }

  void _onNameChanged(String v) {
    _d.name = v;
    final spec = _spec;
    if (!spec.needCat) return;
    final hit = zcMatchContest(v);
    if (hit != null) {
      setState(() {
        _d.cat = hit.cat;
        _d.catAuto = true;
      });
    } else if (_d.catAuto) {
      setState(() {
        _d.cat = '';
        _d.catAuto = false;
      });
    }
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.pickFiles(allowMultiple: true);
      if (res == null) return;
      final paths = [
        for (final f in res.files)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty) return;
      for (final path in paths) {
        try {
          final rel = await widget.store.importFile(path);
          if (!mounted) return;
          setState(() => _d.files = [..._d.files, rel]);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('导入附件失败：$e')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择文件失败：$e')));
    }
  }

  Future<void> _removeFile(String rel) async {
    await widget.store.deleteFile(rel);
    if (!mounted) return;
    setState(
      () => _d.files = [
        for (final f in _d.files)
          if (f != rel) f,
      ],
    );
  }

  /// 竞赛：从目录里点选具体比赛时，「比赛名」与「类别（Ⅰ~Ⅳ）」都是**已定事实**，
  /// 表单里按固定项展示（用户 2026-09-17 裁定「不要把比赛名和类别显示为可选，
  /// 而是显示为固定项，自定义竞赛除外」）——只有「其他比赛（手动录入）」与
  /// 编辑既有材料才保留可编辑。
  ZcActivityItem? get _lockedActivity {
    final a = widget.initialActivity;
    if (widget.existing != null || a == null || a.other) return null;
    final name = a.namePrefill;
    if (name == null || name.isEmpty) return null;
    return a;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // 通用三宫格日期选择器（年 / 月 / 日），取代 Material 月历弹窗。
    // 下限 = 入学年（`widget.firstDate`），上限 = 今天。
    final picked = await showGridDatePicker(
      context,
      initialDate: _date ?? now,
      firstDate: widget.firstDate,
      lastDate: now,
      title: '选择盖章日期',
      helpText: '证书盖章时间',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _d.dateIso =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  bool get _valid {
    final spec = _spec;
    if (spec.needName && _d.name.trim().isEmpty) return false;
    if (_d.dateIso.isEmpty) return false;
    if (spec.needCat && _d.cat.isEmpty) return false;
    if (spec.id == ZcTypeId.foreign) {
      // 外语：目录内**按原始成绩查表 10 档位**（等级类证书无需填分）；
      // 目录外的「其他证书」才需要手填分值（单项不高于 2 分）。
      final cert = zcForeignCertOf(_d.name.trim());
      final needsValue = cert == null || cert.needsScore;
      if (needsValue && (_d.manualScore == null || _d.manualScore! < 0)) {
        return false;
      }
    }
    if (_d.level < 0 || _d.level >= spec.levels.length) return false;
    if (spec.opts.isNotEmpty && (_d.opt < 0 || _d.opt >= spec.opts.length)) {
      return false;
    }
    return true;
  }

  String? get _invalidHint {
    final spec = _spec;
    if (spec.needName && _d.name.trim().isEmpty) {
      return '请填写名称';
    }
    if (_d.dateIso.isEmpty) return '请选择日期';
    if (spec.needCat && _d.cat.isEmpty) {
      return '比赛名称未识别出类别，请手动选择类别';
    }
    if (spec.id == ZcTypeId.foreign) {
      final cert = zcForeignCertOf(_d.name.trim());
      if (cert == null && _d.manualScore == null) {
        return '请填写加分分值（目录外的其他证书，单项不高于 2 分）';
      }
      if (cert != null && cert.needsScore && _d.manualScore == null) {
        return '请填写原始成绩（如四级 489、雅思 6.5、托福 90、GRE 320）';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = _spec;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? '添加证明材料' : '编辑证明材料',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.existing == null &&
                        widget.initialType == null) ...[
                      DropdownButtonFormField<ZcTypeId>(
                        initialValue: _d.typeId,
                        decoration: const InputDecoration(
                          labelText: '材料类型',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in zcTypeSpecs)
                            DropdownMenuItem(value: t.id, child: Text(t.label)),
                        ],
                        onChanged: (v) {
                          if (v != null) _setType(v);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${spec.section} · 计入${spec.hint}',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${spec.label} · ${spec.section}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (spec.needName) ...[
                      if (_lockedActivity case final locked?) ...[
                        _buildLockedActivity(context, locked),
                      ] else ...[
                        TextField(
                          controller: _nameCtrl,
                          onChanged: _onNameChanged,
                          decoration: const InputDecoration(
                            labelText: '名称（竞赛/论文/荣誉等）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (spec.needCat) _buildCatPicker(context),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: '日期（盖章时间）',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _d.dateIso.isEmpty ? '选择日期' : _d.dateIso,
                                style: TextStyle(
                                  color: _d.dateIso.isEmpty
                                      ? scheme.outline
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 竞赛不填「组织单位」（用户 2026-09-17：
                        // 「添加竞赛时不要让我填组织单位」）。
                        if (spec.needOrg && spec.id != ZcTypeId.contest) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _orgCtrl,
                              onChanged: (s) => _d.org = s,
                              decoration: const InputDecoration(
                                labelText: '发证/组织单位',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (spec.manualScore)
                      // 外语等：按证书名目选，得分自己填（用户 2026-09-17 裁定）。
                      _buildManualScore(context)
                    else
                      // 级别 / 档位：一排按钮（用户 2026-09-17 裁定不用下拉）。
                      _choiceGroup(
                        context,
                        label: '级别 / 档位',
                        items: spec.levels,
                        selected: _clampI(_d.level, spec.levels.length - 1),
                        onChanged: (v) => setState(() => _d.level = v),
                      ),
                    const SizedBox(height: 12),
                    if (spec.opts.isNotEmpty) ...[
                      // 奖项 / 细分：同样一排按钮。
                      _choiceGroup(
                        context,
                        label: '奖项 / 细分',
                        items: spec.opts,
                        selected: _clampI(_d.opt, spec.opts.length - 1),
                        onChanged: (v) => setState(() => _d.opt = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (spec.qtyLabel != null) ...[
                      TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (s) => _d.qty = double.tryParse(s) ?? 0,
                        decoration: InputDecoration(
                          labelText: spec.qtyLabel!,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // 附件
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _d.files.isEmpty
                                ? '证明文件（可选）'
                                : '证明文件 ${_d.files.length}',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    if (_d.files.isNotEmpty)
                      for (final f in _d.files)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file,
                                size: 16,
                                color: AppColors.textMuted(context),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  f,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              InkWell(
                                onTap: () => _removeFile(f),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: AppColors.textMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _noteCtrl,
                      onChanged: (s) => _d.note = s,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(_EditDelete()),
                      icon: const Icon(Icons.delete_outline),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      label: const Text('删除'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _valid
                        ? () => Navigator.of(context).pop(_EditSave(_d))
                        : null,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
            if (_invalidHint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _invalidHint!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 目录里选定的比赛：名称与类别按**固定项**展示（不可改）。
  Widget _buildLockedActivity(BuildContext context, ZcActivityItem item) {
    final scheme = Theme.of(context).colorScheme;
    final catName = zcCatNames[item.cat];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(kAppCardRadius),
        border: Border.all(color: AppColors.hairline(context, 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '比赛项目（目录固定）',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (catName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, scheme.primary, 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '类别 $catName',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.namePrefill ?? item.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '要改比赛或类别，请返回上一步重新选择。',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  /// 单选选项组：一排按钮（不用下拉），自动换行。
  /// 得分输入（外语等 `manualScore` 类型）。
  ///
  /// 用户 2026-09-17：「外语能力不要分成 xxx≥aaa/xxx>bbb，直接按证书名字，然后
  /// 手动填入分数」→ 表 10 的档位只作参考文案显示在输入框下方。
  Widget _buildManualScore(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cert = zcForeignCertOf(_d.name.trim());
    // 等级类证书（日语 N1/N2、专八/专四、TOPIK）：表 10 直接给固定分，无需填任何数字。
    if (cert != null && !cert.needsScore) {
      return Text(
        '表 10 档位：${cert.bandHint}（等级类证书无需填分）',
        style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.5),
      );
    }
    final needsRaw = cert != null; // 目录内需填原始成绩；目录外 = 其他证书需填分值
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _scoreCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: needsRaw ? '原始成绩' : '加分分值（其他证书）',
            hintText: needsRaw
                ? '如 ${cert.name == '雅思' || cert.name == '托福' ? '6.5 / 90' : cert.name == 'GRE' ? '320' : '489'}'
                : '上限 $kZcForeignOtherCap 分',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (s) => setState(
            () => _d.manualScore = s.trim().isEmpty
                ? null
                : double.tryParse(s.trim()),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          needsRaw
              // 「按挡位识别」：显示原始成绩查表 10 得到的**实际加分**（不是原始成绩本身）。
              ? '按表 10：${zcForeignScoreLabel(name: _d.name.trim(), rawScore: _d.manualScore)}'
              : '表 10：「其他证书由学院确认最终分值（单项不高于 $kZcForeignOtherCap 分）」',
          style: TextStyle(
            fontSize: 11,
            color: _d.manualScore == null ? scheme.outline : scheme.primary,
            height: 1.5,
            fontWeight: _d.manualScore == null
                ? FontWeight.normal
                : FontWeight.w600,
          ),
        ),
        if (cert != null) ...[
          const SizedBox(height: 2),
          Text(
            '参考档位：${cert.bandHint}',
            style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _choiceGroup(
    BuildContext context, {
    required String label,
    required List<String> items,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < items.length; i++)
              _choiceChip(
                context,
                text: items[i],
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
          ],
        ),
      ],
    );
  }

  Widget _choiceChip(
    BuildContext context, {
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : AppColors.fill(context),
      borderRadius: BorderRadius.circular(kAppCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// 竞赛类别识别区。
  Widget _buildCatPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          if (_d.catAuto && _d.cat.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '自动识别：${zcCatNames[_d.cat]}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _d.cat.isEmpty ? null : _d.cat,
              hint: const Text('类别（未识别手动选）', style: TextStyle(fontSize: 12)),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: [
                for (final e in zcCatNames.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _d.cat = v;
                    _d.catAuto = false;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
const _dimOrder = ['z', 'd', 't', 'm', 'l'];

String _dimLabel(String dim) => switch (dim) {
  'z' => '智育',
  'd' => '德育',
  't' => '体育',
  'm' => '美育',
  'l' => '劳育',
  _ => '',
};

IconData _zcTypeIcon(ZcTypeId id) => switch (id) {
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
class _MaterialTypePickerPage extends StatelessWidget {
  const _MaterialTypePickerPage();

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
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_dimLabel(dim)} · ${specs.length}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      for (final s in specs)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppCardRadius),
            side: BorderSide(
              color: AppColors.hairline(context, 0.6),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.tint(context, scheme.primary, 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_zcTypeIcon(s.id), size: 19, color: scheme.primary),
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
class _ActivityPickPage extends StatefulWidget {
  final ZcTypeSpec spec;

  /// 选中候选（或「直接填写」传 `null`）后的处理，返回是否保存成功。
  /// 由本页调用而不是 `pop` 返回值：本页要**留在路由栈上**以便连续添加。
  final Future<bool> Function(ZcActivityItem? item) onPicked;

  const _ActivityPickPage({required this.spec, required this.onPicked});

  @override
  State<_ActivityPickPage> createState() => _ActivityPickPageState();
}

class _ActivityPickPageState extends State<_ActivityPickPage> {
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        side: BorderSide(color: AppColors.hairline(context, 0.6)),
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        side: BorderSide(color: AppColors.hairline(context, 0.6)),
      ),
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
