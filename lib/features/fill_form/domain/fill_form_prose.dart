/// 填表助手 · **prose 层**（顶层函数，2026-10-09 架构审计第四轮）。
///
/// 拆分自 `fill_form_data.dart`（1061 行 = 1 个模型 + 39 个顶层函数）：
/// 依赖实测为**有向无环** —— `values`(编排) → `prose`(行文) → `zc`(取数) → `ffNum`(叶子)。
/// 桶文件 `fill_form_data.dart` 既 import（自己用）又 export 本文件，**调用点零改动**。
library;

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'fill_form_data.dart';

// ---------------------------------------------------------------------------
// 成段文字（用户 2026-10-07 拍板：自动成文 + 允许适度评价性表述）
// ---------------------------------------------------------------------------

/// 「主要表现（德、智、体等方面）」。
String proseMainPerformance(FillFormData d) {
  final lines = <String>[];
  final zc = d.zc;
  if (zc != null) {
    lines.add(
      '本学年综合素质测评总评成绩 ${ffNum(zc.total)} 分'
      '（德育 ${ffNum(zc.deyu)}、智育 ${ffNum(zc.zhiyu)}、体育 ${ffNum(zc.tiyu)}、'
      '美育 ${ffNum(zc.meiyu)}、劳育 ${ffNum(zc.laoyu)}），测评等次「${zc.overall.label}」。',
    );
  }
  final gradeLine = <String>[];
  final w = ffNum(d.weighted);
  if (w != null) gradeLine.add('学年加权平均成绩 $w 分');
  final min = ffNum(d.minScore);
  if (min != null) gradeLine.add('单科最低 $min 分');
  final cr = ffNum(d.credits);
  if (cr != null) gradeLine.add('学年所修学分 $cr 分');
  gradeLine.add(d.hasFail ? '有不及格课程' : '无不及格课程');
  lines.add('${gradeLine.join('，')}。');

  final duty = _dutyLine(d);
  final honors = ffByType(d, const [ZcTypeId.honorP, ZcTypeId.honorG]);
  if (duty.isNotEmpty || honors.isNotEmpty) {
    final parts = [
      if (duty.isNotEmpty) duty,
      if (honors.isNotEmpty)
        '获${honors.take(3).map(ffNamedWithYear).join('、')}',
    ];
    lines.add('${parts.join('；')}。');
  }
  final contest = ffByType(d, const [ZcTypeId.contest]);
  final paper = ffByType(d, const [ZcTypeId.paper]);
  if (contest.isNotEmpty || paper.isNotEmpty) {
    final parts = [
      if (contest.isNotEmpty) '学科竞赛获${ffAwardSummary(contest)}',
      if (paper.isNotEmpty) '发表论文/获专利 ${paper.length} 项',
    ];
    lines.add('${parts.join('，')}。');
  }
  final vol = ffNum(d.volunteerHours);
  if (vol != null && (d.volunteerHours ?? 0) > 0) {
    lines.add('本学年认定志愿服务时长 $vol 小时。');
  }
  lines.add(_closingLine(d));
  return lines.join('\n');
}

/// 「担任学生干部情况」。
String? proseDuty(FillFormData d) {
  final posts = ffByType(d, const [ZcTypeId.servicePost], all: true);
  if (posts.isEmpty) return null;
  return posts
      .map((m) => '于${d.yearLabelShort}年度${_namedPost(m)}')
      .join('；');
}

/// 「大学期间受表彰情况」（表 7 的模板格式：按级别分行）。
String? proseHonors(FillFormData d) {
  final honors = ffByType(
    d,
    const [ZcTypeId.honorP, ZcTypeId.honorG],
    all: true,
  );
  final contests = ffByType(d, const [ZcTypeId.contest], all: true);
  final buckets = <String, List<String>>{
    '国家级': [],
    '省部级': [],
    '市（校）级': [],
    '院级': [],
  };
  void put(ZcMaterial m, String levelText) {
    final key = levelText.startsWith('国家')
        ? '国家级'
        : levelText.startsWith('省')
            ? '省部级'
            : levelText.startsWith('市') || levelText.startsWith('校') ||
                    levelText.startsWith('学校')
                ? '市（校）级'
                : '院级';
    buckets[key]!.add(ffNamedWithYear(m));
  }

  for (final m in honors) {
    final spec = m.spec;
    put(
      m,
      m.level >= 0 && m.level < spec.levels.length ? spec.levels[m.level] : '',
    );
  }
  for (final m in contests) {
    final spec = m.spec;
    final level = m.level >= 0 && m.level < spec.levels.length
        ? spec.levels[m.level]
        : '';
    put(m, level);
  }
  final out = <String>[];
  var i = 0;
  for (final key in ['国家级', '省部级', '市（校）级', '院级']) {
    final items = buckets[key]!;
    if (items.isEmpty) continue;
    i++;
    out.add('$i.$key奖项/荣誉：${items.join('、')}');
  }
  return out.isEmpty ? null : out.join('\n');
}

