import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

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
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = zcDefaultYear(DateTime.now());
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  // ---------- 学年 ----------
  void _switchYear(int delta) {
    final target = _year + delta;
    if (!mounted) return;
    setState(() => _year = target);
  }

  Widget _buildYearBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: () => _switchYear(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一学年',
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                zcYearLabel(_year),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                '材料按盖章时间归入 ${_year - 1}-09-01 ~ $_year-08-31',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _switchYear(1),
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一学年',
        ),
      ],
    );
  }

  // ---------- 主体 ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('材料库'),
        centerTitle: false,
      ),
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
              Text('材料加载失败：$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error)),
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
        final mats = zcFilterByYear(all, _year);
        if (mats.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
            children: [
              _buildYearBar(context),
              const SizedBox(height: 36),
              Icon(Icons.folder_open, size: 56, color: scheme.outlineVariant),
              const SizedBox(height: 16),
              const Text(
                '本学年还没有证明材料',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '竞赛证书、奖状、评优证明等按类型录入留档，综合测评会自动读取计分，可附加证书照片作证明。\n${zcYearLabel(_year)}窗口：${_year - 1}-09-01 ~ $_year-08-31',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: scheme.outline, height: 1.6),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _buildYearBar(context),
            for (final dim in const ['z', 'd', 't', 'm', 'l'])
              ..._materialSection(context, dim, mats),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
              child: Text(
                '提示：证明材料仅在本档案中维护；综合测评按所选学年自动读取计分，分值口径与测评页计分明细一致。',
                style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.5),
              ),
            ),
          ],
        );
      },
    );
  }

  String _dimName(String dim) => switch (dim) {
        'd' => '德育',
        'z' => '智育',
        't' => '体育',
        'm' => '美育',
        'l' => '劳育',
        _ => '',
      };

  List<Widget> _materialSection(
      BuildContext context, String dim, List<ZcMaterial> mats) {
    final scheme = Theme.of(context).colorScheme;
    final list = [
      for (final m in mats)
        if (m.spec.dim == dim) m,
    ];
    if (list.isEmpty) return const [];
    return [
      Padding(
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
            Text('${_dimName(dim)}加分材料 · ${list.length}',
                style:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      for (final m in list) _materialRow(context, m),
      const SizedBox(height: 4),
    ];
  }

  Widget _materialRow(BuildContext context, ZcMaterial m) {
    final scheme = Theme.of(context).colorScheme;
    final v = zcMaterialValue(m);
    final spec = m.spec;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _editMaterial(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_zcTypeIcon(spec.id), size: 19, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        spec.label,
                        if (m.cat.isNotEmpty) zcCatNames[m.cat] ?? '',
                        m.optionLabel,
                        m.dateIso,
                        if (m.files.isNotEmpty) '附件 ${m.files.length}',
                      ].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (v != null)
                Text(
                  '+${_fmt(v)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
    final type = await Navigator.of(context).push<ZcTypeId>(
      MaterialPageRoute(builder: (_) => const _MaterialTypePickerPage()),
    );
    if (type == null || !mounted) return;
    final spec = zcTypeSpecOf[type]!;
    final outcome = await Navigator.of(context).push<_PickOutcome>(
      MaterialPageRoute(builder: (_) => _ActivityPickPage(spec: spec)),
    );
    if (outcome == null || !mounted) return;
    if (outcome is _PickDirect) {
      await _openEditor(null, type: type);
    } else if (outcome is _PickActivity) {
      await _openEditor(null, type: type, activity: outcome.item);
    }
  }

  void _editMaterial(ZcMaterial m) {
    _openEditor(m);
  }

  Future<void> _openEditor(
    ZcMaterial? existing, {
    ZcTypeId? type,
    ZcActivityItem? activity,
  }) async {
    final store = await ref.read(zcStoreProvider.future);
    if (!mounted) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _MaterialEditDialog(
        store: store,
        existing: existing,
        initialYear: _year,
        initialType: type,
        initialActivity: activity,
      ),
    );
    if (result == null || !mounted) return;
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
      if (ok != true || !mounted) return;
      try {
        final all = await store.loadMaterials();
        await store.deleteMaterial(all, target);
        if (!mounted) return;
        ref.invalidate(zcMaterialsProvider);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e')),
        );
      }
      return;
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
      if (!mounted) return;
      ref.invalidate(zcMaterialsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
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
        files: files,
        note: note.trim(),
      );
}

class _MaterialEditDialog extends StatefulWidget {
  final ZcStore store;
  final ZcMaterial? existing;
  final int initialYear;

  /// 向导已选类型（新增时非 null → 表头改只读显示，不再弹 19 类型下拉）。
  final ZcTypeId? initialType;

  /// 向导二级页选中的具体活动（预填 name/级别/类别）。
  final ZcActivityItem? initialActivity;

  const _MaterialEditDialog({
    required this.store,
    required this.existing,
    required this.initialYear,
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
      final paths = [for (final f in res.files) if (f.path != null) f.path!];
      if (paths.isEmpty) return;
      for (final path in paths) {
        try {
          final rel = await widget.store.importFile(path);
          if (!mounted) return;
          setState(() => _d.files = [..._d.files, rel]);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入附件失败：$e')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  Future<void> _removeFile(String rel) async {
    await widget.store.deleteFile(rel);
    if (!mounted) return;
    setState(() => _d.files = [for (final f in _d.files) if (f != rel) f]);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 6, 1, 1),
      lastDate: now,
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
    if (_d.level < 0 || _d.level >= spec.levels.length) return false;
    if (spec.opts.isNotEmpty &&
        (_d.opt < 0 || _d.opt >= spec.opts.length)) {
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
                          fontSize: 16, fontWeight: FontWeight.w700),
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
                    if (widget.existing == null && widget.initialType == null) ...[
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
                      Text('${spec.section} · 计入${spec.hint}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.outline)),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('${spec.label} · ${spec.section}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 12),
                    if (spec.needName) ...[
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
                                _d.dateIso.isEmpty
                                    ? '选择日期'
                                    : _d.dateIso,
                                style: TextStyle(
                                  color: _d.dateIso.isEmpty
                                      ? scheme.outline
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (spec.needOrg) ...[
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
                    DropdownButtonFormField<int>(
                      initialValue:
                          _clampI(_d.level, spec.levels.length - 1),
                      decoration: const InputDecoration(
                        labelText: '级别 / 档位',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var i = 0; i < spec.levels.length; i++)
                          DropdownMenuItem(value: i, child: Text(spec.levels[i])),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _d.level = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (spec.opts.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: _clampI(_d.opt, spec.opts.length - 1),
                        decoration: const InputDecoration(
                          labelText: '奖项 / 细分',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var i = 0; i < spec.opts.length; i++)
                            DropdownMenuItem(value: i, child: Text(spec.opts[i])),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _d.opt = v);
                        },
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
                            style:
                                TextStyle(fontSize: 13, color: scheme.outline),
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
                              const Icon(Icons.insert_drive_file,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(f,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                              InkWell(
                                onTap: () => _removeFile(f),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.grey),
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
                child: Text(_invalidHint!,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ),
          ],
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
                    fontWeight: FontWeight.w600),
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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
sealed class _PickOutcome {}

/// 选中二级页某个具体活动候选。
class _PickActivity extends _PickOutcome {
  final ZcActivityItem item;
  _PickActivity(this.item);
}

/// 「直接填写（不选具体活动）」。
class _PickDirect extends _PickOutcome {}

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
      ZcTypeId.sportComp || ZcTypeId.psych || ZcTypeId.sportTeam =>
        Icons.directions_run,
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
    final specs = [for (final s in zcTypeSpecs) if (s.dim == dim) s];
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
            Text('${_dimLabel(dim)} · ${specs.length}',
                style:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      for (final s in specs)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Icon(_zcTypeIcon(s.id), size: 19, color: scheme.primary),
            ),
            title: Text(s.label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: Text(s.section,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.outline)),
            trailing:
                Icon(Icons.chevron_right, size: 18, color: scheme.outlineVariant),
            onTap: () => Navigator.of(context).pop(s.id),
          ),
        ),
    ];
  }
}

/// 第二级页：某类型的具体活动/档位候选；点选返回 [_PickOutcome]。
class _ActivityPickPage extends StatefulWidget {
  final ZcTypeSpec spec;
  const _ActivityPickPage({required this.spec});

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

  /// 查询词命中别名（RoboMaster→机器人大赛）时附加主名匹配。
  String? _aliasFor(String q) {
    for (final e in zcContestAliases.entries) {
      if (e.key.toLowerCase() == q) return e.value;
    }
    return null;
  }

  List<ZcActivityItem> _visible() {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _all;
    final alias = _aliasFor(q)?.toLowerCase();
    return [
      for (final it in _all)
        if (it.title.toLowerCase().contains(q) ||
            (alias != null && it.title.toLowerCase().contains(alias)) ||
            (alias != null && it.namePrefill?.toLowerCase() == alias))
          it,
    ];
  }

  void _pick(ZcActivityItem it) => Navigator.of(context).pop(_PickActivity(it));

  void _direct() => Navigator.of(context).pop(_PickDirect());

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
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Text(cur!,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.outline,
                  fontWeight: FontWeight.w600)),
        ));
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
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: scheme.primary),
        ),
        title: Text(it.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: it.other
            ? Text('手动填写名称（比赛类将自动识别类别）',
                style: TextStyle(fontSize: 11, color: scheme.outline))
            : null,
        trailing: Icon(Icons.chevron_right, size: 18, color: scheme.outlineVariant),
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
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
                    const Text('直接填写（不选具体活动）',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _isContest
                          ? '手动输入比赛名称，提交时将自动识别类别'
                          : '手动填写名称与档位',
                      style:
                          TextStyle(fontSize: 11, color: scheme.outline),
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
