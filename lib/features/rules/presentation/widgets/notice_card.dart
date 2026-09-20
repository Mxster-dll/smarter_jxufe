import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';

/// 红头通知卡片：左侧朱红饰条 + 文号/标题 + 可折叠正文区。
/// 内部自带展开收起，[children] 为通知区正文渲染序列。
class NoticeCard extends StatefulWidget {
  final String header;
  final List<Widget> children;

  const NoticeCard({super.key, required this.header, required this.children});

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      // 卡片契约（`lib/design/app_card.dart`）：圆角 12 + hairline 描边 + 卡片底色。
      // 曾是 radius 10 + `outlineVariant` 实线描边 —— 比契约重一档、圆角也不同，
      // 于是同页里「红头通知卡」与其它卡片看起来像两套样式。
      decoration: ShapeDecoration(
        shape: appCardShape(context),
        color: appCardColor(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (_open) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
