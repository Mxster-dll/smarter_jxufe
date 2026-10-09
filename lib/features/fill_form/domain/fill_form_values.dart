/// 填表助手 · **values 层**（顶层函数，2026-10-09 架构审计第四轮）。
///
/// 拆分自 `fill_form_data.dart`（1061 行 = 1 个模型 + 39 个顶层函数）：
/// 依赖实测为**有向无环** —— `values`(编排) → `prose`(行文) → `zc`(取数) → `ffNum`(叶子)。
/// 桶文件 `fill_form_data.dart` 既 import（自己用）又 export 本文件，**调用点零改动**。
library;

import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'docx_fields.dart';
import 'docx_scan.dart' show squashLabel;
import 'fill_form_data.dart';

// ---------------------------------------------------------------------------
// 入口：一个待填项该填什么
// ---------------------------------------------------------------------------

/// 自动值；`null` = 填不了（界面留空给用户手填）。
///
/// [field] 来自 `docxScan`；`field.isListTable` 的走清单表口径（TSV）。
String? fillValueFor(DocxField field, FillFormData d) {
  if (field.isListTable) {
    final tsv = _listTableValue(field.listTable!, d);
    return tsv.isEmpty ? null : tsv;
  }
  final v = labelValueFor(field.label, group: field.group, d: d);
  if (v == null || v.trim().isEmpty) return null;
  final limit = ffCharLimitOf('${field.label}${field.hint}');
  return limit == null ? v : clipToLimit(v, limit);
}

/// 标签比对用的**归一形态**：压掉空白 + 去掉括号说明。
///
/// `培养单位（公章）` → `培养单位`（要填的是单位名，括号只是提醒盖章）；
/// 括号里全是说明时（`（学院公章）`）退回原文，交给扫描器的跳过规则处理。
String coreLabel(String label) {
  final flat = squashLabel(label);
  final stripped = flat.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  return stripped.isEmpty ? flat : stripped;
}

