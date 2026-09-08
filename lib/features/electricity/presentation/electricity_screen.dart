import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/electricity/data/datasources/electricity_remote_datasource.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';

/// 宿舍电费页。
///
/// 对齐智慧江财小程序体验：进入页面若本地记忆了「该学号已绑定宿舍」，
/// 免手动选择直接查询展示剩余电量；点「更换宿舍」才展开
/// 校区 → 楼栋 → 房间 手动选择（选择后立即查询并更新记忆）。
///
/// 数据来自智慧江财供电服务（wxcourse.jxufe.cn/electricity_charges），
/// 楼栋浮窗同系列归组自然排序，房间浮窗按楼层聚合平铺；
/// 视觉遵循 App 同源语言（白卡细描边圆角 8 + 主色浅底图标盒）。
class ElectricityScreen extends ConsumerStatefulWidget {
  const ElectricityScreen({super.key});

  @override
  ConsumerState<ElectricityScreen> createState() => _ElectricityScreenState();
}

class _ElectricityScreenState extends ConsumerState<ElectricityScreen> {
  final _usernameController = TextEditingController();

  List<RoomNode> _campuses = [];
  List<RoomNode> _buildings = [];
  List<FloorGroup> _floorGroups = [];

  int? _campusId;
  int? _buildingId;
  int? _roomId;

  /// 本地记忆的绑定宿舍（进入页面免选直查）。
  RoomBindingRecord? _binding;

  /// 是否处于手动更换/选择面板。
  bool _picking = false;

  bool _loadingCampuses = true;
  bool _loadingBuildings = false;
  bool _loadingRooms = false;
  bool _busy = false;

  ElectricityBalance? _balance;
  String? _error;
  bool _needBind = false;

  /// 当前绑定房间的充值记录。
  List<ChargingRecord> _records = [];
  bool _loadingRecords = false;

  ElectricityRemoteDataSource get _dataSource =>
      ref.read(electricityRemoteDataSourceProvider);

  @override
  void initState() {
    super.initState();
    _usernameController.text = ref.read(currentAccountProvider);
    _loadCampuses();
    _restoreBinding();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // ---------- 本地绑定记忆 ----------

  Future<void> _restoreBinding() async {
    final username = _username();
    if (username.isEmpty) return;
    try {
      final box = await ref.read(electricityBindingBoxProvider.future);
      final raw = box.get(username);
      if (raw == null || !mounted) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final record = RoomBindingRecord.fromJson(
        json.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (record.roomId <= 0 || !mounted) return;
      setState(() {
        _binding = record;
        _picking = false;
        _balance = null;
        _error = null;
        _needBind = false;
        _records = [];
      });
      await _autoQuery(roomId: record.roomId);
    } catch (_) {
      // 记忆损坏时静默忽略，走手动选择。
    }
  }

  Future<void> _saveBinding(RoomBindingRecord record) async {
    try {
      final box = await ref.read(electricityBindingBoxProvider.future);
      await box.put(_username(), jsonEncode(record.toJson()));
    } catch (_) {
      // 写盘失败不影响本次查询。
    }
  }

  /// 学号变更（回车）后按新学号重查记忆。
  void _onUsernameSubmitted(String _) {
    setState(() {
      _binding = null;
      _picking = false;
      _campusId = null;
      _buildingId = null;
      _roomId = null;
      _balance = null;
      _error = null;
      _needBind = false;
      _records = [];
    });
    _restoreBinding();
  }

  // ---------- 加载（目录） ----------

  Future<void> _loadCampuses() async {
    setState(() {
      _loadingCampuses = true;
      _error = null;
    });
    try {
      final campuses = await _dataSource.fetchCampusList();
      if (!mounted) return;
      setState(() {
        _campuses = campuses;
        _loadingCampuses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCampuses = false;
        _error = _messageOf(e);
      });
    }
  }

  Future<void> _loadBuildings(int campusId) async {
    setState(() {
      _loadingBuildings = true;
      _buildings = [];
      _buildingId = null;
      _floorGroups = [];
      _roomId = null;
      _error = null;
    });
    try {
      final buildings = await _dataSource.fetchBuildings(campusId);
      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _loadingBuildings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBuildings = false;
        _error = _messageOf(e);
      });
    }
  }

