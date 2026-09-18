import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

/// 次数步进器（用户 2026-09-18 裁定）。
///
/// 原话：「所有输入次数的输入框都要改成直接显示次数，点击向左右的三角形可以增减，
/// 点击数字可以唤起输入」→ 形态 = `◀  3  ▶`：
/// - 左三角 `Icons.arrow_left` = 减 1（到 [min] 变灰不可点）；
/// - 右三角 `Icons.arrow_right` = 加 1（到 [max] 变灰不可点）；
/// - 中间数字**本身就是按钮**，点一下弹出输入框直接打字（省得连点几十下）。
///
/// 二轮改版（用户同日）：「我希望把所有次数型的项，其次数修改组件放到条目右侧，
/// 并改成胶囊」→ 外观与 [值胶囊] 同款：`AppColors.tint(primary, 0.09)` 实心淡底 +
/// **圆角 999** + 主色 w700 数字，**宽度自适应内容**（不再固定 138）；页面侧把它
/// 当 `_subRow` 的 `trailing` 用（次数项因此也是单行：标题在左、胶囊在最右）。
///
/// 只用于**整数次数**（缺课节数、缺席次数、扰乱/弃权次数…）；评议分、体测分、
/// 志愿时长这类可空/可小数的字段走 [promptNumberValue] 的「点击才输入」。
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.width,
  });

  /// 字段名（只用于生成 Key，**必须在一个页面内唯一**）。
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// 固定宽度；null = 自适应内容（默认，胶囊贴合文字）。
  final double? width;

  static Key minusKey(String label) => Key('countStepperMinus-$label');
  static Key plusKey(String label) => Key('countStepperPlus-$label');
  static Key valueKey(String label) => Key('countStepperValue-$label');
  static Key inputKey(String label) => Key('countStepperInput-$label');

  /// 夹取（纯函数，可单测）。
  static int clampCount(int v, {int min = 0, int max = 99}) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = clampCount(value, min: min, max: max);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        decoration: BoxDecoration(
          // 与 `_staticChip` / `_valueTap` 同款胶囊（用户 2026-09-18 四轮：「我希望
          // 显示胶囊而不是卡片」——次数组件跟着统一）。
          color: AppColors.tint(context, scheme.primary, 0.09),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _triangle(
              context,
              key: minusKey(label),
              icon: Icons.arrow_left,
              tooltip: '减少',
              enabled: shown > min,
              onTap: () => onChanged(clampCount(shown - 1, min: min, max: max)),
            ),
            SizedBox(
              width: width == null ? null : 40,
              child: InkWell(
                key: valueKey(label),
                borderRadius: BorderRadius.circular(999),
                onTap: () => _prompt(context, shown),
                child: Tooltip(
                  message: '点击直接输入',
                  child: SizedBox(
                    height: 26,
                    child: Center(
                      child: Text(
                        '$shown',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _triangle(
              context,
              key: plusKey(label),
              icon: Icons.arrow_right,
              tooltip: '增加',
              enabled: shown < max,
              onTap: () => onChanged(clampCount(shown + 1, min: min, max: max)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _triangle(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? scheme.primary
                : scheme.primary.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }

  Future<void> _prompt(BuildContext context, int current) async {
    final out = await promptNumberValue(
      context,
      title: '输入$label',
      label: label,
      initial: current.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      integer: true,
      helper: '范围 $min ~ $max',
    );
    if (!out.confirmed || out.value == null) return;
    onChanged(clampCount(out.value!.round(), min: min, max: max));
  }
}

/// 数字弹窗的结果：`confirmed == false` = 取消（不改动）。
typedef NumberPromptOutcome = ({bool confirmed, bool cleared, double? value});

/// 「点击才输入」共用的数字弹窗（评议分 / 体测分 / 加权成绩 / 志愿时长）。
///
/// [allowClear] = 额外给一个「用自动值」按钮 → `cleared: true`
/// （加权成绩、志愿时长这类「留空即用自动值」的字段用）。
Future<NumberPromptOutcome> promptNumberValue(
  BuildContext context, {
  required String title,
  required String label,
  double? initial,
  double min = 0,
  double max = 100,
  String? helper,
  bool integer = false,
  bool allowClear = false,
  String clearLabel = '用自动值',
}) async {
  final outcome = await showDialog<NumberPromptOutcome>(
    context: context,
    builder: (dialogContext) => _NumberPromptDialog(
      title: title,
      label: label,
      initial: initial,
      min: min,
      max: max,
      helper: helper,
      integer: integer,
      allowClear: allowClear,
      clearLabel: clearLabel,
    ),
  );
  return outcome ?? (confirmed: false, cleared: false, value: null);
}

class _NumberPromptDialog extends StatefulWidget {
  const _NumberPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
    required this.helper,
    required this.integer,
    required this.allowClear,
    required this.clearLabel,
  });

  final String title;
  final String label;
  final double? initial;
  final double min;
  final double max;
  final String? helper;
  final bool integer;
  final bool allowClear;
  final String clearLabel;

  @override
  State<_NumberPromptDialog> createState() => _NumberPromptDialogState();
}

class _NumberPromptDialogState extends State<_NumberPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial == null
        ? ''
        : (widget.integer
              ? widget.initial!.round().toString()
              : _trim(widget.initial!)),
  );
  String? _error;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请输入${widget.label}');
      return;
    }
    final v = double.tryParse(raw);
    if (v == null) {
      setState(() => _error = '请输入数字');
      return;
    }
    if (v < widget.min || v > widget.max) {
      setState(
        () => _error =
            '范围 ${_trim(widget.min)} ~ ${_trim(widget.max)}',
      );
      return;
    }
    Navigator.of(context).pop((confirmed: true, cleared: false, value: v));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.edit_outlined),
      title: Text(widget.title),
      content: TextField(
        key: widget.integer ? null : const Key('numberPromptInput'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.integer,
          signed: false,
        ),
        inputFormatters: widget.integer
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.allowClear)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop((confirmed: true, cleared: true, value: null)),
            child: Text(widget.clearLabel),
          ),
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((confirmed: false, cleared: false, value: null)),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
