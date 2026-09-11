/// 新生入馆教育「闯关答题」领域模型。
///
/// 协议逆向自 `/Areas/Web/pc/js/ssb/exam.js`(2026-09-10 抓包):
/// - 开考页 `GET /Web/Exam?cid=<章节id>` 下发隐藏字段 `examRecordDetailsId` /
///   `zid` / `stIds`(题目 id 逗号串) / `examinations` / `eqLength`;
/// - 逐题 `GET /web/Exam/GetQueOpt?id=<题目id>` 取题干与选项;
/// - 逐题 `POST /web/Exam/GetAnswer` 提交评分(响应携带**该题正确答案**与解析);
/// - 末题后 `POST /web/exam/GetGameRole` 结算(通过 / 获得道具 / 进下一关)。
///
/// 注意:正确答案只在提交那一刻下发(题目前置请求里 `answer` 恒空、
/// `iscorrect` 恒 false),故题库只能靠逐题提交积累。
library;

/// 题型(服务端 tid GUID,取自 exam.js 的分支常量)。
enum TsgxsQuestionKind {
  single('883881FA-6BC4-48C8-B5A8-DD84255F411D', '单选题'),
  multi('9CEFF19F-54AC-48A8-A378-C8D81F3F52CE', '多选题'),
  judge('A5FFE86A-5F83-446E-B12E-73ADC1544E7C', '判断题'),
  fill('C478855E-31EC-4E5B-9692-B9CFF77EDB8D', '填空题'),
  copy('F1D41F14-79FC-4BB0-A721-F7DA6E734A3D', '抄写题'),
  unknown('', '未知题型');

  const TsgxsQuestionKind(this.id, this.label);

  final String id;
  final String label;

  static TsgxsQuestionKind fromId(String? tid) {
    final t = (tid ?? '').toUpperCase();
    if (t.isEmpty) return TsgxsQuestionKind.unknown;
    for (final k in TsgxsQuestionKind.values) {
      if (k.id.isNotEmpty && k.id == t) return k;
    }
    return TsgxsQuestionKind.unknown;
  }

  /// 文本输入题(填空 / 抄写)。
  bool get isText =>
      this == TsgxsQuestionKind.fill || this == TsgxsQuestionKind.copy;
}

/// 答题模式(用户拍板「公共模式 + 后门模式」双模式)。
enum TsgxsAnswerMode {
  normal('公共模式', '与网页一致:自己作答,提交后看对错与解析'),
  backdoor('后门模式', '题库优先;可一键探底,逐题收集正确答案');

  const TsgxsAnswerMode(this.label, this.hint);

  final String label;
  final String hint;

  /// 从持久化名字（[Enum.name]）解析；未知 / 空 → null。
  static TsgxsAnswerMode? fromName(String? raw) {
    if (raw == null) return null;
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return null;
  }
}

/// 全零 GUID(服务端约定:未使用道具)。
const String tsgxsNilGuid = '00000000-0000-0000-0000-000000000000';

/// 单个选项。
class TsgxsExamOption {
  final String id;
  final String code;
  final String content;

  const TsgxsExamOption({
    required this.id,
    required this.code,
    required this.content,
  });

  factory TsgxsExamOption.fromJson(Map<String, dynamic> json) =>
      TsgxsExamOption(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        content: json['optioncontent']?.toString() ?? '',
      );
}

/// 一道题。
class TsgxsQuestion {
  final String id;
  final String chapterId;
  final TsgxsQuestionKind kind;

  /// 服务端题型名(「单选题」等)。
  final String kindName;
  final String content;
  final List<TsgxsExamOption> options;

  /// 答题提示(部分题有)。
  final String answerTip;

  const TsgxsQuestion({
    required this.id,
    required this.chapterId,
    required this.kind,
    required this.kindName,
    required this.content,
    required this.options,
    this.answerTip = '',
  });

  /// 选项 id → 选项。
  TsgxsExamOption? optionById(String id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// 选项 id 列表 → 代号文本(如 `A、C`)。
  String codesOf(Iterable<String> optionIds) {
    final out = <String>[];
    for (final id in optionIds) {
      final o = optionById(id);
      if (o != null) out.add(o.code);
    }
    return out.join('、');
  }
}

/// 一次开考的服务端会话(答题页隐藏字段)。
class TsgxsExamSession {
  /// 本次考试的记录明细 id(每次提交都要回传)。
  final String examRecordDetailsId;
  final String chapterId;

