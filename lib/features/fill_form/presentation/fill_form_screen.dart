/// 填表助手：**上传学校下发的 .docx → 自动识别待填项 → 自动填 → 逐项改 → 导出**。
///
/// 用户 2026-10-07 原话：「我们学校在评优评先方面会让我们填很多材料，但是我们手填
/// 的话，要整理很多很乱的……我不希望你生成复制文本了，而是允许用户上传一个 docx
/// 文档，然后你自动识别有哪些项需要填，然后把能填的都填了。填不了/不确定的，
/// 空着。然后用户可以在你自动填完后，再手动调整各部分文本。」
///
/// 链路（四步，全部在本页）：
/// 1. [FilePicker.pickFiles]（只认 `.docx`）→ [DocxForm.fromBytes] 解包 + 扫描；
/// 2. `fillFormDataProvider(学年)` 取一份数据快照 → `fillValueFor` 逐项给自动值；
/// 3. 每个待填项一个输入框（内容 = 自动值，可随意改）；
/// 4. [DocxForm.export] 生成新 docx → [FileShare.shareBytes]（Android 走系统分享，
///    桌面写进下载目录）。
///
/// ⚠ 页面**只调** `domain/fill_form/` 里的纯函数，不自己拼文本、不自己解析 XML。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/platform/file_share.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/design/section_title.dart';
import 'package:smarter_jxufe/features/fill_form/data/fill_form_providers.dart';
import 'package:smarter_jxufe/features/fill_form/domain/docx_fields.dart';
import 'package:smarter_jxufe/features/fill_form/domain/docx_form.dart';
import 'package:smarter_jxufe/features/fill_form/domain/fill_form_data.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';

/// 学年选择器的可回溯年数（与综测页同口径，见 `zcYearPickerRange`）。
const int kFillFormYearWindow = 5;

class FillFormScreen extends ConsumerStatefulWidget {
  const FillFormScreen({
    super.key,
    this.debugInitialForm,
    this.debugInitialFileName,
  });

  /// **只给测试用**：跳过系统文件选择器，直接带着一份已解析的表单进页面。
  ///
  /// 真机上文件选择必然经过原生对话框，widget 测试里没法走；给一个显式的注入口，
  /// 页面其余部分（自动填 / 编辑 / 导出）照旧跑真代码。
  final DocxForm? debugInitialForm;
  final String? debugInitialFileName;

  @override
  ConsumerState<FillFormScreen> createState() => _FillFormScreenState();
}

class _FillFormScreenState extends ConsumerState<FillFormScreen> {
  /// 测评学年**结束**年（2026 = 2025-2026 学年）。
  late int _year = zcDefaultYear(DateTime.now());

  DocxForm? _form;
  String _fileName = '';
  bool _busy = false;
  bool _importing = false;
  String? _error;

  /// field id → 当前文本（= 自动值，用户可改）。
  final Map<String, String> _values = {};

  /// field id → 自动填进去的原始值（用来标「已自动填」并支持「还原」）。
  final Map<String, String> _auto = {};

