part of 'AcademicTime.dart';

/// 由于 `academicYears` 需要支持按 start 和按 value 两种查找方法，
/// 所以虽然实现了 `Comparable` 接口，但在调用 `search` 时仍要显式给出比较方式
/// 后面的 `academicPeriods` 同样如此
extension _Search<E extends AcademicTime> on List<E> {
  E? search<K>(K value, int Function(E, K) cmp, [int offset = 0]) {
    int low = 0, high = length;

    while (low < high) {
      int mid = low + ((high - low) >> 1);
      var sgn = cmp(this[mid], value);

      if (sgn == 0) {
        int idx = mid + offset;

        return (0 <= idx && idx < length) ? this[idx] : null;
      }

      if (sgn < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return null;
  }

  E? at(Date date) => search(date, (e, v) {
    final timeRange = e.timeRange;
    if (timeRange == null) throw StateError('$e 缺少 timeRange 字段');

    if (timeRange.includes(v)) return 0;

    return (v < timeRange.start) ? 1 : -1;
  });
}

extension _Period<E extends AcademicPeriod> on List<E> {
  E? period<T extends AcademicPeriodType>(int year, T type, [int offset = 0]) =>
      search((year, type), (e, v) {
        final (year, type) = v;
        if (e.year.value != year) return e.year.value.compareTo(year);
        return e.type.index.compareTo(type.index);
      }, offset);
}

extension Queue<E> on ListQueue<E> {
  E pop() {
    final head = first;
    removeFirst();

    return head;
  }

  void push(E e) => addLast(e);
}

class CalendarService {
  static final box = GetStorage();
  static final CalendarService _initService = CalendarService();

  /// 由于 AcademicPeriod 依赖于 AcademicYear，所以要先 loadAcademicYears，后 loadAcademicPeriods
  static List<AcademicYear> _academicYears = loadAcademicYears();
  static List<AcademicYear> get academicYears => _academicYears;
  static AcademicYear? academicYear(int year, [int offset = 0]) =>
      academicYears.search(year, (e, v) => e.value.compareTo(v), offset);

  static List<AcademicPeriod> _academicPeriods = loadAcademicPeriods();
  static List<AcademicPeriod> get academicPeriods => _academicPeriods;

  static List<Semester> get semesters =>
      _academicYears.whereType<Semester>().toList();
  static List<Vacation> get vacations =>
      _academicYears.whereType<Vacation>().toList();

  static Semester? semester(int year, SemesterType type, [int offset = 0]) =>
      semesters.period(year, type, offset);
  static Vacation? vacation(int year, VacationType type, [int offset = 0]) =>
      vacations.period(year, type, offset);

  late final ImsService _imsService;

  CalendarService([ImsService? imsService]) {
    _imsService = imsService ?? ImsService();
  }

  static Future<void> update() async {
    // box.remove('academicYears');
    // box.remove('academicPeriods');

    final oldAcademicYears = ListQueue<AcademicYear>.from(_academicYears);
    final oldAcademicPeriods = ListQueue<AcademicPeriod>.from(_academicPeriods);
    _academicYears = [];
    _academicPeriods = [];

    FutureOr<void> checkSemester(int i, SemesterType type) async =>
        _academicPeriods.add(
          oldAcademicPeriods.isNotEmpty &&
                  oldAcademicPeriods.first.year.value == i &&
                  oldAcademicPeriods.first.type == type
              ? oldAcademicPeriods.pop()
              : Semester._(i, type, await _initService.calendar(i, type)),
        );

    FutureOr<void> checkVacation(int i, VacationType type) async =>
        _academicPeriods.add(
          oldAcademicPeriods.isNotEmpty &&
                  oldAcademicPeriods.first.year.value == i &&
                  oldAcademicPeriods.first.type == type
              ? oldAcademicPeriods.pop()
              : Vacation._(i, type, await _initService.calendar(i, type)),
        );

    try {
      for (int i = 2016; ; i++) {
        _academicYears.add(
          oldAcademicYears.isNotEmpty && oldAcademicYears.first.value == i
              ? oldAcademicYears.pop()
              : AcademicYear._(
                  i,
                  TimeRange(
                    (await _initService.calendar(i, SemesterType.first)).start,
                    (await _initService.calendar(i, VacationType.summer)).end,
                  ),
                ),
        );

        await checkSemester(i, .first);
        await checkVacation(i, .winter);
        await checkSemester(i, .second);
        if (i != 2018) await checkSemester(i, .short);
        await checkVacation(i, .summer);
      }
    } catch (e) {
      logInfo('学术时间更新完成: $e');
      logInfo('(${academicPeriods.first.start} ~ ${academicPeriods.last.end})');
      logInfo('${academicYears.first} 至 ${academicYears.last}');
      logInfo('${academicPeriods.first} 至 ${academicPeriods.last}');
      //   logInfo('$academicYears');
      //   logInfo('$academicPeriods');
    } finally {
      save('academicYears', _academicYears);
      save('academicPeriods', _academicPeriods);
    }
  }

  static void save<T extends Serializable>(String key, List<T> data) =>
      box.write(key, data.map((e) => e.toJson()).toList());

  static List<AcademicYear> loadAcademicYears() =>
      box
          .read<List>('academicYears')
          ?.map((e) => AcademicYear.fromJson(e))
          .toList() ??
      [];

  static List<AcademicPeriod> loadAcademicPeriods() =>
      box
          .read<List>('academicPeriods')
          ?.map((e) => AcademicPeriod.fromJson(e))
          .toList() ??
      [];

  final Map<int, Map<int, List<Date>>> _cache = {};

  /// 查询范围 2016-本学年
  /// 其中除 2018 年没有第二阶段以外，其他学年均有第一学期、第二学期、第二阶段
  Future<List<Date>> _getCalendar(int year, int xq) async {
    final response = await _imsService.dio.post(
      '/public/SchoolCalendar.show.jsp',
      data: {
        'menucode': 'null',
        'xn': year,
        'xq_m': xq,
        'rad': '1',
        'sel_xn_xq': '$year-$xq',
        'btnQry': '%BC%EC%CB%F7', // GBK 检索
        'btnPreview': '%B4%F2%D3%A1', // GBK 打印
        'menucode_current': '',
      },
      options: Options(
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );

    final textarea = parse(response.data).querySelector('textarea');
    if (textarea == null) throw Exception('($year, $xq) 缺少 textarea 标签');

    final dateRegExp = RegExp(r'\d{4}-\d{2}-\d{2}');

    final yearCache = _cache[year] ??= {};
    return yearCache[xq] = [
      for (var str in textarea.text.split('\n'))
        if (dateRegExp.hasMatch(str))
          Date.parse(dateRegExp.firstMatch(str)!.group(0)!),
    ];
  }

  FutureOr<TimeRange> calendar(int year, AcademicPeriodType type) async {
    if (year == 2022 && type == VacationType.winter) {
      return TimeRange(Date(2023, 2, 12), Date(2023, 2, 12));
    }

    int xq = switch (type) {
      SemesterType.first || VacationType.winter => 0,
      SemesterType.second => 1,
      SemesterType.short => 2,
      VacationType.summer => (year == 2018) ? 1 : 2,
    };

    final yearCache = _cache[year] ??= {};
    final xqCache = yearCache[xq] ??= await _getCalendar(year, xq);

    return (type is SemesterType)
        ? TimeRange(xqCache[0], xqCache[1])
        : TimeRange(xqCache[2], xqCache[3]);
  }

  static void showDurationBetweenAcademicTimes() {
    logInfo('BEGIN::showDurationBetweenAcademicTimes::BEGIN');
    final aps = CalendarService.academicPeriods;
    for (int i = 1; i < aps.length; i++) {
      if (aps[i].start?.difference(aps[i - 1].end!) != 1) {
        logError(
          '${aps[i - 1]}(${aps[i - 1].end})\n  到 ${aps[i]}(${aps[i].start})\n  相隔${aps[i].start?.difference(aps[i - 1].end!)}天\n',
        );
      }
    }
    final ays = CalendarService.academicYears;
    for (int i = 1; i < ays.length; i++) {
      if (ays[i].start?.difference(ays[i - 1].end!) != 1) {
        logError(
          '${ays[i - 1]}(${ays[i - 1].end})\n  到 ${ays[i]}(${ays[i].start})\n  相隔${ays[i].start?.difference(ays[i - 1].end!)}天\n',
        );
      }
    }
    logInfo('END::showDurationBetweenAcademicTimes::END');
  }
}
