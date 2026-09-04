import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as dzj_enc;

/// 竹简数据中台（dzj.jxufe.edu.cn）的双向 AES 加密协议。
///
/// 请求体与 JSON 响应中的 data 字段均为 `timestamp:nonce:base64cipher`
/// 格式的密文串，使用 AES-ECB/PKCS7 无 IV 加密，会话密钥由服务器下发的
/// `fixedSalt` 经两级 HMAC-SHA256 派生：
///
/// ```text
/// a   = HmacSHA256(key = Base64Decode(fixedSalt), msg = "<ts>:<nonce>")
/// key = HmacSHA256(key = a,                      msg = "AES-Key-128")[0..16)
/// ```
class DzjCrypto {
  DzjCrypto._();

  static final Random _random = Random.secure();

  /// 派生指定时间戳与随机数下的 AES-128 会话密钥。
  static List<int> _deriveKey(String fixedSalt, String ts, String nonce) {
    final salt = base64.decode(fixedSalt);
    final msg = utf8.encode('$ts:$nonce');
    final a = Hmac(sha256, salt).convert(msg).bytes;
    final key = Hmac(sha256, a).convert(utf8.encode('AES-Key-128')).bytes;
    return key.sublist(0, 16);
  }

  static String _newNonce() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 加密请求体为 `ts:nonce:base64` 密文串。
  static String encrypt(String plain, String fixedSalt) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _newNonce();
    final key = dzj_enc.Key.fromBase64(
      base64.encode(_deriveKey(fixedSalt, ts, nonce)),
    );
    final encrypter = dzj_enc.Encrypter(
      dzj_enc.AES(key, mode: dzj_enc.AESMode.ecb),
    );
    final cipher = encrypter.encrypt(plain);
    return '$ts:$nonce:${cipher.base64}';
  }

  /// 解密 `ts:nonce:base64` 密文串。
  ///
  /// 传入内容不含两个冒号分隔（如明文 JSON）时原样返回。
  static String decrypt(String payload, String fixedSalt) {
    final parts = payload.split(':');
    if (parts.length != 3) return payload;
    final ts = parts[0];
    final nonce = parts[1];
    final cipherB64 = parts[2];
    final key = dzj_enc.Key.fromBase64(
      base64.encode(_deriveKey(fixedSalt, ts, nonce)),
    );
    final encrypter = dzj_enc.Encrypter(
      dzj_enc.AES(key, mode: dzj_enc.AESMode.ecb),
    );
    final decrypted = encrypter.decrypt(
      dzj_enc.Encrypted.fromBase64(cipherB64),
    );
    return decrypted;
  }
}