/// 按标签取自动值（清单表的列也走它）。
///
/// [group] = 同行分组标签（「德育」「智育」…），用于消解「合计」这种重名标签。
String? labelValueFor(String label, {String group = '', required FillFormData d}) {
  final t = coreLabel(label);
  final g = coreLabel(group);
  final zc = d.zc;

  // ---- 身份 / 学籍 ----
  if (t == '姓名' || t == '学生姓名' || t == '参评人') return d.name;
  if (t == '学号') return d.studentId;
  if (t == '性别') return d.gender;
  if (t == '出生年月' || t == '出生日期') return birthYearMonth(d.birthDate);
  if (t == '民族') return d.ethnicity;
  if (t == '政治面貌') return d.politicalStatus;
  if (t == '班级' || t == '行政班级' || t == '所在班级') return d.className;
  if (t == '学院' || t == '院系' || t == '培养单位' || t == '学院名称') {
    return d.college;
  }
  if (t == '专业') return d.major;
  if (t == '专业类型') return d.trainLevel.isEmpty ? '本科生' : d.trainLevel;
  if (t == '年级') return d.enrollYear.isEmpty ? '' : '${d.enrollYear} 级';
  if (t == '学制') return d.studyYears.isEmpty ? null : '${d.studyYears} 年';
  if (t == '辅导员' || t == '班主任') return d.advisor;
  if (t == '联系电话' || t == '电话' || t == '手机') return d.phone;
  if (t == '电子邮箱' || t == '邮箱') return d.email;
  if (t.contains('通讯地址') || t == '家庭住址' || t == '家庭详细通讯地址、电话') {
    final parts = [
      if (d.address.trim().isNotEmpty) d.address.trim(),
      if (d.phone.trim().isNotEmpty) d.phone.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
  if (t == '籍贯') return d.hometown;
  if (t == '家庭联系人') return d.familyContact;
  if (t == '家庭联系电话' || t == '家庭联系人方式') {
    return d.familyContactPhone;
  }
  if (t == '填表时间' || t == '填表日期') return ffToday(d);

  // ---- 成绩 ----
  if (t == '学年加权' || t == '学年加权平均成绩' || t == '加权平均成绩') {
    return ffNum(d.weighted);
  }
  if (t == '加权成绩' || t == '加权成绩/单科最低分') {
    final w = ffNum(d.weighted);
    final m = ffNum(d.minScore);
    if (w == null && m == null) return null;
    return '${w ?? '—'}/${m ?? '—'}';
  }
  if (t == '最低单科成绩' || t == '单科最低成绩' || t == '最低单科分') {
    return ffNum(d.minScore);
  }
  if (t == '学年所修学分总数' || t == '所修学分' || t == '学分总数') {
    return ffNum(d.credits);
  }
  if (t == '是否有挂科' || t == '有无挂科') return d.hasFail ? '有' : '无';

  // ---- 综测（全部走引擎）----
  if (t == '综合素质测评等次' || t == '综合测评等次' || t == '综合测评等级' ||
      t == '测评等次') {
    return zc?.overall.label;
  }
  if (t.contains('民主评议')) {
    final dim = ffDimOf(t) ?? ffDimOf(g);
    if (dim == null || zc == null) return null;
    return ffNum(ffDetailSum(zc, '${ffDimName(dim)} · 民主评议'));
  }
  if (t.contains('基础分')) {
    final dim = ffDimOf(t) ?? ffDimOf(g);
    if (dim == null || zc == null) return null;
    switch (dim) {
      case 'd':
      case 'm':
      case 'l':
        return '60';
      case 'z':
        return ffNum(zc.weightUsed);
      case 't':
        return ffNum(ffDetailSum(zc, '体育 · 体测'));
    }
  }
  if (t.contains('附加分数合计') || t == '附加分' || t == '附加分合计') {
    final dim = ffDimOf(t) ?? ffDimOf(g);
    if (dim == null || zc == null) return null;
    return ffNum(ffAddedScore(zc, d.manual, dim));
  }
  if (t == '加、减分项目' || t == '加减分项目' || t == '加分项目') {
    final dim = ffDimOf(t) ?? ffDimOf(g);
    if (dim == null || zc == null) return null;
    return ffAddSubtractText(zc, dim);
  }
  if (t == '合计') {
    final dim = ffDimOf(g) ?? ffDimOf(t);
    if (dim == null || zc == null) return null;
    return ffNum(ffDimTotal(zc, dim));
  }
  if (t.contains('等次') && t.contains('班级评议')) {
    final dim = ffDimOf(t) ?? ffDimOf(g);
    if (dim == null || zc == null) return null;
    return ffDimGrade(zc, dim).label;
  }
  if (t == '体测成绩') {
    return d.manual.tMian ? '60（免测）' : ffNum(d.manual.tScore);
  }
  if (t == '志愿服务时长' || t == '志愿时长') return ffNum(d.volunteerHours);

  // ---- 材料清单里的「总分」 ----
  if (t == '总分' || t == '合计分') return ffNum(ffMaterialTotal(d.materials));

  // ---- 成段文字 ----
  if (t == '主要表现' || t.contains('德、智、体')) return proseMainPerformance(d);
  if (t.contains('受表彰') || t == '表彰奖励情况') return proseHonors(d);
  if (t.contains('突出事迹')) return proseDeeds(d);
  if (t.contains('科研成果') || t.contains('实践创新')) return proseResearch(d);
  if (t.contains('服务社会')) return proseService(d);
  if (t.contains('受奖励') || t.contains('处分情况')) return proseAwards(d);
  if (t.contains('申请理由') || t.contains('本人申请')) return proseReason(d);
  if (t == '英语水平') return proseEnglish(d);
  // 「职务」那一格只要职务名（`班长 / 团支书（考核优秀）`）；
  // 「担任学生干部情况」才写成整句（`于2025-2026年度担任…`）。
  if (t == '职务' || t == '担任职务') return ffDutySummary(d);
  if (t.contains('担任学生干部')) return proseDuty(d);

  // ---- 用户自己定，别猜 ----
  // 「授予称号」「奖学金等级」「参评项目」「金额」这类取决于报哪个奖/哪个称号，
  // 应用里没有依据 → 留空由用户填。
  return null;
}

/// `1990-01-01` → `1990年1月`（表里要的是「出生年月」）。
String? birthYearMonth(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{4})[-/年.](\d{1,2})').firstMatch(t);
  if (m == null) return t;
  return '${m.group(1)}年${int.parse(m.group(2)!)}月';
}

// ---------------------------------------------------------------------------
// 清单表（TSV）
// ---------------------------------------------------------------------------

/// 清单表的自动值：**一行一条记录、制表符分列**（顺序 = 表头列序）。
String _listTableValue(DocxListTable table, FillFormData d) {
  if (table.materialRows) return _materialRowsTsv(table, d);
  return _rosterRowTsv(table, d);
}

String _materialRowsTsv(DocxListTable table, FillFormData d) {
  // 按获得时间**倒序**（最近的在前，评审看表就是这个顺序）；没填日期的排最后。
  final sorted = [...d.materials]
    ..sort((a, b) {
      final da = a.dateIso.trim();
      final db = b.dateIso.trim();
      if (da.isEmpty && db.isEmpty) return 0;
      if (da.isEmpty) return 1;
      if (db.isEmpty) return -1;
      return db.compareTo(da);
    });
  final rows = <String>[];
  var i = 0;
  for (final m in sorted) {
    final v = zcMaterialValue(m);
    i++;
    rows.add(
      [
        for (final c in table.columns)
          _materialCell(c.kind, m, v, seq: i, d: d),
      ].join('\t'),
    );
  }
  return rows.join('\n');
}

String _materialCell(
  DocxListColumnKind kind,
  ZcMaterial m,
  double? value, {
  required int seq,
  required FillFormData d,
}) {
  switch (kind) {
    case DocxListColumnKind.seq:
      return '$seq';
    case DocxListColumnKind.project:
      return m.displayName;
    case DocxListColumnKind.category:
      return zcCatNames[m.cat.trim().toLowerCase()] ?? '';
    case DocxListColumnKind.level:
      return _levelAbbr(m);
    case DocxListColumnKind.date:
      return m.dateIso.replaceAll('-', '/');
    case DocxListColumnKind.attachCount:
      return '${m.files.length}';
    case DocxListColumnKind.score:
      return ffNum(value) ?? '';
    default:
      return _rosterCell(kind, d);
  }
}

/// 级别简称（表里给的例子就是「国一」）。
String _levelAbbr(ZcMaterial m) {
  const levelChars = ['国', '省', '校'];
  final spec = m.spec;
  var head = '';
  if (m.level >= 0 && m.level < spec.levels.length) {
    final raw = spec.levels[m.level];
    if (raw.startsWith('国家')) {
      head = levelChars[0];
    } else if (raw.startsWith('省')) {
      head = levelChars[1];
    } else if (raw.startsWith('校')) {
      head = levelChars[2];
    }
  }
  var tail = '';
  if (m.opt >= 0 && m.opt < spec.opts.length) {
    final raw = spec.opts[m.opt];
    for (final p in const [
      ('特等', '特'),
      ('一等', '一'),
      ('二等', '二'),
      ('三等', '三'),
      ('参与', '参与'),
    ]) {
      if (raw.startsWith(p.$1)) {
        tail = p.$2;
        break;
      }
    }
  }
  return '$head$tail';
}

String _rosterRowTsv(DocxListTable table, FillFormData d) {
  return [
    for (final c in table.columns) _clipColumn(_rosterCell(c.kind, d), c.header),
  ].join('\t');
}

/// 表头里写了「限 N 字」的列按 N 字截断（表 7 的受表彰情况 100 字 / 突出事迹 150 字）。
String _clipColumn(String value, String header) {
  if (value.isEmpty) return value;
  final limit = ffCharLimitOf(header);
  return limit == null ? value : clipToLimit(value, limit);
}

String _rosterCell(DocxListColumnKind kind, FillFormData d) {
  final zc = d.zc;
  switch (kind) {
    case DocxListColumnKind.seq:
      return '1';
    case DocxListColumnKind.name:
      return d.name;
    case DocxListColumnKind.studentId:
      return d.studentId;
    case DocxListColumnKind.className:
      return d.className;
    case DocxListColumnKind.collegeClass:
      final parts = [
        if (d.college.isNotEmpty) d.college,
        if (d.className.isNotEmpty) d.className,
      ];
      return parts.join('/');
    case DocxListColumnKind.gender:
      return d.gender;
    case DocxListColumnKind.political:
      return d.politicalStatus;
    case DocxListColumnKind.duty:
      return ffDutySummary(d) ?? '';
    case DocxListColumnKind.weighted:
      return ffNum(d.weighted) ?? '';
    case DocxListColumnKind.weightedMin:
      final w = ffNum(d.weighted);
      final m = ffNum(d.minScore);
      if (w == null && m == null) return '';
      return '${w ?? '—'}/${m ?? '—'}';
    case DocxListColumnKind.englishLevel:
      return proseEnglish(d) ?? '';
    case DocxListColumnKind.dutyText:
      return proseDuty(d) ?? '';
    case DocxListColumnKind.honorsText:
      return proseHonors(d) ?? '';
    case DocxListColumnKind.deedsText:
      return proseDeeds(d) ?? '';
    case DocxListColumnKind.researchText:
      return proseResearch(d) ?? '';
    case DocxListColumnKind.serviceText:
      return proseService(d) ?? '';
    case DocxListColumnKind.gradeD:
      return ffNum(zc?.deyu) ?? '';
    case DocxListColumnKind.gradeZ:
      return ffNum(zc?.zhiyu) ?? '';
    case DocxListColumnKind.gradeT:
      return ffNum(zc?.tiyu) ?? '';
    case DocxListColumnKind.gradeM:
      return ffNum(zc?.meiyu) ?? '';
    case DocxListColumnKind.gradeL:
      return ffNum(zc?.laoyu) ?? '';
    case DocxListColumnKind.rankD:
      return zc?.gD.label ?? '';
    case DocxListColumnKind.rankZ:
      return zc?.gZ.label ?? '';
    case DocxListColumnKind.rankT:
      return zc?.gT.label ?? '';
    case DocxListColumnKind.rankM:
      return zc?.gM.label ?? '';
    case DocxListColumnKind.rankL:
      return zc?.gL.label ?? '';
    case DocxListColumnKind.overallGrade:
      return zc?.overall.label ?? '';
    case DocxListColumnKind.total:
      return ffNum(ffMaterialTotal(d.materials)) ?? '';
    default:
      // 授予称号 / 奖学金 / 金额 / 学院审核分值 / 备注 … 用户自己定。
      return '';
  }
}
