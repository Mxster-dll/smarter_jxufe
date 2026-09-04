/// 学生个人数据中心全量概览（dzj.jxufe.edu.cn 数据中台首页等价）。
///
/// 一个不可变聚合对象，承载个人首页全部卡片所需的展示数据。
class DataCenterOverview {
  /// 姓名 / 学号 / 学院（班主任信息单独列出）
  final String username;
  final String userid;
  final String college;
  final String advisorName;
  final String advisorPhone;

  /// 学业：加权平均成绩 / 平均绩点 / 本学年修读学分 / 本学年已获学分
  final double weightedScore;
  final double gpa;
  final double semesterCredit;
  final double earnedCredit;

  /// 基础指标：今日进出校门 / 校园卡余额 / 今日登录门户 / 网费余额
  final double gateToday;
  final double cardBalance;
  final double todayLoginCount;
  final double networkBalance;

  /// 校园卡消费（元）：本年 / 当月 / 本周
  final double spendYear;
  final double spendMonth;
  final double spendWeek;
  final List<DzjConsumeRecord> consumeRecords;

  /// 奖助贷勤（奖学金等）摘要文本列表
  final List<String> awards;

  /// 教材：费用 / 数量
  final double textbookFee;
  final double textbookCount;

  /// 图书借阅：本周 / 本月 / 本年
  final Map<String, int> borrowCounts;

  /// 门户登录趋势（周一到周日次数）
  final List<DzjLoginDay> loginTrend;

  /// 校内关系（同侪）人数：grade 同年级 / class 同班级 /
  /// major 同年级同专业 / dorm 同宿舍 / college 同学院同天生日。
  /// 失败维度记 -1（不展示）。
  final Map<String, int> peerCounts;

  /// 当前周次信息（如「2026 第一学期 第0周」）与今日课程数
  final String weekTitle;
  final List<DzjWeekDay> weekDays;
  final int todayClassCount;

  const DataCenterOverview({
    this.username = '',
    this.userid = '',
    this.college = '',
    this.advisorName = '',
    this.advisorPhone = '',
    this.weightedScore = 0,
    this.gpa = 0,
    this.semesterCredit = 0,
    this.earnedCredit = 0,
    this.gateToday = 0,
    this.cardBalance = 0,
    this.todayLoginCount = 0,
    this.networkBalance = 0,
    this.spendYear = 0,
    this.spendMonth = 0,
    this.spendWeek = 0,
    this.consumeRecords = const [],
    this.awards = const [],
    this.textbookFee = 0,
    this.textbookCount = 0,
    this.borrowCounts = const {},
    this.loginTrend = const [],
    this.peerCounts = const {},
    this.weekTitle = '',
    this.weekDays = const [],
    this.todayClassCount = 0,
  });
}

/// 校园卡消费明细记录。
class DzjConsumeRecord {
  final String shopName;
  final String time;
  final double amount;

  const DzjConsumeRecord({
    required this.shopName,
    required this.time,
    required this.amount,
  });
}

/// 门户登录折线单日数据。
class DzjLoginDay {
  final String weekday;
  final int count;

  const DzjLoginDay({required this.weekday, required this.count});
}

/// 一周各日信息（周次组件返回）。
class DzjWeekDay {
  final String date;
  final String weekday;
  final String title;

  const DzjWeekDay({
    required this.date,
    required this.weekday,
    required this.title,
  });
}
