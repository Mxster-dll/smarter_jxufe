import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// 微信 Native 支付链接的前缀（校方那张二维码里装的就是它）。
const String kWeChatPayUrlScheme = 'weixin://';

/// 从校方那张二维码 jpg 里解出支付链接；解不出来返回 `null`。
///
/// **为什么需要它**（2026-10-09 四轮 · 用户原话「我希望在手机端可以唤起微信支付」）：
/// 校方二维码是**服务端生成的图片**，图片内容是微信 Native 支付的 code_url
/// （实测解出来就是 `weixin://wxpay/bizpayurl?pr=…`），而服务端**不暴露**这个链接 ——
/// `checkOrder` 只回 `{orderno, paystate}`，另外试的 7 个可能的 JSON 路径全是 404。
/// 手机上也没有第二台设备可以扫码，所以只能把码解出来、交给系统打开去唤起微信。
///
/// 解码链：`image`（已在依赖里）把 jpg 解成像素 → `zxing2`（纯 Dart 的 ZXing 移植，
/// 无平台配置）读二维码。**失败一律返回 `null`**（调用方回退到「显示二维码让人扫」），
/// 不抛异常 —— 二维码解不出来不该让整笔充值走不下去。
String? decodeWeChatPayUrl(Uint8List qrJpgBytes) {
  // ⚠ `decodeImage` 对**垃圾字节**是抛异常（不是返回 null）—— 实测喂 3 个字节就炸。
  // 这条链上的任何失败都必须退化成 null，否则一笔充值会被一张坏图卡死。
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(qrJpgBytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  // ⚠ **必须先强制转 3 通道**：`image` 解 1-bit / 调色板 PNG 时，`getPixel()` 给的
  // 是**未缩放的通道值**（0/1 而不是 0/255），照原样打包成亮度 → zxing2 看到一张
  // 全黑图 → `ReaderException`（实测：同一张码存成 1-bit PNG 解不出来、存成 RGB PNG
  // 或 jpg 就能解）。校方现在给的是 jpg，但这条加固能挡住它哪天换 PNG。
  final rgb = decoded.convert(numChannels: 3);
  final width = rgb.width;
  final height = rgb.height;
  if (width <= 0 || height <= 0) return null;

  // zxing2 要的是「每像素一个 int」的亮度源（RGB 打包），逐点取。
  final pixels = Int32List(width * height);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = rgb.getPixel(x, y);
      pixels[i++] = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
  }
  try {
    final source = RGBLuminanceSource(width, height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final text = QRCodeReader().decode(bitmap).text.trim();
    if (text.isEmpty) return null;
    return text;
  } catch (_) {
    // NotFoundException / FormatException / ChecksumException 都归这里。
    return null;
  }
}
