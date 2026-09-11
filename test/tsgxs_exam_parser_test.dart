import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/library_edu/data/anti_corruption/tsgxs_exam_parser.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

/// 答题页解析测试。
///
/// fixture 为 2026-09-10 抓包原文(已确认不含账号/姓名等个人信息):
/// - `tsgxs_exam_page.html`:`/Web/Exam?cid=` 的答题页(含隐藏字段);
/// - `tsgxs_exam_question.json`:`/web/Exam/GetQueOpt` 的题干与选项响应。
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('开考页:隐藏字段解析出本次考试的完整会话', () {
    final page = parseTsgxsExamPage(_fixture('tsgxs_exam_page.html'));

    expect(page.passed, isFalse);
    expect(page.canAnswer, isTrue);
    final session = page.session!;
    expect(session.examRecordDetailsId, 'f741c1aa-7c0f-45b1-80bc-2250bf2d3b04');
    expect(session.chapterId, '7f6d456b-2372-4b80-8e5a-0f6bf8c979c4');
    expect(session.questionIds.length, 5);
    expect(session.questionIds.first, 'a4beb4bc-23db-436c-8321-34b5c1c486c2');
    expect(session.examinations, 1);
    expect(session.length, 5);
    expect(session.isChapterExam, isTrue);
  });

  test('已通过页:识别通过状态并给出下一章', () {
    const html = '<html><body><div>您已通过本章节考试,请点击进入下一章节</div>'
        '<a href="/Web/Chapter/Index/11111111-2222-3333-4444-555555555555">下一章</a>'
        '</body></html>';
    final page = parseTsgxsExamPage(html);

    expect(page.passed, isTrue);
    expect(page.nextChapterId, '11111111-2222-3333-4444-555555555555');
    expect(page.session, isNull);
    expect(page.canAnswer, isFalse);
  });

  test('题干页:题型判别与选项映射', () {
    final json =
        jsonDecode(_fixture('tsgxs_exam_question.json')) as Map<String, dynamic>;
    final q = parseTsgxsQuestion(json);

    expect(q.id, 'a4beb4bc-23db-436c-8321-34b5c1c486c2');
    expect(q.chapterId, '9605f523-8b0e-416d-a084-6d3930a51468');
    expect(q.kind, TsgxsQuestionKind.single);
    expect(q.kindName, '单选题');
    expect(q.content, contains('图书馆自习室开放时间'));
    expect(q.options.length, 4);
    expect(q.options.first.code, 'A');
    expect(q.optionById(q.options[2].id)!.code, 'C');
    expect(q.codesOf([q.options[1].id, q.options[3].id]), 'B、D');
    expect(q.kind.isText, isFalse);
  });

  test('评分响应:错误 + 正确答案 + 可用道具', () {
    final json =
        jsonDecode(_fixture('tsgxs_exam_question.json')) as Map<String, dynamic>;
    final q = parseTsgxsQuestion(json);
    final res = parseTsgxsAnswerResult({
      'Success': 1,
      'isCorrect': false,
      'isRestart': false,
      'examQuestion': {
        'tid': '883881FA-6BC4-48C8-B5A8-DD84255F411D',
        'answer': q.options[3].id,
        'answeranalysis': '自习室开放时间 7:00—23:00。',
      },
      'myPropsInfos': [
        {'id': '22222222-2222-4222-8222-222222222222', 'title': '时光倒流'}
      ],
    });

    expect(res.graded, isTrue);
    expect(res.isCorrect, isFalse);
    expect(res.failedChapter, isFalse);
    expect(res.myProps.single.title, '时光倒流');
    expect(q.codesOf(res.correctRaw.split(',')), 'D');
    expect(res.analysis, contains('7:00—23:00'));
  });

  test('评分响应:闯关失败标志(错题阈值由服务端判定)', () {
    final res = parseTsgxsAnswerResult({
      'Success': 1,
      'isCorrect': false,
      'isRestart': true,
      'examQuestion': {'answer': '', 'answeranalysis': ''},
    });

    expect(res.graded, isTrue);
    expect(res.failedChapter, isTrue);
    expect(res.correctRaw, isEmpty);
  });

  test('评分响应:本关已通过(Success=-1)与下一关 id', () {
    final res = parseTsgxsAnswerResult({
      'Success': -1,
      'NCid': '33333333-3333-4333-8333-333333333333',
      'Msg': '本关已通过,将进入下一关!',
      'JumpWhich': 2,
    });

    expect(res.graded, isFalse);
    expect(res.chapterPassed, isTrue);
    expect(res.nextChapterId, '33333333-3333-4333-8333-333333333333');
    expect(res.jumpWhich, 2);
  });

  test('结算响应:通过 / 获得道具 / 下一章 / 需重新闯关', () {
    final ok = parseTsgxsFinishResult({
      'Success': 1,
      'NCid': '44444444-4444-4444-8444-444444444444',
      'Examinations': 1,
      'PropsInfos': [
        {'id': '55555555-5555-4555-8555-555555555555', 'title': '知识护盾'}
      ],
    });
    expect(ok.passed, isTrue);
    expect(ok.nextChapterId, '44444444-4444-4444-8444-444444444444');
    expect(ok.props.single.title, '知识护盾');
    expect(ok.needRestart, isFalse);

    final restart = parseTsgxsFinishResult({'Success': -2, 'Msg': '闯关失败'});
    expect(restart.passed, isFalse);
    expect(restart.needRestart, isTrue);

    final nilGuid = parseTsgxsFinishResult({
      'Success': -1,
      'NCid': tsgxsNilGuid,
      'JumpWhich': 2,
    });
    expect(nilGuid.nextChapterId, isNull, reason: '全零 GUID 视为无下一章');
  });

  test('题型判别:四种选择题型与文本题、未知题型', () {
    expect(TsgxsQuestionKind.fromId('883881fa-6bc4-48c8-b5a8-dd84255f411d'),
        TsgxsQuestionKind.single);
    expect(TsgxsQuestionKind.fromId('9CEFF19F-54AC-48A8-A378-C8D81F3F52CE'),
        TsgxsQuestionKind.multi);
    expect(TsgxsQuestionKind.fromId('A5FFE86A-5F83-446E-B12E-73ADC1544E7C'),
        TsgxsQuestionKind.judge);
    expect(TsgxsQuestionKind.fromId('C478855E-31EC-4E5B-9692-B9CFF77EDB8D'),
        TsgxsQuestionKind.fill);
    expect(TsgxsQuestionKind.fill.isText, isTrue);
    expect(TsgxsQuestionKind.copy.isText, isTrue);
    expect(TsgxsQuestionKind.multi.isText, isFalse);
    expect(TsgxsQuestionKind.fromId('deadbeef'), TsgxsQuestionKind.unknown);
    expect(TsgxsQuestionKind.fromId(null), TsgxsQuestionKind.unknown);
  });

  test('隐藏字段解析:模板占位不覆盖真实值、坏值不误判为 GUID', () {
    final fields = tsgxsHiddenFields(
        '<input value="v1" id="a" /><input value="v2" id="a" />');
    expect(fields['a'], 'v1');

    expect(isGuid('f741c1aa-7c0f-45b1-80bc-2250bf2d3b04'), isTrue);
    expect(isGuid('{{examQuestion.id}}'), isFalse);
    expect(isGuid(''), isFalse);

    // 缺隐藏字段的页面 → 不给会话,只回页面明文提示。
    final broken = parseTsgxsExamPage('<html><body>请先完成学习</body></html>');
    expect(broken.session, isNull);
    expect(broken.message, contains('请先完成学习'));
  });

  test('题库条目:JSON 往返与选项 id 解析', () {
    const entry = TsgxsBankEntry(
      questionId: 'q-1',
      answer: 'a1,a2',
      codes: ['A', 'B'],
      kind: 'multi',
      updatedAt: '2026-09-10T12:00:00',
    );
    final back = TsgxsBankEntry.fromJson(entry.toJson());

    expect(back.questionId, 'q-1');
    expect(back.answer, 'a1,a2');
    expect(back.optionIds, ['a1', 'a2']);
    expect(back.codes, ['A', 'B']);
    expect(back.kind, 'multi');
  });

  test('会话登录态判定:必须有 cblogin 签发的 uid', () {
    // 已登录(实测主账号缓存形态)。
    expect(
      TsgxsAuthRemoteDataSource.hasUid(
          'ASP.NET_SessionId=abc123; from=0; uid=c6c878af-0000-4000-8000-000000000000'),
      isTrue,
    );
    // uid 在首位同样成立。
    expect(
      TsgxsAuthRemoteDataSource.hasUid('uid=x; from=0'),
      isTrue,
    );
    // 匿名态:只有预热产物(实测未通关账号的坏缓存)→ 必须判失效。
    expect(
      TsgxsAuthRemoteDataSource.hasUid('ASP.NET_SessionId=bye456; from=0'),
      isFalse,
    );
    expect(TsgxsAuthRemoteDataSource.hasUid(''), isFalse);
  });

  test('首次登录:从 success=-2 跳转地址取待激活 uid', () {
    expect(
      parseTsgxsPendingUid('http://tsgxs.jxufe.cn/Web/User?success=-2&uid='
          'c6c878af-1111-4111-8111-111111111111'),
      'c6c878af-1111-4111-8111-111111111111',
    );
    // 无 uid / 模板占位 → null(不能把 {{uid}} 当成登录态)。
    expect(
        parseTsgxsPendingUid('http://tsgxs.jxufe.cn/Web/User?success=-2'), isNull);
    expect(parseTsgxsPendingUid('http://x/Web/User?uid=%7B%7Buid%7D%7D'), isNull);
  });

  test('登录页皮肤解析:取被勾选的 radio(书生版)而非页面里其它 tid', () {
    // fixture 为真实登录页的「选择版式」弹框(三个 radio,仅书生版 checked)。
    final html = _fixture('tsgxs_login_anon_theme.html');
    expect(parseTsgxsThemeId(html), '5d037bb3-12c5-4554-a3c2-d128766dd025');
    // 只有裸 tid= 链接时回退取第一个。
    expect(
      parseTsgxsThemeId(
          '<a href="/Web/Chapter/Index/x?tid=e3e409c4-7b51-4a75-a58f-92201dd6e660">'),
      'e3e409c4-7b51-4a75-a58f-92201dd6e660',
    );
    expect(parseTsgxsThemeId('<html></html>'), isNull);
  });
}
