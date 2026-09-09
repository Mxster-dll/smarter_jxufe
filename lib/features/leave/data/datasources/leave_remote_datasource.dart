import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/leave/domain/leave_models.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/wxcal_remote_datasource.dart';

/// 请假接口异常（message 面向 UI 直显）。
class LeaveApiException implements Exception {
  final String message;

  const LeaveApiException(this.message);

  @override
  String toString() => message;
}

/// 「学生请假」记录数据源（智慧江财小程序 · 金智流程应用）。
///
/// 实测链路（2026-09）：全部走 https://wxcourse.jxufe.edu.cn 的
/// `/interface/api/interface/*` 聚合接口，请求体 = 业务参数 + 平台注入的
/// username=平台 GUID + bn_timestamp/bn_nonce/bn_sign（复用
/// [bnSignedBody]，与校历同款 MD5 签名）。无需 jwtToken/accessKey。
///
/// 调用方：
/// - 列表：getCurrentActHandProcessFlow（我参与的流程，type 1 + id 120 + code 01）
/// - 详情：getApplicationForLeaveInfo（按 instanceId 取单条）
/// - 审批：getHiProcessCommentsFlow（按 instanceId 取审批历史）
class LeaveRemoteDataSource {
  LeaveRemoteDataSource(this._dio);

  final Dio _dio;

  static const String _host = 'https://wxcourse.jxufe.edu.cn';
  static const String _interface = '$_host/interface/api/interface';

  /// 「我的申请」应用 appid（processParticipate 学生请假）。
  static const String _appid = '1590716335264';

  static const String _defId = 'applicationForLeave:1:1298232';

  static const String _flagCommon = 'weixin';
  static const String _callback = 'callback';

  /// 请假记录列表（我参与的流程，含全部状态）。
  Future<List<LeaveListRecord>> fetchList({
    required String guid,
    required String wxUsername,
    int pageNo = 1,
    int pageSize = 20,
  }) async {
    final body = bnSignedBody(
      guid: guid,
      appid: _appid,
      params: <String, dynamic>{
        'callback': _callback,
        'flag': _flagCommon,
        'jsonpCallback': 'callback',
        'forwardUrl': '/management/workFlow/myParticipantFlows/list.htm',
        'wxUsername': wxUsername,
        'pageNo': pageNo,
        'pageSize': pageSize,
        'formKeys': '',
        'startTime': '',
        'endTime': '',
        'statusFlag': '',
        'type': 1,
        'id': 120,
        'code': '01',
      },
    );
    final resp = await _dio.post<dynamic>('$_interface/getCurrentActHandProcessFlow',
        data: body);
    final root = _unwrap(resp);
    final page = root['page'];
    final rows = (page is Map ? page['result'] : null);
    if (rows is! List) return const [];
    final out = <LeaveListRecord>[];
    for (final r in rows) {
      if (r is Map) {
        out.add(LeaveListRecord.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))));
      }
    }
    // 进行中的流程优先，其次按开始时间倒序。
    out.sort((a, b) {
      if (a.inProgress != b.inProgress) return a.inProgress ? -1 : 1;
      final at = a.startedAt;
      final bt = b.startedAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return out;
  }

  /// 单条请假详情。
  Future<LeaveDetailInfo> fetchDetail({
    required String guid,
    required String wxUsername,
    required String instanceId,
  }) async {
    final body = bnSignedBody(
      guid: guid,
      appid: _appid,
      params: <String, dynamic>{
        'defId': _defId,
        'instanceId': instanceId,
        'wxUsername': wxUsername,
        'pageNum': 1,
        'pageSize': 20,
      },
    );
    final resp = await _dio.post<dynamic>(
        '$_interface/getApplicationForLeaveInfo',
        data: body);
    final data = _asMap(resp.data);
    final code = data['code'];
    if (code != 1 && code != '1') {
      throw LeaveApiException('请假详情查询失败：${_msg(data, 'code $code')}');
    }
    // 三重嵌套：result.result.result[0]
    final rows = data['result']?['result']?['result'];
    if (rows is! List || rows.isEmpty) {
      throw const LeaveApiException('请假详情为空（记录不存在或无权查看）');
    }
    final row = rows.first;
    if (row is! Map) {
      throw const LeaveApiException('请假详情响应格式异常');
    }
    return LeaveDetailInfo.fromJson(
        row.map((k, v) => MapEntry(k.toString(), v)));
  }

  /// 审批历史。
  Future<List<LeaveApprovalStep>> fetchApprovals({
    required String guid,
    required String wxUsername,
    required String instanceId,
  }) async {
    final body = bnSignedBody(
      guid: guid,
      appid: _appid,
      params: <String, dynamic>{
        'callback': _callback,
        'flag': _flagCommon,
        'jsonpCallback': 'callback',
        'forwardUrl':
            '/management/workFlow/pageModule/dispActHistInfo.htm',
        'defId': _defId,
        'wxUsername': wxUsername,
        'instanceId': instanceId,
      },
    );
    final resp = await _dio.post<dynamic>(
        '$_interface/getHiProcessCommentsFlow',
        data: body);
    final data = _asMap(resp.data);
    final code = data['code'];
    if (code != 1 && code != '1') {
      throw LeaveApiException('审批记录查询失败：${_msg(data, 'code $code')}');
    }
    final list = data['result']?['hiList'];
    if (list is! List) return const [];
    final out = <LeaveApprovalStep>[];
    for (final r in list) {
      if (r is Map) {
        out.add(LeaveApprovalStep.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))));
      }
    }
    out.sort((a, b) {
      final at = a.operTime;
      final bt = b.operTime;
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });
    return out;
  }

  /// 校验 code==1 / statusCode==200 并返回 result 体（列表接口）。
  Map<String, dynamic> _unwrap(Response<dynamic> resp) {
    final data = _asMap(resp.data);
    final code = data['code'];
    if (code != 1 && code != '1') {
      throw LeaveApiException('请假接口返回异常：${_msg(data, 'code $code')}');
    }
    final result = data['result'];
    if (result is! Map) {
      throw const LeaveApiException('请假接口响应缺少 result');
    }
    final statusCode = result['statusCode'];
    if (statusCode != null && statusCode != 200 && statusCode != '200') {
      throw LeaveApiException('请假接口返回状态异常：$statusCode');
    }
    return result.map((k, v) => MapEntry(k.toString(), v));
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // fallthrough
      }
    }
    throw const LeaveApiException('请假接口响应格式异常');
  }

  String _msg(Map<String, dynamic> data, String fallback) {
    final msg = data['message']?.toString() ?? '';
    return msg.isEmpty ? fallback : msg;
  }
}
