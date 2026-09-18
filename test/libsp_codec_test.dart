// 图书馆订阅词云同步 · 编解码守卫。
//
// 守住的是协议里最容易悄悄坏掉的东西：
// - **字母表容量不变式**（139 字节必须装得进 78 个 20,992 进制数字）；
// - **识别只看结构**：前缀里的全角标点被服务端归一（NFKC）也不影响解码；
// - **超长静默截断的对照组**：我们自己绝不产生非 100 字的词；
// - **CRC 能抓到单字节翻转**（服务端对订阅词零规范化，但存储层仍可能出错）；
// - 分片/重组的完整性（缺片、重片、混槽位一律拒绝，不做半恢复）。

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_codec.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_chunk.dart';

List<int> bytesOf(int length, int Function(int) f) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) f(i)]);

LibspChunk chunkOf(List<int> bytes, {int slot = 0, int index = 1, int total = 1}) =>
    LibspChunk(
      slot: slot,
      index: index,
      total: total,
      checksum: libspChecksum(bytes),
      bytes: bytes,
    );

void main() {
  group('字母表与容量不变式', () {
    test('78 个字母表字符装得下 139 字节（20992^78 ≥ 256^139）', () {
      final capacity = BigInt.from(kLibspAlphabetSize).pow(kLibspPayloadChars);
      final need = BigInt.from(256).pow(kLibspChunkBytes);
      expect(capacity >= need, isTrue,
          reason: '常量被改动会破坏编码：$capacity < $need');
    });

    test('字母表恰好落在 CJK 基本区内（1 字 = 1 UTF-16 单元）', () {
      expect(kLibspAlphabetBase, 0x4E00);
      expect(kLibspAlphabetLast, 0x9FFF);
      expect(kLibspAlphabetSize, 20992);
      final chars = String.fromCharCodes([
        kLibspAlphabetBase,
        kLibspAlphabetBase + 1,
        kLibspAlphabetLast,
      ]);
      expect(chars.codeUnits.length, 3, reason: '不得出现代理对');
      expect(chars.runes.length, 3);
    });

    test('字段长度自洽：15 + 5 + 2 + 78 = 100', () {
      expect(kLibspPrefixLength, kLibspPrefix.length);
      expect(kLibspPrefixLength +
              kLibspDigitsLength +
              kLibspChecksumLength +
              kLibspPayloadChars,
          kLibspWordLength);
    });
  });

  group('单条词：编码与解码', () {
    test('词长恒为 100、前缀在开头、无代理对', () {
      final word = encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i)));
      expect(word.length, kLibspWordLength);
      expect(word.startsWith(kLibspPrefix), isTrue);
      expect(word.runes.length, kLibspWordLength);
    });

    test('各类字节形态都能原样往返（全 0 / 全 FF / 递增 / 随机）', () {
      final samples = <List<int>>[
        bytesOf(kLibspChunkBytes, (_) => 0x00),
        bytesOf(kLibspChunkBytes, (_) => 0xFF),
        bytesOf(kLibspChunkBytes, (i) => i & 0xFF),
        bytesOf(kLibspChunkBytes, (i) => Random(42 + i).nextInt(256)),
      ];
      for (final bytes in samples) {
        final word = encodeLibspWord(chunkOf(bytes));
        final back = decodeLibspWord(word);
        expect(back, isNotNull);
        expect(back!.bytes, bytes);
        expect(back.slot, 0);
        expect(back.index, 1);
        expect(back.total, 1);
        expect(verifyLibspChunk(back), isTrue);
      }
    });

    test('载荷全为 CJK 基本区字符（含首字节为 0 的极端情况）', () {
      final word = encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (_) => 0)));
      final body = word.substring(kLibspWordLength - kLibspPayloadChars);
      for (final unit in body.codeUnits) {
        expect(unit >= kLibspAlphabetBase && unit <= kLibspAlphabetLast, isTrue,
            reason: 'U+${unit.toRadixString(16)} 不在字母表内');
      }
    });

    test('槽位 0/1/2 与多片序号编码正确', () {
      for (var slot = 0; slot < kLibspSlots; slot++) {
        final word = encodeLibspWord(
            chunkOf(bytesOf(kLibspChunkBytes, (i) => i), slot: slot, index: 7, total: 9));
        final back = decodeLibspWord(word)!;
        expect(back.slot, slot);
        expect(back.index, 7);
        expect(back.total, 9);
        expect(word.substring(kLibspPrefixLength, kLibspPrefixLength + 5), '${slot}0709');
      }
    });
  });

  group('识别：只看结构，不认前缀文本', () {
    test('前缀里的全角 ！/： 被 NFKC 归一后仍能解码（服务端实测零规范化，这里是保险）', () {
      final word = encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i * 3)));
      final rewritten = word
          .replaceFirst('！', '!')
          .replaceFirst('：', ':');
      expect(rewritten, isNot(word));
      final back = decodeLibspWord(rewritten);
      expect(back, isNotNull, reason: '识别必须不依赖前缀文本');
      expect(back!.bytes, decodeLibspWord(word)!.bytes);
    });

    test('前缀被换成别的文字（长度也不同）仍能解码', () {
      final word = encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i + 1)));
      final head = word.substring(kLibspPrefixLength);
      // 12 字替身前缀 → 词长变成 97，仍必须认得出来（识别锚在末尾结构上）。
      expect(decodeLibspWord('图书馆检索词订阅：$head'), isNotNull);
      expect(decodeLibspWord('江财云同步提醒$head'), isNotNull);
      expect(decodeLibspWord(head), isNull, reason: '没有前缀就不认');
    });

    test('真实的检索词 / 其它长度的串一律不认', () {
      for (final other in <String>[
        '计算机网络',
        '数据结构与算法',
        'a' * 100,
        '0' * 100,
        '',
        '勿删！智慧er江财云同步信息：00107${'0' * 78}', // 载荷是 ASCII → 不认
        encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i))).substring(0, 99),
        '${encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i)))}甲',
      ]) {
        expect(decodeLibspWord(other), isNull, reason: '不该认：${other.length} 字');
        expect(isLibspWord(other), isFalse);
      }
    });

    test('数字头越界（槽位 ≥3 / 序号 0 / 序号 > 总片 / 总片 0）一律拒收', () {
      final good = encodeLibspWord(chunkOf(bytesOf(kLibspChunkBytes, (i) => i)));
      String withHead(String head) =>
          kLibspPrefix + head + good.substring(kLibspPrefixLength + 5);
      expect(decodeLibspWord(withHead('00107')), isNotNull);
      expect(decodeLibspWord(withHead('90107')), isNull, reason: '槽位 9 越界');
      expect(decodeLibspWord(withHead('00007')), isNull, reason: '序号 0');
      expect(decodeLibspWord(withHead('00807')), isNull, reason: '序号 8 > 总片 7');
      expect(decodeLibspWord(withHead('00100')), isNull, reason: '总片 0');
    });
  });

  group('校验与损坏检测', () {
    test('单字节翻转会被 CRC 抓到', () {
      final bytes = bytesOf(kLibspChunkBytes, (i) => (i * 7) & 0xFF);
      final word = encodeLibspWord(chunkOf(bytes));
      final chunk = decodeLibspWord(word)!;
      expect(verifyLibspChunk(chunk), isTrue);

      // 模拟**存储损坏**：词里记着的校验值不变，载荷字节被改动一位。
      final corrupted = [...chunk.bytes];
      corrupted[70] = corrupted[70] ^ 0x01;
      final bad = LibspChunk(
        slot: chunk.slot,
        index: chunk.index,
        total: chunk.total,
        checksum: chunk.checksum,
        bytes: corrupted,
      );
      expect(verifyLibspChunk(bad), isFalse);
    });

    test('校验值只占低 24 位', () {
      final bytes = bytesOf(kLibspChunkBytes, (i) => i);
      final chunk = decodeLibspWord(encodeLibspWord(chunkOf(bytes)))!;
      expect(chunk.checksum, lessThan(1 << 24));
      expect(chunk.checksum, libspChecksum(bytes));
    });
  });

  group('一份快照：分片与重组', () {
    test('858 字节 → 7 片（与方案 §四 的容量账一致）', () {
      final words = encodeLibspWords(
        bytesOf(858, (i) => (i * 31) & 0xFF),
        slot: 0,
      );
      expect(words.length, 7);
      expect(words.every((w) => w.length == kLibspWordLength), isTrue);
      final chunks = words.map((w) => decodeLibspWord(w)!).toList();
      expect(chunks.map((c) => c.index), [1, 2, 3, 4, 5, 6, 7]);
      expect(chunks.every((c) => c.total == 7), isTrue);
    });

    test('分片 → 重组还原出「载荷 + 片对齐的 0 填充」（截断由信封层负责）', () {
      for (final length in <int>[1, 138, 139, 140, 700, 139 * 7]) {
        final payload = bytesOf(length, (i) => (i * 13 + 5) & 0xFF);
        final words = encodeLibspWords(payload, slot: 2);
        final chunks = words.map((w) => decodeLibspWord(w)!).toList();
        final joined = joinLibspChunks(chunks);
        expect(joined, isNotNull, reason: '长度 $length');
        expect(joined!.length, chunks.length * kLibspChunkBytes);
        expect(joined.sublist(0, payload.length), payload, reason: '长度 $length');
        expect(joined.sublist(payload.length).every((b) => b == 0), isTrue,
            reason: '尾部必须是 0 填充：长度 $length');
      }
    });

    test('缺片 / 多片 / 混槽位 / 坏校验一律拒绝（不做半恢复）', () {
      final words = encodeLibspWords(
        bytesOf(500, (i) => (i * 17) & 0xFF),
        slot: 1,
      );
      final chunks = words.map((w) => decodeLibspWord(w)!).toList();
      expect(joinLibspChunks(chunks), isNotNull);

      expect(joinLibspChunks(chunks.sublist(0, chunks.length - 1)), isNull,
          reason: '缺片');
      expect(joinLibspChunks([...chunks, chunks.first]), isNull, reason: '重复片');
      expect(
        joinLibspChunks([chunks.first, ...chunks.skip(2)]),
        isNull,
        reason: '序号不连续',
      );
      final foreign = <LibspChunk>[
        chunks.first,
        ...chunks.skip(1).map((c) => LibspChunk(
              slot: c.slot,
              index: c.index,
              total: c.total,
              checksum: c.checksum ^ 0xFF,
              bytes: c.bytes,
            )),
      ];
      expect(joinLibspChunks(foreign), isNull, reason: '校验不过');
      expect(joinLibspChunks(const []), isNull);
    });

    test('超出单份上限时抛错（容量天花板可被上层捕获并降级）', () {
      expect(
        () => encodeLibspWords(
          bytesOf(kLibspMaxChunks * kLibspChunkBytes + 1, (i) => i & 0xFF),
          slot: 0,
        ),
        throwsArgumentError,
      );
    });

    test('groupLibspChunks 只收我们的词，并按槽位分组、按序号排序', () {
      final a = encodeLibspWords(bytesOf(300, (i) => i & 0xFF), slot: 0);
      final b = encodeLibspWords(bytesOf(300, (i) => (i + 9) & 0xFF), slot: 2);
      final grouped = groupLibspChunks(['计算机网络', ...a.reversed, ...b, 'x' * 100]);
      expect(grouped.keys.toSet(), {0, 2});
      expect(grouped[0]!.map((c) => c.index), [1, 2, 3]);
      expect(grouped[2]!.map((c) => c.index), [1, 2, 3]);
    });
  });

  group('信封', () {
    test('长度前缀往返 + 非法长度返回 null', () {
      final gzipLike = bytesOf(853, (i) => (i * 3) & 0xFF);
      final envelope = packLibspEnvelope(gzipLike);
      expect(envelope.length, 857);
      expect(unpackLibspEnvelope(envelope), gzipLike);

      expect(unpackLibspEnvelope([0, 0, 0, 255, 1, 2]), isNull, reason: '长度超出实长');
      expect(unpackLibspEnvelope([0, 0, 0, 0]), isNull, reason: '长度 0');
      expect(unpackLibspEnvelope([1, 2, 3]), isNull, reason: '不足 4 字节');
    });

    test('信封 + 分片 + 重组端到端（模拟一次真实同步的字节流）', () {
      final payload = bytesOf(853, (i) => Random(i).nextInt(256));
      final envelope = packLibspEnvelope(payload);
      final words = encodeLibspWords(envelope, slot: 2);
      final grouped = groupLibspChunks(words);
      final joined = joinLibspChunks(grouped[2]!);
      expect(joined, isNotNull);
      expect(unpackLibspEnvelope(joined!), payload);
    });
  });
}