  /// 本次考试的题目 id 顺序(服务端下发,固定)。
  final List<String> questionIds;

  /// 考试模式码:1/4=章节闯关,2=链式下一章。
  final int examinations;
  final int length;

  const TsgxsExamSession({
    required this.examRecordDetailsId,
    required this.chapterId,
    required this.questionIds,
    required this.examinations,
    required this.length,
  });

  bool get isChapterExam => examinations == 1 || examinations == 4;
}

/// `GET /Web/Exam?cid=` 的结果:要么拿到会话,要么本章已通过。
class TsgxsExamPage {
  final TsgxsExamSession? session;
  final bool passed;
  final String message;
  final String? nextChapterId;

  const TsgxsExamPage({
    this.session,
    this.passed = false,
    this.message = '',
    this.nextChapterId,
  });

  bool get canAnswer => session != null && !passed;
}

/// 可用于重答的道具。
class TsgxsExamProp {
  final String id;
  final String title;
  final String path;

  const TsgxsExamProp({required this.id, required this.title, this.path = ''});

  factory TsgxsExamProp.fromJson(Map<String, dynamic> json) => TsgxsExamProp(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '道具',
    path: json['path']?.toString() ?? '',
  );
}

/// 单题提交(`POST /web/Exam/GetAnswer`)结果。
class TsgxsAnswerResult {
  /// 1=已评分;-1=本关已通过;其它=异常。
  final int success;
  final bool isCorrect;

  /// 服务端判定「本章闯关失败,需重新闯关」(错题数阈值由服务端掌握)。
  final bool isRestart;

  /// 正确答案原文:选项 id 逗号串,或填空/抄写的文本。
  final String correctRaw;
  final String analysis;

  /// 答错时服务端给出的可用道具。
  final List<TsgxsExamProp> myProps;
  final String? nextChapterId;
  final String message;
  final int jumpWhich;

  const TsgxsAnswerResult({
    required this.success,
    this.isCorrect = false,
    this.isRestart = false,
    this.correctRaw = '',
    this.analysis = '',
    this.myProps = const [],
    this.nextChapterId,
    this.message = '',
    this.jumpWhich = 0,
  });

  bool get graded => success == 1;
  bool get chapterPassed => success == -1;
  bool get failedChapter => isRestart;
}

/// 结算(`POST /web/exam/GetGameRole`)结果。
class TsgxsExamFinishResult {
  /// -1=本关已通过;1=结算(可能获得道具/角色);-2=需重新闯关;0=异常。
  final int success;
  final String? nextChapterId;
  final int examinations;
  final List<TsgxsExamProp> props;
  final String message;
  final int jumpWhich;
  final String? chapterId;

  const TsgxsExamFinishResult({
    required this.success,
    this.nextChapterId,
    this.examinations = 0,
    this.props = const [],
    this.message = '',
    this.jumpWhich = 0,
    this.chapterId,
  });

  bool get passed => success == -1 || success == 1;
  bool get needRestart => success == -2;
}

/// 本地题库条目:题目 id → 正确答案(逐题提交时服务端下发)。
class TsgxsBankEntry {
  final String questionId;

  /// 选项 id 逗号串,或填空/抄写文本。
  final String answer;
  final List<String> codes;
  final String kind;
  final String updatedAt;

  const TsgxsBankEntry({
    required this.questionId,
    required this.answer,
    this.codes = const [],
    this.kind = '',
    this.updatedAt = '',
  });

  factory TsgxsBankEntry.fromJson(Map<String, dynamic> json) => TsgxsBankEntry(
    questionId: json['qid']?.toString() ?? '',
    answer: json['answer']?.toString() ?? '',
    codes: ((json['codes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    kind: json['kind']?.toString() ?? '',
    updatedAt: json['at']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'qid': questionId,
    'answer': answer,
    'codes': codes,
    'kind': kind,
    'at': updatedAt,
  };

  /// 选择题的正确答案选项 id 列表。
  List<String> get optionIds => answer
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
