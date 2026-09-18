/// 图书馆订阅词云同步 · 编解码（纯函数、无 IO、无网络）。
///
/// 职责：**字节 ⇄ 订阅词**。所有布局常量与不变式见 `domain/libsp_chunk.dart`。
///
/// - 载荷编码 = 把一段定长字节串当作大整数，转成 78 位 20,992 进制数字，
///   数字 d 映射到 U+4E00 + d（CJK 基本区，1 字 = 1 UTF-16 单元 = 1 MySQL 字符）。
/// - 校验 = CRC-32 低 24 位，占 2 个字母表字符（28.7 bit 容量）。
/// - 识别**只看结构**：ASCII 数字头 + 其后全为字母表字符 + 校验可解。
library;

import 'dart:typed_data';

import 'package:smarter_jxufe/features/library_sync/domain/libsp_chunk.dart';

// ─────────────────────────────── 校验 ───────────────────────────────

final List<int> _crcTable = _buildCrcTable();

List<int> _buildCrcTable() {
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[i] = c;
  }
  return table;
}

/// 标准 CRC-32（IEEE 802.3，反射多项式 0xEDB88320）。
int libspCrc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 片校验值 = CRC-32 低 24 位（装进 2 个字母表字符）。
int libspChecksum(List<int> bytes) => libspCrc32(bytes) & 0xFFFFFF;

/// 校验一片载荷（重算 CRC 与片内记录值比对）。
bool verifyLibspChunk(LibspChunk chunk) =>
    libspChecksum(chunk.bytes) == (chunk.checksum & 0xFFFFFF);

// ─────────────────────────── 字母表 / 大整数 ───────────────────────────

BigInt _base = BigInt.from(kLibspAlphabetSize);

/// 定长字母表编码：`value` → 恰好 [length] 个汉字（高位在左，前导补 U+4E00）。
String _encodeDigits(BigInt value, int length) {
  final out = List<int>.filled(length, 0);
  var x = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x % _base).toInt();
    x = x ~/ _base;
  }
  if (x != BigInt.zero) {
    throw ArgumentError('数值超出 $length 位字母表容量');
  }
  return String.fromCharCodes(out.map((d) => kLibspAlphabetBase + d));
}

/// 字母表解码（不含校验，调用方保证每个字符都在字母表内）。
BigInt _decodeDigits(String text) {
  var x = BigInt.zero;
  for (final unit in text.codeUnits) {
    x = x * _base + BigInt.from(unit - kLibspAlphabetBase);
  }
  return x;
}

BigInt _bytesToBigInt(List<int> bytes) {
  var x = BigInt.zero;
  for (final byte in bytes) {
    x = (x << 8) | BigInt.from(byte & 0xFF);
  }
  return x;
}

List<int> _bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var x = value;
  final mask = BigInt.from(0xFF);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & mask).toInt();
    x = x >> 8;
  }
  return out;
}

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isAlphabetUnit(int unit) =>
    unit >= kLibspAlphabetBase && unit <= kLibspAlphabetLast;

bool _isAllAlphabet(String text) =>
    text.codeUnits.every(_isAlphabetUnit);

// ─────────────────────────────── 单条词 ───────────────────────────────

/// 把一片编成 100 字符的订阅词。
String encodeLibspWord(LibspChunk chunk) {
  if (chunk.bytes.length != kLibspChunkBytes) {
    throw ArgumentError('载荷必须是 $kLibspChunkBytes 字节，实际 ${chunk.bytes.length}');
  }
  if (chunk.slot < 0 || chunk.slot >= kLibspSlots) {
    throw ArgumentError('槽位越界：${chunk.slot}');
  }
  if (chunk.total < 1 || chunk.total > kLibspMaxChunks) {
    throw ArgumentError('总片数越界：${chunk.total}');
  }
  if (chunk.index < 1 || chunk.index > chunk.total) {
    throw ArgumentError('片序号越界：${chunk.index}/${chunk.total}');
  }
  final head = '${chunk.slot}'
      '${chunk.index.toString().padLeft(2, '0')}'
      '${chunk.total.toString().padLeft(2, '0')}';
  final sum = _encodeDigits(BigInt.from(chunk.checksum & 0xFFFFFF),
      kLibspChecksumDigits);
  final body = _encodeDigits(_bytesToBigInt(chunk.bytes), kLibspPayloadChars);
  assert(head.length == kLibspDigitsLength);
  final word = '$kLibspPrefix$head$sum$body';
  assert(word.length == kLibspWordLength, '词长必须恒为 $kLibspWordLength');
  return word;
}

