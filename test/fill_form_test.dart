/// 「填表助手」守卫：**上传 docx → 识别待填项 → 自动填 → 手动改 → 导出**。
///
/// 用户 2026-10-07 原话：「允许用户上传一个 docx 文档，然后你自动识别有哪些项需要填，
/// 然后把能填的都填了。填不了/不确定的，空着。然后用户可以在你自动填完后，
/// 再手动调整各部分文本」。
///
/// 本文件用**合成 docx**（内存里现场造的 zip）钉住整条链路，不依赖任何外部文件：
/// 1. `DocxPackage` 解包 / 重打包（其余部件逐字节原样回写）；
/// 2. `docxScan` 的五种待填项 + 清单表识别 + **表单被误判成清单表**的闸门；
/// 3. `docxApplyValues` 的四种写法 + 清单表行不够时**复制表格行**；
/// 4. 导出幂等（同一份值导两次，不会在已填内容后面再贴一遍）；
/// 5. `fillValueFor` 的标签映射与成段文字（只用真实数据、取不到就留空）；
/// 6. `zcYearGradeStats` 的学年成绩统计（`score <= 0` 的非数字成绩不算挂科）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/fill_form/data/fill_form_providers.dart';
import 'package:smarter_jxufe/features/fill_form/domain/docx_fields.dart';
import 'package:smarter_jxufe/features/fill_form/domain/docx_form.dart';
import 'package:smarter_jxufe/features/fill_form/domain/docx_package.dart';
import 'package:smarter_jxufe/features/fill_form/domain/fill_form_data.dart';
import 'package:smarter_jxufe/features/fill_form/presentation/fill_form_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_prior_grades.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_year_sources.dart';

// ---------------------------------------------------------------------------
// 合成 docx
// ---------------------------------------------------------------------------

const String _wNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// 一段正文（有文字）。
String _p(String text) =>
    '<w:p><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>';

/// 一段正文（空段，但带着段落字符格式 —— 与学校表格里的空格一致）。
String _emptyP() =>
    '<w:p><w:pPr><w:rPr><w:rFonts w:ascii="仿宋_GB2312" w:eastAsia="仿宋_GB2312"/>'
    '<w:sz w:val="24"/></w:rPr></w:pPr></w:p>';

/// 段落里带多个 run（Word 会把一句话按格式切开）—— 用来验「塌成一个 run」的写法。
String _pRuns(List<String> runs) =>
    '<w:p>${runs.map((r) => '<w:r><w:t xml:space="preserve">$r</w:t></w:r>').join()}</w:p>';

String _tc(String inner, {int span = 1, String? vMerge}) {
  final vm = switch (vMerge) {
    null => '',
    'restart' => '<w:vMerge w:val="restart"/>',
    _ => '<w:vMerge/>',
  };
  return '<w:tc><w:tcPr><w:tcW w:w="1200" w:type="dxa"/>'
      '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}$vm</w:tcPr>$inner</w:tc>';
}

String _tr(List<String> cells) => '<w:tr>${cells.join()}</w:tr>';

String _tbl(List<String> rows) =>
    '<w:tbl><w:tblPr/><w:tblGrid/>${rows.join()}</w:tbl>';

String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="$_wNs"><w:body>$body'
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:body></w:document>';

/// 造一个能打开的 .docx（含 OPC 必备件）。
Uint8List _buildDocx(String documentXml) {
  final archive = Archive();
  archive.add(
    ArchiveFile.string(
      kDocxContentTypesPart,
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>',
    ),
  );
  archive.add(
    ArchiveFile.string(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    ),
  );
  archive.add(
    ArchiveFile.string('word/styles.xml', '<w:styles xmlns:w="$_wNs"/>'),
  );
  archive.add(ArchiveFile.string(kDocxDocumentPart, documentXml));
  return ZipEncoder().encodeBytes(archive);
}

/// 导出后的 document.xml 文本。
String _exportedXml(Uint8List bytes) =>
    DocxPackage.fromBytes(bytes)!.readUtf8(kDocxDocumentPart)!;

/// 一份「表单」docx：姓名/班级/出生年月/性别 + 学号/职务/政治面貌 + 主要表现。
///
/// 结构与《先进个人登记表》同形：空格靠左邻标签认；「主要表现」格是
/// 提示 + 空白书写区 + 签名行。
Uint8List _formDocx() => _buildDocx(
  _doc(
    _p('2025-2026学年江西财经大学学生先进个人登记表') +
        _tbl([
          _tr([
            _tc(_p('姓名')),
            _tc(_emptyP(), span: 2),
            _tc(_p('班级')),
            _tc(_emptyP(), span: 2),
            _tc(_p('出生年月')),
            _tc(_emptyP(), span: 2),
            _tc(_p('性别')),
            _tc(_emptyP(), span: 2),
            _tc(_p('照片'), vMerge: 'restart'),
          ]),
          _tr([
            _tc(_p('学号')),
            _tc(_emptyP(), span: 2),
            _tc(_p('职务')),
            _tc(_emptyP(), span: 2),
            _tc(_p('政治面貌')),
            _tc(_emptyP(), span: 5),
            _tc(_emptyP(), vMerge: 'cont'),
          ]),
          _tr([
            _tc(_p('主要表现')),
            _tc(
              _pRuns(['(德、智、体等方面)']) +
                  _emptyP() +
                  _emptyP() +
                  _p('班长（团支部书记） 签名') +
                  _p('年   月    日'),
              span: 13,
            ),
          ]),
          _tr([
            _tc(_p('学院意见')),
            _tc(_p('（学院公章）  年  月  日'), span: 13),
          ]),
        ]),
  ),
);

