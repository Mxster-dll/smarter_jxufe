/// 阅读学分「四部分进度」模型与纯计算（实际口径 vs 平台口径）。
///
/// 用户 2026-09-11 需求：「进度要区分实际与远端（因为服务端更新数据不及时），
/// 蛟湖阅读的四个部分都要显示进度条（有多个数值要求就都显示）」。
///
/// 两档口径：
/// - **实际（App 侧能实时拿到的口径）**：入馆教育 = App 里五章闯关的实时状态；
///   普通阅读的纸质借阅 = 学生个人数据中心的借阅册数；其余部分平台没有实时接口，
///   用**平台明细表的实时统计**（明细是随学随更新的，只有汇总页停在 5 月 / 11 月）。
/// - **平台（远端）**：学分查询页的达标状态与计数摘要（`电子阅读[2]` 之类），
///   即用户说的「更新不及时」的那一份数据。
///
/// 本文件只做纯计算（无网络 / 无 Flutter 依赖），界面层直接消费。
library;

import 'read_credit_models.dart';

/// 经典阅读要求：10 册 + 总时长 ≥ 20 小时（平台首页原文）。
const int kReadCreditClassicBooks = 10;
const double kReadCreditClassicHours = 20;

/// 普通阅读要求：纸质 + 电子累计 ≥ 10 册。
const int kReadCreditOrdinaryBooks = 10;

/// 信息素养要求：学习视频 ≥ 20 个。
const int kReadCreditInfoVideos = 20;

