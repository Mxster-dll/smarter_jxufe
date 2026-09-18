/// 图书馆订阅词云同步 · 分片布局常量与分片模型（协议冻结版）。
///
/// 单条订阅词恒为 **100 个字符**（服务端上限实测 = 100 字符，超出静默截断）：
///
/// ```
/// 勿删！智慧er江财云同步信息：  0  01  07  XX  <78 个汉字载荷>
/// └──────── 15 字 ────────┘  │  │   │   │   └─ CJK 基本区编码（14.357 bit/字）
///                           │  │   │   └─ 2 字校验（CRC-32 低 24 位）
///                           │  │   └─ 总片数（ASCII 两位）
///                           │  └─ 片序号（ASCII 两位）
///                           └─ 槽位（ASCII 一位，0/1/2 = 三组冗余）
/// ```
///
/// **识别只认结构、不认前缀文本**：ASCII 数字头能解出合法 (槽位, 序号, 总片)、
/// 数字头之后全为 CJK 基本区字符、且校验通过 → 即我们的词。服务端若对前缀里的
/// 全角 `！` / `：` 做全半角归一（NFKC 会把 U+FF01→`!`、U+FF1A→`:`），识别、清除、
/// 恢复都不受影响 —— 这是实测「服务端零规范化」之外的额外保险。
///
/// ⚠ 读回校验**只覆盖「数字头 + 校验 + 载荷」**，不覆盖前缀：否则服务端一改标点
/// 就会误报「数据损坏」。
library;

/// 人类可读前缀（15 字；含 2 个会被 NFKC 改写的全角标点，故意不参与识别）。
const String kLibspPrefix = '勿删！智慧er江财云同步信息：';

/// 前缀长度（15）。
const int kLibspPrefixLength = 15;

/// 单条订阅词的固定字符数（服务端上限实测 = 100）。
const int kLibspWordLength = 100;

/// ASCII 数字头长度：槽位 1 + 序号 2 + 总片 2。
const int kLibspDigitsLength = 5;

/// 校验字段的字符数（2 字 = 14.357×2 = 28.7 bit 容量，装 24 bit 校验）。
const int kLibspChecksumLength = 2;

/// 校验字段占用的汉字数（与 [kLibspChecksumLength] 同值，名称表意用）。
const int kLibspChecksumDigits = kLibspChecksumLength;

/// 每片承载的载荷字符数：100 − 15 − 5 − 2 = 78。
const int kLibspPayloadChars = kLibspWordLength -
    kLibspPrefixLength -
    kLibspDigitsLength -
    kLibspChecksumLength;

/// 每片承载的原始字节数（78 字 × log2(20992)/8 = 139.98 → 取 139）。
///
/// 不变式：`20992^78 ≥ 256^139`（由 `test/libsp_codec_test.dart` 守住）。
const int kLibspChunkBytes = 139;

/// 汉字字母表起点 U+4E00（CJK 统一表意文字基本区）。
const int kLibspAlphabetBase = 0x4E00;

/// 字母表大小 20,992（U+4E00–U+9FFF）。
///
/// 刻意**不扩** CJK 扩展 A / 谚文 / emoji：余量 4 倍以上时密度一文不值，
/// 而多一个码块就多一份未验证的规范化与存储行为（U+F900–FAFF 会被 NFKC 改写、
/// U+3000 是空白会被 trim、Ext-B 是 4 字节）。
const int kLibspAlphabetSize = 20992;

/// 汉字字母表终点 U+9FFF。
const int kLibspAlphabetLast = kLibspAlphabetBase + kLibspAlphabetSize - 1;

/// 槽位（组）数量：三组 = 最新版 ×2 + 上一版 ×1。
const int kLibspSlots = 3;

/// 单份快照的最大片数（序号/总片是两位 ASCII）。
const int kLibspMaxChunks = 99;

/// 一片订阅词的解码结果。
class LibspChunk {
  const LibspChunk({
    required this.slot,
    required this.index,
    required this.total,
    required this.checksum,
    required this.bytes,
  });

  /// 槽位（0 起，见 [kLibspSlots]）。
  final int slot;

  /// 片序号（1 起）。
  final int index;

  /// 同一份快照的总片数。
  final int total;

  /// 24 位校验（CRC-32 低 24 位，覆盖 [bytes]）。
  final int checksum;

  /// 载荷字节（恒 [kLibspChunkBytes] 个）。
  final List<int> bytes;

  @override
  String toString() =>
      'LibspChunk(slot=$slot, index=$index/$total, bytes=${bytes.length})';
}