/// 一份带清单表的 docx（表头 + 3 个数据行 + 合计行）。
Uint8List _listDocx({int rows = 3}) => _buildDocx(
  _doc(
    _p('附加分审核表') +
        _p('学院：  计算机与人工智能学院      学生姓名：      　      学号：                班级：     　    ') +
        _tbl([
          _tr([
            _tc(_p('序号')),
            _tc(_p('项目')),
            _tc(_p('类别')),
            _tc(_p('级别')),
            _tc(_p('获得时间')),
            _tc(_p('附件数')),
            _tc(_p('分值')),
            _tc(_p('学院审核分值')),
          ]),
          for (var i = 0; i < rows; i++) _tr([for (var c = 0; c < 8; c++) _tc(_emptyP())]),
          _tr([
            _tc(_p('总分'), span: 6),
            _tc(_emptyP(), span: 2),
          ]),
        ]),
  ),
);

/// 一份「表单被误判成清单表」的陷阱 docx：第一行 姓名|空|班级|空|性别|空。
Uint8List _rosterTrapDocx() => _buildDocx(
  _doc(
    _tbl([
      _tr([
        _tc(_p('姓名')),
        _tc(_emptyP()),
        _tc(_p('班级')),
        _tc(_emptyP()),
        _tc(_p('性别')),
        _tc(_emptyP()),
        _tc(_p('照片')),
      ]),
      _tr([
        _tc(_p('学号')),
        _tc(_emptyP()),
        _tc(_p('职务')),
        _tc(_emptyP()),
        _tc(_p('政治面貌')),
        _tc(_emptyP(), span: 3),
      ]),
    ]),
  ),
);

/// 一份「人员清单表」docx（45 行空表那种）。
Uint8List _rosterDocx() => _buildDocx(
  _doc(
    _p('江西财经大学学生先进个人汇总表') +
        _p('学院名称：           （盖章）填表人：               填表时间：           ') +
        _tbl([
          _tr([
            _tc(_p('序号')),
            _tc(_p('班级')),
            _tc(_p('学号')),
            _tc(_p('姓 名')),
            _tc(_p('性别')),
            _tc(_p('政治面貌')),
            _tc(_p('职务')),
            _tc(_p('授予称号')),
            _tc(_p('奖学金等级')),
          ]),
          for (var i = 0; i < 4; i++) _tr([for (var c = 0; c < 9; c++) _tc(_emptyP())]),
        ]),
  ),
);

/// 一份「两行表头 + 纵向合并」的汇总表（《综测班级汇总表》那种）。
Uint8List _mergedHeaderDocx() => _buildDocx(
  _doc(
    _tbl([
      _tr([
        _tc(_p('姓名'), vMerge: 'restart'),
        _tc(_p('学号'), vMerge: 'restart'),
        _tc(_p('德育'), span: 2),
        _tc(_p('智育'), span: 2),
        _tc(_p('综合测评等次'), vMerge: 'restart'),
      ]),
      _tr([
        _tc(_emptyP(), vMerge: 'cont'),
        _tc(_emptyP(), vMerge: 'cont'),
        _tc(_p('德育')),
        _tc(_p('德育评定等次')),
        _tc(_p('智育')),
        _tc(_p('智育评定等次')),
        _tc(_emptyP(), vMerge: 'cont'),
      ]),
      _tr([for (var c = 0; c < 7; c++) _tc(_emptyP())]),
      _tr([for (var c = 0; c < 7; c++) _tc(_emptyP())]),
    ]),
  ),
);

// ---------------------------------------------------------------------------
// 测试数据
// ---------------------------------------------------------------------------

ZcMaterial _mat({
  required ZcTypeId type,
  String name = '',
  String dateIso = '',
  String cat = '',
  int level = 0,
  int opt = 0,
  double? manualScore,
  List<String> files = const [],
}) => ZcMaterial(
  id: 'm-${name.hashCode}-${type.name}',
  typeId: type,
  name: name,
  dateIso: dateIso,
  cat: cat,
  level: level,
  opt: opt,
  manualScore: manualScore,
  files: files,
);

GePriorGrade _g(String name, double score, double credits, String semester) =>
    GePriorGrade(
      courseCode: name,
      courseName: name,
      score: score,
      credits: credits,
      semester: semester,
    );