/// 「突出事迹」（按表 7 模板的四段式，编号按实际有内容的段顺延）。
String? proseDeeds(FillFormData d) {
  final items = <String>[];
  final w = ffNum(d.weighted);
  final min = ffNum(d.minScore);
  items.add(
    '学业表现：${
        [
          if (w != null) '学年加权平均成绩 $w 分',
          if (min != null) '单科最低 $min 分',
          d.hasFail ? '有不及格课程' : '无不及格课程',
          if (d.zc != null) '综合素质测评等次「${d.zc!.overall.label}」',
        ].join('，')
      }。',
  );

  final contest = ffByType(d, const [ZcTypeId.contest], all: true);
  if (contest.isNotEmpty) items.add('学科竞赛：获${ffAwardSummary(contest)}。');

  final paper = ffByType(d, const [ZcTypeId.paper], all: true);
  if (paper.isNotEmpty) {
    items.add('科研成果：${paper.take(3).map(ffNamedWithYear).join('、')}。');
  }

  final work = <String>[
    if (_dutyLine(d, all: true).isNotEmpty) _dutyLine(d, all: true),
    if ((d.volunteerHours ?? 0) > 0)
      '本学年认定志愿服务时长 ${ffNum(d.volunteerHours)} 小时',
  ];
  if (work.isNotEmpty) items.add('学生工作与社会实践：${work.join('；')}。');

  if (items.isEmpty) return null;
  return [
    for (var i = 0; i < items.length; i++) '${i + 1}.${items[i]}',
  ].join('\n');
}

/// 「科研成果及实践创新情况」。
String? proseResearch(FillFormData d) {
  final parts = <String>[];
  final paper = ffByType(d, const [ZcTypeId.paper], all: true);
  if (paper.isNotEmpty) {
    parts.add('发表论文/获专利：${paper.take(3).map(ffNamedWithYear).join('、')}');
  }
  final contest = ffByType(d, const [ZcTypeId.contest], all: true);
  if (contest.isNotEmpty) parts.add('学科竞赛获${ffAwardSummary(contest)}');
  final startup = ffByType(d, const [ZcTypeId.startup], all: true);
  if (startup.isNotEmpty) {
    parts.add('自主创业：${startup.map(ffNamedWithYear).join('、')}');
  }
  return parts.isEmpty ? null : '${parts.join('；')}。';
}

/// 「服务社会情况」。
String? proseService(FillFormData d) {
  final parts = <String>[];
  final vol = ffNum(d.volunteerHours);
  if (vol != null && (d.volunteerHours ?? 0) > 0) {
    parts.add('本学年认定志愿服务时长 $vol 小时');
  }
  final social = ffByType(
    d,
    const [ZcTypeId.social, ZcTypeId.deed, ZcTypeId.laborAct],
    all: true,
  );
  if (social.isNotEmpty) {
    parts.add(
      '参加社会实践与公益活动：${social.take(3).map(ffNamedWithYear).join('、')}',
    );
  }
  return parts.isEmpty ? null : '${parts.join('；')}。';
}

/// 「受奖励、处分情况」。
String? proseAwards(FillFormData d) {
  final parts = <String>[];
  final honors = ffByType(
    d,
    const [ZcTypeId.honorP, ZcTypeId.honorG, ZcTypeId.contest],
    all: true,
  );
  if (honors.isNotEmpty) {
    parts.add('奖励：${honors.take(6).map(ffNamedWithYear).join('、')}');
  }
  parts.add(d.manual.kouCf > 0 ? '本学年有违纪处分记录' : '本学年无违纪处分记录');
  return '${parts.join('；')}。';
}

