/// 网费数据来源。
enum NetFeeSource {
  /// 智慧江财小程序实时校园网计费源（需平台 GUID → 加密 userId）。
  wxLive('实时计费源'),

  /// 门户个人数据中心概览源（人事表口径，非实时；免配置兜底）。
  portal('门户概览'),

  /// 无任何可用来源。
  none('未接入');

  const NetFeeSource(this.label);

  /// 面向用户的短标签。
  final String label;
}

/// 网费余额（小程序计费源口径，单位：元）。
class NetFeeAccount {
  final double balance;

  /// 账号学号（接口回显）。
  final String username;

  const NetFeeAccount({required this.balance, required this.username});
}

/// 网费充值记录（计费源仅有充值明细，无扣费明细）。
class NetFeeRecord {
  final int payId;
  final String businessType;
  final String feeType;
  final double payMoney;
  final String account;
  final DateTime paidAt;
  final String? remark;

  const NetFeeRecord({
    required this.payId,
    required this.businessType,
    required this.feeType,
    required this.payMoney,
    required this.account,
    required this.paidAt,
    this.remark,
  });

  factory NetFeeRecord.fromJson(Map<String, dynamic> json) {
    return NetFeeRecord(
      payId: (json['pay_id'] is num)
          ? (json['pay_id'] as num).toInt()
          : int.tryParse(json['pay_id']?.toString() ?? '') ?? 0,
      businessType: json['business_type']?.toString() ?? '',
      feeType: json['fee_type']?.toString() ?? '',
      payMoney: (json['pay_money'] is num)
          ? (json['pay_money'] as num).toDouble()
          : double.tryParse(json['pay_money']?.toString() ?? '') ?? 0,
      account: json['account']?.toString() ?? '',
      paidAt: _parsePaidAt(json['pay_time']?.toString() ?? ''),
      remark: json['remark']?.toString(),
    );
  }
}

DateTime _parsePaidAt(String raw) {
  // 服务端格式：yyyy-MM-dd HH:mm:ss（本地时间）。
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})')
      .firstMatch(raw);
  if (match == null) return DateTime.now();
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

/// 网费双源汇总结果。
class NetFeeSummary {
  /// 实际展示来源。
  final NetFeeSource source;

  /// 是否已配置平台 GUID（实时源可用前提）。
  final bool hasGuid;

  /// 余额（元）；无任何可用源时为 null。
  final double? balance;

  /// 账号学号。
  final String? username;

  /// 充值记录（仅实时源返回；门户兜底为空）。
  final List<NetFeeRecord> records;

  /// 配置了 GUID 但实时源拉取失败的原因（已自动回退门户）。
  final String? liveError;

  const NetFeeSummary({
    required this.source,
    required this.hasGuid,
    this.balance,
    this.username,
    this.records = const [],
    this.liveError,
  });
}

/// 金额展示：整数不带小数位（50 → '50'），小数保留最短形式（12.5 → '12.5'）。
String fmtYuan(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toString();
}
