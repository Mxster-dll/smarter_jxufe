/// 五育占比设置弹层（总评成绩口径）。
///
/// 用户 2026-09-18：「综测不是直接算平均分，而是有一个总评成绩，这个成绩的占比
/// 由班主任定，应该让用户自行设置」+ 入口拍板「综测页点『总评成绩』那一行的胶囊
/// 就地弹层」→ 与评议分/加权/体测同一种「点胶囊改」的交互，改完立刻看到总评变化。
///
/// 口径：五项之和必须是 100%（±0.5 个百分点），否则保存按钮禁用并就地提示；
/// 编辑用**百分数**（20 = 20%），保存回 [ZcWeights]。默认档 = 用户拍板的
/// `20/35/15/15/15`，另给「各 20%」便捷档（= 旧的五育平均口径）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/app_theme.dart';
import '../../domain/zc_weights.dart';

/// 打开占比弹层；确定返回新的一套占比，取消/点背景返回 null。
Future<ZcWeights?> showZcWeightSheet(
  BuildContext context, {
  required ZcWeights weights,
}) => showModalBottomSheet<ZcWeights>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _ZcWeightSheet(weights: weights),
);

class _ZcWeightSheet extends StatefulWidget {
  final ZcWeights weights;

  const _ZcWeightSheet({required this.weights});

  @override
  State<_ZcWeightSheet> createState() => _ZcWeightSheetState();
}

class _ZcWeightSheetState extends State<_ZcWeightSheet> {
  static const _keys = ['d', 'z', 't', 'm', 'l'];

  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = [
      for (final v in widget.weights.values)
        TextEditingController(text: zcWeightPercentText(v)),
    ];
    for (final c in _ctrls) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// 当前输入解析成一套占比；任一项非法（空/非数）→ null。
  ZcWeights? get _parsed {
    final out = <double>[];
    for (final c in _ctrls) {
      final v = double.tryParse(c.text.trim());
      if (v == null || v < 0 || v > 100) return null;
      out.add(v);
    }
    return ZcWeights(d: out[0], z: out[1], t: out[2], m: out[3], l: out[4]);
  }

  void _applyPreset(ZcWeights w) {
    for (var i = 0; i < _ctrls.length; i++) {
      _ctrls[i].text = zcWeightPercentText(w.values[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = _parsed;
    final sum = parsed?.sum;
    final ok = parsed != null && parsed.isValid;
    final sumColor = ok
        ? AppColors.success(context)
        : (parsed == null ? scheme.outline : AppColors.critical(context));

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
            '五育占比（总评成绩）',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '总评成绩 = 德育×占比 + 智育×占比 + 体育×占比 + 美育×占比 + 劳育×占比。'
            '比例由班主任公布，填一次即可，按学年各存一套。',
            style: TextStyle(fontSize: 11.5, color: scheme.outline, height: 1.35),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _keys.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      kZcWeightLabels[i],
                      style: TextStyle(fontSize: 13, color: scheme.onSurface),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: Key('zcWeightField-${_keys[i]}'),
                      controller: _ctrls[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                sum == null ? '合计 —' : '合计 ${zcWeightPercentText(sum)}%',
                key: const Key('zcWeightTotal'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: sumColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok ? '各项之和为 100%' : '五项之和必须是 100%',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                key: const Key('zcWeightPreset-default'),
                label: const Text('默认 20/35/15/15/15', style: TextStyle(fontSize: 11.5)),
                onPressed: () => _applyPreset(ZcWeights.initial),
              ),
              ActionChip(
                key: const Key('zcWeightPreset-even'),
                label: const Text('各 20%', style: TextStyle(fontSize: 11.5)),
                onPressed: () => _applyPreset(ZcWeights.even),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('zcWeightCancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('zcWeightSave'),
                onPressed: ok ? () => Navigator.of(context).pop(parsed) : null,
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
