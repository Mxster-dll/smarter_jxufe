import 'dart:typed_data';

class QrCodeData {
  final String id;
  final String? verifyCode;
  final String imgUrl;
  final Uint8List img;

  const QrCodeData({
    required this.id,
    this.verifyCode,
    required this.imgUrl,
    required this.img,
  });

  QrCodeData copyWith({
    String? id,
    String? verifyCode,
    String? imgUrl,
    Uint8List? img,
  }) {
    return QrCodeData(
      id: id ?? this.id,
      verifyCode: verifyCode ?? this.verifyCode,
      imgUrl: imgUrl ?? this.imgUrl,
      img: img ?? this.img,
    );
  }
}
