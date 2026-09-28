/// 材料库「编辑材料」弹层（2026-09-20 从 `materials_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原同文件私有件 `_MaterialEditDialog` / `_MaterialEditDialogState`（718 行）+ 结果类型
/// `_EditResult` / `_EditSave` / `_EditDelete` + 草稿模型 `_MaterialDraft` —— 整体搬到本文件并
/// **改为公开名**（Dart 的 `_` 是库私有，跨文件即不可见）。`materials_screen.dart` 的 State 仍会
/// 构造它（`showDialog` + `MaterialEditResult` 判定），故必须公开。
library;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

import 'package:smarter_jxufe/shared/widgets/grid_date_picker.dart';

/// 对话框结果。
sealed class MaterialEditResult {}

class MaterialEditSave extends MaterialEditResult {
  final MaterialDraft draft;
  MaterialEditSave(this.draft);
}

class MaterialEditDelete extends MaterialEditResult {}

/// 编辑过程中的草稿（可来回改类型不丢数据）。
class MaterialDraft {
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

  MaterialDraft({
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

  factory MaterialDraft.from(ZcMaterial m) => MaterialDraft(
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

class MaterialEditDialog extends StatefulWidget {
  final ZcStore store;
  final ZcMaterial? existing;

  /// 日期可选范围下限（= 入学年 1 月 1 日）。
  final DateTime firstDate;

  /// 向导已选类型（新增时非 null → 表头改只读显示，不再弹 19 类型下拉）。
  final ZcTypeId? initialType;

  /// 向导二级页选中的具体活动（预填 name/级别/类别）。
  final ZcActivityItem? initialActivity;

  const MaterialEditDialog({
      super.key,
    
    required this.store,
    required this.existing,
    required this.firstDate,
    this.initialType,
    this.initialActivity,
  });

  @override
  State<MaterialEditDialog> createState() => MaterialEditDialogState();
}

class MaterialEditDialogState extends State<MaterialEditDialog> {
  late MaterialDraft _d;
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
      _d = MaterialDraft.from(existing);
    } else {
      _d = MaterialDraft(typeId: widget.initialType ?? zcTypeSpecs.first.id);
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
    // ⚠ 必须无条件 `setState`：名称直接参与 `_valid`（必填）与 `_invalidHint`，
    // 旧写法在「非竞赛类型」和「竞赛类型但名字不命中目录」两条路上都不重建 →
    // 填完名称后「保存」还是灰的、也不给原因（与次数输入框同款坑，
    // 2026-09-27 一并修）。
    setState(() {
      _d.name = v;
      final spec = _spec;
      if (!spec.needCat) return;
      final hit = zcMatchContest(v);
      if (hit != null) {
        _d.cat = hit.cat;
        _d.catAuto = true;
      } else if (_d.catAuto) {
        _d.cat = '';
        _d.catAuto = false;
      }
    });
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
    // ⚠ `spec.levels` 为空的类型（今天只有「思想教育 · 活动参与」，它走**次数**
    // 输入）必须跳过这条 —— 否则 `0 >= 0` 恒真，保存按钮永远灰着、也没有任何
    // 提示（用户 2026-09-27 报的「思想教育-活动参与添加材料时无法保存」）。
    if (spec.levels.isNotEmpty &&
        (_d.level < 0 || _d.level >= spec.levels.length)) {
      return false;
    }
    // 次数型：0 次 = 0 分，存进去只会是条「没分」的材料 → 要求至少 1 次。
    if (spec.qtyLabel != null && _d.qty < 1) return false;
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
    if (spec.qtyLabel != null && _d.qty < 1) {
      return '请填写${spec.qtyLabel}';
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
                    else if (spec.levels.isNotEmpty)
                      // 级别 / 档位：一排按钮（用户 2026-09-17 裁定不用下拉）。
                      // ⚠ 空的按钮组不画 —— 「思想教育 · 活动参与」没有档位，
                      // 画出来就是一个只有标题、没有选项的空区（2026-09-27 修）。
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
                        onChanged: (s) =>
                            setState(() => _d.qty = double.tryParse(s) ?? 0),
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
                      onPressed: () => Navigator.of(context).pop(MaterialEditDelete()),
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
                        ? () => Navigator.of(context).pop(MaterialEditSave(_d))
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
      decoration: ShapeDecoration(
        shape: appCardShape(context),
        color: AppColors.fill(context),
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
