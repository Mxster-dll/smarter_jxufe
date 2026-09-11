/// 分数估计 · 通用小件：数字格式、删除确认、计分模型说明。
library;

import 'package:flutter/material.dart';

import '../../../design/feature_palette.dart';
import '../domain/ge_models.dart';

/// 数字展示：保留 [decimals] 位并去掉无意义尾零（100.0 → 100；0.5 → 0.5）。
String geFmt(num v, {int decimals = 1}) {
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return s;
}

/// 通用删除确认框；返回是否确认。
Future<bool> geConfirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 计分模型说明正文（详情页折叠卡与帮助弹层复用）。
Widget geModelHintBody() {
  Widget row(IconData icon, Color color, String title, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      row(
        Icons.percent,
        const Color(0xFF536DFE),
        '构成占比',
        '平时分与期末成绩按比例计入总评（两档合计 100%，默认为平时 30% + 期末 70%）。'
            '总评 = 平时均分（百分制）× 平时占比 + 期末分 × 期末占比。',
      ),
      row(
        Icons.hub_outlined,
        const Color(0xFF00897B),
        '平时分由分项组成',
        '每个分项设一个「分值上限」（占平时满分的分值），各分项分值之和即平时满分，'
            '如平时 30 分 = 考勤 5 + 作业 15 + 表现 10。',
      ),
      row(
        Icons.trending_up,
        const Color(0xFF2E7D32),
        '正计数分项（从 0 累计）',
        '适合打卡、提交等「做了才算」的事件：目标 N 次，已做 k 次 → 得分率 k/N，'
            '如打卡 12/20 → 60%。超过目标仍按满分计。',
      ),
      row(
        Icons.trending_down,
        const Color(0xFFC62828),
        '负计数分项（从目标总数向下扣）',
        '适合考勤等「缺席才扣」的事件：目标 N 为总事件数（如全学期 16 次课），'
            '每缺勤一次计数 −1，得分率 = 剩余次数 / N（下限 0），如剩 13/16 → 81.25%。'
            '已扣减无法挽回，属于「已达上限即现状」的分项。',
      ),
      row(
        Icons.edit_note,
        const Color(0xFF0277BD),
        '直接分数分项（老师直接给分）',
        '适合期中测验、实验报告等老师直接打分的项：填该项满分与实际得分'
            '（如 85 / 100 → 得分率 85%），得分 = 得分率 × 分值上限；'
            '满分与分值上限填成一样时，就是直接填「得了几分」。得分可填小数。',
      ),
      row(
        Icons.flag_outlined,
        const Color(0xFFE65100),
        '目标反推与预警',
        '反推：为达到目标总评，期末最低需要多少分；若期末满分也不够，会提示平时'
            '剩余分项能否补足（正计数还能再刷、直接分数项未拿满的部分还能再挣；'
            '负计数损失不回），并给出全局上限。',
      ),
    ],
  );
}

/// 模型说明弹层（AppBar 帮助）。
void geShowModelSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(child: geModelHintBody()),
    ),
  );
}

/// 计分方式配色：up = 绿、down = 红、score = 蓝（唯一出处，徽章与芯片共用）。
Color geModeColor(GePartMode mode) => switch (mode) {
  GePartMode.up => const Color(0xFF2E7D32),
  GePartMode.down => const Color(0xFFC62828),
  GePartMode.score => const Color(0xFF0277BD),
};

/// 计分方式图标。
IconData geModeIcon(GePartMode mode) => switch (mode) {
  GePartMode.up => Icons.arrow_upward,
  GePartMode.down => Icons.arrow_downward,
  GePartMode.score => Icons.edit_note,
};

/// 计分方式徽章（分项行首）。
class GeModeBadge extends StatelessWidget {
  final GePartMode mode;
  final double size;

  const GeModeBadge({super.key, required this.mode, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final color = geModeColor(mode);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(geModeIcon(mode), size: size * 0.52, color: color),
    );
  }
}

/// 计分方式芯片（模式语义小标签）。
class GeModeChip extends StatelessWidget {
  final GePartMode mode;

  const GeModeChip({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final color = geModeColor(mode);
    final label = switch (mode) {
      GePartMode.up => '向上计数 +',
      GePartMode.down => '向下计数 −',
      GePartMode.score => '直接分数',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.9)),
      ),
    );
  }
}

// ---- 与 App 首页统一的卡片语言 ----

/// 卡片外形：圆角 8 + outline 细边框（无阴影），与首页功能卡一致。
RoundedRectangleBorder geCardShape(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    side: BorderSide(color: scheme.outline),
  );
}

/// 卡内区块标题：3px 竖条 + 标题（仿首页「全部服务」节标题）。
///
/// [accent] 默认模块靛蓝；[trailing] 非空时靠右显示。
Widget geCardTitle(
  BuildContext context, {
  required String text,
  Widget? trailing,
  Color? accent,
}) {
  final a = accent ?? FeaturePalette.scoreEstimate;
  return Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: a,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      if (trailing != null) ...[const Spacer(), trailing],
    ],
  );
}
