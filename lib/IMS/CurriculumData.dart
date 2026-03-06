import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/AcademicUnit.dart';
import 'package:smarter_jxufe/ims/Course.dart';
import 'package:smarter_jxufe/ims/CurriculumService.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 主修课程数据管理器（单例），管理主修数据库
class MajorCurriculum {
  static Database? _database;
  final curriculumService = CurriculumService();

  static final MajorCurriculum _instance = MajorCurriculum._internal();
  factory MajorCurriculum() => _instance;
  MajorCurriculum._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'curriculum_major.db');
    return await openDatabase(
      path,
      version: 2, // 升级版本号以触发 onUpgrade
      onCreate: (db, version) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await _createTables(db);
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 简单处理：删除旧表重建（数据将在下次同步时重新拉取）
          await db.execute('DROP TABLE IF EXISTS major_course');
          await db.execute('DROP TABLE IF EXISTS course');
          await db.execute('DROP TABLE IF EXISTS major');
          await db.execute('DROP TABLE IF EXISTS college');
          await db.execute('DROP TABLE IF EXISTS year');
          await _createTables(db);
          await _createIndexes(db);
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE year (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER UNIQUE NOT NULL
      )
    ''');

    // college 表增加 code 字段，同时保留 name 字段，添加两个唯一约束
    await db.execute('''
      CREATE TABLE college (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        year_id INTEGER NOT NULL,
        FOREIGN KEY (year_id) REFERENCES year(id) ON DELETE CASCADE,
        UNIQUE(year_id, code),
        UNIQUE(year_id, name)
      )
    ''');

    // major 表增加 code 字段，同时保留 name 字段，添加两个唯一约束
    await db.execute('''
      CREATE TABLE major (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        college_id INTEGER NOT NULL,
        FOREIGN KEY (college_id) REFERENCES college(id) ON DELETE CASCADE,
        UNIQUE(college_id, code),
        UNIQUE(college_id, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE course (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        credit REAL NOT NULL,
        total INTEGER NOT NULL,
        lecture INTEGER NOT NULL,
        lab INTEGER NOT NULL,
        practice INTEGER NOT NULL,
        other INTEGER NOT NULL,
        weekly REAL NOT NULL,
        main_category TEXT NOT NULL,
        sub_category TEXT NOT NULL,
        tertiary_category TEXT,
        requirement TEXT NOT NULL,
        nature TEXT NOT NULL,
        importance TEXT NOT NULL,
        assessment_method TEXT NOT NULL,
        identification TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE major_course (
        major_id INTEGER NOT NULL,
        course_id INTEGER NOT NULL,
        PRIMARY KEY (major_id, course_id),
        FOREIGN KEY (major_id) REFERENCES major(id) ON DELETE CASCADE,
        FOREIGN KEY (course_id) REFERENCES course(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_year_year ON year(year)');
    await db.execute(
      'CREATE INDEX idx_college_name_year ON college(name, year_id)',
    );
    await db.execute(
      'CREATE INDEX idx_major_name_college ON major(name, college_id)',
    );
    await db.execute(
      'CREATE INDEX idx_course_main_cat ON course(main_category)',
    );
    await db.execute('CREATE INDEX idx_course_sub_cat ON course(sub_category)');
  }

  // ========== 私有辅助方法（查找ID） ==========

  Future<int?> _findYearId(int year) async {
    final db = await database;
    final result = await db.query('year', where: 'year = ?', whereArgs: [year]);
    return result.isNotEmpty ? result.first['id'] as int : null;
  }

  Future<int?> _findCollegeId(College college, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT c.id FROM college c
      INNER JOIN year y ON c.year_id = y.id
      WHERE c.name = ? AND y.year = ?
    ''',
      [college.name, year],
    );
    return result.isNotEmpty ? result.first['id'] as int : null;
  }

  Future<int?> _findMajorId(Major major, College college, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT m.id FROM major m
      INNER JOIN college c ON m.college_id = c.id
      INNER JOIN year y ON c.year_id = y.id
      WHERE m.name = ? AND c.name = ? AND y.year = ?
    ''',
      [major.name, college.name, year],
    );
    return result.isNotEmpty ? result.first['id'] as int : null;
  }

  // ========== 公共插入接口 ==========

  Future<int> insertYear(int year) async {
    final db = await database;
    try {
      return await db.insert('year', {'year': year});
    } catch (e) {
      return -1;
    }
  }

  Future<int> insertCollege(College college, int year) async {
    final db = await database;
    final yearId = await _findYearId(year);
    if (yearId == null) return -1;
    try {
      return await db.insert('college', {
        'code': college.code, // 新增 code 字段
        'name': college.name,
        'year_id': yearId,
      });
    } catch (e) {
      return -1;
    }
  }

  Future<int> insertMajor(Major major, College college, int year) async {
    final db = await database;
    final collegeId = await _findCollegeId(college, year);
    if (collegeId == null) return -1;
    try {
      return await db.insert('major', {
        'code': major.code, // 新增 code 字段
        'name': major.name,
        'college_id': collegeId,
      });
    } catch (e) {
      return -1;
    }
  }

  /// 插入课程到指定专业
  Future<int> insertItem(
    Course course,
    Major major,
    College college,
    int year,
  ) async {
    final db = await database;
    final majorId = await _findMajorId(major, college, year);
    if (majorId == null) return -1;

    int courseId;
    try {
      courseId = await db.insert('course', {
        'code': course.code,
        'name': course.name,
        'credit': course.credit,
        'total': course.creditHour.total,
        'lecture': course.creditHour.lecture,
        'lab': course.creditHour.lab,
        'practice': course.creditHour.practice,
        'other': course.creditHour.other,
        'weekly': course.creditHour.weekly,
        'main_category': course.mainCategory,
        'sub_category': course.subCategory,
        'tertiary_category': course.tertiaryCategory ?? '',
        'requirement': course.requirement.name,
        'nature': course.nature.name,
        'importance': course.importance.name,
        'assessment_method': course.assessmentMethod.name,
        'identification': course.identification,
      });
    } catch (e) {
      final existing = await db.query(
        'course',
        where: 'code = ?',
        whereArgs: [course.code],
      );
      if (existing.isEmpty) return -1;
      courseId = existing.first['id'] as int;
    }

    try {
      await db.insert('major_course', {
        'major_id': majorId,
        'course_id': courseId,
      });
      return courseId;
    } catch (e) {
      return courseId;
    }
  }

  // ========== 查询接口（返回 List<Course>） ==========

  /// 将数据库行转换为 Course 对象
  Course _courseFromMap(Map<String, dynamic> map) {
    return Course(
      map['code'],
      map['name'],
      (map['credit'] as num).toDouble(),
      CreditHour(
        map['total'],
        map['lecture'],
        map['lab'],
        map['practice'],
        map['other'],
        (map['weekly'] as num).toDouble(),
      ),
      map['main_category'],
      map['sub_category'],
      map['tertiary_category'] ?? '',
      CourseRequirement.parse(map['requirement']),
      CourseNature.parse(map['nature']),
      CourseImportance.parse(map['importance']),
      AssessmentMethod.parse(map['assessment_method']),
      map['identification'],
    );
  }

  /// 接口1：同时指定年份、学院、专业查询所有课程
  Future<List<Course>> getCoursesByYearCollegeMajor(
    int year,
    College college,
    Major major,
  ) async {
    final db = await database;
    final results = await db.rawQuery(
      '''
      SELECT c.* FROM course c
      INNER JOIN major_course mc ON c.id = mc.course_id
      INNER JOIN major m ON mc.major_id = m.id
      INNER JOIN college col ON m.college_id = col.id
      INNER JOIN year y ON col.year_id = y.id
      WHERE y.year = ? AND col.name = ? AND m.name = ?
    ''',
      [year, college.name, major.name],
    );
    return results.map((map) => _courseFromMap(map)).toList();
  }

  Future<List<Major>> getMajorsByYearCollege(int year, College college) async {
    final db = await database;
    final results = await db.rawQuery(
      '''
    SELECT DISTINCT m.code, m.name FROM major m
    INNER JOIN college col ON m.college_id = col.id
    INNER JOIN year y ON col.year_id = y.id
    WHERE y.year = ? AND col.name = ?
    ORDER BY m.name
    ''',
      [year, college.name],
    );
    return results
        .map((row) => Major(row['code'] as String, row['name'] as String))
        .toList();
  }

  /// 接口3：根据任意组合条件查询课程
  Future<List<Course>> searchCourses(Map<String, String?> filters) async {
    final db = await database;

    String sql = 'SELECT DISTINCT c.* FROM course c';
    List<dynamic> params = [];

    final bool needMajor =
        filters.containsKey('major') ||
        filters.containsKey('college') ||
        filters.containsKey('year');

    if (needMajor) {
      sql += '''
        INNER JOIN major_course mc ON c.id = mc.course_id
        INNER JOIN major m ON mc.major_id = m.id
        INNER JOIN college col ON m.college_id = col.id
        INNER JOIN year y ON col.year_id = y.id
      ''';
    }

    List<String> conditions = [];

    final courseFields = [
      'main_category',
      'sub_category',
      'tertiary_category',
      'requirement',
      'nature',
      'importance',
      'assessment_method',
      'identification',
    ];
    for (var field in courseFields) {
      if (filters.containsKey(field) && filters[field] != null) {
        conditions.add('c.$field = ?');
        params.add(filters[field]);
      }
    }

    if (filters.containsKey('year') && filters['year'] != null) {
      conditions.add('y.year = ?');
      params.add(int.parse(filters['year']!));
    }
    if (filters.containsKey('college') && filters['college'] != null) {
      conditions.add('col.name = ?');
      params.add(filters['college']);
    }
    if (filters.containsKey('major') && filters['major'] != null) {
      conditions.add('m.name = ?');
      params.add(filters['major']);
    }

    if (conditions.isNotEmpty) {
      sql += ' WHERE ${conditions.join(' AND ')}';
    }

    final results = await db.rawQuery(sql, params);
    return results.map((map) => _courseFromMap(map)).toList();
  }

  Future<bool> hasYearData(int year) async {
    final db = await database;
    final result = await db.query('year', where: 'year = ?', whereArgs: [year]);
    return result.isNotEmpty;
  }

  Future<List<College>> getAllColleges() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT code, name FROM college GROUP BY code ORDER BY name
    ''');
    return result
        .map((row) => College(row['code'] as String, row['name'] as String))
        .toList();
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ========== 数据更新与维护方法 ==========

  Future<bool> hasYear(int year) async {
    final db = await database;
    final result = await db.query('year', where: 'year = ?', whereArgs: [year]);
    return result.isNotEmpty;
  }

  Future<void> deleteYear(int year) async {
    final db = await database;
    await db.delete('year', where: 'year = ?', whereArgs: [year]);
  }

  Future<void> updateYear(int year) async {
    logInfo('正在更新 $year 的数据');

    if (await hasYear(year)) await deleteYear(year);

    await insertYear(year);

    final colleges = await curriculumService.getCollegeList();
    for (final college in colleges) {
      await updateCollege(college, year);
    }

    logInfo('$year 更新完成');
  }

  /// 检查指定年份下是否存在某学院
  Future<bool> hasCollege(College college, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 1 FROM college c
      INNER JOIN year y ON c.year_id = y.id
      WHERE c.name = ? AND y.year = ?
      LIMIT 1
      ''',
      [college.name, year],
    );
    return result.isNotEmpty;
  }

  /// 删除指定年份下的某学院（级联删除其下的专业及关联）
  Future<void> deleteCollege(College college, int year) async {
    final db = await database;
    final collegeId = await _findCollegeId(college, year);
    if (collegeId != null) {
      await db.delete('college', where: 'id = ?', whereArgs: [collegeId]);
    }
  }

  /// 更新指定学院的数据：先删除该学院及其下所有专业，再从远程拉取重新插入
  Future<void> updateCollege(College college, int year) async {
    logInfo(' 正在更新 $year-$college 的数据');

    if (await hasCollege(college, year)) await deleteCollege(college, year);

    final collegeId = await insertCollege(college, year);
    if (collegeId == -1) {
      logInfo('插入学院失败: ${college.name}');
      return;
    }

    final majorList = await curriculumService.getMajorList(year, college.code);
    for (final majorMap in majorList) {
      final major = Major(
        majorMap['code'] as String,
        majorMap['name'] as String,
      );
      final majorId = await insertMajor(major, college, year);
      if (majorId == -1) {
        logInfo('插入专业失败: ${major.name}');
        continue;
      }

      final courseList = await curriculumService.getCurriculum(
        year,
        college.code,
        majorMap['code'] as String,
      );
      for (final course in courseList) {
        await insertItem(course, major, college, year);
      }
    }

    logInfo(' $year-$college 更新完成');
  }

  /// 检查指定年份、学院下是否存在某专业
  Future<bool> hasMajor(Major major, College college, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 1 FROM major m
      INNER JOIN college c ON m.college_id = c.id
      INNER JOIN year y ON c.year_id = y.id
      WHERE m.name = ? AND c.name = ? AND y.year = ?
      LIMIT 1
      ''',
      [major.name, college.name, year],
    );
    return result.isNotEmpty;
  }

  /// 删除指定年份、学院下的某专业（级联删除其课程关联）
  Future<void> deleteMajor(Major major, College college, int year) async {
    final db = await database;
    final majorId = await _findMajorId(major, college, year);
    if (majorId != null) {
      await db.delete('major', where: 'id = ?', whereArgs: [majorId]);
    }
  }

  Future<void> checkUpdate() async {
    for (int i = AcademicYear.now.value; i >= 2024; i--) {
      if (!await hasYear(i)) await updateYear(i);
    }
  }
}