/// 「本人申请理由」。
String? proseReason(FillFormData d) {
  final lines = <String>[];
  final who = <String>[
    if (d.college.isNotEmpty) d.college,
    if (d.major.isNotEmpty) '${d.major}专业',
  ].join();
  final head = <String>[
    if (who.isNotEmpty)
      '本人系$who${d.enrollYear.isEmpty ? '' : '${d.enrollYear}级'}学生',
    if (d.className.isNotEmpty) '所在班级 ${d.className}',
  ];
  if (head.isNotEmpty) lines.add('${head.join('，')}。');
  if (d.zc != null) {
    lines.add(
      '${d.yearLabel}综合素质测评总评成绩 ${ffNum(d.zc!.total)} 分，'
      '测评等次「${d.zc!.overall.label}」。',
    );
  }
  final grade = <String>[
    if (ffNum(d.weighted) != null) '学年加权平均成绩 ${ffNum(d.weighted)} 分',
    if (ffNum(d.minScore) != null) '单科最低 ${ffNum(d.minScore)} 分',
    d.hasFail ? '有不及格课程' : '无不及格课程',
  ];
  if (grade.isNotEmpty) lines.add('${grade.join('，')}。');
  final honors = ffByType(
    d,
    const [ZcTypeId.honorP, ZcTypeId.honorG, ZcTypeId.contest],
  );
  if (honors.isNotEmpty) {
    lines.add('本学年获${honors.take(4).map(ffNamedWithYear).join('、')}。');
  }
  return lines.isEmpty ? null : lines.join('\n');
}

/// 「英语水平（四六级通过情况及分数）」。
String? proseEnglish(FillFormData d) {
  final items = ffByType(d, const [ZcTypeId.foreign], all: true);
  if (items.isEmpty) return null;
  return items.map((m) {
    final score = m.manualScore;
    final s = ffNum(score);
    return s == null ? m.displayName : '${m.displayName}，$s 分';
  }).join('；');
}

/// 「职务」那一格（只要职务名，带顿号分隔）。
String? ffDutySummary(FillFormData d) {
  final posts = ffByType(d, const [ZcTypeId.servicePost], all: true);
  if (posts.isEmpty) return null;
  return posts.map((m) => _namedPost(m).replaceFirst('担任', '')).join('、');
}

// ---------------------------------------------------------------------------
// 「限 N 字」截断
// ---------------------------------------------------------------------------

/// 从标签/提示里抠出字数上限（`限100字以内` / `限 150 字`）。
int? ffCharLimitOf(String text) {
  final m = RegExp(r'限\s*(\d{1,4})\s*字').firstMatch(text);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return n == null || n <= 0 ? null : n;
}

/// 按字数上限截断（学校原话：「多出字数按前后顺序直接删除」）。
///
/// ⚠ 先按**行**丢整行（宁可少一条，也不要留半句），最后一行才逐字截。
String clipToLimit(String text, int limit) {
  final flat = text.replaceAll('\n', ' ');
  if (flat.runes.length <= limit) return text;
  final lines = text.split('\n');
  final kept = <String>[];
  var used = 0;
  for (final line in lines) {
    final cost = line.runes.length + (kept.isEmpty ? 0 : 1);
    if (used + cost > limit) break;
    kept.add(line);
    used += cost;
  }
  if (kept.isEmpty) {
    return String.fromCharCodes(flat.runes.take(limit));
  }
  return kept.join('\n');
}

/// 结尾那句克制的评价 —— **按数据挑**（没有荣誉就不写「表现突出」）。
String _closingLine(FillFormData d) {
  final overall = d.zc?.overall;
  final hasAward = ffByType(d, const [
    ZcTypeId.contest,
    ZcTypeId.honorP,
    ZcTypeId.paper,
  ]).isNotEmpty;
  if (hasAward && overall == ZcGrade.ok) {
    return '思想端正，学习认真，工作负责，各方面表现均衡，能起到较好的示范带头作用。';
  }
  if (overall == ZcGrade.ok || overall == ZcGrade.good) {
    return '思想端正，学习态度认真，能够按时完成各项学习与工作任务。';
  }
  return '能够遵守校纪校规，按学校要求完成各项学习任务。';
}

String _dutyLine(FillFormData d, {bool all = false}) {
  final posts = ffByType(d, const [ZcTypeId.servicePost], all: all);
  if (posts.isEmpty) return '';
  return posts.take(2).map(_namedPost).join('；');
}

String _namedPost(ZcMaterial m) {
  final spec = m.spec;
  final level = m.level >= 0 && m.level < spec.levels.length
      ? spec.levels[m.level].split('（').first
      : m.displayName;
  final opt = m.opt >= 0 && m.opt < spec.opts.length
      ? spec.opts[m.opt].split('（').first
      : '';
  return opt.isEmpty ? '担任$level' : '担任$level（$opt）';
}
