/// 「我的校区」在学校地址 / 校区地图两页共用的展示件。
///
/// 两页的置顶规则一致（[pinMineFirst]），徽标与提示行也保持一致，
/// 避免各写一份导致口径漂移。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';

const _accent = FeaturePalette.cardAccent;

/// 「我的校区」徽标（图钉 + 文字）。
///
/// [onImage] 为真时用实底白字，供压在图片上时保证可读性；否则用浅底彩字。
Widget myCampusBadge(BuildContext context, {bool onImage = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: onImage ? _accent : _accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.push_pin, size: 11, color: onImage ? Colors.white : _accent),
        const SizedBox(width: 4),
        Text(
          '我的校区',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: onImage ? Colors.white : _accent,
          ),
        ),
      ],
    ),
  );
}

/// 列表顶部的一行状态提示：未设置 / 已置顶哪几条 / 本列表无对应条目。
///
/// [pinnedNames] 由调用方按自己的条目粒度给出（校区地图是北区、南区两条）。
Widget myCampusHint(
  BuildContext context, {
  required MyCampus? mine,
  required List<String> pinnedNames,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isSet = mine != null;
  final text = !isSet
      ? '未设置我的校区 · 可在「设置」中指定，本列表将自动置顶对应条目'
      : pinnedNames.isEmpty
      ? '我的校区：${mine.label} · 本列表无对应条目'
      : '已置顶我的校区：${pinnedNames.join('、')}';
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(
          isSet ? Icons.push_pin_outlined : Icons.info_outline,
          size: 15,
          color: isSet ? _accent : scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: isSet ? _accent : scheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}