  Future<void> _loadRoomsGrouped(int buildingId) async {
    setState(() {
      _loadingRooms = true;
      _floorGroups = [];
      _roomId = null;
      _error = null;
    });
    try {
      final groups = await _dataSource.fetchRoomsGroupedByFloor(buildingId);
      if (!mounted) return;
      setState(() {
        _floorGroups = groups;
        _loadingRooms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
        _error = _messageOf(e);
      });
    }
  }

  // ---------- 查询 ----------

  String _username() => _usernameController.text.trim();

  /// 核心查询：target = 待查房间（记忆绑定房或手动选择房）。
  Future<void> _autoQuery({required int roomId}) async {
    final username = _username();
    if (username.isEmpty) {
      _showError('请输入学号');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _needBind = false;
      _balance = null;
    });
    try {
      final balance = await _dataSource.fetchBalance(
        username: username,
        roomId: roomId,
      );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _busy = false;
      });
      await _loadRecords(roomId);
    } catch (e) {
      if (!mounted) return;
      final message = _messageOf(e);
      setState(() {
        _busy = false;
        _error = message;
        _needBind = e is ElectricityApiException && message.contains('未绑定');
      });
    }
  }

  /// 拉取当前绑定房间的充值记录（成功后调用；失败静默，不打断查询结果）。
  Future<void> _loadRecords(int roomId) async {
    final username = _username();
    if (username.isEmpty || _loadingRecords) return;
    setState(() => _loadingRecords = true);
    try {
      final (records, _) = await _dataSource.fetchChargingRecords(
        username: username,
        roomId: roomId,
        pageSize: 20,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loadingRecords = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRecords = false;
      });
    }
  }

  /// 「绑定到当前房间并查询」：把当前学号绑定到目标房间后重查。
  Future<void> _bindAndQuery() async {
    final username = _username();
    final targetRoomId = _binding?.roomId ?? _roomId;
    if (username.isEmpty || targetRoomId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _dataSource.bindRoom(username: username, roomId: targetRoomId);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('绑定成功，正在查询电量...')),
      );
      await _autoQuery(roomId: targetRoomId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageOf(e);
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _needBind = false;
      _balance = null;
    });
  }

  String _messageOf(Object e) =>
      e is ElectricityApiException ? e.message : e.toString();

  // ---------- 手动更换流程 ----------

  /// 宿舍卡点击：进入更换（预载原宿舍校区楼栋，方便快速换房）。
  void _startPicking() {
    setState(() {
      _picking = true;
      _balance = null;
      _error = null;
      _needBind = false;
    });
    if (_campusId == null && _binding != null) {
      _campusId = _binding!.campusId;
      _loadBuildings(_binding!.campusId);
    }
  }

  void _onCampusSelected(int campusId) {
    if (_campusId == campusId) return;
    setState(() => _campusId = campusId);
    _loadBuildings(campusId);
  }

  Future<void> _pickBuilding() async {
    if (_loadingBuildings) return;
    if (_buildings.isEmpty) {
      _showError('该校区暂无楼栋数据');
      return;
    }
    final selected = await _showPicker<int>(
      title: '选择楼栋',
      blocks: _buildingBlocks(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _buildingId = selected;
      _roomId = null;
      _balance = null;
      _error = null;
    });
    await _loadRoomsGrouped(selected);
  }

  Future<void> _pickRoom() async {
    if (_loadingRooms) return;
    if (!_floorGroups.any((g) => g.rooms.isNotEmpty)) {
      _showError('该楼栋暂无房间数据');
      return;
    }
    final roomId = await _showPicker<int>(
      title: '选择房间',
      subtitle: '房号按楼层聚合',
      blocks: _roomBlocks(),
    );
    if (roomId == null || !mounted) return;
    // 组装本地记忆记录并落盘。
    String? floorName;
    int? floorId;
    String? roomName;
    for (final g in _floorGroups) {
      for (final r in g.rooms) {
        if (r.id == roomId) {
          floorName = g.floorName;
          floorId = g.floorId;
          roomName = r.name;
        }
      }
    }
    final record = RoomBindingRecord(
      campusId: _campusId ?? 0,
      buildingId: _buildingId ?? 0,
      floorId: floorId ?? 0,
      roomId: roomId,
      campusName: _campusName(),
      buildingName: _selectedBuildingName() ?? '',
      floorName: floorName ?? '',
      roomName: roomName ?? '',
    );
    setState(() {
      _roomId = roomId;
      _binding = record;
      _picking = false;
      _balance = null;
      _error = null;
      _needBind = false;
      _records = [];
    });
    await _saveBinding(record);
    await _autoQuery(roomId: roomId);
  }

  String _campusName() {
    for (final c in _campuses) {
      if (c.id == _campusId) return c.name;
    }
    return '';
  }

  String? _selectedBuildingName() {
    if (_buildingId == null) return null;
    for (final b in _buildings) {
      if (b.id == _buildingId) return b.name;
    }
    return null;
  }

  // ---------- 楼栋聚合分组 ----------

  static String _buildingGroupKey(String name) {
    final match = RegExp(r'^(.*?)([0-9]+|[A-Za-z])栋$').firstMatch(name);
    if (match == null) return name;
    final prefix = match.group(1)!;
    return prefix.isEmpty ? name : prefix;
  }

  static String _buildingShortName(String name) {
    final match = RegExp(r'^.*?([0-9]+|[A-Za-z])栋$').firstMatch(name);
    if (match == null) return name;
    return '${match.group(1)}栋';
  }

  static List<RoomNode> _sortBuildingGroup(List<RoomNode> group) {
    final sorted = [...group];
    sorted.sort((a, b) => _compareBuildingNames(a.name, b.name));
    return sorted;
  }

  static int _compareBuildingNames(String a, String b) {
    String? tailOf(String name) {
      final m = RegExp(r'^.*?([0-9]+|[A-Za-z])栋$').firstMatch(name);
      return m?.group(1);
    }

    final at = tailOf(a);
    final bt = tailOf(b);
    if (at == null || bt == null) {
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.compareTo(b);
    }
    final an = int.tryParse(at);
    final bn = int.tryParse(bt);
    if (an != null && bn != null) return an - bn;
    if (an != null) return -1;
    if (bn != null) return 1;
    return at.compareTo(bt);
  }

  List<MapEntry<String, List<RoomNode>>> _groupedBuildings() {
    final order = <String>[];
    final map = <String, List<RoomNode>>{};
    for (final b in _buildings) {
      final key = _buildingGroupKey(b.name);
      if (!map.containsKey(key)) {
        map[key] = [];
        order.add(key);
      }
      map[key]!.add(b);
    }
    return [
      for (final key in order) MapEntry(key, _sortBuildingGroup(map[key]!)),
    ];
  }

  // ---------- 窗口式选择浮窗 ----------

  Future<T?> _showPicker<T>({
    required String title,
    String? subtitle,
    required List<Widget> blocks,
  }) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final width = size.width > 600 ? 480.0 : size.width - 48;
        final height = size.height * 0.72;
        final scheme = Theme.of(dialogContext).colorScheme;
        final text = Theme.of(dialogContext).textTheme;
        return Dialog(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: height),
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16, thickness: 0.6),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
                      children: blocks,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dialogGroupHeader(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _dialogChip({
    required BuildContext context,
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildingBlocks() {
    return [
      for (final group in _groupedBuildings()) ...[
        _dialogGroupHeader(context, group.key),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in group.value)
              _dialogChip(
                context: context,
                selected: _buildingId == b.id,
                onTap: () => Navigator.of(context).pop(b.id),
                child: Text(_buildingShortName(b.name)),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _roomBlocks() {
    final groups =
        _floorGroups.where((g) => g.rooms.isNotEmpty).toList(growable: false);
    return [
      for (final group in groups) ...[
        _dialogGroupHeader(context, group.floorName),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final room in group.rooms)
              _dialogChip(
                context: context,
                selected: _roomId == room.id,
                onTap: () => Navigator.of(context).pop(room.id),
                child: Text(room.name),
              ),
          ],
        ),
      ],
    ];
  }

  // ---------- 页面布局 ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('宿舍电费'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          TextField(
            controller: _usernameController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: _onUsernameSubmitted,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              labelText: '学号',
              hintText: '默认当前登录账号 · 回车切换',
              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel(context, '我的宿舍'),
          const SizedBox(height: 10),
          _buildDormCard(context),
          if (_picking) ...[
            const SizedBox(height: 20),
            _sectionLabel(context, '更换宿舍'),
            const SizedBox(height: 10),
            if (_loadingCampuses)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_campuses.isNotEmpty) ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final campus in _campuses)
                    _campusPill(
                      context,
                      label: campus.name,
                      selected: _campusId == campus.id,
                      onTap: () => _onCampusSelected(campus.id),
                    ),
                ],
              ),
              if (_campusId != null) ...[
                const SizedBox(height: 12),
                _selectCard(
                  context: context,
                  icon: Icons.apartment_outlined,
                  selected: _buildingId != null,
                  loading: _loadingBuildings,
                  value: _selectedBuildingName(),
                  placeholder: '点击选择楼栋',
                  onTap: _pickBuilding,
                ),
              ],
              if (_buildingId != null) ...[
                const SizedBox(height: 12),
                _selectCard(
                  context: context,
                  icon: Icons.door_sliding_outlined,
                  selected: _roomId != null,
                  loading: _loadingRooms,
                  value: _roomId == null
                      ? null
                      : _selectedRoomLabel(),
                  placeholder: '点击选择房间',
                  onTap: _pickRoom,
                ),
              ],
            ],
          ],
          const SizedBox(height: 24),
          _buildResult(context),
          if (_binding != null && _balance != null) ...[
            const SizedBox(height: 24),
            _sectionLabel(context, '充值记录'),
            const SizedBox(height: 10),
            _buildRecords(context),
          ],
        ],
      ),
    );
  }

  /// 充值记录区块：余额下的小卡列表（金额 + 支付方式/备注 + 时间）。
  Widget _buildRecords(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingRecords && _records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_records.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '暂无充值记录',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _records.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 0.6, color: scheme.outlineVariant),
            _buildRecordRow(context, _records[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordRow(BuildContext context, ChargingRecord record) {
    final scheme = Theme.of(context).colorScheme;
    final time = record.paidAt;
    final timeText = time == null
        ? ''
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-'
            '${time.day.toString().padLeft(2, '0')} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_card_outlined,
                size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.remark.isEmpty ? '电费充值' : record.remark,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (record.payTypeName.isNotEmpty) record.payTypeName,
                    if (timeText.isNotEmpty) timeText,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${record.amountYuan.toStringAsFixed(2)} 元',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 宿舍卡：已绑定 → 显示宿舍串，点击更换；未绑定 → 提示点击选择。
  Widget _buildDormCard(BuildContext context) {
    final binding = _binding;
    return _selectCard(
      context: context,
      icon: Icons.home_work_outlined,
      selected: binding != null,
      loading: false,
      value: binding?.display,
      placeholder: _picking ? '正在选择…' : '尚未绑定宿舍，点击选择',
      onTap: _picking ? null : _startPicking,
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ---------- 选择卡 ----------

  String? _selectedRoomLabel() {
    if (_roomId == null) return null;
    for (final group in _floorGroups) {
      for (final r in group.rooms) {
        if (r.id == _roomId) {
          return r.code == null || r.code!.isEmpty
              ? r.name
              : '${r.name} · 编码 ${r.code}';
        }
      }
    }
    return null;
  }

  Widget _campusPill(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// App 同源选择卡：白底细描边圆角 8 + 主色浅底图标盒；
  /// 选中后主色描边 + 淡底 + 勾选。
  Widget _selectCard({
    required BuildContext context,
    required IconData icon,
    required bool selected,
    required bool loading,
    required String? value,
    required String placeholder,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.05)
            : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: loading
                      ? Text(
                          '查询中…',
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : Text(
                          value ?? placeholder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: value != null ? 14.5 : 15,
                            fontWeight: value != null
                                ? FontWeight.w500
                                : FontWeight.w400,
                            height: 1.3,
                            color: value != null
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (onTap == null)
                  const SizedBox.shrink()
                else if (selected)
                  Icon(Icons.edit_outlined, size: 18, color: scheme.primary)
                else
                  Icon(Icons.chevron_right,
                      size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 结果 / 错误 ----------

  Widget _buildResult(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final error = _error;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.error.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_needBind) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _bindAndQuery,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: scheme.primary),
                foregroundColor: scheme.primary,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.link, size: 18),
              label: Text(_binding != null ? '绑定该宿舍并查询' : '绑定到当前房间并查询'),
            ),
          ],
        ],
      );
    }

    final balance = _balance;
    if (balance == null) {
      if (_binding != null && _busy) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        );
      }
      if (_binding == null && !_picking) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '点上方「我的宿舍」选择或绑定宿舍后，将自动显示剩余电量。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            '剩余电量',
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                balance.balance,
                style: TextStyle(
                  fontSize: 42,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                balance.unit,
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _binding?.display ?? balance.roomNo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
