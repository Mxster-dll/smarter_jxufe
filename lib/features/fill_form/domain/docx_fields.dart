/// 「填表助手」的**字段模型**（待填项 + 清单表结构）。
///
/// 一份 docx 里的「待填位」共五种，都由扫描器（`docx_scan.dart`）产出：
/// - [DocxFieldKind.cell]：整格是空的 → 值直接写进这一格（姓名 / 学号 / 合计…）；
/// - [DocxFieldKind.cellInline]：格内写着「加、减分项目：」这种**标签带冒号**的段落
///   → 在标签后面就地把值接上（不新增段落）；
/// - [DocxFieldKind.cellProse]：格内是**提示文字 + 空白书写区**（先进个人登记表的
///   「主要表现」格：`(德、智、体等方面)` + 若干空段 + `签名 年 月 日`）
///   → 在提示段之后**插入一个新段落**，提示与签名行都原样留着；
/// - [DocxFieldKind.paragraph]：正文段落里的「学院：<若干空白>」→ 替换那段空白；
/// - [DocxFieldKind.listCell]：清单表（序号/项目/类别/级别/获得时间/附件数/分值）
///   的一格 —— 由 [DocxListTable] 按列头决定填什么，行不够会自动复制表格行。
library;

import 'package:xml/xml.dart';

/// 待填项种类。
enum DocxFieldKind {
  /// 整格是空的 → 值直接写进这一格。
  cell,

  /// 格内「标签：」段落 → 就地追加。
  cellInline,

  /// 格内提示 + 空白书写区 → 在提示段后插入新段落。
  cellProse,

  /// 正文段落里的「标签：<空白>」→ 替换空白。
  paragraph,

  /// 清单表（整张表当一个 **TSV 多行文本**编辑）。
  listTable,
}

/// 一个待填项。
class DocxField {
  /// 稳定 id（重扫后不变）：`t0.r1.c3` / `t0.r1.c3.p2` / `b7` / `list0.r3.c5`。
  final String id;

  final DocxFieldKind kind;

  /// 标签（「姓名」「学年加权平均成绩」「加、减分项目」…）——已压掉全部空白。
  final String label;

  /// 人话定位：「表 1 · 第 2 行」「正文第 3 段」。
  final String context;

  /// 格内原有的提示文字（`(德、智、体等方面)`），没有则空串。
  final String hint;

  /// 扫描时的现值（绝大多数是空串）。
  final String initial;

  /// 清单表的列头（[DocxFieldKind.listTable] 才有；其余为空串 —— 由 `hint` 描述）。
  final String column;

  /// **同行的分组标签**（该行第一格的文字，纵向合并时往上取锚格）。
  ///
  /// 综测登记表里「合计」「班级评议德育等次」各出现 5 次（德/智/体/美/劳 各一行），
  /// 光看标签分不清填哪个 —— 分组标签就是「这一行属于哪一育」。取不到为空串。
  final String group;

  /// 清单表契约（[DocxFieldKind.listTable] 非空）。
  final DocxListTable? listTable;

  /// 写回定位：`w:tc`（前三种）或 `w:p`（paragraph）。
  final XmlElement element;

  /// `w:tc` 内段落序号；`cell` 为 -1（整格）。
  final int paragraphIndex;

  /// [DocxFieldKind.paragraph] 的空白区间（相对 `paragraphText`）。
  final int blankStart;
  final int blankEnd;

  /// 表格坐标（正文段落为 -1）。
  final int tableIndex;
  final int rowIndex;
  final int cellIndex;
  final int gridStart;
  final int gridSpan;

  const DocxField({
    required this.id,
    required this.kind,
    required this.label,
    required this.context,
    required this.element,
    this.hint = '',
    this.initial = '',
    this.column = '',
    this.group = '',
    this.listTable,
    this.paragraphIndex = -1,
    this.blankStart = -1,
    this.blankEnd = -1,
    this.tableIndex = -1,
    this.rowIndex = -1,
    this.cellIndex = -1,
    this.gridStart = -1,
    this.gridSpan = 1,
  });

  /// 这一项是不是清单表（整表编辑）。
  bool get isListTable => kind == DocxFieldKind.listTable;

  @override
  String toString() => 'DocxField($id, $label, ${kind.name})';
}

/// 清单表的列语义。
enum DocxListColumnKind {
  seq, // 序号
  name, // 姓名
  studentId, // 学号
  className, // 班级
  gender, // 性别
  political, // 政治面貌
  duty, // 职务
  title, // 授予称号
  scholarship, // 奖学金等级
  project, // 项目 / 竞赛名称
  category, // 类别（Ⅰ/Ⅱ/Ⅲ类）
  level, // 级别（国一）
  date, // 获得时间
  attachCount, // 附件数
  score, // 分值
  weighted, // 加权成绩
  gradeD,
  gradeZ,
  gradeT,
  gradeM,
  gradeL, // 五育分数
  rankD,
  rankZ,
  rankT,
  rankM,
  rankL, // 五育评定等次
  overallGrade, // 综合测评等次
  total, // 总分
  collegeScore, // 学院审核分值（不填）
  collegeClass, // 学院/班级
  weightedMin, // 加权成绩/单科最低分
  englishLevel, // 英语水平（四六级）
  dutyText, // 担任学生干部情况
  honorsText, // 大学期间受表彰情况
  deedsText, // 突出事迹
  researchText, // 科研成果及实践创新情况
  serviceText, // 服务社会情况
  other,
}

/// 清单表的一列。
class DocxListColumn {
  final DocxListColumnKind kind;

  /// 表头原文（压掉空白后）。
  final String header;

  /// 起始网格列。
  final int gridStart;

  final int gridSpan;

  const DocxListColumn({
    required this.kind,
    required this.header,
    required this.gridStart,
    this.gridSpan = 1,
  });
}

/// 识别出来的清单表。
class DocxListTable {
  final int tableIndex;

  /// 表头行序号。
  final int headerRow;

  /// 数据行序号（不含表头、不含合计行），按文档顺序。
  final List<int> dataRows;

  /// 合计行序号（没有 → null）。
  final int? totalRow;

  final List<DocxListColumn> columns;

  /// true = 材料清单（逐条材料占一行）；false = 人员清单（本人占一行）。
  final bool materialRows;

  const DocxListTable({
    required this.tableIndex,
    required this.headerRow,
    required this.dataRows,
    required this.totalRow,
    required this.columns,
    required this.materialRows,
  });

  DocxListColumn? columnOf(DocxListColumnKind kind) {
    for (final c in columns) {
      if (c.kind == kind) return c;
    }
    return null;
  }
}
