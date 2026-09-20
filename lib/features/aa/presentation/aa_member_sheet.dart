/// 成员弹层（添加 / 编辑：姓名 + 学号 + 班级）。
///
/// ⚠ 刻意**不用 `AlertDialog`**：弹窗内容恒被 `IntrinsicWidth` 包裹，里面放输入框
/// 又窄又要靠内层约束猜宽度；底部弹层是这个仓库里「改一个字段」的统一形态
/// （见 `zongce/presentation/widgets/weight_sheet.dart`、`ge_deadline_card.dart`）。
///
/// 学号 / 班级是**选填**（用户 2026-09-19 五轮原话「我希望成员可以显示学号和班级」）：
/// 从数据中心名单导入时自带，手打成员时可以留空 —— 只填姓名一样能用，
/// 空值在成员列表里不会被渲染成一行空白（见 `AaMember.detail`）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';

/// 成员弹层的编辑结果。
class AaMemberDraft {
  final String name;
  final String studentNo;
  final String className;

  const AaMemberDraft({
    required this.name,
    this.studentNo = '',
    this.className = '',
  });

  /// 已有成员 → 回填用。
  factory AaMemberDraft.of(AaMember m) =>
      AaMemberDraft(name: m.name, studentNo: m.studentNo, className: m.className);
}

/// 打开成员弹层；确定（姓名非空）返回草稿，取消 / 点背景返回 null。
Future<AaMemberDraft?> showAaMemberEditor(
  BuildContext context, {
  AaMemberDraft initial = const AaMemberDraft(name: ''),
  String title = '添加成员',
}) => showModalBottomSheet<AaMemberDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _AaMemberSheet(initial: initial, title: title),
);

class _AaMemberSheet extends StatefulWidget {
  final AaMemberDraft initial;
  final String title;

  const _AaMemberSheet({required this.initial, required this.title});

  @override
  State<_AaMemberSheet> createState() => _AaMemberSheetState();
}

class _AaMemberSheetState extends State<_AaMemberSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name,
  );
  late final TextEditingController _no = TextEditingController(
    text: widget.initial.studentNo,
  );
  late final TextEditingController _cls = TextEditingController(
    text: widget.initial.className,
  );

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onChanged);
    _name.dispose();
    _no.dispose();
    _cls.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      AaMemberDraft(
        name: name,
        studentNo: _no.text.trim(),
        className: _cls.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = _name.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('aaMemberNameField'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '姓名 / 昵称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('aaMemberNoField'),
                  controller: _no,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '学号（选填）',
                    hintText: '如 2202500004',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('aaMemberClassField'),
                  controller: _cls,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '班级（选填）',
                    hintText: '如 25计算机2班',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '学号 / 班级只作标识，用来在重名时认人；不参与任何金额计算。',
            style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.3),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('aaMemberCancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('aaMemberSave'),
                onPressed: ok ? _save : null,
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
