/// 教务前端参数加密（Kingo DES）—— 逐位移植教务的
/// `/custom/js/jkingo.des.js`（`strEnc`）与 `/custom/js/SetKingoEncypt.jsp`（`getEncParams`）。
///
/// 提交选课 / 退选的端点要求请求体形如：
/// ```
/// params=<base64(hex(strEnc(明文参数, 服务端临时密钥)))>&token=<md5>&timestamp=<服务端时间>
/// ```
/// 其中
/// * **临时密钥** = `GET /frame/homepage?method=getTempDeskey`（每次随机）
/// * ** timestamp** = `GET /frame/homepage?method=getTempNowtime`（形如 `2026-09-14 13:06:49`）
/// * **token** = `md5(md5(明文参数) + md5(timestamp))`（小写十六进制）
/// * **strEnc** = 教务那支 JS 库自己的 DES 变体（`kingo_des_tables.dart` 的表由该库机械导出，
///   位序约定与标准 DES 输出不同，**不能换成 pointycastle 的 DESEngine**）。
///
/// 明文参数的 4 字符一块、末块零填充，每块依次用密钥的前 4 字符块迭代加密——
/// 密钥是随机数字串（约 23 字符 → 6 块），所以块数与密钥长度都要按传入值走。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'kingo_des_tables.dart';

/// 教务 JS `strToBt`：≤4 个 UTF-16 码元 → 64 位（每码元 16 位，高位在前，不足补 0）。
List<int> _strToBt(String str) {
  final bits = List<int>.filled(64, 0);
  final count = str.length < 4 ? str.length : 4;
  for (var i = 0; i < count; i++) {
    final code = str.codeUnitAt(i);
    for (var j = 0; j < 16; j++) {
      bits[16 * i + j] = (code >> (15 - j)) & 1;
    }
  }
  return bits;
}

/// 教务 JS `getKeyBytes`：密钥按 4 字符切块，每块一个 64 位子密钥。
List<List<int>> _keyBlocks(String key) {
  final blocks = <List<int>>[];
  final full = key.length ~/ 4;
  for (var i = 0; i < full; i++) {
    blocks.add(_strToBt(key.substring(i * 4, i * 4 + 4)));
  }
  if (key.length % 4 > 0) {
    blocks.add(_strToBt(key.substring(full * 4)));
  }
  return blocks;
}

List<int> _permute(List<int> input, List<int> table) =>
    List<int>.generate(table.length, (j) => input[table[j]]);

/// 16 组 48 位子密钥（表已把 PC1 + 循环左移 + PC2 复合成「来源位」映射）。
List<List<int>> _generateKeys(List<int> keyBits) => List<List<int>>.generate(
  16,
  (k) => List<int>.generate(48, (j) => keyBits[kDesSubkeySource[k * 48 + j]]),
);

List<int> _sBoxPermute(List<int> expanded) {
  final out = List<int>.filled(32, 0);
  for (var box = 0; box < 8; box++) {
    var index = 0;
    for (var k = 0; k < 6; k++) {
      index = (index << 1) | expanded[box * 6 + k];
    }
    final value = kDesSBox[box * 64 + index];
    for (var k = 0; k < 4; k++) {
      out[box * 4 + k] = (value >> (3 - k)) & 1;
    }
  }
  return out;
}

/// 单块 DES（教务 JS `enc`）。
List<int> _encryptBlock(List<int> dataBits, List<int> keyBits) {
  final keys = _generateKeys(keyBits);
  final permuted = _permute(dataBits, kDesInitPermute);
  var left = permuted.sublist(0, 32);
  var right = permuted.sublist(32);
  for (var round = 0; round < 16; round++) {
    final previousLeft = left;
    left = right;
    final expanded = _permute(right, kDesExpandPermute);
    final mixed = List<int>.generate(48, (j) => expanded[j] ^ keys[round][j]);
    final substituted = _permute(_sBoxPermute(mixed), kDesPPermute);
    right = List<int>.generate(32, (j) => substituted[j] ^ previousLeft[j]);
  }
  // 教务 JS 的循环里自带左右交换，因此末块直接拼 (right, left)。
  return _permute(<int>[...right, ...left], kDesFinallyPermute);
}

String _bitsToHex(List<int> bits) {
  const digits = '0123456789ABCDEF';
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final nibble =
        (bits[i * 4] << 3) |
        (bits[i * 4 + 1] << 2) |
        (bits[i * 4 + 2] << 1) |
        bits[i * 4 + 3];
    buffer.write(digits[nibble]);
  }
  return buffer.toString();
}

/// 教务 JS `strEnc(data, key, null, null)`：返回大写十六进制串（每 4 个明文字符 16 个十六进制字符）。
String kingoStrEnc(String data, String key) {
  if (data.isEmpty || key.isEmpty) return '';
  final keyBlocks = _keyBlocks(key);
  String encryptChunk(String chunk) {
    var bits = _strToBt(chunk);
    for (final keyBits in keyBlocks) {
      bits = _encryptBlock(bits, keyBits);
    }
    return _bitsToHex(bits);
  }

  final buffer = StringBuffer();
  if (data.length < 4) {
    buffer.write(encryptChunk(data));
    return buffer.toString();
  }
  final full = data.length ~/ 4;
  for (var i = 0; i < full; i++) {
    buffer.write(encryptChunk(data.substring(i * 4, i * 4 + 4)));
  }
  if (data.length % 4 > 0) {
    buffer.write(encryptChunk(data.substring(full * 4)));
  }
  return buffer.toString();
}

/// 教务 JS `getEncParams` 的 token 部分：`md5(md5(params) + md5(timestamp))`（小写十六进制）。
///
/// ⚠️ 与 JS 一致，按**每个 UTF-16 码元的低 8 位**做 MD5（教务的 md5.js 用 `charCodeAt & 0xff`），
/// 因此对 ASCII 参数（选课/退选的全部字段都是码值）与 UTF-8 等价。
String kingoEncToken(String params, String timestamp) {
  List<int> lowBytes(String s) =>
      List<int>.generate(s.length, (i) => s.codeUnitAt(i) & 0xff);
  final paramsDigest = md5.convert(lowBytes(params)).toString();
  final timeDigest = md5.convert(lowBytes(timestamp)).toString();
  return md5.convert(utf8.encode('$paramsDigest$timeDigest')).toString();
}

/// 教务 JS `getEncParams`：把明文参数变成可直接发送的 urlencoded 请求体。
///
/// 返回值形如 `params=<base64>&token=<md5>&timestamp=<服务端时间>`，
/// 直接作为 `application/x-www-form-urlencoded` 请求体提交即可。
String kingoEncParams(
  String params, {
  required String tempDeskey,
  required String timestamp,
}) {
  final hex = kingoStrEnc(params, tempDeskey);
  // 教务 b64_encode(data) = base64encode(utf16to8(data))，这里的 data 是纯 ASCII 十六进制串。
  final encoded = base64.encode(ascii.encode(hex));
  final token = kingoEncToken(params, timestamp);
  // 时间戳里的空格必须是 %20（不能用 Uri.encodeQueryComponent，它会把空格变成 '+'）。
  return 'params=$encoded&token=$token&timestamp=${Uri.encodeComponent(timestamp)}';
}
