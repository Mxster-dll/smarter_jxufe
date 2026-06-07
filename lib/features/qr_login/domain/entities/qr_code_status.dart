/// QR码状态枚举
enum QrCodeStatus {
  loading, // 包括未初始化状态
  pending, // 待扫描
  scanned, // 已扫描/待验证
  cancelled, // 手机端已取消
  authorized, // 手机端已确认
  expired, // 失效
  error;

  bool get isFinal => !isNotFinal;
  bool get isNotFinal =>
      this == QrCodeStatus.loading ||
      this == QrCodeStatus.pending ||
      this == QrCodeStatus.scanned;

  /// 是否可重试（显示刷新按钮）
  bool get canRetry =>
      this == QrCodeStatus.cancelled ||
      this == QrCodeStatus.expired ||
      this == QrCodeStatus.error;
}
