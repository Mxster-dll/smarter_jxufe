/// 分数估计 · 编辑弹窗：课程信息 / 平时分项。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../design/feature_palette.dart';
import '../domain/ge_models.dart';
import 'ge_common.dart';

const _uuid = Uuid();

/// 课程信息草稿（弹窗返回）。
class GeCourseDraft {
  final String name;
  final double dailyPercent;

  /// 学分（学分加权平均权重）。
  final double credits;
  final String note;

  const GeCourseDraft({
    required this.name,
    required this.dailyPercent,
    this.credits = 1,
    this.note = '',
  });
}

/// 课程信息弹窗（新建 / 改名共用）。
///
/// 返回 null 表示取消；确认后返回草稿（含最新占比与学分）。
Future<GeCourseDraft?> showGeCourseDialog(
  BuildContext context, {
  String title = '课程信息',
  required String initialName,
  required double initialDailyPercent,
  double initialCredits = 1,
  String initialNote = '',
}) async {
  final nameCtrl = TextEditingController(text: initialName);
  final noteCtrl = TextEditingController(text: initialNote);
  var daily = initialDailyPercent.clamp(0.0, 100.0);
  final dailyCtrl = TextEditingController(text: '${daily.round()}');
  var credits = initialCredits <= 0 ? 1.0 : initialCredits.clamp(0.0, 100.0);
  final creditsCtrl = TextEditingController(text: geFmt(credits));
  var nameError = false;

  /// 手输平时占比（0-100 整数）；空串或非法则回写当前值。
  void applyDailyText() {
    final v = int.tryParse(dailyCtrl.text.trim());
    if (v == null) {
      dailyCtrl.text = '${daily.round()}';
      return;
    }
    final clamped = v.clamp(0, 100);
    dailyCtrl.text = '$clamped';
    daily = clamped.toDouble();
  }

  /// 手输学分（可小数）；空串或非法则回写当前值。
  void applyCreditsText() {
    final v = double.tryParse(creditsCtrl.text.trim());
    if (v == null) {
      creditsCtrl.text = geFmt(credits);
      return;
    }
    final clamped = v.clamp(0.0, 100.0);
    creditsCtrl.text = geFmt(clamped);
    credits = clamped;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final f = fp(context);
        final dailyColor = f.scoreEstimate;
        final finalColor = f.scoreEstimateFinal;
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: initialName.isEmpty,
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: '课程名',
                    hintText: '如 高等数学（上）',
                    errorText: nameError ? '请填写课程名' : null,
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() => nameError = false),
                ),
                const SizedBox(height: 10),
                Text(
                  '占比：平时 ${geFmt(daily)}% · 期末 ${geFmt(100 - daily)}%',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: daily,
                        max: 100,
                        divisions: 10,
                        label: '平时 ${geFmt(daily)}%',
                        onChanged: (v) {
                          setState(() => daily = v.roundToDouble());
                          dailyCtrl.text = '${daily.round()}';
                        },
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        controller: dailyCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: const TextStyle(fontSize: 13.5),
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '%',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        onSubmitted: (_) => applyDailyText(),
                        onTapOutside: (_) => applyDailyText(),
                      ),
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(
                          flex: daily.round(),
                          child: ColoredBox(color: dailyColor),
                        ),
                        Expanded(
                          flex: (100 - daily).round(),
                          child: ColoredBox(color: finalColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '总评 = 平时均分 × ${geFmt(daily)}% + 期末 × ${geFmt(100 - daily)}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      '学分',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        controller: creditsCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(fontSize: 13.5),
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '分',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        onSubmitted: (_) => applyCreditsText(),
                        onTapOutside: (_) => applyCreditsText(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '用于学分加权平均（课表导入自动带入）',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    hintText: '如授课教师 / 学期',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                applyDailyText();
                applyCreditsText();
                if (nameCtrl.text.trim().isEmpty) {
                  setState(() => nameError = true);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  return GeCourseDraft(
    name: nameCtrl.text.trim(),
    dailyPercent: daily,
    credits: credits,
    note: noteCtrl.text.trim(),
  );
}

/// 分项弹窗结局：null = 取消；[deleted] = 删除该分项；否则为保存结果。
class GePartOutcome {
  final GePart part;
  final bool deleted;

  const GePartOutcome(this.part, {this.deleted = false});

  const GePartOutcome.deleted(GePart part) : this(part, deleted: true);
}

/// 平时分项编辑弹窗。
///
/// [part] 为 null 时新建（返回新 id）；编辑时保留原 id。
Future<GePartOutcome?> showGePartDialog(
  BuildContext context, {
  GePart? part,
}) async {
  final isNew = part == null;
  final id = part?.id ?? _uuid.v4();
  var mode = part?.mode ?? GePartMode.up;
  var target = part?.target ?? (mode == GePartMode.down ? 16 : 20);
  var cap = part?.cap ?? 5.0;

  final nameCtrl = TextEditingController(text: part?.name ?? '');
  final noteCtrl = TextEditingController(text: part?.note ?? '');
  final targetCtrl = TextEditingController(text: '$target');
  final currentCtrl = TextEditingController(
    text: '${part?.current ?? (mode == GePartMode.down ? target : 0)}',
  );
  final scoreCtrl = TextEditingController(
    text: geFmt(part?.score ?? 0, decimals: 2),
  );
  final capCtrl = TextEditingController(text: geFmt(cap, decimals: 2));

  String? nameError;
  String? targetError;
  String? scoreError;
  String? capError;

  /// 当前计数状态（与 currentCtrl 同步维护）。
  var current = int.tryParse(currentCtrl.text) ?? 0;

  /// 直接分数模式下的实际得分（与 scoreCtrl 同步维护）。
  var scoreValue = part?.score ?? 0.0;

  void syncFromCurrentText() {
    current = int.tryParse(currentCtrl.text) ?? 0;
  }

  void syncFromScoreText() {
    scoreValue = double.tryParse(scoreCtrl.text) ?? 0;
  }

  void applyMode(GePartMode m) {
    final prev = mode;
    mode = m;
    if (m == GePartMode.score) {
      if (prev != GePartMode.score) {
        // 切到「直接分数」：满分默认取分值上限（= 直接填得分的用法），得分从 0 起。
        target = cap.round().clamp(1, 1 << 20);
        syncFromScoreText();
        scoreCtrl.text = geFmt(scoreValue, decimals: 2);
        targetCtrl.text = '$target';
      }
      return;
    }
    // 计数模式：换方向后计数语义翻转，给出新方向下最自然的起点。
    current = m == GePartMode.down ? target : 0;
    currentCtrl.text = '$current';
    targetCtrl.text = '$target';
  }

  final scheme = Theme.of(context).colorScheme;

  return showDialog<GePartOutcome>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // 确保模式相关字段立即反映（对话框重建时读取最新闭包变量）。
        final isDown = mode == GePartMode.down;
        final isScore = mode == GePartMode.score;
        return AlertDialog(
          title: Text(isNew ? '添加分项' : '编辑分项'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: isNew,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: '分项名称',
                      hintText: '如 考勤 / 作业提交 / 课堂打卡',
                      errorText: nameError,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() => nameError = null),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<GePartMode>(
                      segments: const [
                        ButtonSegment(value: GePartMode.up, label: Text('正计数')),
                        ButtonSegment(
                          value: GePartMode.down,
                          label: Text('负计数'),
                        ),
                        ButtonSegment(
                          value: GePartMode.score,
                          label: Text('直接分数'),
                        ),
                      ],
                      selected: {mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => applyMode(s.first)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    gePartModeHint(mode),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: isScore
                          ? '该项满分'
                          : (isDown ? '总事件数 N（满分）' : '目标次数 N'),
                      hintText: isScore
                          ? '如 100（百分制）/ 10'
                          : (isDown ? '如全学期共 16 次课' : '如本项需完成 20 次'),
                      errorText: targetError,
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      final n = int.tryParse(v) ?? 0;
                      target = n;
                      targetError = n < 1
                          ? (isScore ? '满分须 ≥ 1' : '目标须 ≥ 1')
                          : null;
                      if (isDown && current > n) {
                        current = n;
                        currentCtrl.text = '$current';
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  if (isScore)
                    TextField(
                      controller: scoreCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: '实际得分',
                        hintText: '如 85 或 85.5',
                        helperText: '得分率 = 得分 ÷ 满分（封顶 100%）',
                        errorText: scoreError,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() {
                        final s = double.tryParse(v);
                        scoreValue = s ?? 0;
                        if (v.isEmpty) {
                          scoreError = null;
                        } else if (s == null) {
                          scoreError = '请输入数字，如 85.5';
                        } else {
                          scoreError = s < 0 ? '得分须 ≥ 0' : null;
                        }
                      }),
                    )
                  else
                    TextField(
                      controller: currentCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: isDown ? '当前剩余次数' : '已完成次数',
                        helperText: isDown
                            ? '从 N 起，每缺勤一次 −1（最少 0）'
                            : '从 0 累计，可超过目标（得分封顶）',
                        isDense: true,
                      ),
                      onChanged: (_) {
                        syncFromCurrentText();
                        setState(() {});
                      },
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: capCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '分值上限（占平时满分）',
                      hintText: '如 5 分',
                      errorText: capError,
                      helperText: '该分项做满后在平时满分内的分值',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      final c = double.tryParse(v);
                      cap = c ?? 0;
                      capError = (v.isNotEmpty && c != null && c <= 0)
                          ? '分值须 > 0'
                          : null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      hintText: '如 双周提交',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (!isNew)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () =>
                    Navigator.pop(context, GePartOutcome.deleted(part)),
                child: const Text('删除分项'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                var valid = true;
                final nm = nameCtrl.text.trim();
                if (nm.isEmpty) {
                  nameError = '请填写分项名称';
                  valid = false;
                }
                if (target < 1) {
                  targetError = isScore ? '满分须 ≥ 1' : '目标须 ≥ 1';
                  valid = false;
                }
                if (isScore) {
                  syncFromScoreText();
                  if (scoreValue < 0) {
                    scoreError = '得分须 ≥ 0';
                    valid = false;
                  }
                }
                final capV = double.tryParse(capCtrl.text) ?? 0;
                if (capV <= 0) {
                  capError = '分值须 > 0';
                  valid = false;
                }
                if (!valid) return;
                syncFromCurrentText();
                Navigator.pop(
                  context,
                  GePartOutcome(
                    GePart(
                      id: id,
                      name: nm,
                      mode: mode,
                      target: target,
                      current: isScore
                          ? 0
                          : (isDown ? current.clamp(0, target) : current),
                      score: isScore ? scoreValue : 0,
                      cap: capV,
                      note: noteCtrl.text.trim(),
                    ),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
}