/// 一份「什么都有」的填表数据。
FillFormData _data({
  List<ZcMaterial>? materials,
  int yearEnd = 2026,
  bool withStudent = true,
}) {
  final mats = materials ?? _defaultMaterials();
  final manual = const ZcManual(
    deyuPingyi: 18,
    meiyuPingyi: 17,
    laoyuPingyi: 16,
    tScore: 82,
    volunteerHours: 36,
  );
  final zc = zcCalculate(
    mats,
    manual: manual,
    autoWeight: 89.21,
    autoVolunteer: 36,
  );
  final base = withStudent
      ? FillFormData.ofStudent(null, yearEnd: yearEnd)
      : FillFormData(yearEnd: yearEnd);
  return base.copyWith(
    weighted: 89.21,
    minScore: 76,
    credits: 42,
    hasFail: false,
    manual: manual,
    volunteerHours: 36,
    zc: zc,
    allMaterials: mats,
    materials: zcFilterByYear(mats, yearEnd),
    now: DateTime(2026, 10, 7),
  );
}

List<ZcMaterial> _defaultMaterials() => [
  _mat(
    type: ZcTypeId.contest,
    name: '中国国际大学生创新大赛',
    dateIso: '2025-10-11',
    cat: 'c1',
    level: 0,
    opt: 1,
    files: const ['a.jpg', 'b.jpg'],
  ),
  _mat(
    type: ZcTypeId.contest,
    name: '全国大学生数学建模竞赛',
    dateIso: '2025-06-01',
    cat: 'c2',
    level: 1,
    opt: 2,
  ),
  _mat(
    type: ZcTypeId.honorP,
    name: '优秀学生干部',
    dateIso: '2025-09-10',
    level: 3,
  ),
  _mat(
    type: ZcTypeId.servicePost,
    name: '',
    dateIso: '2025-09-01',
    level: 6,
    opt: 0,
  ),
  _mat(type: ZcTypeId.foreign, name: '大学英语六级', manualScore: 512),
];

/// 一份带真实姓名/学号的数据（给学生信息那几个标签用）。
FillFormData _dataWithStudentInfo() {
  final d = _data();
  return FillFormData(
    name: '同学甲',
    studentId: '2202500001',
    gender: '男',
    birthDate: '2004-03-15',
    politicalStatus: '中共预备党员',
    college: '计算机与人工智能学院',
    major: '计算机科学与技术',
    className: '计算机科学与技术252',
    enrollYear: '2025',
    studyYears: '4',
    trainLevel: '本科',
    address: '江西省南昌市示例区示例路1号示例小区1栋101室',
    phone: '13800000001',
    yearEnd: d.yearEnd,
    weighted: d.weighted,
    minScore: d.minScore,
    credits: d.credits,
    hasFail: d.hasFail,
    manual: d.manual,
    volunteerHours: d.volunteerHours,
    zc: d.zc,
    allMaterials: d.allMaterials,
    materials: d.materials,
    now: d.now,
  );
}

