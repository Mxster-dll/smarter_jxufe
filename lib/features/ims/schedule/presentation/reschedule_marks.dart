import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';

/// 调课相关的展示小件 —— 网格与横版列表共用，避免两处各写一遍。

/// 标记对应的角标颜色。
Color rescheduleMarkColor(EffectiveMark mark) => switch (mark) {
  EffectiveMark.moved => FeaturePalette.reschedule,
  EffectiveMark.movedAway => FeaturePalette.classCancelled,
  EffectiveMark.cancelled => FeaturePalette.classCancelled,
  EffectiveMark.extra => FeaturePalette.makeUpClass,
  EffectiveMark.normal => FeaturePalette.schedule,
};

/// 标记对应的角标文案；[EffectiveMark.normal] 返回 null（无角标）。
String? rescheduleBadgeText(EffectiveMark mark) => switch (mark) {
  EffectiveMark.moved => '调',
  EffectiveMark.movedAway => '调',
  EffectiveMark.cancelled => '停',
  EffectiveMark.extra => '补',
  EffectiveMark.normal => null,
};

/// 角标组件；[EffectiveMark.normal] 返回 null。
Widget? rescheduleBadge(EffectiveMark mark) {
  final text = rescheduleBadgeText(mark);
  if (text == null) return null;
  return _Badge(text: text, color: rescheduleMarkColor(mark));
}

/// 整学期视图专用：某个原课位上有 [count] 条单次调课时的提示角标。
///
/// 整学期模板不区分周次，单次调课无法就地展开，因此只提示「这里有过调整」，
/// 让用户切到具体某一周去看细节。
Widget? rescheduleOnceBadge(int count) {
  if (count <= 0) return null;
  return _Badge(
    text: count > 1 ? '调×$count' : '调',
    color: FeaturePalette.reschedule,
  );
}

/// 原时段简述，如「周三 3-4节」。
String rescheduleOriginShort(Reschedule? r) {
  if (r == null) return '';
  final d = r.originDay;
  final s = r.originStartPeriod;
  final e = r.originEndPeriod;
  if (d == null || s == null || e == null) return '';
  return '${d.displayName} ${periodRangeText(s, e)}';
}

/// 目标时段简述，如「周五 6-8节」。
String rescheduleTargetShort(Reschedule? r) {
  if (r == null) return '';
  final d = r.targetDay;
  final s = r.targetStartPeriod;
  final e = r.targetEndPeriod ?? s;
  if (d == null || s == null || e == null) return '';
  return '${d.displayName} ${periodRangeText(s, e)}';
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        color: Colors.white,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    ),
  );
}
