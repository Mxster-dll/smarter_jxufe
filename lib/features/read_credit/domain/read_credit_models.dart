/// 阅读学分平台（蛟湖阅读学分）领域模型。
///
/// 数据源 = 智信「阅读学分平台」`https://jhread.zhixinst.com`（服务端渲染
/// HTML，无 JSON 接口）：学分查询页给出 5 项达标状态，其中 4 项另有明细表。
/// 该学分共 1 分，由经典阅读 / 普通阅读 / 入馆教育 / 信息素养四部分构成
/// （另有「蛟湖文化活动」项由平台单独标记），规则见 [readCreditRules]。
library;

/// 学分查询页的五个抓取项。
enum ReadCreditKind {
  ordinary('普通阅读', 'pt'),
  classic('经典阅读', 'jd'),
  libraryEdu('入馆教育', 'rg'),
  infoLiteracy('信息素养', 'xx'),
  culture('蛟湖文化活动', '');

  const ReadCreditKind(this.label, this.detailSegment);

  /// 页面上的中文名（解析与展示共用同一口径）。
  final String label;

  /// 明细页路径段（`/Web/Read/Index/<segment>`）；空串 = 平台未提供明细页。
  final String detailSegment;

  /// 该平台是否提供明细表（蛟湖文化活动没有「详细列表」链接）。
  bool get hasDetail => detailSegment.isNotEmpty;

  String get detailPath => '/Web/Read/Index/$detailSegment';

  static ReadCreditKind? fromLabel(String label) {
    for (final kind in values) {
      if (kind.label == label) return kind;
    }
    return null;
  }
}

/// 普通阅读 / 信息素养等项的计数摘要（如 `电子阅读[2]`）。
class ReadCreditCount {
  final String label;
  final int value;

  const ReadCreditCount(this.label, this.value);

  @override
  String toString() => '$label[$value]';
}

/// 学分查询页的一项。
class ReadCreditItem {
  final ReadCreditKind kind;

  /// 平台原文状态：`通过` / `未通过` / 空串（平台未给出）。
  final String statusText;

  /// 平台原文为「通过」时 true、「未通过」时 false、无状态时 null。
  final bool? passed;

  /// 更新时间原文（如 `2026年09月03日`），平台未给则为 null。
  final String? updatedAt;

  /// 摘要原文（如 `电子阅读[2] 纸质阅读[0]`）；平台返回「无信息」时为 null。
  final String? infoRaw;

  /// 从 [infoRaw] 解析出的计数项。
  final List<ReadCreditCount> counts;

  const ReadCreditItem({
    required this.kind,
    this.statusText = '',
    this.passed,
    this.updatedAt,
    this.infoRaw,
    this.counts = const [],
  });

  bool get hasInfo => counts.isNotEmpty;

  bool get hasDetail => kind.hasDetail;
}

/// 学分查询页整体结果。
class ReadCreditScore {
  final List<ReadCreditItem> items;

  /// 学分状态：已获得学分。
  final bool creditGranted;

  /// 学分状态原文（`获得学分` / `未获得学分`）。
  final String creditText;

  const ReadCreditScore({
    this.items = const [],
    this.creditGranted = false,
    this.creditText = '',
  });

  ReadCreditItem? itemOf(ReadCreditKind kind) {
    for (final item in items) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  int get passedCount => items.where((i) => i.passed == true).length;
}

/// 某一项的明细表（列名由服务端决定，按 kind 不同而异）。
class ReadCreditDetail {
  final ReadCreditKind kind;
  final List<String> headers;
  final List<List<String>> rows;

  const ReadCreditDetail({
    required this.kind,
    this.headers = const [],
    this.rows = const [],
  });

  bool get isEmpty => rows.isEmpty;

  /// 列下标（找不到返回 -1）。
  int indexOfHeader(String keyword) =>
      headers.indexWhere((h) => h.contains(keyword));

  /// 某项所有行的该列取值（缺列返回空表）。
  List<String> columnValues(String keyword) {
    final i = indexOfHeader(keyword);
    if (i < 0) return const [];
    return [
      for (final row in rows)
        if (i < row.length) row[i].trim(),
    ];
  }

  /// 数值列求和（非数字忽略）。
  int sumColumn(String keyword) {
    var sum = 0;
    for (final v in columnValues(keyword)) {
      sum += int.tryParse(v) ?? 0;
    }
    return sum;
  }
}

/// 明细单元格展示文案：时长列（秒）补一个「小时」换算，空值显示 `—`。
///
/// 纯函数，供界面层统一调用（不重算口径，只做展示换算）。
String readCreditCellText(String header, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '—';
  final seconds = int.tryParse(value);
  if (seconds != null && header.contains('时长')) {
    if (seconds <= 0) return '0 秒';
    final hours = seconds / 3600;
    final text = hours >= 10
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return '$value 秒（$text 小时）';
  }
  return value;
}

/// 明细行里不必逐行重复展示的本人身份列。
const List<String> kReadCreditIdentityHeaders = [
  '一卡通号',
  '姓名',
  '学院',
  '专业',
  '班级',
];

/// 学分构成说明的一条。
class ReadCreditRule {
  final String title;
  final String body;

  const ReadCreditRule(this.title, this.body);
}

/// 学分说明（取自平台首页原文，静态规则文本）。
const List<ReadCreditRule> readCreditRules = [
  ReadCreditRule('第一部分 · 经典阅读', '通过经典电子阅读平台在线阅读 10 册图书，且阅读总时长须不少于 20 小时。'),
  ReadCreditRule(
    '第二部分 · 普通阅读',
    '通过借阅馆藏纸质图书或电子阅读平台在线阅读完成。纸质借阅按读者实际借阅'
        '册数计算；电子阅读册数按阅读平台认可的读完册数计算。纸质借阅和电子阅读'
        '累计册数须不少于 10 册。',
  ),
  ReadCreditRule('第三部分 · 入馆教育', '通过入馆教育平台进行在线自主学习，并须通过平台测试。'),
  ReadCreditRule('第四部分 · 信息素养能力', '通过信息素养平台进行在线视频学习，学习小视频数量须不少于 20 个。'),
];

/// 平台首页的固定提示（原文）。
const String readCreditNotice =
    '蛟湖阅读学分共 1 分，应于大学本科三年级结束前完成；'
    '四部分内容全部完成后即为修满该学分，由图书馆统一出具证明。';

/// 平台首页的登录 / 更新提示（原文）。
const String readCreditUpdateHint =
    '学习前务必先登录再学习；'
    '蛟湖阅读学分的更新时间分别是 5 月份和 11 月份。';
