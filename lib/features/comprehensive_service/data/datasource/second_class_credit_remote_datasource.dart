import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/second_class_credit.dart';

/// 第二课堂学分数据源。
///
/// 两个页面均为登录后页面（需要 JSESSIONID）：
/// - 成绩单：`/admin/tzz/dektRecordSummary/schoolReport.html`
///   （学生信息 + 全部明细 + 总学分/有效学分 + 十二平台汇总）；
/// - 学分预警板：首页 `/admin/common/index.html` 内嵌的「学分预警」表格
///   （各板块已获/应获学分、认定标准、是否达标，以及阶段学分要求）。
///
/// 会话失效时服务端返回 302 或登录页 HTML，统一抛
/// [SspSessionExpiredException]，由上层刷新会话后重试。
class SecondClassCreditRemoteDataSource {
  final Dio _dio;

  SecondClassCreditRemoteDataSource(this._dio);

  static const _reportUrl = '/admin/tzz/dektRecordSummary/schoolReport.html';
  static const _homeUrl = '/admin/common/index.html';

  /// 拉取第二课堂成绩单。
  Future<SecondClassCreditReport> fetchCreditReport({
    required String sessionId,
  }) async {
    final body = await _getPage(_reportUrl, sessionId);
    return _parseReport(body);
  }

  /// 拉取学分预警板（首页内嵌表格）。
  Future<CreditBoardData> fetchCreditBoard({required String sessionId}) async {
    final body = await _getPage(_homeUrl, sessionId);
    return _parseBoard(body);
  }

