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

  /// 本时段在 [week] 这一教学周是否上课（周次区间 + 单双周）。
  bool appliesInWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    return switch (weekParity) {
      WeekParity.every => true,
      WeekParity.odd => week.isOdd,
      WeekParity.even => week.isEven,
    };
  }

  /// 周次范围描述，如 "1-16周"
  String get weekRangeText => '$startWeek-$endWeek周';

  /// 完整的周次描述，如 "1-16周(单)"
  String get fullWeekText {
    final parity = weekParity.displayName;
    return parity.isEmpty ? weekRangeText : '$weekRangeText($parity)';
  }

  Map<String, dynamic> toJson() => {
    'startWeek': startWeek,
    'endWeek': endWeek,
    'weekParity': weekParity.name,
    'dayOfWeek': dayOfWeek.name,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'classroom': classroom,
    'capacity': capacity,
    'campus': campus,
  };

  /// 容错解析：关键字段缺失或类型不符时返回 null（旧缓存不得导致崩溃）。
  static ClassTime? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final startWeek = raw['startWeek'];
    final endWeek = raw['endWeek'];
    final startPeriod = raw['startPeriod'];
    final endPeriod = raw['endPeriod'];
    final classroom = raw['classroom'];
    if (startWeek is! num ||
        endWeek is! num ||
        startPeriod is! num ||
        endPeriod is! num ||
        classroom is! String) {
      return null;
    }
    return ClassTime(
      startWeek: startWeek.toInt(),
      endWeek: endWeek.toInt(),
      weekParity: _parityByName(raw['weekParity']),
      dayOfWeek: _dayByName(raw['dayOfWeek']),
      startPeriod: startPeriod.toInt(),
      endPeriod: endPeriod.toInt(),
      classroom: classroom,
      capacity: raw['capacity'] is num
          ? (raw['capacity'] as num).toInt()
          : null,
      campus: raw['campus'] is String ? raw['campus'] as String : null,
    );
  }

  static WeekParity _parityByName(Object? name) {
    for (final p in WeekParity.values) {
      if (p.name == name) return p;
    }
    return WeekParity.every;
  }

  static DayOfWeek _dayByName(Object? name) {
    for (final d in DayOfWeek.values) {
      if (d.name == name) return d;
    }
    return DayOfWeek.monday;
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
