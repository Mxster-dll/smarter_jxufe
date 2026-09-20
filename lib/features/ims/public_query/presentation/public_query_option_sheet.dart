/// 公共查询的**可搜索选择面板**（唯一实现）。
///
/// 从 `public_query_screen.dart` 的私有 `_OptionSheet` 原样搬出，供两处共用：
/// - 公共查询页（教师 5000+ / 课程 1000+ / 班级 1000+ 的单选与多选）；
/// - 找无课时间页（班级多选）。
///
/// 面板形态：标题带总数（有搜索词时再带命中数）+ 搜索框（按名字或代码，忽略空白与大小写）
/// + 长列表；`single` 为真时点一行直接返回，否则每行一个复选框、右上角「确定（N）」。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';

/// 弹出一个可搜索的选择面板，返回选中的项（取消 / 未选返回空表）。
Future<List<PublicQueryOption>> pickPublicQueryOptions(
  BuildContext context, {
  required String title,
  required List<PublicQueryOption> options,
  bool single = false,
}) async {
  final result = await showModalBottomSheet<List<PublicQueryOption>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        PublicQueryOptionSheet(title: title, options: options, single: single),
  );
  return result ?? const [];
}

/// 可搜索的选择面板。
class PublicQueryOptionSheet extends StatefulWidget {
  const PublicQueryOptionSheet({
    super.key,
    required this.title,
    required this.options,
    this.single = false,
  });

  final String title;
  final List<PublicQueryOption> options;

  /// 单选（点行即回）还是多选（复选框 + 确定）。
  final bool single;

  @override
  State<PublicQueryOptionSheet> createState() => _PublicQueryOptionSheetState();
}

class _PublicQueryOptionSheetState extends State<PublicQueryOptionSheet> {
  final _controller = TextEditingController();
  final _selected = <String>{};
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PublicQueryOption> get _filtered {
    final key = _keyword.trim().toLowerCase();
    if (key.isEmpty) return widget.options;
    return widget.options
        .where(
          (o) =>
              o.name.toLowerCase().contains(key) ||
              o.code.toLowerCase().contains(key),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _filtered;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title}（共 ${widget.options.length} 项'
                    '${list.length == widget.options.length ? '' : ' · 命中 ${list.length}'}）',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!widget.single)
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final picked = widget.options
                                .where((o) => _selected.contains(o.code))
                                .toList();
                            Navigator.of(context).pop(picked);
                          },
                    child: Text('确定（${_selected.length}）'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const Key('publicQueryOptionSearch'),
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '输入名称或代码搜索',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配项',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final o = list[i];
                      final checked = _selected.contains(o.code);
                      return ListTile(
                        key: Key('publicQueryOption-${o.code}'),
                        dense: true,
                        selected: checked,
                        leading: widget.single
                            ? null
                            : Checkbox(
                                value: checked,
                                onChanged: (_) => setState(() {
                                  if (checked) {
                                    _selected.remove(o.code);
                                  } else {
                                    _selected.add(o.code);
                                  }
                                }),
                              ),
                        title: Text(o.displayName),
                        subtitle: o.bracketCode.isEmpty
                            ? null
                            : Text(
                                o.bracketCode,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(widget.single ? [o] : null),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