  Future<String> _getPage(String path, String sessionId) async {
    final response = await _dio.get(
      path,
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$sessionId',
          'Referer': 'http://ssp.jxufe.edu.cn/admin/common/main.html',
        },
        followRedirects: false,
      ),
    );

    final status = response.statusCode ?? 0;

    // 3xx（登录页/失效页重定向）→ 会话已过期
    if (status >= 300 && status < 400) {
      throw SspSessionExpiredException();
    }

    if (status != 200) {
      throw Exception('请求失败: $status');
    }

    final body = response.data?.toString() ?? '';
    if (_looksLikeLoginRedirect(body)) {
      throw SspSessionExpiredException();
    }
    return body;
  }

  /// 判断响应体是否为登录页/失效页（authFailure 或 SSO 登录入口）。
  /// 仅当页面以 HTML 开头时才检测，避免误判业务数据。
  bool _looksLikeLoginRedirect(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('<!DOCTYPE html') && !trimmed.startsWith('<html')) {
      return false;
    }
    return trimmed.contains('authFailure') ||
        trimmed.contains('/sso/login') ||
        RegExp(r'<title>\s*登录').hasMatch(trimmed);
  }

  // ---- 成绩单解析 ----

  SecondClassCreditReport _parseReport(String html) {
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');
    // 页面含两张表：表 0 为抬头（标题/证书编号），表 1 为主体数据。
    Element? mainTable;
    for (final t in tables) {
      if (t.text.contains('获奖年份') && t.text.contains('总学分')) {
        mainTable = t;
        break;
      }
    }
    if (mainTable == null) {
      throw Exception('成绩单页面结构异常：未找到主表格');
    }

    final rows = mainTable.querySelectorAll('tr');
    // ---- 学生信息（前两行：姓名行/性别行）----
    SecondClassStudent? student;
    String name = '',
        studentId = '',
        college = '',
        gender = '',
        className = '',
        major = '';

    final recordRows = <Element>[];
    // 平台汇总：从「总学分」行开始到最后
    double totalCredit = 0, validCredit = 0;
    final platformCredits = <String, double>{};

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      final texts = cells.map((c) => _cellText(c)).toList();

      // 姓名行：姓名/学号/学院
      if (texts[0] == '姓名') {
        name = _valueAfter(texts, '姓名');
        studentId = _valueAfter(texts, '学号');
        college = _valueAfter(texts, '学院');
        continue;
      }
      // 性别行：性别/班级/专业
      if (texts[0] == '性别') {
        gender = _valueAfter(texts, '性别');
        className = _valueAfter(texts, '班级');
        major = _valueAfter(texts, '专业');
        continue;
      }
      // 明细记录行：第一个单元格为年份（可能为空=志愿服务总计行），
      // 特征：含学分（第 2 个 td）与所属平台（第 3 个 td）。
      if (cells.length >= 4 &&
          texts[0] != '获奖年份' &&
          (texts[0].isNotEmpty || texts[1].isNotEmpty)) {
        final creditText = texts[2].trim();
        final platform = texts[3].trim();
        if (_isCredit(creditText) && platform.isNotEmpty) {
          recordRows.add(row);
          continue;
        }
      }
      // 总学分行：总学分/有效学分
      if (texts[0] == '总学分' && cells.length >= 4) {
        totalCredit = double.tryParse(texts[1]) ?? 0;
        validCredit = double.tryParse(texts[3]) ?? 0;
        continue;
      }
      // 平台汇总行：形如「思想引领平台 0.5 学术论文平台 0」
      if (cells.length >= 4 && texts[0].endsWith('平台')) {
        final first = double.tryParse(texts[1]);
        final second = double.tryParse(texts[3]);
        if (first != null) {
          platformCredits[_trimPlatform(texts[0])] = first;
        }
        if (second != null && texts[2].endsWith('平台')) {
          platformCredits[_trimPlatform(texts[2])] = second;
        }
      }
    }

    if (studentId.isEmpty) {
      throw Exception('成绩单页面结构异常：未找到学生信息');
    }

    student = SecondClassStudent(
      name: name.isEmpty ? '未知' : name,
      studentId: studentId,
      college: college,
      gender: gender,
      className: className,
      major: major,
    );

    // ---- 解析明细行 ----
    final records = <SecondClassRecord>[];
    double volunteerHours = 0;
    for (final row in recordRows) {
      final cells = row.querySelectorAll('td');
      final texts = cells.map(_cellText).toList();
      final year = texts[0];
      final projectName = texts[1];
      final credit = double.tryParse(texts[2]) ?? 0;
      final platform = texts[3];
      // 志愿服务总计行：项目名形如「志愿服务总计24.0小时」
      final volMatch = RegExp(r'志愿服务总计([\d.]+)小时').firstMatch(projectName);
      if (volMatch != null) {
        volunteerHours = double.tryParse(volMatch.group(1) ?? '') ?? 0;
      }
      records.add(
        SecondClassRecord(
          year: year,
          projectName: projectName,
          credit: credit,
          platform: platform,
        ),
      );
    }

    return SecondClassCreditReport(
      student: student,
      records: records,
      totalCredit: totalCredit,
      validCredit: validCredit,
      platformCredits: platformCredits,
      volunteerHours: volunteerHours,
    );
  }

  // ---- 学分预警板解析 ----

  CreditBoardData _parseBoard(String html) {
    final document = html_parser.parse(html);

    // 定位学分预警表格：表头含「板块名称」「已获学分」。
    Element? boardTable;
    for (final t in document.querySelectorAll('table')) {
      if (t.text.contains('板块名称') &&
          t.text.contains('已获学分') &&
          t.text.contains('是否达标')) {
        boardTable = t;
        break;
      }
    }
    if (boardTable == null) {
      throw Exception('首页结构异常：未找到学分预警表格');
    }

    final rows = boardTable.querySelectorAll('tr');
    final boardRows = <CreditBoardRow>[];
    double totalEarned = 0, totalRequired = 0;
    bool totalPassed = false;

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) continue;
      final texts = cells.map(_cellText).toList();

      // 表头行
      if (texts[0] == '板块名称') continue;

      final name = texts[0];
      final earned = double.tryParse(texts[1]) ?? 0;
      final requiredText = texts[2];
      final required = double.tryParse(requiredText);
      final standard = texts[3].trim();
      final status = texts[4].trim();

      if (name == '总计') {
        totalEarned = earned;
        totalRequired = required ?? 0;
        totalPassed = status == '已达标';
        continue;
      }

      boardRows.add(
        CreditBoardRow(
          name: name,
          earned: earned,
          required: required,
          standard: standard.isEmpty ? null : standard,
          status: status.isEmpty ? null : status,
        ),
      );
    }

    // 阶段学分要求：学分预警表格内的 data-content（总计行旁 popover），
    // 用 <br> 分隔的阶段文案。
    final milestones = <String>[];
    final contentMatch = RegExp(
      r'data-content="([^"]*)"',
    ).firstMatch(boardTable.outerHtml);
    if (contentMatch != null) {
      final raw = contentMatch.group(1) ?? '';
      final parts = raw.split(RegExp(r'<br\s*/?>'));
      for (final p in parts) {
        final t = p.replaceAll('&nbsp;', ' ').trim();
        if (t.isNotEmpty) milestones.add(t);
      }
    }

    return CreditBoardData(
      rows: boardRows,
      totalEarned: totalEarned,
      totalRequired: totalRequired,
      totalPassed: totalPassed,
      milestones: milestones,
    );
  }

  // ---- 工具 ----

  static String _cellText(Element cell) =>
      cell.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _valueAfter(List<String> texts, String label) {
    final i = texts.indexOf(label);
    if (i >= 0 && i + 1 < texts.length) return texts[i + 1];
    return '';
  }

  static bool _isCredit(String text) {
    final v = double.tryParse(text);
    return v != null;
  }

  static String _trimPlatform(String name) =>
      name.endsWith('平台') ? name.substring(0, name.length - 2) : name;
}

/// 学分预警板数据（含总计与阶段要求）。
class CreditBoardData {
  final List<CreditBoardRow> rows;
  final double totalEarned;
  final double totalRequired;
  final bool totalPassed;
  final List<String> milestones;

  const CreditBoardData({
    required this.rows,
    required this.totalEarned,
    required this.totalRequired,
    required this.totalPassed,
    required this.milestones,
  });
}
