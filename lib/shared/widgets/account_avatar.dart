import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/auth/data/providers/account_avatar_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_display_name_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';

/// 账号头像 —— **三级回退**：本地图片 → 姓名首字 → 通用图标。
///
/// 图片来源 = 绑定到当前账号的本地文件（[accountAvatarProvider] / `avatars/` 目录）；
/// 文件不存在（未设置 / 被外部清掉）时用 [name] 的首字（缺省取本地账户显示名），
/// 名字也没有才退到 person 图标。图片加载失败也落回首字 —— 不会出现空白圈。
///
/// 首页顶栏与「我的」页共用本组件，读同一个控制器实例 → 换图同帧生效。
class AccountAvatar extends ConsumerWidget {
  /// 半径（外径 = 2 × radius）。
  final double radius;

  /// 首字回退用的名字（如「我的」页的学籍姓名）；为空时用本地账户显示名。
  final String? name;

  /// 传入即为可点击（圆形容器 + 水波纹），缺省只做展示。
  final VoidCallback? onTap;

  /// 触摸提示（可点击时建议给，如「我的」）。
  final String? tooltip;

  const AccountAvatar({
    super.key,
    this.radius = 18,
    this.name,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = ref.watch(accountAvatarProvider);
    // 「??」短路：调用方给了名字就不再订阅本地显示名
    final displayName =
        name ?? ref.watch(currentAccountNameProvider).valueOrNull ?? '';
    final resolved = resolveAvatarKind(
      hasFile: avatar.filePath != null,
      displayName: displayName,
    );
    final path = avatar.filePath;

    final Widget content;
    if (avatar.busy) {
      content = SizedBox(
        width: radius,
        height: radius,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onError),
      );
    } else if (resolved.initial.isEmpty) {
      content = Icon(Icons.person, size: radius * 1.2, color: scheme.onError);
    } else {
      // 图片形态下这层仍会画在 foregroundImage 之下 —— 图片坏了不至于空白
      content = Text(
        resolved.initial,
        style: TextStyle(fontSize: radius * 0.9, color: scheme.onError),
      );
    }

    final circle = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.error,
      foregroundImage: path == null || avatar.busy
          ? null
          : FileImage(File(path)),
      onForegroundImageError: path == null ? null : (_, _) {},
      child: content,
    );

    if (onTap == null) return circle;

    final button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(padding: const EdgeInsets.all(2), child: circle),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
