/// 周次奇偶性
enum WeekParity {
  /// 每周
  every,

  /// 单周
  odd,

  /// 双周
  even;

  /// 从中文括号内文字解析："单"→odd、"双"→even、null→every
  static WeekParity fromChinese(String? text) {
    if (text == '单') return WeekParity.odd;
    if (text == '双') return WeekParity.even;
    return WeekParity.every;
  }

  String get displayName {
    switch (this) {
      case WeekParity.odd:
        return '单周';
      case WeekParity.even:
        return '双周';
      case WeekParity.every:
        return '';
    }
  }
}

/// 一周中的星期几（1=周一，7=周日）
enum DayOfWeek {
  monday(1, '一', '周一'),
  tuesday(2, '二', '周二'),
  wednesday(3, '三', '周三'),
  thursday(4, '四', '周四'),
  friday(5, '五', '周五'),
  saturday(6, '六', '周六'),
  sunday(7, '日', '周日');

  final int dayIndex;
  final String shortName;
  final String displayName;
  const DayOfWeek(this.dayIndex, this.shortName, this.displayName);

  static DayOfWeek fromChinese(String chinese) {
    for (final d in DayOfWeek.values) {
      if (d.shortName == chinese) return d;
    }
    throw ArgumentError('无法解析星期: $chinese');
  }
}

/// 单次上课时间地点
///
/// 解析自"上课时间地点"列中的一条记录，格式如：
/// `1-16周(单) 一[6-8] 麦三教3407(70)(麦庐园校区)`
class ClassTime {
  /// 起始周
  final int startWeek;

  /// 结束周
  final int endWeek;

  /// 周次奇偶性
  final WeekParity weekParity;

  /// 星期几
  final DayOfWeek dayOfWeek;

  /// 起始节次（1-12）
  final int startPeriod;

  /// 结束节次（1-12）
  final int endPeriod;

  /// 教室名称
  final String classroom;

  /// 教室容量（人）
  final int? capacity;

  /// 校区名称
  final String? campus;

  const ClassTime({
    required this.startWeek,
    required this.endWeek,
    required this.weekParity,
    required this.dayOfWeek,
    required this.startPeriod,
    required this.endPeriod,
    required this.classroom,
    this.capacity,
    this.campus,
  });

  /// 该课程跨越的节次数
  int get periodSpan => endPeriod - startPeriod + 1;

  /// 周次范围描述，如 "1-16周"
  String get weekRangeText => '$startWeek-$endWeek周';

  /// 完整的周次描述，如 "1-16周(单)"
  String get fullWeekText {
    final parity = weekParity.displayName;
    return parity.isEmpty ? weekRangeText : '$weekRangeText($parity)';
  }

  @override
  String toString() =>
      'ClassTime($fullWeekText ${dayOfWeek.displayName}[$startPeriod-$endPeriod] $classroom${capacity != null ? '($capacity人)' : ''}${campus != null ? '($campus)' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassTime &&
          startWeek == other.startWeek &&
          endWeek == other.endWeek &&
          weekParity == other.weekParity &&
          dayOfWeek == other.dayOfWeek &&
          startPeriod == other.startPeriod &&
          endPeriod == other.endPeriod &&
          classroom == other.classroom;

  @override
  int get hashCode => Object.hash(
    startWeek,
    endWeek,
    weekParity,
    dayOfWeek,
    startPeriod,
    endPeriod,
    classroom,
  );
}
