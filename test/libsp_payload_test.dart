// 图书馆订阅词云同步 · 载荷白名单与降级链守卫。
//
// 守住的是「上云的东西」这件事本身：
// - **白名单不许偷偷放宽**（令牌 / 设备标识 / 可重取缓存一旦混进来，测试必须红）；
// - **uuid 与备忘录必须被剥掉**（跨设备 id 无意义；备忘录按 Q7-B 不上云）；
// - **降级链优先级固定**（先丢备注 → 再丢截止日期 → 再丢课程 → 再丢综测 → 最后只留偏好），
//   且每一步都如实写进 trim 报告，绝不静默丢；
// - 恢复出来的课程能直接被真实 `GeCourse.fromJson` 吃下（不留坏引用）。

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_codec.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';

int _seq = 0;
String _newId() => 'id-${_seq++}';

/// 压不动的汉字噪声：**超载样本必须用这个**。
///
/// 教训：120 门「除课名外完全一样」的课，gzip 之后只有几百字节 —— 于是
/// 降级链根本不会被触发，测试会假绿。真实的分数估计数据（课名 / 分项 / 备注
/// 各不相同）压缩率约 2.7:1（实测 2289 B → 853 B），噪声样本才接近真实。
String _noise(int seed, int length) {
  final random = Random(seed);
  return String.fromCharCodes([
    for (var i = 0; i < length; i++) 0x4E00 + random.nextInt(0x1000),
  ]);
}

Map<String, dynamic> course({
  String name = '计算机网络',
  String note = '教师：陈润平 · 学分 2',
  int createdAt = 1000,
  int partCount = 2,
  int deadlineCount = 0,
  String deadlineNote = '第二章',
  int noise = 0,
}) => {
  'id': 'uuid-$name-$createdAt',
  'name': name,
  'courseCode': '1004606732',
  'dailyPercent': 30.0,
  'credits': 2.0,
  'parts': [
    for (var i = 0; i < partCount; i++)
      {
        'id': 'part-uuid-$name-$i',
        'name': '考勤$i',
        'mode': 'down',
        'target': 16,
        'current': 14,
        'score': 0.0,
        'cap': 5.0,
        'note': noise == 0 ? '每周四上课' : _noise(noise + 7, 24),
      },
  ],
  'finalScore': null,
  'note': noise == 0 ? note : _noise(noise, 30),
  'memo': {
    'text': '这门课要背的东西很多',
    'images': [
      {'fileName': 'a.jpg', 'bytes': 1024, 'width': 100, 'height': 100},
    ],
  },
  'deadlines': [
    for (var i = 0; i < deadlineCount; i++)
      {
        'id': 'dl-uuid-$name-$i',
        'title': '作业$i',
        'kind': 'homework',
        'dueAt': 1789000000000 + i * 86400000,
        'repeat': 'none',
        'note': noise == 0 ? deadlineNote : _noise(noise + 13, 40),
        'doneAt': null,
        'remind': true,
      },
  ],
  'createdAt': createdAt,
};

Map<String, Map<String, String>> prefsFixture() => {
  'themePrefs': {'themeMode': 'dark'},
  'myCampusPrefs': {'campus': '麦庐园校区'},
  'electricityBinding': {'campusId': '2', 'room': 'B12-305'},
};

