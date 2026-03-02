import 'package:smarter_jxufe/utils/Serializable.dart';

final class TimeRange implements Comparable<TimeRange>, Serializable {
  final Date start, end;

  const TimeRange(this.start, [Date? end])
    : end = end ?? start,
      assert(start <= (end ?? start));

  bool includes(Date d) => start.isBefore(d) && d <= end;

  @override
  String toString() => '$start ~ $end';

  @override
  int compareTo(TimeRange tr) {
    if (start != tr.start) return start.compareTo(tr.start);

    return end.compareTo(tr.end);
  }

  @override
  toJson() => {'start': start, 'end': end};

  factory TimeRange.fromJson(Map<String, dynamic> json) =>
      TimeRange(Date.fromJson(json['start']), Date.fromJson(json['end']));

  static TimeRange? fromNullableJson(Map<String, dynamic>? json) =>
      (json == null)
      ? null
      : TimeRange(Date.fromJson(json['start']), Date.fromJson(json['end']));
}

extension ToDate on DateTime {
  Date toDate() => Date._fromDateTime(this);
}

class Date implements Comparable<Date>, Serializable {
  final int year, month, day;

  Date([this.year = 1, this.month = 1, this.day = 1]);

  Date._fromDateTime(DateTime dateTime)
    : year = dateTime.year,
      month = dateTime.month,
      day = dateTime.day;

  factory Date.now() => DateTime.now().toDate();

  static Date parse(String s) => DateTime.parse(s).toDate();

  static Date? tryParse(String formattedString) {
    try {
      return parse(formattedString);
    } on FormatException {
      return null;
    }
  }

  DateTime toDateTime() => DateTime(year, month, day);

  bool isAtSameMomentAs(Date date) =>
      toDateTime().isAtSameMomentAs(date.toDateTime());

  bool isAfter(Date date) => toDateTime().isAfter(date.toDateTime());
  bool isBefore(Date date) => toDateTime().isBefore(date.toDateTime());

  @override
  int compareTo(Date date) => toDateTime().compareTo(date.toDateTime());

  bool operator <(Date d) => compareTo(d) < 0;
  bool operator <=(Date d) => compareTo(d) <= 0;
  bool operator >(Date d) => compareTo(d) > 0;
  bool operator >=(Date d) => compareTo(d) >= 0;

  Date operator +(int days) => toDateTime().add(Duration(days: days)).toDate();
  Date operator -(int days) =>
      toDateTime().subtract(Duration(days: days)).toDate();

  int difference(Date date) =>
      toDateTime().difference(date.toDateTime()).inDays;

  @override
  String toString() => toDateTime().toString().substring(0, 10);

  @override
  String toJson() => toString();
  factory Date.fromJson(String date) => Date.parse(date);
}
