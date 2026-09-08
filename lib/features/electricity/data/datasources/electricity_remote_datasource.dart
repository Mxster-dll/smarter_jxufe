import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';

/// 智慧江财小程序供电服务（wxcourse.jxufe.cn/electricity_charges）远程数据源。
///
/// 逆向自小程序包 wx70c0beda0bb7b021（智慧江财）内 sdjf/dfcz 页面：
/// - 宿舍级联目录：`/electricity_charges/room/find{Campus,Building,Floor,Room}List*`
///   （免鉴权，仅需 Referer）；
/// - 绑定：GET `/electricity_charges/room/bindUserRoom?username=<学号>&roomId=<房间id>`；
/// - 余额：GET `/electricity_charges/api/charges/findRoomBalance?username&roomId`，
///   仅对「已绑定该房间」的学号返回余额，其余返回
///   code -1「未绑定该房间！」/「房间信息不存在！」。
///
/// 注意：`roomId` 是内部主键（如 6499），与展示用房间号
/// （roomManuCode，如 12464 / name 如 05602）不同，只能经由级联目录获得。
class ElectricityRemoteDataSource {
  final Dio _dio;

  ElectricityRemoteDataSource(this._dio);

  // ---------- 宿舍级联目录 ----------

  Future<List<RoomNode>> fetchCampusList() async {
    final result = await _get('/electricity_charges/room/findCampusList');
    return _toNodes(result, nameKey: 'campus');
  }

  Future<List<RoomNode>> fetchBuildings(int campusId) async {
    final result = await _get(
      '/electricity_charges/room/findBuildingList',
      queryParameters: {'campusId': campusId},
    );
    return _toNodes(result);
  }

  Future<List<RoomNode>> fetchFloors(int buildingId) async {
    final result = await _get(
      '/electricity_charges/room/findFloorListByBuilding',
      queryParameters: {'buildingId': buildingId},
    );
    return _toNodes(result);
  }

  Future<List<RoomNode>> fetchRooms(int floorId) async {
    final result = await _get(
      '/electricity_charges/room/findRoomListByFloor',
      queryParameters: {'floorId': floorId},
    );
    if (result is! List) return const [];
    final nodes = <RoomNode>[];
    for (final item in result) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is! num || name is! String) continue;
      final code = item['roomManuCode'];
      nodes.add(
        RoomNode(
          id: id.toInt(),
          name: name,
          code: code is String && code.isNotEmpty ? code : null,
        ),
      );
    }
    return nodes;
  }

  /// 一次性取某楼栋的全部房间：先列楼层，再并发拉取每层房间，
  /// 按楼层顺序聚合（供「平铺但按楼层分组」的 UI 使用）。
  Future<List<FloorGroup>> fetchRoomsGroupedByFloor(int buildingId) async {
    final floors = await fetchFloors(buildingId);
    final groups = await Future.wait(
      floors.map((floor) async {
        final rooms = await fetchRooms(floor.id);
        return FloorGroup(
          floorId: floor.id,
          floorName: floor.name,
          rooms: rooms,
        );
      }),
    );
    return groups;
  }

  // ---------- 绑定 ----------

  /// 将 [username]（学号）绑定到 [roomId]（智慧江财内自选宿舍）。
  Future<void> bindRoom({
    required String username,
    required int roomId,
  }) async {
    await _get(
      '/electricity_charges/room/bindUserRoom',
      queryParameters: {'username': username, 'roomId': roomId},
    );
  }

  // ---------- 余额查询 ----------

  /// 查询 [username] 已绑定宿舍（[roomId]）的剩余电量。
  ///
  /// 服务端要求学号已绑定该房间；未绑定时抛
  /// [ElectricityApiException]（code -1「未绑定该房间！」）。
  ///
  /// [_get] 已解包 `{code,message,result}` 并返回 `result` 本体，
  /// 这里 `data` 直接就是 `{unit, roomNo, balance}`，勿再取 `result` 键。
  Future<ElectricityBalance> fetchBalance({
    required String username,
    required int roomId,
  }) async {
    final data = await _get(
      '/electricity_charges/api/charges/findRoomBalance',
      queryParameters: {'username': username, 'roomId': roomId},
    );
    if (data is! Map) {
      throw const ElectricityApiException(-1, '响应缺少电量数据');
    }
    return ElectricityBalance(
      roomNo: (data['roomNo'] ?? '').toString(),
      balance: (data['balance'] ?? '--').toString(),
      unit: (data['unit'] ?? 'kWh').toString(),
    );
  }

  /// 查询 [username] 在 [roomId] 的电费充值记录（按时间倒序，最多 [pageSize] 条）。
  ///
  /// 服务端接口必须用 form-urlencoded 提交（JSON 编码会报「房间信息不存在」）。
  /// 返回（记录列表, 总条数）。
  Future<(List<ChargingRecord>, int)> fetchChargingRecords({
    required String username,
    required int roomId,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.post(
      '/electricity_charges/api/charges/findRoomChargesRecord',
      data: FormData.fromMap({
        'username': username,
        'roomId': roomId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      }),
    );
    final result = _unwrap(response.data);
    final list = result is Map ? result['data'] : null;
    final records = <ChargingRecord>[];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final money = item['money'];
        final remark = item['remark'];
        if (money is! String || remark is! String) continue;
        final moneyYuan = (double.tryParse(money) ?? 0) / 100;
        records.add(
          ChargingRecord(
            amountYuan: moneyYuan,
            payTypeName: item['payTypeName'] as String? ?? '',
            remark: remark,
            paidAt: _parseUtcTime(item['createTime']),
          ),
        );
      }
    }
    final allCount = result is Map ? result['allCount'] : null;
    return (records, allCount is num ? allCount.toInt() : records.length);
  }

  static DateTime? _parseUtcTime(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  // ---------- 内部 ----------

  List<RoomNode> _toNodes(Object? result, {String nameKey = 'name'}) {
    if (result is! List) return const [];
    final nodes = <RoomNode>[];
    for (final item in result) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item[nameKey];
      if (id is! num || name is! String) continue;
      nodes.add(RoomNode(id: id.toInt(), name: name));
    }
    return nodes;
  }

  /// 发起 GET 并解包 `{code, message, success, result}`。
  ///
  /// code != 1 时抛 [ElectricityApiException]（message 可能为
  /// 「未绑定该房间！」等业务提示，UI 原样展示）。
  Future<Object?> _get(String path, {Map<String, Object>? queryParameters}) async {
    final response = await _dio.get(
      path,
      queryParameters: queryParameters,
    );
    return _unwrap(response.data);
  }

  /// 解包 `{code, message, success, result}`；code != 1 抛
  /// [ElectricityApiException]（message 原样给 UI）。
  Object? _unwrap(Object? data) {
    if (data is! Map) {
      throw const ElectricityApiException(-1, '服务响应异常，请稍后重试');
    }
    final code = data['code'];
    if (code is! num || code.toInt() != 1) {
      final message = data['message'];
      throw ElectricityApiException(
        code is num ? code.toInt() : -1,
        message is String && message.isNotEmpty
            ? message
            : '查询失败，请稍后重试',
      );
    }
    return data['result'];
  }
}