void main() {
  // =========================================================================
  group('docx 包：解包 / 重打包', () {
    test('解包后其余部件逐字节原样、重打包还能再解', () {
      final bytes = _formDocx();
      final pkg = DocxPackage.fromBytes(bytes)!;
      expect(pkg.contains(kDocxDocumentPart), isTrue);
      expect(pkg.contains(kDocxContentTypesPart), isTrue);
      expect(pkg.readUtf8('word/styles.xml'), contains('<w:styles'));

      final again = DocxPackage.fromBytes(pkg.toBytes());
      expect(again, isNotNull);
      expect(again!.readUtf8('word/styles.xml'), contains('<w:styles'));
      expect(again.readUtf8(kDocxDocumentPart), pkg.readUtf8(kDocxDocumentPart));
    });

    test('不是 zip / 不是 OPC 包 → null', () {
      expect(DocxPackage.fromBytes(utf8.encode('这不是一个 zip')), isNull);
      final plainZip = Archive()
        ..add(ArchiveFile.string('hello.txt', 'hi'));
      expect(
        DocxPackage.fromBytes(ZipEncoder().encodeBytes(plainZip)),
        isNull,
        reason: '缺 [Content_Types].xml 与 word/document.xml → 不是 docx',
      );
    });

    test('DocxForm.fromBytes 认不出 → null（旧版 .doc 走这条路）', () {
      expect(DocxForm.fromBytes(utf8.encode('D0CF11E0A1B11AE1')), isNull);
    });

    test('导出名字：原名 + _已填写.docx', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      expect(form.suggestedFileName('先进个人登记表.docx'), '先进个人登记表_已填写.docx');
      expect(form.suggestedFileName('登记表.DOCX'), '登记表_已填写.docx');
      expect(form.suggestedFileName(''), '表单_已填写.docx');
    });
  });

  // =========================================================================
  group('扫描：空格靠左邻标签', () {
    test('表单四项都认出来，标签正确', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      final byId = {for (final f in form.scan.fields) f.id: f};
      expect(byId['t0.r0.c1']?.label, '姓名');
      expect(byId['t0.r0.c3']?.label, '班级');
      expect(byId['t0.r0.c5']?.label, '出生年月');
      expect(byId['t0.r0.c7']?.label, '性别');
      expect(byId['t0.r1.c1']?.label, '学号');
      expect(byId['t0.r1.c3']?.label, '职务');
      expect(byId['t0.r1.c5']?.label, '政治面貌');
      expect(byId['t0.r0.c1']?.kind, DocxFieldKind.cell);
    });

    test('「主要表现」是提示格（成段文字），提示与签名行都留着', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      final prose = form.scan.fields.firstWhere(
        (f) => f.label == '主要表现',
      );
      expect(prose.kind, DocxFieldKind.cellProse);
      expect(prose.hint, contains('德、智、体'));
      expect(prose.group, '主要表现');
    });

    test('「学院意见」不认（那是给别人写的）', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      expect(form.scan.fields.any((f) => f.label.contains('意见')), isFalse);
    });
  });

  // =========================================================================
  group('扫描：表单不被误判成清单表', () {
    test('姓名|空|班级|空|性别|空 的表头行不算人员清单表', () {
      final form = DocxForm.fromBytes(_rosterTrapDocx())!;
      expect(form.scan.listTables, isEmpty, reason: '表头行夹着待填空格 → 是表单');
      expect(
        form.scan.fields.where((f) => f.kind == DocxFieldKind.cell).length,
        6,
        reason: '六个空格该逐格列出来，而不是被吞成一行 TSV',
      );
      expect(
        form.scan.fields.map((f) => f.label),
        containsAll(<String>['姓名', '班级', '性别', '学号', '职务', '政治面貌']),
      );
    });

    test('真清单表（表头行没有空格）→ 整表一个 TSV 字段', () {
      final form = DocxForm.fromBytes(_rosterDocx())!;
      expect(form.scan.listTables.length, 1);
      final table = form.scan.listTables.single;
      expect(table.materialRows, isFalse);
      expect(table.dataRows.length, 4);
      expect(
        table.columns.map((c) => c.kind),
        containsAllInOrder([
          DocxListColumnKind.seq,
          DocxListColumnKind.className,
          DocxListColumnKind.studentId,
          DocxListColumnKind.name,
        ]),
      );
      final field = form.scan.fields.firstWhere((f) => f.isListTable);
      expect(field.kind, DocxFieldKind.listTable);
      expect(field.hint, contains('序号'));
      // 正文那句「学院名称：…填表人：…填表时间：」照旧逐项识别（清单表只管表里）。
      expect(
        form.scan.fields.where((f) => f.kind == DocxFieldKind.paragraph).length,
        2,
      );
    });

    test('两行表头 + 纵向合并 → 续格往上取锚格（姓名/学号不会丢）', () {
      final form = DocxForm.fromBytes(_mergedHeaderDocx())!;
      final table = form.scan.listTables.single;
      final kinds = table.columns.map((c) => c.kind).toList();
      expect(kinds.first, DocxListColumnKind.name, reason: 'R00 的「姓名」是 vMerge 锚格');
      expect(kinds[1], DocxListColumnKind.studentId);
      expect(kinds.last, DocxListColumnKind.overallGrade);
      expect(table.headerRow, 1);
    });

    test('材料清单表：表头 序号/项目/类别/级别/获得时间/附件数/分值', () {
      final form = DocxForm.fromBytes(_listDocx())!;
      final table = form.scan.listTables.single;
      expect(table.materialRows, isTrue);
      expect(table.dataRows.length, 3);
      expect(table.totalRow, 4, reason: '「总分」行不算数据行');
      expect(
        table.columns.map((c) => c.kind),
        containsAllInOrder([
          DocxListColumnKind.seq,
          DocxListColumnKind.project,
          DocxListColumnKind.category,
          DocxListColumnKind.level,
          DocxListColumnKind.date,
          DocxListColumnKind.attachCount,
          DocxListColumnKind.score,
          DocxListColumnKind.collegeScore,
        ]),
      );
      expect(
        form.scan.fields.any((f) => f.label == '总分'),
        isTrue,
        reason: '合计行照旧逐格识别（清单表只管数据行）',
      );
    });
  });

  // =========================================================================
  group('扫描：正文段落与格内标签', () {
    test('正文「标签：<空白>」认出来、空白后面已有值的不认', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _p('学院：                        填表日期：  年    月     日') +
                _p('学院：  计算机与人工智能学院      学生姓名：      　      学号：                班级：     　    ') +
                _p('注：本表一式两份'),
          ),
        ),
      )!;
      final labels = form.scan.fields.map((f) => f.label).toList();
      expect(labels, contains('学院'));
      expect(labels, isNot(contains('填表日期')), reason: '空白后紧跟「年」→ 日期模板，不填');
      expect(labels, isNot(contains('注')), reason: '没有空格位');
      expect(labels.where((l) => l == '学院').length, 1, reason: '已填的「学院：」不算空位');
      expect(labels, contains('学生姓名'));
      expect(labels, contains('学号'));
      expect(labels, contains('班级'));

      // 段落里同一行的多个空位要各自落位（从后往前替换，前面的偏移才不会漂）。
      final xml = _exportedXml(
        form.export({
          for (final f in form.scan.fields)
            if (f.kind == DocxFieldKind.paragraph)
              f.id: switch (f.label) {
                '学院' => '计算机与人工智能学院',
                '学生姓名' => '同学甲',
                '学号' => '2202500001',
                _ => '计算机科学与技术252',
              },
        })!,
      );
      expect(xml, contains('学生姓名：同学甲'));
      expect(xml, contains('学号：2202500001'));
      expect(xml, contains('班级：计算机科学与技术252'));
      expect(
        xml,
        contains('学院：  计算机与人工智能学院'),
        reason: '已经填好的那一处不动',
      );
    });

    test('格内「加、减分项目：」「XX附加分数合计：」就地追加，标签保留', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _tbl([
              _tr([
                _tc(_p('德育'), vMerge: 'restart'),
                _tc(
                  _emptyP() +
                      _p('加、减分项目：') +
                      _emptyP() +
                      _p('德育附加分数合计：'),
                  span: 9,
                ),
              ]),
            ]),
          ),
        ),
      )!;
      final labels = form.scan.fields.map((f) => f.label).toList();
      expect(labels, contains('加、减分项目'));
      expect(labels, contains('德育附加分数合计'));
      expect(
        form.scan.fields.every((f) => f.kind == DocxFieldKind.cellInline),
        isTrue,
      );
      final out = form.export({
        form.scan.fields.first.id: '优秀事迹 +5',
      })!;
      final xml = _exportedXml(out);
      // 值是**追加在新 run 里**（标签那一 run 原样保留），所以断言分两段。
      expect(xml, contains('加、减分项目：'));
      expect(xml, contains('优秀事迹 +5'));
      expect(xml, contains('德育附加分数合计：'), reason: '另一个标签原样留着');
      expect(
        xml.indexOf('加、减分项目：'),
        lessThan(xml.indexOf('优秀事迹 +5')),
        reason: '值要接在标签后面，不能跑到别处',
      );
    });

    test('「签    名：」这种被空格拆开的标签会被并回来并跳过', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _tbl([
              _tr([
                _tc(_p('辅导员（班主任）意见')),
                _tc(_p('签    名：') + _emptyP() + _emptyP(), span: 3),
              ]),
            ]),
          ),
        ),
      )!;
      expect(form.scan.fields, isEmpty, reason: '签名 / 意见 都不该出现在待填项里');
    });

    test('整格只有一段「本人申请理由（…）：」→ 成段文字题头', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _tbl([
              _tr([
                _tc(_p('本人申请理由（本人德智体等情况、家庭经济情况等方面）：'), span: 4),
              ]),
              _tr([_tc(_emptyP(), span: 4)]),
            ]),
          ),
        ),
      )!;
      final f = form.scan.fields.single;
      expect(f.kind, DocxFieldKind.cellProse);
      expect(f.label, '本人申请理由');
    });

    test('「培养单位（公章）：」要填（括号只是提醒盖章），「（学院公章）」不填', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _p('培养单位（公章）：            参评人：              学号：            专业：') +
                _p('（学院公章）  年  月  日'),
          ),
        ),
      )!;
      final labels = form.scan.fields.map((f) => f.label).toList();
      expect(labels, contains('培养单位（公章）'));
      expect(labels, contains('参评人'));
      expect(labels, contains('学号'));
      expect(
        labels,
        contains('专业'),
        reason: '以标签收尾的行，只要本段已有别的空位，就该补出来',
      );
      expect(
        labelValueFor('培养单位（公章）', d: _dataWithStudentInfo()),
        '计算机与人工智能学院',
        reason: '「括号说明」要在取值时摘掉',
      );
    });

    test('以标签收尾的**标题段**不算空位（「表1：」不该变成待填项）', () {
      final form = DocxForm.fromBytes(
        _buildDocx(_doc(_p('表1：') + _p('2025-2026学年江西财经大学学生先进个人登记表'))),
      )!;
      expect(form.scan.fields, isEmpty);
    });
  });

  // =========================================================================
  group('写回', () {
    test('整格写值 + 段落空位替换（不在段尾要留一个空格）', () {
      final form = DocxForm.fromBytes(
        _buildDocx(
          _doc(
            _p('学院：                        填表日期：  年    月     日') +
                _tbl([
                  _tr([_tc(_p('姓名')), _tc(_emptyP())]),
                ]),
          ),
        ),
      )!;
      final values = {
        for (final f in form.scan.fields)
          f.id: f.label == '姓名' ? '同学甲' : '计算机与人工智能学院',
      };
      final xml = _exportedXml(form.export(values)!);
      expect(xml, contains('同学甲'));
      expect(xml, contains('学院：计算机与人工智能学院 '), reason: '段中空位补一个空格');
      expect(xml, contains('填表日期：'), reason: '日期模板原样不动');
    });

    test('提示格：值插在提示段之后，签名行仍在', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      final prose = form.scan.fields.firstWhere((f) => f.label == '主要表现');
      final xml = _exportedXml(
        form.export({prose.id: '第一行表现\n第二行表现'})!,
      );
      final hintAt = xml.indexOf('(德、智、体等方面)');
      final bodyAt = xml.indexOf('第一行表现');
      final signAt = xml.indexOf('班长（团支部书记） 签名');
      expect(hintAt, greaterThanOrEqualTo(0));
      expect(bodyAt, greaterThan(hintAt));
      expect(signAt, greaterThan(bodyAt));
      expect(xml, contains('<w:br/>'), reason: '换行要写成 w:br，不能塞 \\n');
    });

    test('清单表：逐行逐列写入 + 行不够时复制表格行', () {
      final form = DocxForm.fromBytes(_listDocx(rows: 3))!;
      final field = form.scan.fields.firstWhere((f) => f.isListTable);
      expect(field.listTable!.dataRows.length, 3);
      final tsv = [
        '1\t中国国际大学生创新大赛\tⅠ类\t国一\t2025/10/11\t2\t18',
        '2\t全国大学生数学建模竞赛\tⅡ类\t省二\t2025/06/01\t1\t4',
        '3\t蓝桥杯大赛\tⅡ类\t省一\t2025/04/12\t1\t5',
        '4\t第 4 条（需要复制表格行）\tⅢ类\t校一\t2025/03/01\t1\t2',
      ].join('\n');
      final xml = _exportedXml(form.export({field.id: tsv})!);
      for (final kw in [
        '中国国际大学生创新大赛',
        'Ⅰ类',
        '国一',
        '2025/10/11',
        '第 4 条（需要复制表格行）',
      ]) {
        expect(xml, contains(kw));
      }
      // 复制出来的第 4 行仍要在「总分」行之前。
      expect(xml.indexOf('第 4 条'), lessThan(xml.indexOf('总分')));
      // 合计行的值格照旧能填。
      final total = form.scan.fields.firstWhere((f) => f.label == '总分');
      final xml2 = _exportedXml(form.export({total.id: '29'})!);
      expect(xml2, contains('总分'));
    });

    test('导出幂等：同一份值导两次结果一致（不会贴两遍）', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      final values = {
        for (final f in form.scan.fields)
          if (f.label == '姓名') f.id: '同学甲',
      };
      final a = form.export(values)!;
      final b = form.export(values)!;
      expect(_exportedXml(a), _exportedXml(b));
      expect('同学甲'.allMatches(_exportedXml(b)).length, 1);
    });

    test('空值 = 不写（原本空的还是空的）', () {
      final form = DocxForm.fromBytes(_formDocx())!;
      final xml = _exportedXml(form.export(const {})!);
      expect(xml, isNot(contains('同学甲')));
      expect(xml, contains('姓名'));
    });
  });

  // =========================================================================
  group('自动值：标签映射', () {
    final d = _dataWithStudentInfo();

    String? v(String label, {String group = ''}) =>
        labelValueFor(label, group: group, d: d);

    test('身份 / 学籍 / 成绩', () {
      expect(v('姓名'), '同学甲');
      expect(v('学生姓名'), '同学甲');
      expect(v('学号'), '2202500001');
      expect(v('班级'), '计算机科学与技术252');
      expect(v('行政班级'), '计算机科学与技术252');
      expect(v('学院'), '计算机与人工智能学院');
      expect(v('出生年月'), '2004年3月');
      expect(v('政治面貌'), '中共预备党员');
      expect(v('学年加权平均成绩'), '89.21');
      expect(v('最低单科成绩'), '76');
      expect(v('学年所修学分总数'), '42');
      expect(v('是否有挂科'), '无');
      expect(v('加权成绩/单科最低分'), '89.21/76');
      expect(v('填表时间'), '2026年10月7日');
    });

    test('综测分项全部走引擎（合计/等次靠「所属育」消歧）', () {
      final zc = d.zc!;
      expect(v('综合素质测评等次'), zc.overall.label);
      expect(v('德育基础分'), '60');
      expect(v('德育民主评议分'), '18');
      expect(v('合计', group: '德育'), _numOf(zc.deyu));
      expect(v('合计', group: '智育'), _numOf(zc.zhiyu));
      expect(v('班级评议德育等次', group: '德育'), zc.gD.label);
      expect(v('体测成绩'), '82');
      expect(v('是否有挂科'), '无');
      // 「合计」不给所属育 → 分不清，宁可留空
      expect(v('合计'), isNull);
    });

    test('加、减分项目逐条列出来，附加合计 = 总分−基础分−评议+扣分', () {
      final text = v('加、减分项目', group: '德育')!;
      expect(text, contains('公共服务'));
      expect(text, contains('荣誉称号'));
      final added = double.parse(v('德育附加分数合计', group: '德育')!);
      final zc = d.zc!;
      final expectAdded = zc.deyu - 60 - 18; // 本用例没有扣分
      expect(added, closeTo(expectAdded, 0.01));
    });

    test('清单表：材料逐条 TSV + 人员一行 TSV', () {
      final material = DocxForm.fromBytes(_listDocx())!;
      final f = material.scan.fields.firstWhere((x) => x.isListTable);
      final tsv = fillValueFor(f, d)!;
      final lines = tsv.split('\n');
      expect(lines.length, d.materials.length);
      final first = lines.first.split('\t');
      expect(first[0], '1', reason: '序号列');
      expect(first[1], '中国国际大学生创新大赛');
      expect(first[2], 'Ⅰ类');
      expect(first[3], '国一', reason: '级别简称：国家 + 一等奖');
      expect(first[4], '2025/10/11', reason: '时间统一成斜杠');
      expect(first[5], '2', reason: '附件数');
      expect(double.parse(first[6]), greaterThan(0), reason: '分值');
      expect(first[7], '', reason: '「学院审核分值」不该自动填');
    });

    test('清单表：人员一行 TSV（含五育分数与等次）', () {
      final roster = DocxForm.fromBytes(_rosterDocx())!;
      final f = roster.scan.fields.firstWhere((x) => x.isListTable);
      final cells = fillValueFor(f, d)!.split('\t');
      expect(cells.length, f.listTable!.columns.length);
      expect(cells[0], '1');
      expect(cells[2], '2202500001');
      expect(cells[3], '同学甲');
      expect(cells[6], contains('班长'), reason: '职务取自「公共服务职务」材料');
      expect(cells[7], '', reason: '授予称号取决于报哪个称号 → 留空');
      expect(cells[8], '', reason: '奖学金等级 → 留空');
    });

    test('用户自己定的项一律留空（不猜）', () {
      for (final label in ['授予称号', '奖学金等级', '参评项目', '备注', '金额']) {
        expect(v(label), isNull, reason: '$label 应由用户填');
      }
    });
  });

  // =========================================================================
  group('成段文字：只用真实数据', () {
    test('主要表现含真实分数，且带一句克制的评价', () {
      final text = proseMainPerformance(_dataWithStudentInfo());
      expect(text, contains('89.21'));
      expect(text, contains('76'));
      expect(text, contains('优秀学生干部'));
      expect(text, contains('志愿服务时长'));
      expect(text, contains('示范带头作用'), reason: '有荣誉 + 等次优秀 → 允许的那句评价');
    });

    test('没有数据的项 → null（绝不编造）', () {
      final empty = FillFormData(yearEnd: 2026, now: DateTime(2026, 10, 7));
      expect(proseDuty(empty), isNull);
      expect(proseHonors(empty), isNull);
      expect(proseResearch(empty), isNull);
      expect(proseService(empty), isNull);
      expect(proseEnglish(empty), isNull);
      expect(fillValueFor(_fakeField('姓名'), empty), isNull);
    });

    test('受表彰情况按级别分行（表 7 模板格式）', () {
      final text = proseHonors(_dataWithStudentInfo())!;
      expect(text, contains('1.国家级奖项/荣誉：中国国际大学生创新大赛（2025年）'));
      expect(text, contains('省部级奖项/荣誉：'));
      expect(text, contains('市（校）级奖项/荣誉：优秀学生干部（2025年）'));
    });

    test('突出事迹按表 7 的四段式顺延编号', () {
      final text = proseDeeds(_dataWithStudentInfo())!;
      expect(text.startsWith('1.学业表现：'), isTrue);
      expect(text, contains('2.学科竞赛：'));
      expect(text, contains('学生工作与社会实践：'));
    });

    test('限 N 字截断：先丢整行、再逐字截', () {
      expect(clipToLimit('短', 10), '短');
      const long = '第一行内容\n第二行内容\n第三行内容';
      final clipped = clipToLimit(long, 12);
      expect(clipped.runes.length, lessThanOrEqualTo(12));
      expect(clipped, startsWith('第一行内容'));
      expect(clipToLimit('一二三四五', 3), '一二三');
    });

    test('标记了「限 N 字」的清单列会被截断', () {
      final doc = _buildDocx(
        _doc(
          _tbl([
            _tr([
              _tc(_p('姓名')),
              _tc(_p('学号')),
              _tc(_p('突出事迹（限10字以内，多出字数按前后顺序直接删除）')),
            ]),
            _tr([_tc(_emptyP()), _tc(_emptyP()), _tc(_emptyP())]),
            _tr([_tc(_emptyP()), _tc(_emptyP()), _tc(_emptyP())]),
          ]),
        ),
      );
      final form = DocxForm.fromBytes(doc)!;
      final f = form.scan.fields.firstWhere((x) => x.isListTable);
      final tsv = fillValueFor(f, _dataWithStudentInfo())!;
      final cells = tsv.split('\t');
      expect(cells[2].runes.length, lessThanOrEqualTo(10));
      expect(cells[2], isNotEmpty);
    });
  });

  // =========================================================================
  group('学年成绩统计（填登记表那一行）', () {
    test('最低单科 / 学分合计 / 有没有挂科', () {
      final grades = [
        _g('A', 90, 2, '251'),
        _g('B', 55, 3, '252'),
        _g('C', 78, 1.5, '253'),
        _g('D', 100, 2, '261'), // 别的学年
      ];
      final s = zcYearGradeStats(grades, yearEnd: 2026);
      expect(s.minScore, 55);
      expect(s.credits, 6.5);
      expect(s.hasFail, isTrue);
    });

    test('非数字成绩（优秀/缓考）按 0 存 → 不算最低分也不算挂科', () {
      final grades = [
        _g('A', 90, 2, '251'),
        _g('考查课', 0, 1, '251'), // 「优秀」被解析成 0
      ];
      final s = zcYearGradeStats(grades, yearEnd: 2026);
      expect(s.minScore, 90, reason: '0 分不能当最低单科成绩');
      expect(s.hasFail, isFalse, reason: '0 分不能谎报挂科');
      expect(s.credits, 3);
    });

    test('该学年一门学期码明确的课都没有 → 全 null（别拿认不出学期的课凑数）', () {
      final grades = [_g('X', 90, 2, '')];
      final s = zcYearGradeStats(grades, yearEnd: 2026);
      expect(s.minScore, isNull);
      expect(s.credits, isNull);
      expect(zcWeightedForYear(grades, yearEnd: 2026), isNull);
    });

    test('加权口径没变：学期码认不出的课并入该学年', () {
      final grades = [
        _g('A', 90, 2, '251'),
        _g('实训', 80, 2, ''), // 认不出学期
      ];
      expect(zcWeightedForYear(grades, yearEnd: 2026), 85);
    });
  });

  // =========================================================================
  group('页面 · 独立入口（用户 2026-10-07：「这个填材料的功能应该独立出来」）', () {
    test('首页目录里有「填表助手」，自成一组 fillForm，且材料库里不再有它', () {
      // ① 首页目录：条目在、分组是 fillForm（独立一节）、打开的是 FillFormScreen。
      final pushed = <Widget>[];
      final entries = homeServiceEntries(push: pushed.add);
      final tile = entries.where((e) => e.title == '填表助手').toList();
      expect(tile.length, 1, reason: '首页目录里应当**恰好一条**「填表助手」');
      expect(tile.single.group, HomeServiceGroup.fillForm);
      expect(
        tile.single.builder(),
        isA<FillFormScreen>(),
        reason: '磁贴要打开填表助手页',
      );
      expect(
        HomeServiceGroup.fillForm.title,
        '评优评先',
        reason: '侧栏里它是独立的一节（不是塞进现有四组）',
      );

      // ② 材料库**移除**了这个入口（用户拍板「移除材料库入口」）——
      //    用源码守卫钉住，防止以后又被加回去变回「寄生」形态。
      final materialsSrc = File(
        'lib/features/materials/presentation/materials_screen.dart',
      ).readAsStringSync();
      expect(materialsSrc.contains('FillForm'), isFalse);
      expect(materialsSrc.contains('fill_form'), isFalse);
    });

    testWidgets('填表助手页本身能起来（未选文件时是说明 + 选文件）', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            zcMaterialsProvider.overrideWith((ref) async => const <ZcMaterial>[]),
          ],
          child: const MaterialApp(home: FillFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('填表助手'), findsOneWidget);
      expect(find.text('上传要填的表格'), findsOneWidget);
      expect(find.text('选择 .docx 文件'), findsOneWidget);
    });

    testWidgets('整份文档没有待填项时给出原因，而不是一片空白', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 一份「评选说明」：全是正文，没有表格也没有空位。
      final form = DocxForm.fromBytes(
        _buildDocx(_doc(_p('1.参评“优秀学生”的人选本学年所有课程单科初次成绩无不及格。'))),
      )!;
      expect(form.scan.fields, isEmpty, reason: '前提：这份文档确实没有待填项');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fillFormDataProvider.overrideWith(
              (ref, yearEnd) async => _dataWithStudentInfo(),
            ),
          ],
          child: MaterialApp(
            home: FillFormScreen(
              debugInitialForm: form,
              debugInitialFileName: '先进个人评选标准.docx',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fillFormNoField')), findsOneWidget);
      expect(find.textContaining('没找到待填的空位'), findsOneWidget);
      expect(find.textContaining('已经填过'), findsOneWidget);
      expect(find.text('换一份表格'), findsWidgets);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('已导入后：待填项逐条可编辑、状态可读', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final form = DocxForm.fromBytes(_formDocx())!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fillFormDataProvider.overrideWith(
              (ref, yearEnd) async => _dataWithStudentInfo(),
            ),
          ],
          child: MaterialApp(
            home: FillFormScreen(
              debugInitialForm: form,
              debugInitialFileName: '先进个人登记表.docx',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 文件卡 + 逐项输入框
      expect(find.textContaining('共 ${form.scan.fields.length} 个待填项'), findsOneWidget);
      expect(find.text('姓名'), findsOneWidget);
      expect(find.text('主要表现'), findsOneWidget);
      expect(find.text('自动填入'), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(form.scan.fields.length));

      // 用户改一处 → 值进到导出用的那份 map 里
      final nameField = find.ancestor(
        of: find.text('姓名'),
        matching: find.byType(Card),
      );
      await tester.enterText(
        find.descendant(of: nameField, matching: find.byType(TextField)),
        '同学乙',
      );
      await tester.pumpAndSettle();
      expect(find.text('还原'), findsOneWidget, reason: '改过之后出现「还原」');

      await tester.tap(find.text('还原'));
      await tester.pumpAndSettle();
      expect(find.text('同学甲'), findsOneWidget);
    });
  });
}

String _numOf(double v) {
  final r = zcRound2(v);
  if (r == r.roundToDouble()) return r.round().toString();
  var s = r.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

/// 借一个**真实扫出来的** [DocxField]（`fillValueFor` 要 element 才能定位），
/// 只把标签换掉 —— 用来验「没有数据的标签 → 留空」。
DocxField _fakeField(String label) {
  final f = DocxForm.fromBytes(_formDocx())!.scan.fields.first;
  return DocxField(
    id: f.id,
    kind: f.kind,
    label: label,
    context: f.context,
    element: f.element,
    group: f.group,
  );
}
