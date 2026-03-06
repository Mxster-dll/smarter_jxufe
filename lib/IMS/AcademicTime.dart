library;

import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:get_storage/get_storage.dart';

import 'package:smarter_jxufe/ims/ImsService.dart';
import 'package:smarter_jxufe/utils/Serializable.dart';
import 'package:smarter_jxufe/utils/Log.dart';
import 'package:smarter_jxufe/utils/Time.dart';

part 'CalendarService.dart';

abstract class AcademicTime implements Serializable {
  final TimeRange? timeRange;

  AcademicTime(this.timeRange);

  Date? get start => timeRange?.start;
  Date? get end => timeRange?.end;

  @override
  toJson() => {'timeRange': ?timeRange?.toJson()};
}

class AcademicYear extends AcademicTime implements Comparable<AcademicYear> {
  final int value;

  AcademicYear._(this.value, [super.timeRange]);

  static final Map<int, AcademicYear> _cache = {};

  factory AcademicYear(int year) =>
      CalendarService.academicYear(year) ??
      _cache.putIfAbsent(year, () => AcademicYear._(year));

  @override
  String toString() => '$value-${value + 1}学年';

  String get short {
    final str = value.toString();

    return str.substring(str.length - 2);
  }

  @override
  int compareTo(AcademicYear ay) => value.compareTo(ay.value);

  @override
  Map<String, dynamic> toJson() => super.toJson()..['year'] = value;

  factory AcademicYear.fromJson(Map<String, dynamic> json) => AcademicYear._(
    json['year'],
    TimeRange.fromNullableJson(json['timeRange']),
  );

  static AcademicYear get now {
    final current = Date.now();
    final ay = CalendarService.academicYears.at(current);
    // TODO 实现允许模糊匹配，即10-8月一定可以判断学年
    if (ay == null) throw ArgumentError('查找不到处于 $current 的学年信息');

    return ay;
  }

  AcademicYear get nextYear => AcademicYear(value + 1);
  AcademicYear get lastYear => AcademicYear(value - 1);

  AcademicYear operator +(int interval) => AcademicYear(value + interval);
  AcademicYear operator -(int interval) => AcademicYear(value - interval);
}

T _parseEnum<T extends Enum>(List<T> values, String s) {
  for (final v in values) {
    if (s == v.toString()) return v;
  }
  throw FormatException('未知的值: $s');
}

sealed class AcademicPeriod<T extends AcademicPeriodType> extends AcademicTime
    implements Comparable<AcademicPeriod> {
  final AcademicYear year;
  final T type;

  AcademicPeriod._(int year, this.type, [super.timeRange])
    : year = AcademicYear(year);

  @override
  String toString() => '$year$type';

  @override
  int compareTo(AcademicPeriod ap) {
    if (year != ap.year) return year.compareTo(ap.year);

    return type.index.compareTo(ap.type.index);
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..['runtimeType'] = runtimeType.toString()
    ..['year'] = year.value
    ..['type'] = type.toString();

  factory AcademicPeriod.fromJson(Map<String, dynamic> json) =>
      switch (json['runtimeType']) {
            'Semester' => Semester._fromJson(json),
            'Vacation' => Vacation._fromJson(json),
            _ => throw Exception('错误的 type: ${json['runtimeType']}'),
          }
          as AcademicPeriod<T>;

  static AcademicPeriod get now {
    final now = CalendarService.academicPeriods.at(Date.now());
    if (now == null) throw ArgumentError('日期超限, AP 初始化失败: ${Date.now()}');

    return now;
  }

  Semester get lastSemester =>
      ((type is SemesterType)
          ? CalendarService.semester(year.value, type as SemesterType, -1)
          : null) ??
      switch (type) {
        SemesterType.first => Semester(year.value - 1, .short),
        VacationType.winter => Semester(year.value, .first),
        SemesterType.second => Semester(year.value, .first),
        SemesterType.short => Semester(year.value, .second),
        VacationType.summer => Semester(year.value, .short),
      };

  bool get inLastYear => year == AcademicYear.now.lastYear;
}

sealed class AcademicPeriodType {
  int get index;
}

enum SemesterType implements AcademicPeriodType, Comparable<SemesterType> {
  first('第一学期', 1),
  second('第二学期', 2),
  short('第二阶段', -1);

  const SemesterType(this.name, this.code);

  final String name;
  final int code;

  @override
  String toString() => name;

  @override
  int compareTo(AcademicPeriodType other) => index.compareTo(other.index);

  static SemesterType parse(String s) => _parseEnum(values, s);
}

class Semester extends AcademicPeriod<SemesterType> {
  Semester._(super.year, super.type, [super.timeRange]) : super._();

  static final Map<(int, SemesterType), Semester> _cache = {};

  factory Semester(int year, SemesterType type) =>
      CalendarService.semester(year, type) ??
      _cache.putIfAbsent((year, type), () => Semester._(year, type));

  static Semester _fromJson(Map<String, dynamic> json) => ._(
    json['year'],
    .parse(json['type']),
    TimeRange.fromNullableJson(json['timeRange']),
  );

  String get code => '${year.short}${type.code}';
}

enum VacationType implements AcademicPeriodType, Comparable<VacationType> {
  summer('暑假'),
  winter('寒假');

  const VacationType(this.name);

  final String name;

  @override
  String toString() => name;

  @override
  int compareTo(AcademicPeriodType other) => index.compareTo(other.index);

  static VacationType parse(String s) => _parseEnum(values, s);
}

class Vacation extends AcademicPeriod<VacationType> {
  Vacation._(super.year, super.type, [super.timeRange]) : super._();

  static final Map<(int, VacationType), Vacation> _cache = {};

  factory Vacation(int year, VacationType type) =>
      CalendarService.vacation(year, type) ??
      _cache.putIfAbsent((year, type), () => Vacation._(year, type));

  static Vacation _fromJson(Map<String, dynamic> json) => ._(
    json['year'],
    .parse(json['type']),
    TimeRange.fromNullableJson(json['timeRange']),
  );
}

enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.name, this.value);

  final String name;
  final String value;
}

class CreditHour {
  final int total, lecture, lab, practice, other;
  final double weekly;

  CreditHour(
    this.total,
    this.lecture,
    this.lab,
    this.practice,
    this.other,
    this.weekly,
  );
}