/// 数值展示：整数不带小数位，非整数保留 1 位小数。
String readCreditNum(double value) {
  if (value.isNaN || value.isInfinite) return '—';
  if ((value - value.roundToDouble()).abs() < 0.05) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

/// 一条「要求 → 进度」的进度条，带实际与平台两档数值。
///
/// [remote] 为 null 表示平台侧没有可比的数值（只有达标状态），此时界面只画
/// 实际那一条，平台信息走 [ReadCreditPartProgress.remoteStatusText]。
class ReadCreditProgressBar {
  /// 计量名（如「已读册数」）。
  final String label;

  /// 实际口径当前值。
  final double actual;

  /// 平台口径当前值；null = 平台未提供。
  final double? remote;

  /// 要求值（达标线）。
  final double target;

  /// 单位（册 / 小时 / 章 / 个）。
  final String unit;

  /// 实际值来源说明。
  final String? actualNote;

  /// 平台值来源说明。
  final String? remoteNote;

  const ReadCreditProgressBar({
    required this.label,
    required this.actual,
    required this.target,
    required this.unit,
    this.remote,
    this.actualNote,
    this.remoteNote,
  });

  double _ratio(double value) =>
      target <= 0 ? 0 : (value / target).clamp(0.0, 1.0);

  double get actualRatio => _ratio(actual);

  double? get remoteRatio => remote == null ? null : _ratio(remote!);

  bool get actualReached => target > 0 && actual >= target;

  bool? get remoteReached =>
      remote == null ? null : (target > 0 && remote! >= target);

  String get targetText => '${readCreditNum(target)} $unit';

  String get actualText => '${readCreditNum(actual)} / $targetText';

  String? get remoteText =>
      remote == null ? null : '${readCreditNum(remote!)} / $targetText';
}

/// 某一部分的进度（要求 + 若干进度条 + 两档达标状态）。
class ReadCreditPartProgress {
  final ReadCreditKind kind;

  /// 该部分的计量要求（取自平台规则原文）。
  final String requirementText;

  final List<ReadCreditProgressBar> bars;

  /// 实际口径是否达标；null = 该项没有 App 侧口径。
  final bool? actualMet;

  /// 平台口径是否达标（平台未给状态则 null）。
  final bool? remoteMet;

  /// 平台状态行（如「未通过 · 更新于 2026年09月03日」）。
  final String remoteStatusText;

  /// 补充口径明细行（如「电子阅读：实际 2 册 · 平台 2 册」）。
  final List<String> lines;

  /// 实际口径的取值说明。
  final String? actualSourceNote;

  const ReadCreditPartProgress({
    required this.kind,
    required this.requirementText,
    this.bars = const [],
    this.actualMet,
    this.remoteMet,
    this.remoteStatusText = '',
    this.lines = const [],
    this.actualSourceNote,
  });

  bool get hasActual => actualMet != null;
}

/// 四部分（+ 蛟湖文化活动）进度汇总。
class ReadCreditProgressBundle {
  final List<ReadCreditPartProgress> parts;

  /// 实际口径达标的部分数。
  final int actualMetCount;

  /// 平台口径达标的部分数。
  final int remoteMetCount;

  /// 四部分里「已完成」的个数（圆环亮起口径，见 [readCreditPartCompleted]）。
  final int completedCount;

  /// 服务端给的学分状态（`true` = 已获得学分）。
  final bool creditGranted;

  /// 学分状态原文（`获得学分` / `未获得学分`）。
  final String creditText;

  const ReadCreditProgressBundle({
    this.parts = const [],
    this.actualMetCount = 0,
    this.remoteMetCount = 0,
    this.completedCount = 0,
    this.creditGranted = false,
    this.creditText = '',
  });

  int get partCount => parts.length;

  /// 四个学分类部分（不含「蛟湖文化活动」）。
  List<ReadCreditPartProgress> get creditParts =>
      parts.where((p) => p.kind != ReadCreditKind.culture).toList();

  ReadCreditPartProgress? partOf(ReadCreditKind kind) {
    for (final part in parts) {
      if (part.kind == kind) return part;
    }
    return null;
  }
}

/// 该部分是否「已完成」（圆环亮起与完成计数的唯一口径）。
///
/// 以**实际**口径为准（App 能实时拿到的那份）；实际口径缺席时（平台明细取不到、
/// 入馆教育会话不可用）才回退服务端状态；两者都没有 → 未完成。
bool readCreditPartCompleted(ReadCreditPartProgress part) {
  final actual = part.actualMet;
  if (actual != null) return actual;
  return part.remoteMet ?? false;
}

/// 入馆教育闯关实时进度（App 侧口径）。
typedef ReadCreditEduProgress = ({int passed, int total});

/// 组装四部分进度（纯函数，供 provider 与测试共用）。
///
/// - [score] 平台学分查询结果（可为 null = 拉取失败，只出实际口径）。
/// - [details] 已取到的明细表（缺项即视为「未取到」，对应进度条不给实际值）。
/// - [libraryEdu] 入馆教育五章闯关实时进度（App 侧）；null = 会话不可用。
/// - [borrowCounts] 学生个人数据中心的借阅册数（键 `本周/本月/本年`）。
ReadCreditProgressBundle buildReadCreditProgress({
  required ReadCreditScore? score,
  Map<ReadCreditKind, ReadCreditDetail> details = const {},
  ReadCreditEduProgress? libraryEdu,
  Map<String, int> borrowCounts = const {},
}) {
  final parts = <ReadCreditPartProgress>[
    _classicPart(score, details[ReadCreditKind.classic]),
    _ordinaryPart(score, details[ReadCreditKind.ordinary], borrowCounts),
    _libraryEduPart(score, details[ReadCreditKind.libraryEdu], libraryEdu),
    _infoLiteracyPart(score, details[ReadCreditKind.infoLiteracy]),
    _culturePart(score),
  ];
  var actualMet = 0;
  var remoteMet = 0;
  var completed = 0;
  for (final part in parts) {
    if (part.actualMet == true) actualMet++;
    if (part.remoteMet == true) remoteMet++;
    if (part.kind != ReadCreditKind.culture && readCreditPartCompleted(part)) {
      completed++;
    }
  }
  return ReadCreditProgressBundle(
    parts: parts,
    actualMetCount: actualMet,
    remoteMetCount: remoteMet,
    completedCount: completed,
    creditGranted: score?.creditGranted ?? false,
    creditText: score?.creditText ?? '',
  );
}

/// 平台状态行文案（含更新时间）。
String _remoteStatus(ReadCreditItem? item) {
  if (item == null) return '平台未返回该项';
  final status = item.statusText.isEmpty ? '无状态' : item.statusText;
  final updated = item.updatedAt;
  return updated == null || updated.isEmpty ? status : '$status · 更新于 $updated';
}

int _rowCount(ReadCreditDetail? detail) => detail?.rows.length ?? 0;

double _sumSeconds(ReadCreditDetail? detail) =>
    (detail?.sumColumn('时长') ?? 0).toDouble();

/// 普通阅读明细里按「厂商」列区分电子阅读 / 纸质借阅。
({int electronic, int paper}) _ordinarySplit(ReadCreditDetail? detail) {
  if (detail == null) return (electronic: 0, paper: 0);
  final i = detail.indexOfHeader('厂商');
  var electronic = 0;
  var paper = 0;
  for (final row in detail.rows) {
    final vendor = (i >= 0 && i < row.length) ? row[i] : '';
    if (vendor.contains('纸质')) {
      paper++;
    } else {
      electronic++;
    }
  }
  return (electronic: electronic, paper: paper);
}

int? _countOf(ReadCreditItem? item, String keyword) {
  if (item == null) return null;
  for (final count in item.counts) {
    if (count.label.contains(keyword)) return count.value;
  }
  return null;
}

/// 第一部分 · 经典阅读（10 册 + 20 小时，平台的计数摘要为空 → 只有状态可比）。
ReadCreditPartProgress _classicPart(
  ReadCreditScore? score,
  ReadCreditDetail? detail,
) {
  final item = score?.itemOf(ReadCreditKind.classic);
  final available = detail != null;
  final books = _rowCount(detail).toDouble();
  final hours = _sumSeconds(detail) / 3600;
  return ReadCreditPartProgress(
    kind: ReadCreditKind.classic,
    requirementText: '经典电子阅读 10 册 + 阅读总时长 ≥ 20 小时',
    bars: [
      ReadCreditProgressBar(
        label: '已读册数',
        actual: books,
        target: kReadCreditClassicBooks.toDouble(),
        unit: '册',
        actualNote: available ? '平台明细实时统计' : '明细未取到',
      ),
      ReadCreditProgressBar(
        label: '阅读总时长',
        actual: hours,
        target: kReadCreditClassicHours,
        unit: '小时',
        actualNote: available ? '平台明细实时统计' : '明细未取到',
      ),
    ],
    actualMet: available
        ? (books >= kReadCreditClassicBooks && hours >= kReadCreditClassicHours)
        : null,
    remoteMet: item?.passed,
    remoteStatusText: _remoteStatus(item),
    actualSourceNote: '实际值 = 名著明细表实时统计（平台汇总不提供计数）',
  );
}

/// 第二部分 · 普通阅读（纸质 + 电子累计 ≥ 10 册）。
ReadCreditPartProgress _ordinaryPart(
  ReadCreditScore? score,
  ReadCreditDetail? detail,
  Map<String, int> borrowCounts,
) {
  final item = score?.itemOf(ReadCreditKind.ordinary);
  final split = _ordinarySplit(detail);
  final remoteElectronic = _countOf(item, '电子');
  final remotePaper = _countOf(item, '纸质');
  // 数据中心「本年」借阅册数（键为本周 / 本月 / 本年，值是册数）。
  final borrowYearCount = borrowCounts['本年'];
  final paperActual = borrowYearCount ?? split.paper;
  final electronicActual = split.electronic;
  final actualTotal = electronicActual + paperActual;
  final remoteTotal = (remoteElectronic == null && remotePaper == null)
      ? null
      : (remoteElectronic ?? 0) + (remotePaper ?? 0);
  final lines = <String>[
    '电子阅读：实际 $electronicActual 册'
        '${remoteElectronic == null ? '' : ' · 平台 $remoteElectronic 册'}',
    '纸质借阅：实际 $paperActual 册'
        '${borrowYearCount == null ? '（明细表口径）' : '（数据中心 · 本年借阅）'}'
        '${remotePaper == null ? '' : ' · 平台 $remotePaper 册'}',
  ];
  return ReadCreditPartProgress(
    kind: ReadCreditKind.ordinary,
    requirementText: '纸质借阅 + 电子阅读累计 ≥ 10 册',
    bars: [
      ReadCreditProgressBar(
        label: '累计册数',
        actual: actualTotal.toDouble(),
        remote: remoteTotal?.toDouble(),
        target: kReadCreditOrdinaryBooks.toDouble(),
        unit: '册',
        actualNote: borrowYearCount == null
            ? '实际值 = 平台明细实时统计'
            : '实际值 = 电子阅读 $electronicActual 册（实时明细）'
                  ' + 纸质借阅 $paperActual 册（数据中心 · 本年借阅）',
        remoteNote: remoteTotal == null ? null : '平台汇总计数',
      ),
    ],
    actualMet: (detail == null && borrowYearCount == null)
        ? null
        : actualTotal >= kReadCreditOrdinaryBooks,
    remoteMet: item?.passed,
    remoteStatusText: _remoteStatus(item),
    lines: lines,
    actualSourceNote: '实际值取自 App 可实时获取的数据源；平台计数停在汇总更新日',
  );
}

/// 第三部分 · 入馆教育（通过平台测试 = 五章闯关）。
ReadCreditPartProgress _libraryEduPart(
  ReadCreditScore? score,
  ReadCreditDetail? detail,
  ReadCreditEduProgress? libraryEdu,
) {
  final item = score?.itemOf(ReadCreditKind.libraryEdu);
  final total = libraryEdu?.total ?? 0;
  final passed = libraryEdu?.passed ?? 0;
  final detailRows = _rowCount(detail);
  final lines = <String>[];
  if (detailRows > 0) {
    final timeIndex = detail?.indexOfHeader('时间') ?? -1;
    final passIndex = detail?.indexOfHeader('通过') ?? -1;
    final last = detail?.rows.last;
    final passText = (last != null && passIndex >= 0 && passIndex < last.length)
        ? last[passIndex]
        : '';
    final timeText = (last != null && timeIndex >= 0 && timeIndex < last.length)
        ? last[timeIndex]
        : '';
    lines.add(
      '平台闯关记录：$detailRows 条'
      '${passText.isEmpty ? '' : ' · 最近结果「$passText」'}'
      '${timeText.isEmpty ? '' : ' · $timeText'}',
    );
  } else {
    lines.add('平台闯关记录：暂无（汇总与明细都常滞后，不代表未通过）');
  }
  return ReadCreditPartProgress(
    kind: ReadCreditKind.libraryEdu,
    requirementText: '通过入馆教育平台测试（五章闯关）',
    bars: total > 0
        ? [
            ReadCreditProgressBar(
              label: '已通过章节',
              actual: passed.toDouble(),
              target: total.toDouble(),
              unit: '章',
              actualNote: '入馆教育闯关实时状态（App 直连）',
            ),
          ]
        : const [],
    actualMet: libraryEdu == null ? null : (total > 0 && passed >= total),
    remoteMet: item?.passed,
    remoteStatusText: _remoteStatus(item),
    lines: lines,
    actualSourceNote: total > 0
        ? '实际值 = App 内五章闯关的实时结果（无需等平台汇总）'
        : '入馆教育会话不可用，暂无法读到实际进度',
  );
}

/// 第四部分 · 信息素养（学习视频 ≥ 20 个）。
ReadCreditPartProgress _infoLiteracyPart(
  ReadCreditScore? score,
  ReadCreditDetail? detail,
) {
  final item = score?.itemOf(ReadCreditKind.infoLiteracy);
  final available = detail != null;
  final videos = (detail?.sumColumn('视频') ?? 0).toDouble();
  final hours = _sumSeconds(detail) / 3600;
  final lines = <String>[if (available) '累计学习时长：${readCreditNum(hours)} 小时'];
  return ReadCreditPartProgress(
    kind: ReadCreditKind.infoLiteracy,
    requirementText: '信息素养平台在线视频学习 ≥ 20 个',
    bars: [
      ReadCreditProgressBar(
        label: '学习视频',
        actual: videos,
        target: kReadCreditInfoVideos.toDouble(),
        unit: '个',
        actualNote: available ? '平台明细实时统计' : '明细未取到',
      ),
    ],
    actualMet: available ? videos >= kReadCreditInfoVideos : null,
    remoteMet: item?.passed,
    remoteStatusText: _remoteStatus(item),
    lines: lines,
    actualSourceNote: '实际值 = 信息素养明细表实时统计（平台汇总不提供计数）',
  );
}

/// 附加项 · 蛟湖文化活动（平台单独标记，无量化要求）。
ReadCreditPartProgress _culturePart(ReadCreditScore? score) {
  final item = score?.itemOf(ReadCreditKind.culture);
  return ReadCreditPartProgress(
    kind: ReadCreditKind.culture,
    requirementText: '参与蛟湖文化活动（平台单独标记，无量化要求）',
    remoteMet: item?.passed,
    remoteStatusText: _remoteStatus(item),
  );
}
