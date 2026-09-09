/// 「学生请假」域模型（智慧江财小程序 · 金智流程应用）。
///
/// 数据源为 wxcourse.jxufe.edu.cn 平台 interface 接口，鉴权 = 平台 GUID +
/// bn 三参数签名（与校历/网费同款，见 wxcal_remote_datasource.bnSignedBody）。
/// 仅实现「我的请假」记录列表 + 详情只读（用户拍板，发起留待后续）。
library;

/// 请假列表行（getCurrentActHandProcessFlow · 我参与的流程）。
class LeaveListRecord {
  const LeaveListRecord({
    required this.instanceId,
    required this.statusFlag,
    required this.defDescription,
    required this.sequenceName,
    required this.formTitle,
    required this.curTaskName,
    required this.startedByName,
    required this.startedByDept,
    required this.startedByGroup,
    this.startedAt,
    this.endedAt,
  });

  /// 实例 id（详情/审批查询参数）。
  final String instanceId;

  /// 0 = 流转中；100 = 已结束。
  final int statusFlag;

  /// 流程定义描述，如「学生请假申请流程」。
  final String defDescription;

  /// 当前（或最后完成）节点名，如「班主任审核」。
  final String sequenceName;

  /// 标题 = form_keys 去掉「姓名-」前缀后的内容（请假事由）。
  final String formTitle;

  /// 节点状态描述（cur_task_name：进行中含节点名，已结束为「流程已结束」）。
  final String curTaskName;

  /// 发起人姓名。
  final String startedByName;

  /// 发起人部门（学院）。
  final String startedByDept;

  /// 发起人分组（本科生等）。
  final String startedByGroup;

  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get inProgress => statusFlag == 0;

  factory LeaveListRecord.fromJson(Map<String, dynamic> json) {
    return LeaveListRecord(
      instanceId: '${json['instance_id'] ?? json['id'] ?? ''}',
      statusFlag: (json['status_flag'] as num?)?.toInt() ?? 100,
      defDescription: json['def_description']?.toString() ?? '',
      sequenceName: json['sequence_name']?.toString() ?? '',
      formTitle: _stripNamePrefix(
        json['form_keys']?.toString() ?? '',
        json['startor_realname']?.toString() ?? '',
      ),
      curTaskName: json['cur_task_name']?.toString() ?? '',
      startedByName: json['startor_realname']?.toString() ?? '',
      startedByDept: json['startor_dept_name']?.toString() ?? '',
      startedByGroup: json['startor_group_name']?.toString() ?? '',
      startedAt: _fromMs(json['start_time']),
      endedAt: _fromMs(json['end_time']),
    );
  }
}

/// 请假单详情（getApplicationForLeaveInfo 单条）。
class LeaveDetailInfo {
  const LeaveDetailInfo({
    required this.instanceId,
    required this.statusName,
    required this.leaveType,
    required this.reason,
    required this.leaveStart,
    required this.leaveEnd,
    required this.leaveDays,
    required this.appliedByName,
    required this.appliedByUsername,
    required this.deptName,
    required this.className,
    required this.buildingDormitory,
    required this.leaveNanchang,
    required this.classHours,
    required this.myPhone,
    required this.parentPhone,
    required this.leaveFile,
    required this.applyDate,
    required this.sex,
    this.id,
  });

  final String instanceId;
  final String? id;

  /// 审批状态（同意 / 待审核…）。
  final String statusName;

  /// 请假类型（事假 / 病假 / 课假）。
  final String leaveType;

  /// 请假事由。
  final String reason;

  /// 起止日期 yyyy-MM-dd。
  final String leaveStart;
  final String leaveEnd;
  final String leaveDays;

  final String appliedByName;
  final String appliedByUsername;
  final String deptName;
  final String className;
  final String buildingDormitory;

  /// 是否离昌（是 / 否）。
  final String leaveNanchang;

  /// 课假节次（课假时如「1,2,3」）。
  final String classHours;

  final String myPhone;
  final String parentPhone;
  final String leaveFile;

  /// 创建时间（如 2026年05月19日）。
  final String applyDate;

  final String sex;

  factory LeaveDetailInfo.fromJson(Map<String, dynamic> json) {
    return LeaveDetailInfo(
      instanceId: '${json['instanceId'] ?? ''}',
      id: json['id']?.toString(),
      statusName: json['leave_status_name']?.toString() ?? '',
      leaveType: json['leave_type']?.toString() ?? '',
      reason: json['leave_reason']?.toString() ?? '',
      leaveStart: json['leave_start']?.toString() ?? '',
      leaveEnd: json['leave_end']?.toString() ?? '',
      leaveDays: json['leave_days']?.toString() ?? '',
      appliedByName: json['apply_cnname']?.toString() ?? '',
      appliedByUsername: json['apply_username']?.toString() ?? '',
      deptName: json['apply_dept_name']?.toString() ?? '',
      className: json['class_name']?.toString() ?? '',
      buildingDormitory: json['building_dormitory']?.toString() ?? '',
      leaveNanchang: json['leave_nanchang']?.toString() ?? '',
      classHours: json['class_hours']?.toString() ?? '',
      myPhone: json['my_phone']?.toString() ?? '',
      parentPhone: json['parent_phone']?.toString() ?? '',
      leaveFile: json['leave_file']?.toString() ?? '',
      applyDate: json['create_date']?.toString() ?? '',
      sex: json['sex']?.toString() ?? '',
    );
  }
}

/// 审批节点（getHiProcessCommentsFlow 历史）。
class LeaveApprovalStep {
  const LeaveApprovalStep({
    required this.actName,
    required this.sequenceName,
    required this.comment,
    required this.assignName,
    required this.assignDept,
    required this.operTime,
  });

  /// 节点名（学生申请请假 / 班主任审核 / 学院分团委审核 / 学院党委副书记审核）。
  final String actName;

  /// 流转名称（交班主任审核…）。
  final String sequenceName;

  /// 审批意见。
  final String comment;

  /// 处理人姓名。
  final String assignName;

  final String assignDept;
  final DateTime? operTime;

  factory LeaveApprovalStep.fromJson(Map<String, dynamic> json) {
    return LeaveApprovalStep(
      actName: json['act_name']?.toString() ?? '',
      sequenceName: json['sequence_name']?.toString() ?? '',
      comment: json['comment']?.toString() ?? '',
      assignName: json['assign_cnname']?.toString() ?? '',
      assignDept: json['assign_dept_name']?.toString() ?? '',
      operTime: _fromMs(json['oper_time']),
    );
  }
}

/// 详情页汇总（单条请假 + 审批历史）。
class LeaveDetailBundle {
  const LeaveDetailBundle({required this.info, required this.approvals});

  final LeaveDetailInfo info;
  final List<LeaveApprovalStep> approvals;
}

DateTime? _fromMs(dynamic v) {
  if (v == null) return null;
  final ms = int.tryParse('$v');
  if (ms == null || ms <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// form_keys 形如「某同学-赴广西…」，去掉发起人姓名前缀得事由。
String _stripNamePrefix(String raw, String name) {
  if (name.isEmpty) return raw;
  final prefix = '$name-';
  if (raw.startsWith(prefix)) return raw.substring(prefix.length);
  return raw;
}
