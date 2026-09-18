/// 学科竞赛（第二课堂 · 申请与公示）解析与口径守卫。
///
/// fixture 全是**真实抓取**（2026-09-16，ssp.jxufe.edu.cn 团委模块，已裁掉 script/style），
/// 页面结构一变这里就会红：
/// `_competition_apply_list.html` / `_competition_gs_list.html` /
/// `_competition_find_game.html` / `_competition_find_student.html` /
/// `_competition_apply_detail.html` / `_competition_publicity_detail.html` /
/// `_competition_awards.json`。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/competition_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/competition_image_picker.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_apply_form_screen.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

String _source(String path) => File(path).readAsStringSync();

const _datasourcePath =
    'lib/features/comprehensive_service/data/datasource/'
    'competition_remote_datasource.dart';
const _repositoryPath =
    'lib/features/comprehensive_service/data/competition_repository.dart';
const _screenPath =
    'lib/features/comprehensive_service/presentation/competition_screen.dart';
const _formPath =
    'lib/features/comprehensive_service/presentation/'
    'competition_apply_form_screen.dart';

void main() {
  group('我的申请列表（apply_list.html）', () {
    final items = parseCompetitionApplyList(
      _fixture('_competition_apply_list.html'),
    );

    test('解析出全部行并取到行 id', () {
      expect(items, hasLength(3));
      expect(items.map((e) => e.id), [199963, 199962, 199960]);
    });

    test('字段与官网列一一对应', () {
      final first = items.first;
      expect(first.year, '2026');
      expect(first.studentId, '0000000');
      expect(first.studentName, '某同学');
      expect(first.gameName, startsWith('中国高校计算机大赛'));
      expect(first.type, CompetitionType.individual);
      expect(first.applyTime, '2026-07-06');
      expect(first.status, '未审批');
      expect(first.pending, isTrue);
      expect(first.approved, isFalse);
    });

    test('结构不符时不抛异常，返回空表', () {
      expect(
        parseCompetitionApplyList('<html><body>没有表格</body></html>'),
        isEmpty,
      );
    });
  });

  group('竞赛公示列表（gs_list.html）', () {
    final html = _fixture('_competition_gs_list.html');
    final items = parseCompetitionPublicityList(html);

    test('解析 20 行（官网每页 20 条）', () {
      expect(items, hasLength(20));
      expect(items.first.id, 202354);
    });

    test('字段：学号 / 姓名 / 学院 / 班级 / 比赛 / 类型 / 时间', () {
      final first = items.first;
      expect(first.studentId, '0254173');
      expect(first.studentName, '张艺馨');
      expect(first.college, '计算机与人工智能学院');
      expect(first.className, '25计算机4班');
      expect(first.gameName, '全国大学生数学建模竞赛');
      expect(first.type, CompetitionType.team);
      expect(first.time, '2026-08-26');
    });

    test(r'总页数取自分页条的 $.pageSkip(N)（公示 13 页）', () {
      expect(competitionTotalPages(html), 13);
    });
  });

  group('比赛目录（find_game.do）', () {
    final html = _fixture('_competition_find_game.html');
    final games = parseCompetitionGameList(html);

    test('解析 20 行，gameId 与赛别来自行内 radio', () {
      expect(games, hasLength(20));
      final first = games.first;
      expect(first.id, 7584);
      expect(first.level, '国赛');
      expect(first.name, '香港会计师公会 QP 个案分析比赛【国赛】');
      expect(first.year, '2026');
      expect(first.college, '会计学院');
    });

    test('奖项前缀 = 【赛别】', () {
      expect(games.first.awardPrefix, '【国赛】');
      const noLevel = CompetitionGame(
        id: 1,
        year: '2026',
        name: 'x',
        level: '',
        college: '',
        time: '',
        url: '',
      );
      expect(noLevel.awardPrefix, '');
    });

    test('总页数 208（比赛目录很长，必须靠搜索）', () {
      expect(competitionTotalPages(html), 208);
    });
  });

  group('学生检索（find_student.do）', () {
    final students = parseCompetitionStudentList(
      _fixture('_competition_find_student.html'),
    );

    test('解析 20 行；rowId = radio value，studentId = 学号列', () {
      expect(students, hasLength(20));
      expect(students.first.rowId, 350377);
      expect(students.first.studentId, '826200545');
      expect(students.first.name, '黄天乐');
      expect(students.first.college, '虚拟现实（VR）现代产业学院');
      expect(students.first.className, '2026级虚拟现实技术与应用学硕班');
    });

    test('team 字段用内部 id（radio value），不是学号', () {
      expect(students.first.teamValue, '350377');
      expect(students.first.teamValue, isNot(students.first.studentId));
      // 官网 find_student.do 的 setGame() 读的就是 :radio:checked 的 value。
      final source = _source(_datasourcePath);
      expect(source, contains("'team': memberIds.join(';')"));
    });
  });

  group('详情页（label + 只读控件）', () {
    test('申请详情：比赛信息与附件地址', () {
      final detail = parseCompetitionDetail(
        _fixture('_competition_apply_detail.html'),
      );
      expect(detail.valueOf('比赛名称'), startsWith('中国高校计算机大赛'));
      expect(detail.valueOf('比赛年份'), '2026');
      expect(detail.valueOf('比赛类别'), 'II类国赛');
      expect(detail.valueOf('比赛级别'), '省级以上');
      expect(detail.attachments, hasLength(1));
      expect(detail.attachments.first, endsWith('.jpg'));
    });

    test('公示详情：申请人与班级', () {
      final detail = parseCompetitionDetail(
        _fixture('_competition_publicity_detail.html'),
      );
      expect(detail.valueOf('申请人姓名'), '肖雅');
      expect(detail.valueOf('学号'), '0252633');
      expect(detail.valueOf('行政班级'), '25人工智能1班');
      expect(detail.fields, isNotEmpty);
    });

    test('公示详情 · 团队记录：没有申请人字段，改出团队成员表', () {
      final detail = parseCompetitionDetail(
        _fixture('_competition_publicity_team_detail.html'),
      );
      expect(detail.valueOf('申请人姓名'), '');
      expect(detail.valueOf('比赛名称'), '全国大学生数学建模竞赛');
      expect(detail.valueOf('学生提交的奖项'), '【校赛】一等奖');
      expect(detail.valueOf('最终获得奖项'), '', reason: '还没评出最终奖项时应为空串');
      final members = detail.fields
          .where((f) => f.label.startsWith('团队成员'))
          .toList();
      expect(members, hasLength(3));
      expect(members.first.label, '团队成员 1');
      expect(members.first.value, contains('何欣俞'));
      expect(members.first.value, contains('0245651'));
      expect(members[1].value, contains('张艺馨'));
    });

    test('解析不到表单时不抛异常', () {
      final detail = parseCompetitionDetail('<html><body>x</body></html>');
      expect(detail.isEmpty, isTrue);
      expect(detail.valueOf('学号'), '');
    });
  });

  group('奖项 JSON（getCredit.do）', () {
    final awards = parseCompetitionAwards(
      _fixture('_competition_awards.json'),
      gameId: 7584,
    );

    test('解析奖项与分值', () {
      expect(awards, hasLength(4));
      expect(awards.first.name, '三等奖');
      expect(awards.first.score, 2);
      expect(awards.last.name, '特等奖');
      expect(awards.last.score, 5);
      expect(awards.every((a) => a.gameId == 7584), isTrue);
    });

    test('remark = 【赛别】奖项名（与官网 JS 拼法一致）', () {
      const game = CompetitionGame(
        id: 7584,
        year: '2026',
        name: 'x',
        level: '国赛',
        college: '',
        time: '',
        url: '',
      );
      expect(awards.last.remarkFor(game), '【国赛】特等奖');
    });

    test('非 JSON / 空数据 → 空表', () {
      expect(parseCompetitionAwards('<html>error</html>', gameId: 1), isEmpty);
      expect(parseCompetitionAwards('[]', gameId: 1), isEmpty);
    });
  });

  group('写接口应答（add.do / delete.do / upload.do）', () {
    test('成功应答', () {
      final reply = CompetitionJsonReply.parse(
        '{"type":"success","content":"申请成功","data":null}',
      );
      expect(reply.ok, isTrue);
      expect(reply.message, '申请成功');
    });

    test('上传应答里取附件 id', () {
      final reply = CompetitionJsonReply.parse(
        '{"type":"success","content":"上传成功！","data":[{"id":641432,'
        '"name":"a.png","path":"/upload/base/indexdownload/"}]}',
      );
      expect(reply.ok, isTrue);
      expect(reply.attachmentIds, [641432]);
    });

    test('失败 / 非 JSON 应答', () {
      expect(
        CompetitionJsonReply.parse('{"type":"error","content":"无权"}').ok,
        isFalse,
      );
      expect(CompetitionJsonReply.parse('<html>400</html>').ok, isFalse);
    });
  });

  group('分页与筛选参数（官网口径）', () {
    test('第 1 页带 pageInit=yes 才会应用筛选', () {
      final params = competitionPageRequestParams(
        page: 1,
        filters: {
          'search_like_parent.gameName': '蓝桥杯',
          'search_eq_parent.year': '',
        },
      );
      expect(params['pageInit'], 'yes');
      expect(params['pageNumber'], '1');
      expect(params['pageSize'], '20');
      expect(params['search_like_parent.gameName'], '蓝桥杯');
      expect(params.containsKey('search_eq_parent.year'), isFalse);
    });

    test('翻页必须重复筛选参数、且不能带 pageInit', () {
      final params = competitionPageRequestParams(
        page: 3,
        filters: {'search_like_parent.gameName': '蓝桥杯'},
      );
      expect(params.containsKey('pageInit'), isFalse);
      expect(params['pageNumber'], '3');
      expect(params['search_like_parent.gameName'], '蓝桥杯');
    });
  });

  group('获奖等级（公示列表无等级列 → 详情取）', () {
    test('「【级别】奖项」拆成级别 + 奖项', () {
      final level = CompetitionAwardLevel.parse('【省赛】二等奖');
      expect(level.level, '省赛');
      expect(level.award, '二等奖');
      expect(level.label, '省赛 · 二等奖');
      expect(level.isNotEmpty, isTrue);
    });

    test('「参与未获奖」照原样保留（它也是一种等级）', () {
      expect(CompetitionAwardLevel.parse('【校赛】参与未获奖').label, '校赛 · 参与未获奖');
    });

    test('去掉官网附带的分值后缀', () {
      expect(CompetitionAwardLevel.parse('特等奖(2)分').label, '特等奖');
      expect(CompetitionAwardLevel.parse('一等奖（1.5）分').label, '一等奖');
      expect(CompetitionAwardLevel.parse('【国赛】三等奖 (2)分').label, '国赛 · 三等奖');
    });

    test('空值 / 「无」→ 没有等级', () {
      for (final raw in const ['', '   ', '无', '无奖项']) {
        expect(
          CompetitionAwardLevel.parse(raw).isEmpty,
          isTrue,
          reason: '「$raw」应视为没有等级',
        );
      }
    });

    test('真实 fixture：个人公示记录', () {
      final detail = parseCompetitionDetail(
        _fixture('_competition_publicity_detail.html'),
      );
      expect(
        competitionAwardLevelOf(detail),
        const CompetitionAwardLevel(level: '校赛', award: '参与未获奖'),
        reason: '详情里「最终获得奖项」为空 → 回退「学生提交的奖项」',
      );
    });

    test('真实 fixture：团队公示记录', () {
      final detail = parseCompetitionDetail(
        _fixture('_competition_publicity_team_detail.html'),
      );
      expect(
        competitionAwardLevelOf(detail),
        const CompetitionAwardLevel(level: '校赛', award: '一等奖'),
      );
    });

    test('「最终获得奖项」优先，赛别沿用提交项的【】前缀', () {
      const detail = CompetitionDetail(
        fields: [
          CompetitionDetailField(label: '学生提交的奖项', value: '【省赛】二等奖'),
          CompetitionDetailField(label: '最终获得奖项', value: '一等奖(4)分'),
        ],
      );
      expect(
        competitionAwardLevelOf(detail),
        const CompetitionAwardLevel(level: '省赛', award: '一等奖'),
      );
    });

    test('两个字段都没有 → 空等级（界面不显示胶囊）', () {
      expect(competitionAwardLevelOf(CompetitionDetail.empty).isEmpty, isTrue);
    });
  });

  group('接口 / 字段漂移守卫', () {
    final datasource = _source(_datasourcePath);

    test('端点路径与官网一致', () {
      for (final path in const [
        '/admin/tzz/dektSubjectGame/apply_list.html',
        '/admin/tzz/dektSubjectGame/gs_list.html',
        '/admin/tzz/dektSubjectGame/find_game.do',
        '/admin/tzz/dektSubjectGame/find_student.do',
        '/admin/tzz/dektSubjectGame/getCredit.do',
        '/admin/tzz/dektSubjectGame/detail.html',
        '/admin/tzz/dektSubjectGame/xd_detail.html',
        '/admin/tzz/dektSubjectGame/add.do',
        '/admin/tzz/dektSubjectGame/delete.do',
        '/admin/accessory/upload.do',
      ]) {
        expect(datasource, contains(path), reason: '缺少端点 $path');
      }
    });

    test('写请求字段拼法：team 分号、enclosure 逗号、ids[] 数组', () {
      expect(datasource, contains("'team': memberIds.join(';')"));
      expect(datasource, contains("'enclosure': attachmentIds.join(',')"));
      expect(datasource, contains("'ids[]'"));
      expect(datasource, contains("'system_dir_path': 'base/indexdownload'"));
      expect(datasource, contains("'accessorys'"));
    });

    test('上传类型来自文件名（官网只收 jpg/jpeg/png）', () {
      expect(competitionImageMimeOf('a.JPG'), 'image/jpeg');
      expect(competitionImageMimeOf('a.png'), 'image/png');
      expect(competitionImageMimeOf('a.pdf'), 'application/octet-stream');
    });

    test('会话失效走统一的 SspSessionExpiredException + 刷新重试', () {
      expect(datasource, contains('SspSessionExpiredException'));
      final repository = _source(_repositoryPath);
      expect(repository, contains('refreshSessionId'));
      expect(repository, contains('综合管理平台会话刷新失败，请稍后重试'));
    });

    test('表单前端校验的硬口径（官网 add.do 不做服务端校验）', () {
      final form = _source(_formPath);
      expect(form, contains('请选择比赛'));
      expect(form, contains('请选择获得奖项'));
      expect(form, contains('请上传证书图片'));
      expect(form, contains('团队申请成员不能少于'));
      expect(form, contains('不做服务端校验'));
      expect(competitionMaxAttachmentBytes, 3072 * 1024);
      expect(competitionMaxAttachments, 10);
      expect(competitionMinTeamMembers, 2);
    });

    test('页面：两个 Tab + 申请/公示入口都在', () {
      final screen = _source(_screenPath);
      expect(screen, contains("Tab(text: '我的申请')"));
      expect(screen, contains("Tab(text: '竞赛公示')"));
      expect(screen, contains('申请竞赛'));
      expect(screen, contains('CompetitionPagerBar'));
    });

    test('公示等级：列表没有这一列 → 只走「逐行拉详情」的 provider', () {
      // 公示列表页的列里没有奖项（真实页面：序号/学号/姓名/学院/班级/比赛名称/类型/时间/操作）
      final rows = parseCompetitionPublicityList(
        _fixture('_competition_gs_list.html'),
      );
      expect(rows, isNotEmpty);
      expect(rows.first.gameName, isNotEmpty);

      final providers = _source(
        'lib/features/comprehensive_service/data/providers/'
        'competition_providers.dart',
      );
      expect(providers, contains('competitionPublicityAwardProvider'));
      expect(providers, contains('competitionAwardLevelOf'));
      expect(providers, contains('fetchPublicityDetail'));

      final screen = _source(_screenPath);
      expect(screen, contains('competitionPublicityAwardProvider(('));
      expect(screen, contains('CompetitionAwardChip'));
    });
  });

  group('模型口径', () {
    test('申请类型由官网文本反推', () {
      expect(CompetitionType.fromLabel('团队'), CompetitionType.team);
      expect(CompetitionType.fromLabel('个人'), CompetitionType.individual);
      expect(CompetitionType.individual.formValue, '0');
      expect(CompetitionType.team.formValue, '1');
    });

    test('审批状态判定（未审批 / 通过 / 不通过）', () {
      CompetitionApply make(String status) => CompetitionApply(
        id: 1,
        year: '2026',
        studentId: '1',
        studentName: 'a',
        gameName: 'g',
        type: CompetitionType.individual,
        applyTime: '2026-01-01',
        status: status,
      );
      expect(make('未审批').pending, isTrue);
      expect(make('通过').pending, isFalse);
      expect(make('通过').approved, isTrue);
      expect(make('未通过').approved, isFalse);
    });
  });
}