void main() {
  group('白名单', () {
    test('同步与排除两个清单不许有交集', () {
      for (final box in kLibspSyncedPrefBoxes) {
        expect(kLibspExcludedBoxes, isNot(contains(box)), reason: '$box 同时在两份清单里');
      }
    });

    test('会话令牌 / 设备标识 / 可重取缓存必须都在排除清单里', () {
      for (final box in <String>[
        'imsAuth', 'auth', 'sspAuth', 'dzjAuth', 'cxstar', 'readCredit', // 令牌
        'wxPlatform', 'homeWidget', // 设备标识（GUID 跨设备共用是错的）
        'gradesCache', 'scheduleCache', 'curriculums', 'studentInfo', // 可重取
      ]) {
        expect(kLibspExcludedBoxes, contains(box), reason: '$box 没被排除');
      }
    });

    test('电费绑定按 Q7-B 在白名单里（明示文案必须逐项列出宿舍房间号）', () {
      expect(kLibspSyncedPrefBoxes, contains('electricityBinding'));
      expect(kLibspSyncedPrefBoxes, contains('themePrefs'));
      expect(kLibspSyncedPrefBoxes, contains('schoolCalendarPrefs'));
    });
  });

  group('分数估计的剥离', () {
    test('id / createdAt / memo 一律被剥掉，业务字段一个不少', () {
      final out = sanitizeGeCourse(course(deadlineCount: 2));
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('createdAt'), isFalse);
      expect(out.containsKey('memo'), isFalse, reason: 'Q7-B：备忘录文字不上云');
      expect(out['name'], '计算机网络');
      expect(out['courseCode'], '1004606732');
      expect(out['dailyPercent'], 30.0);
      expect(out['credits'], 2.0);
      expect(out['note'], '教师：陈润平 · 学分 2');
      expect((out['parts'] as List).length, 2);
      expect((out['deadlines'] as List).length, 2);
      for (final p in out['parts'] as List) {
        expect((p as Map).containsKey('id'), isFalse, reason: '分项 id 跨设备无意义');
      }
      for (final d in out['deadlines'] as List) {
        expect((d as Map).containsKey('id'), isFalse, reason: '截止日期 id 同理');
      }
      final part = (out['parts'] as List).first as Map;
      expect(part['mode'], 'down');
      expect(part['cap'], 5.0);
      expect(part['note'], '每周四上课');
    });

    test('dropNotes 清空课程 / 分项 / 截止日期的备注文字', () {
      final out = sanitizeGeCourse(course(deadlineCount: 1), dropNotes: true);
      expect(out['note'], '');
      expect(((out['parts'] as List).first as Map)['note'], '');
      expect(((out['deadlines'] as List).first as Map)['note'], '');
    });

    test('maxDeadlines 只留最近（dueAt 最小）的若干条', () {
      final out = sanitizeGeCourse(course(deadlineCount: 5), maxDeadlines: 2);
      final list = (out['deadlines'] as List).cast<Map>();
      expect(list.length, 2);
      expect(list.map((d) => d['dueAt']).toList(), [
        1789000000000,
        1789000000000 + 86400000,
      ]);
    });
  });

  group('恢复（认领回本机）', () {
    test('补上新 id / createdAt / 空备忘录，且能被真实 GeCourse.fromJson 吃下', () {
      _seq = 0;
      final payload = sanitizeGeCourse(course(deadlineCount: 2));
      final adopted = adoptGeCourse(
        payload,
        newId: _newId,
        createdAt: 1789578751890,
      );
      final model = GeCourse.fromJson(adopted);
      expect(model.name, '计算机网络');
      expect(model.courseCode, '1004606732');
      expect(model.credits, 2.0);
      expect(model.parts.length, 2);
      expect(model.deadlines.length, 2);
      expect(model.createdAt, 1789578751890);
      expect(model.memo.text, '', reason: '备忘录不上云 → 恢复为空');
      expect(model.memo.images, isEmpty);
      expect(model.id, isNotEmpty);
      expect(model.parts.first.id, isNotEmpty);
      expect(model.deadlines.first.id, isNotEmpty);
      expect(
        {model.id, model.parts.first.id, model.deadlines.first.id}.length,
        3,
        reason: '每个 id 必须各不相同',
      );
      // 两门课不许共用 id（uuid 逐条生成）
      final second = GeCourse.fromJson(
        adoptGeCourse(sanitizeGeCourse(course(name: '线性代数(工)')), newId: _newId, createdAt: 1),
      );
      expect(second.id, isNot(model.id));
    });

    test('剥掉 id 后同一门课两次认领会得到不同 id（跨设备不共享 uuid 是设计）', () {
      _seq = 0;
      final payload = sanitizeGeCourse(course());
      final a = adoptGeCourse(payload, newId: _newId, createdAt: 1);
      final b = adoptGeCourse(payload, newId: _newId, createdAt: 1);
      expect(a['id'], isNot(b['id']));
    });
  });

  group('快照序列化与压缩', () {
    test('JSON 往返字段不丢', () {
      final snapshot = LibspSnapshot(
        generatedAt: 1789578751890,
        account: '2000000000',
        prefs: prefsFixture(),
        courses: [sanitizeGeCourse(course(deadlineCount: 1))],
        zongce: {'manual-2026': '{"tScore":88}'},
        trim: const LibspTrimReport(droppedDeadlines: 3),
      );
      final back = LibspSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      )!;
      expect(back.version, kLibspPayloadVersion);
      expect(back.generatedAt, 1789578751890);
      expect(back.account, '2000000000');
      expect(back.prefs['electricityBinding']!['room'], 'B12-305');
      expect(back.courses.length, 1);
      expect(back.zongce['manual-2026'], '{"tScore":88}');
      expect(back.trim.droppedDeadlines, 3);
      expect(back.courseCount, 1);
      expect(back.prefEntryCount, 4);
    });

    test('损坏 / 非 gzip 字节 → null（云端脏数据不能崩 App）', () {
      expect(decodeLibspSnapshotBytes([1, 2, 3, 4]), isNull);
      final good = encodeLibspSnapshotBytes(LibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: const {},
        courses: const [],
        zongce: const {},
      ));
      expect(decodeLibspSnapshotBytes(good), isNotNull);
      final broken = [...good];
      broken[broken.length ~/ 2] ^= 0xFF;
      expect(decodeLibspSnapshotBytes(broken), isNull);
    });

    test('gzip 之后的信封能装进 7 片（与方案 §四 的实测容量账一致）', () {
      final snapshot = LibspSnapshot(
        generatedAt: 1789578751890,
        account: '2000000000',
        prefs: prefsFixture(),
        courses: [
          for (var i = 0; i < 10; i++)
            sanitizeGeCourse(course(name: '课程$i', createdAt: 1000 + i)),
        ],
        zongce: const {},
      );
      final bytes = encodeLibspSnapshotBytes(snapshot);
      // 实测：本机真实数据 2289 B JSON → gzip 853 B；这里 10 门课同量级。
      expect(bytes.length, lessThan(1400));
      final words = encodeLibspWords(packLibspEnvelope(bytes), slot: 0);
      expect(words.length, lessThanOrEqualTo(7));
      final joined = joinLibspChunks(groupLibspChunks(words)[0]!);
      final decoded = decodeLibspSnapshotBytes(unpackLibspEnvelope(joined!)!);
      expect(decoded!.courses.length, 10);
      expect(decoded.prefs['themePrefs']!['themeMode'], 'dark');
    });
  });

  group('降级链', () {
    test('装得下时零裁剪', () {
      final result = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: [course()],
        zongce: const {'manual-2026': '{"tScore":88}'},
      );
      expect(result.snapshot.trim.isEmpty, isTrue);
      expect(result.snapshot.trim.summary, '');
      expect(result.snapshot.courses.length, 1);
    });

    test('先丢备注 → 再丢截止日期，且都如实记录', () {
      final big = [
        for (var i = 0; i < 30; i++)
          course(
            name: '课程$i',
            createdAt: 1000 + i,
            partCount: 5,
            deadlineCount: 6,
            deadlineNote: '第二章 课后习题 1-20 全部完成',
          ),
      ];
      final full = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: big,
        zongce: const {},
        maxEnvelopeBytes: 1 << 20,
      );
      expect(full.snapshot.trim.isEmpty, isTrue);

      // 预算压到「完整装不下、丢了备注就装得下」的档位
      final budget = (full.envelopeBytes * 0.75).round();
      final trimmed = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: big,
        zongce: const {},
        maxEnvelopeBytes: budget,
      );
      expect(trimmed.envelopeBytes, lessThanOrEqualTo(budget));
      expect(trimmed.snapshot.trim.isEmpty, isFalse);
      final trim = trimmed.snapshot.trim;
      expect(trim.droppedAllCourses, isFalse, reason: '不该直接跳到最狠的一档');
      if (trim.droppedDeadlines == 0) {
        expect(trim.droppedCourseNotes, greaterThan(0),
            reason: '要丢就必须先丢备注（固定优先级）');
      }
      expect(trim.summary, contains('已精简：'));
    });

    test('极端超载时逐级降到底：课程变少 / 丢综测 / 最后只留偏好', () {
      final huge = [
        for (var i = 0; i < 120; i++)
          course(
            name: '课程$i${_noise(i + 1, 12)}',
            createdAt: i,
            partCount: 6,
            deadlineCount: 8,
            noise: i + 1,
          ),
      ];
      final zc = {
        for (var y = 2020; y <= 2030; y++) 'manual-$y': '{"tScore":8$y}',
      };

      // 中间档：应当保住偏好与部分课程，丢掉备注 / 截止日期 / 综测中的至少一项
      final mid = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: huge,
        zongce: zc,
        maxEnvelopeBytes: 3000,
      );
      expect(mid.envelopeBytes, lessThanOrEqualTo(3000));
      expect(mid.snapshot.prefs['themePrefs']!['themeMode'], 'dark',
          reason: '偏好永远不该被丢');
      final trim = mid.snapshot.trim;
      expect(
        trim.droppedCourseNotes > 0 ||
            trim.droppedDeadlines > 0 ||
            trim.droppedCourses > 0 ||
            trim.droppedZongce,
        isTrue,
        reason: '超载必须有裁剪记录',
      );

      // 最狠档：只剩偏好
      final floor = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: huge,
        zongce: zc,
        maxEnvelopeBytes: 400,
      );
      expect(floor.snapshot.trim.droppedAllCourses, isTrue);
      expect(floor.snapshot.trim.droppedZongce, isTrue);
      expect(floor.snapshot.courses, isEmpty);
      expect(floor.snapshot.zongce, isEmpty);
      expect(floor.snapshot.prefs['electricityBinding']!['room'], 'B12-305');
      expect(floor.snapshot.trim.summary, contains('分数估计整体'));
    });

    test('连纯偏好都装不下时抛 StateError（宁可不传，也不上传空快照覆盖云端）', () {
      expect(
        () => buildLibspSnapshot(
          generatedAt: 1,
          account: 'a',
          prefs: prefsFixture(),
          rawCourses: const [],
          zongce: const {},
          maxEnvelopeBytes: 1,
        ),
        throwsStateError,
      );
    });

    test('丢课程时丢的是最旧的（按 createdAt）', () {
      final many = [
        for (var i = 0; i < 60; i++)
          course(name: '课程$i', createdAt: i, partCount: 3, deadlineCount: 2),
      ];
      final result = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: many,
        zongce: const {},
        maxEnvelopeBytes: 1200,
        courseKeepRatio: 0.5,
      );
      final kept = result.snapshot.courses
          .map((c) => (c['name'] as String))
          .toSet();
      expect(kept, isNotEmpty);
      if (result.snapshot.trim.droppedCourses > 0) {
        expect(kept.contains('课程0'), isFalse, reason: '最旧的应当先被丢');
        expect(kept.contains('课程59'), isTrue, reason: '最新的必须留下');
      }
    });

    test('课程顺序 = 本机原序（恢复不该把用户列表倒过来）', () {
      // 2026-09-17 真机端到端实测：早先实现输出了「新在前」，恢复后 10 门课全反序。
      final mine = [
        for (var i = 0; i < 6; i++)
          course(name: '第$i门', createdAt: 1000 + i, partCount: 1),
      ];
      final result = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: mine,
        zongce: const {},
      );
      expect(
        [for (final c in result.snapshot.courses) c['name']],
        ['第0门', '第1门', '第2门', '第3门', '第4门', '第5门'],
      );
    });

    test('裁剪时：丢的是最旧的，剩下的仍按本机原序', () {
      // ⚠ 名字里必须带**随机汉字噪声**：只差一个序号的 40 门课 gzip 后只有几百字节，
      // 根本撑不到裁剪那一步（第一版就这么写的，断言 `droppedCourses > 0` 直接假失败）。
      String noise(int seed) => List.generate(
        24,
        (k) => String.fromCharCode(0x4E00 + (seed * 131 + k * 37) % 0x2000),
      ).join();
      final mine = [
        for (var i = 0; i < 40; i++)
          course(name: '第$i门${noise(i)}', createdAt: 1000 + i, partCount: 2),
      ];
      final result = buildLibspSnapshot(
        generatedAt: 1,
        account: 'a',
        prefs: prefsFixture(),
        rawCourses: mine,
        zongce: const {},
        maxEnvelopeBytes: 1200,
        courseKeepRatio: 0.5,
      );
      final names = [for (final c in result.snapshot.courses) c['name'] as String];
      final keptIdx = [
        for (final n in names)
          int.parse(RegExp(r'^第(\d+)门').firstMatch(n)!.group(1)!),
      ];
      expect(result.snapshot.trim.droppedCourses, greaterThan(0));
      // 丢的是最旧的那批（下标小的），留下的是连续的一段、且仍是本机原序。
      expect(keptIdx.last, 39, reason: '最新的必须留下');
      expect(keptIdx.contains(0), isFalse, reason: '最旧的先被丢');
      expect(
        keptIdx,
        List.generate(keptIdx.length, (i) => keptIdx.first + i),
        reason: '留下的必须是连续一段、且按本机原序（没被倒序/重排）',
      );
    });
  });

  group('trim 报告文案', () {
    test('空报告不显示；有内容时逐项列出', () {
      expect(const LibspTrimReport().summary, '');
      expect(
        const LibspTrimReport(droppedCourses: 3, droppedDeadlines: 12).summary,
        '已精简：3 门课程、12 条截止日期 未同步',
      );
      expect(
        const LibspTrimReport(droppedAllCourses: true, droppedZongce: true).summary,
        '已精简：分数估计整体、综测填写项 未同步',
      );
    });
  });
}
