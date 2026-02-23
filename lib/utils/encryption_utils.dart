// lib/utils/encryption_utils.dart
// import 'package:pointycastle/pointycastle.dart';
// import 'package:pointycastle/api.dart';
// import 'dart:convert';
// import 'dart:typed_data';

class EncryptionUtils {
  static String rsaEncrypt(String plaintext, String publicKey) {
    // TODO: 实现RSA加密
    // 由于RSA加密较复杂，这里暂时返回原始文本
    // 实际应用中需要导入pointycastle库并实现RSA加密
    return '__RSA__' + plaintext;
  }

  static bool isRsaEncrypted(String text) {
    return text.startsWith('__RSA__');
  }

  static String removeRsaPrefix(String text) {
    if (isRsaEncrypted(text)) {
      return text.substring(8);
    }
    return text;
  }

  // 生成指纹ID（简化版）
  static String generateFingerprint() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 1000000;
    // return 'fp_${timestamp}_${random}';
    return '';
  }
}