  /// field id → 控制器。
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    final injected = widget.debugInitialForm;
    if (injected != null) {
      _form = injected;
      _fileName = widget.debugInitialFileName ?? '表格.docx';
      // 微任务里跑：`_autoFill` 第一句就是 setState，initState 里不允许。
      Future<void>.microtask(_autoFill);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('填表助手'),
        centerTitle: false,
        actions: [
          if (_form != null)
            IconButton(
              tooltip: '重新自动填写',
              onPressed: _busy ? null : _autoFill,
              icon: const Icon(Icons.auto_fix_high_outlined),
            ),
          if (_form != null)
            IconButton(
              tooltip: '导出 docx',
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt),
            ),
        ],
      ),
      body: PaneBody(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        actions: [
          if (_form != null)
            TextButton.icon(
              onPressed: _busy ? null : _autoFill,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: const Text('重新自动填写'),
            ),
          if (_form != null)
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt, size: 18),
              label: const Text('导出'),
            ),
        ],
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _yearRow(context),
            const SizedBox(height: 10),
            if (_error != null) ...[
              _errorCard(context, scheme),
              const SizedBox(height: 10),
            ],
            if (_form == null) _introCard(context) else ...[
              _fileCard(context),
              const SizedBox(height: 4),
              if (_form!.scan.fields.isEmpty)
                _noFieldCard(context)
              else ...[
                for (final group in _groups()) ..._groupSection(context, group),
                const SizedBox(height: 8),
                _footer(context),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: _form == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt),
              label: const Text('导出 docx'),
            ),
    );
  }

  // -------------------------------------------------------------------------
  // 顶部：学年选择
  // -------------------------------------------------------------------------

  Widget _yearRow(BuildContext context) {
    final range = zcYearPickerRange(
      latestEnd: zcDefaultYear(DateTime.now()),
      yearEnd: _year,
      window: kFillFormYearWindow,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            '按「${_year - 1}-$_year 学年」的数据填写',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        AcademicYearPicker(
          startYear: range.startYear,
          endYear: range.endYear,
          initialYear: range.initialYear,
          compact: true,
          onChanged: (pickerYear) {
            final next = pickerYear + 1;
            if (next == _year) return;
            setState(() => _year = next);
            if (_form != null) _autoFill();
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 未导入时：说明 + 选文件
  // -------------------------------------------------------------------------

  Widget _introCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            appSectionTitle(context, text: '上传要填的表格'),
            const SizedBox(height: 8),
            Text(
              '把学校下发的那份 .docx（先进个人登记表 / 综合素质测评登记表 / '
              '附加分审核表 / 奖助学金审批表 / 候选人简介表…）原样选进来即可。\n\n'
              '应用会先认出**哪些格子是空的**，再用你已经在应用里的数据'
              '（学籍 / 成绩 / 综测 / 材料库 / 体测 / 志愿时长）把能填的都填上；'
              '填不了或不确定的一律留空，最后一个字都可以自己改，'
              '确认后导出一份新的 .docx。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: _importing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_importing ? '正在解析…' : '选择 .docx 文件'),
            ),
            const SizedBox(height: 8),
            Text(
              '只支持 .docx（Word 2007 以后的格式）。若表格是老的 .doc，'
              '请先用 Word「另存为」成 .docx。',
              style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, ColorScheme scheme) {
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12.5, color: scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 已导入：文件信息 + 字段列表
  // -------------------------------------------------------------------------

  Widget _fileCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final form = _form!;
    final filled = _auto.length;
    final total = form.scan.fields.length;
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    form.title.isEmpty ? _fileName : form.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_fileName · 共 $total 个待填项，已自动填 $filled 项'
              '${total - filled > 0 ? '，其余 ${total - filled} 项留给你填' : ''}',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('换一份表格'),
                ),
                const SizedBox(width: 4),
                Text(
                  '改动只影响导出的新文件，原文件不会动',
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 这份文档**一个空位都没找到**时的兜底（空态要说清是「没有」还是「没取到」）。
  ///
  /// 实测确实会撞上：选成《评选办法》《名额分配》这类没有待填项的说明文件，
  /// 或者下载到的是一份**别人已经填过**的版本 —— 两种都不该只给一个空白列表。
  Widget _noFieldCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('fillFormNoField'),
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search_off, size: 18, color: scheme.outline),
                const SizedBox(width: 8),
                const Text(
                  '这份文档里没找到待填的空位',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '三种常见原因：\n'
              '· 选到的不是表格模版（评选办法 / 名额分配 / 材料要求这类说明文件本来就没有空位）；\n'
              '· 这份是**已经填过**的版本，格子都不是空的了；\n'
              '· 表格整体是图片或排版特殊，读不出文字。\n\n'
              '换一份学校下发的空白表格再试即可。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('换一份表格'),
            ),
          ],
        ),
      ),
    );
  }

  /// 字段按「所在表格 / 正文」分组。
  List<_FieldGroup> _groups() {
    final form = _form!;
    final byKey = <String, List<DocxField>>{};
    for (final f in form.scan.fields) {
      final key = f.tableIndex < 0 ? '正文' : '表 ${f.tableIndex + 1}';
      byKey.putIfAbsent(key, () => []).add(f);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) {
        if (a == '正文') return -1;
        if (b == '正文') return 1;
        return a.compareTo(b);
      });
    return [
      for (final k in keys) _FieldGroup(k, byKey[k]!),
    ];
  }

  List<Widget> _groupSection(BuildContext context, _FieldGroup group) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(
          children: [
            appSectionTitle(context, text: '${group.title} · ${group.fields.length}'),
            const Spacer(),
            Text(
              '已填 ${group.fields.where((f) => _filledValue(f.id).isNotEmpty).length}',
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
          ],
        ),
      ),
      for (final f in group.fields) _fieldTile(context, f),
    ];
  }

  String _filledValue(String id) => (_values[id] ?? '').trim();

  Widget _fieldTile(BuildContext context, DocxField f) {
    final scheme = Theme.of(context).colorScheme;
    // 懒建控制器：`build` 可能先于 `_autoFill` 跑（注入表单的初始帧），
    // 这时 map 里还没有这一项 —— 用 `!` 会直接抛 _TypeError。
    final controller = _controllers.putIfAbsent(
      f.id,
      () => TextEditingController(text: _values[f.id] ?? ''),
    );
    final auto = _auto.containsKey(f.id);
    final long = _isLongField(f);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: auto
                        ? scheme.primary
                        : (_filledValue(f.id).isEmpty
                              ? scheme.outlineVariant
                              : scheme.tertiary),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    f.isListTable ? '${f.label}（整表，一行一条，制表符分列）' : f.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (auto)
                  Text(
                    '自动填入',
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                  ),
                if (auto && _filledValue(f.id) != _auto[f.id]) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() {
                      _values[f.id] = _auto[f.id]!;
                      controller.text = _auto[f.id]!;
                    }),
                    child: Text(
                      '还原',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                f.context,
                if (f.group.isNotEmpty) '所属：${f.group}',
                if (f.isListTable && f.hint.isNotEmpty) f.hint,
              ].join(' · '),
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              minLines: long ? 2 : 1,
              maxLines: long ? null : 1,
              style: TextStyle(fontSize: 13, height: long ? 1.6 : 1.3),
              decoration: InputDecoration(
                isDense: true,
                hintText: long ? '（留空即不填）' : '留空即不填',
                hintStyle: TextStyle(fontSize: 12, color: scheme.outlineVariant),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
              ),
              // ⚠ 必须 setState：否则「自动填入 / 还原」这两个状态标记不会跟着刷新
              // （与材料表单 §24.1 的教训同源 —— 输入不重建 = 用户看不到反馈）。
              onChanged: (v) => setState(() => _values[f.id] = v),
            ),
          ],
        ),
      ),
    );
  }

  /// 长文本字段（成段文字 / 整张清单表 / 本身就很长的值）。
  bool _isLongField(DocxField f) {
    if (f.isListTable) return true;
    if (f.kind == DocxFieldKind.cellProse) return true;
    final v = _values[f.id] ?? '';
    return v.contains('\n') || v.length > 24;
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Text(
        '提示：只有「原本就是空的」位置会被写进去，已经印着字的格子不会被覆盖；'
        '标了「限 N 字」的字段（如受表彰情况 100 字、突出事迹 150 字）已按学校口径'
        '自动截断，你可以直接改。\n'
        '导出后原文件不受影响，新文件叫「原名_已填写.docx」。',
        style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.5),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 动作
  // -------------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _importing = true;
      _error = null;
    });
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx'],
        withData: true,
        dialogTitle: '选择要填的 docx 表格',
      );
      if (res == null || res.files.isEmpty) {
        return;
      }
      final file = res.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = '读不到文件内容，请重新选择。');
        return;
      }
      final form = DocxForm.fromBytes(bytes);
      if (form == null) {
        setState(
          () => _error = '「${file.name}」不是可识别的 .docx'
              '（旧版 .doc 请先用 Word 另存为 .docx）。',
        );
        return;
      }
      _installForm(form, file.name);
    } catch (e) {
      setState(() => _error = '选择文件失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importing = false;
        });
      }
    }
  }

  void _installForm(DocxForm form, String fileName) {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _values.clear();
    _auto.clear();
    setState(() {
      _form = form;
      _fileName = fileName;
      _error = null;
    });
    _autoFill();
  }

  /// 按当前学年重新算一遍自动值（**覆盖**用户改动）。
  Future<void> _autoFill() async {
    final form = _form;
    if (form == null) return;
    setState(() => _busy = true);
    try {
      final data = await ref.read(fillFormDataProvider(_year).future);
      if (!mounted) return;
      final auto = <String, String>{};
      for (final f in form.scan.fields) {
        final v = fillValueFor(f, data) ?? '';
        if (v.trim().isEmpty) continue;
        auto[f.id] = v;
      }
      setState(() {
        _auto
          ..clear()
          ..addAll(auto);
        _values.clear();
        for (final f in form.scan.fields) {
          final v = auto[f.id] ?? '';
          _values[f.id] = v;
          final c = _controllers.putIfAbsent(
            f.id,
            () => TextEditingController(),
          );
          c.text = v;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '自动填写失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final form = _form;
    if (form == null) return;
    setState(() => _busy = true);
    try {
      final bytes = form.export(_values);
      if (bytes == null) {
        setState(() => _error = '导出失败：原文件解析异常，请换一份表格重试。');
        return;
      }
      final name = form.suggestedFileName(_fileName);
      final result = await FileShare.shareBytes(
        bytes: bytes,
        fileName: name,
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        subject: name,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (result.shared) {
        messenger.showSnackBar(
          const SnackBar(content: Text('已生成填写好的 docx，请选择要发送到的应用')),
        );
      } else if (result.savedPath != null) {
        final path = result.savedPath!;
        messenger.showSnackBar(
          SnackBar(
            content: Text('已保存到 $path'),
            duration: const Duration(seconds: 8),
            // 带 action 的 SnackBar 必须显式写 persist: false（§ core_conventions 的
            // 「SnackBar 的 persist 口径」：否则无障碍播报会一直挂着）。
            persist: false,
            action: SnackBarAction(
              label: '打开',
              onPressed: () => FileShare.openFile(path),
            ),
          ),
        );
      } else {
        setState(() => _error = result.error ?? '导出失败');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FieldGroup {
  final String title;
  final List<DocxField> fields;
  const _FieldGroup(this.title, this.fields);
}
