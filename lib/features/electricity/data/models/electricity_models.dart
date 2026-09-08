/// 宿舍电费（智慧江财供电服务）数据模型。
library;

/// 级联目录节点（校区 / 楼栋 / 楼层 / 房间通用）。
class RoomNode {
  final int id;
  final String name;

  /// 房间内部编码（roomManuCode，如 `12464`），仅房间级存在。
  final String? code;

  const RoomNode({required this.id, required this.name, this.code});

  /// 下拉展示文本：房间带内部编码（如 `05602 (12464)`）。
  String get label => code == null || code!.isEmpty ? name : '$name ($code)';
}

/// 宿舍电量余额。
class ElectricityBalance {
  /// 房间号（服务端返回的内部编码，如 `12464`）。
  final String roomNo;

  /// 剩余电量数值字符串（如 `194.47`）。
  final String balance;

  /// 计量单位（如 `kWh`）。
  final String unit;

  const ElectricityBalance({
    required this.roomNo,
    required this.balance,
    required this.unit,
  });
}

/// 一个楼层的房间集合（用于「取消楼层选择、按楼层聚合平铺」）。
class FloorGroup {
  final int floorId;
  final String floorName;
  final List<RoomNode> rooms;

  const FloorGroup({
    required this.floorId,
    required this.floorName,
    required this.rooms,
  });
}

/// 本地记忆的「学号 → 已绑定宿舍」，用于进入页面免选直接查询。
///
/// 与智慧江财服务端绑定表相互独立：仅作 App 内快捷记忆；
/// 每次查询仍以服务端「该学号是否绑定该房间」校验为准。
class RoomBindingRecord {
  final int campusId;
  final int buildingId;
  final int floorId;
  final int roomId;

  final String campusName;
  final String buildingName;
  final String floorName;
  final String roomName;

  const RoomBindingRecord({
    required this.campusId,
    required this.buildingId,
    required this.floorId,
    required this.roomId,
    required this.campusName,
    required this.buildingName,
    required this.floorName,
    required this.roomName,
  });

  /// 展示串，如「麦庐校区 · 北区5栋 · 6层 · 05602」。
  String get display =>
      '$campusName · $buildingName · $floorName · $roomName';

  factory RoomBindingRecord.fromJson(Map<String, Object?> json) {
    return RoomBindingRecord(
      campusId: (json['campusId'] as num?)?.toInt() ?? 0,
      buildingId: (json['buildingId'] as num?)?.toInt() ?? 0,
      floorId: (json['floorId'] as num?)?.toInt() ?? 0,
      roomId: (json['roomId'] as num?)?.toInt() ?? 0,
      campusName: json['campusName'] as String? ?? '',
      buildingName: json['buildingName'] as String? ?? '',
      floorName: json['floorName'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'campusId': campusId,
        'buildingId': buildingId,
        'floorId': floorId,
        'roomId': roomId,
        'campusName': campusName,
        'buildingName': buildingName,
        'floorName': floorName,
        'roomName': roomName,
      };
}

/// 业务失败（如「未绑定该房间！」），携带服务端 code 与 message。
class ElectricityApiException implements Exception {
  final int code;
  final String message;

  const ElectricityApiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 一条电费充值记录。
class ChargingRecord {
  /// 充值金额（元）。
  final double amountYuan;

  /// 支付方式名，如「微信支付」。
  final String payTypeName;

  /// 备注，如「充值电费 100.0 元」。
  final String remark;

  /// 支付时间（本地时区）。
  final DateTime? paidAt;

  const ChargingRecord({
    required this.amountYuan,
    required this.payTypeName,
    required this.remark,
    this.paidAt,
  });
}