/// 解一条订阅词；不是我们的词 / 结构不合法 → `null`。
///
/// 刻意**不校验前缀文本**：从第 1 个字符起找第一段「5 位 ASCII 数字 +
/// 其后全为字母表字符」的布局，因此前缀被服务端改写（全角标点归一、加空格）
/// 也不影响识别。
LibspChunk? decodeLibspWord(String word) {
  // 只要求「末尾 85 字是结构（5 数字 + 2 校验 + 78 载荷）+ 前面至少还有 1 个字符」，
  // **不锁死恰好 100 字**：服务端实测零规范化，但万一哪天对前缀加/减一个字符
  // （如 trim），锁死长度会让整份快照读不回来 → 误判「云端为空」→ 重复上传。
  const minLength = 1 + kLibspDigitsLength + kLibspChecksumLength + kLibspPayloadChars;
  if (word.length < minLength) return null;
  for (var i = 1; i + kLibspDigitsLength < word.length; i++) {
    final head = word.substring(i, i + kLibspDigitsLength);
    if (!head.codeUnits.every(_isAsciiDigit)) continue;
    final tail = word.substring(i + kLibspDigitsLength);
    if (tail.length != kLibspChecksumLength + kLibspPayloadChars) continue;
    if (!_isAllAlphabet(tail)) continue;

    final slot = head.codeUnitAt(0) - 0x30;
    final index = int.parse(head.substring(1, 3));
    final total = int.parse(head.substring(3, 5));
    if (slot < 0 || slot >= kLibspSlots) return null;
    if (total < 1 || total > kLibspMaxChunks) return null;
    if (index < 1 || index > total) return null;

    final checksum = _decodeDigits(tail.substring(0, kLibspChecksumLength));
    final bytes = _bigIntToBytes(
      _decodeDigits(tail.substring(kLibspChecksumLength)),
      kLibspChunkBytes,
    );
    return LibspChunk(
      slot: slot,
      index: index,
      total: total,
      checksum: checksum.toInt(),
      bytes: bytes,
    );
  }
  return null;
}

/// 这条词看起来是不是我们写的（结构合法即可，不校验 CRC）。
bool isLibspWord(String word) => decodeLibspWord(word) != null;

/// 从服务端返回的一堆词里挑出我们的片，按槽位分组。
///
/// 结构合法但 **CRC 不过** 的片也会被保留（由调用方决定是自愈还是报警）。
Map<int, List<LibspChunk>> groupLibspChunks(Iterable<String> words) {
  final out = <int, List<LibspChunk>>{};
  for (final word in words) {
    final chunk = decodeLibspWord(word);
    if (chunk == null) continue;
    (out[chunk.slot] ??= <LibspChunk>[]).add(chunk);
  }
  for (final list in out.values) {
    list.sort((a, b) => a.index.compareTo(b.index));
  }
  return out;
}

// ─────────────────────────── 一份快照（分片/重组）───────────────────────────

/// 把信封字节切片成一整份快照的词列表（末片 0 填充到定长）。
///
/// 抛 [ArgumentError] 当片数超过 [kLibspMaxChunks]（容量天花板，见方案 §四）。
List<String> encodeLibspWords(List<int> envelope, {required int slot}) {
  if (envelope.isEmpty) throw ArgumentError('信封为空');
  final total =
      (envelope.length + kLibspChunkBytes - 1) ~/ kLibspChunkBytes;
  if (total > kLibspMaxChunks) {
    throw ArgumentError(
        '载荷过大：需要 $total 片，单份上限 $kLibspMaxChunks 片（${kLibspMaxChunks * kLibspChunkBytes} 字节）');
  }
  final padded = Uint8List(total * kLibspChunkBytes)
    ..setRange(0, envelope.length, envelope);
  return [
    for (var i = 0; i < total; i++)
      () {
        final bytes = padded.sublist(
          i * kLibspChunkBytes,
          (i + 1) * kLibspChunkBytes,
        );
        return encodeLibspWord(LibspChunk(
          slot: slot,
          index: i + 1,
          total: total,
          checksum: libspChecksum(bytes),
          bytes: bytes,
        ));
      }(),
  ];
}

/// 一组片 → 信封字节；不完整 / 校验不过 / 混了槽位或总片数 → `null`。
List<int>? joinLibspChunks(List<LibspChunk> chunks) {
  if (chunks.isEmpty) return null;
  final slot = chunks.first.slot;
  final total = chunks.first.total;
  if (chunks.length != total) return null;
  if (chunks.any((c) => c.slot != slot || c.total != total)) return null;
  final sorted = [...chunks]..sort((a, b) => a.index.compareTo(b.index));
  for (var i = 0; i < total; i++) {
    if (sorted[i].index != i + 1) return null;
    if (!verifyLibspChunk(sorted[i])) return null;
  }
  return [for (final chunk in sorted) ...chunk.bytes];
}

// ─────────────────────────────── 信封 ───────────────────────────────

/// 信封 = `[4 字节大端长度][gzip 字节]`（0 填充交给分片层）。
List<int> packLibspEnvelope(List<int> gzipBytes) {
  final out = Uint8List(4 + gzipBytes.length);
  ByteData.view(out.buffer).setUint32(0, gzipBytes.length, Endian.big);
  out.setRange(4, out.length, gzipBytes);
  return out;
}

/// 解信封（截掉分片填充的 0）；长度非法 → `null`。
List<int>? unpackLibspEnvelope(List<int> bytes) {
  if (bytes.length < 4) return null;
  final view = ByteData.sublistView(Uint8List.fromList(bytes), 0, 4);
  final length = view.getUint32(0, Endian.big);
  if (length <= 0 || 4 + length > bytes.length) return null;
  return bytes.sublist(4, 4 + length);
}
