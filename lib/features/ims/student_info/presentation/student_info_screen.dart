import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';

/// 「我的」页面 —— 左右双列纵排，纯色标题背景。
class StudentInfoScreen extends ConsumerWidget {
  final bool showAppBar;

  const StudentInfoScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(_studentInfoProvider);

    final body = infoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text('加载失败\n$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(_studentInfoProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (info) => _buildContent(context, info),
    );

    if (showAppBar) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的'), centerTitle: true),
        body: body,
      );
    }
    return body;
  }

  Widget _buildContent(BuildContext context, StudentInfo i) {
    const pad = 12.0;
    const colGap = 10.0;

    return ListView(
      padding: const EdgeInsets.all(pad),
      children: [
        _header(context, i),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  _card(context, '身份信息', [
                    _r(context, '姓名', i.name),
                    _r(context, '拼音', i.namePinyin),
                    _r(context, '曾用名', i.formerName),
                    _r(context, '性别', i.gender),
                    _r(context, '民族', i.ethnicity),
                    _r(context, '出生日期', i.birthDate),
                    _r(context, '出生地', i.birthPlace),
                  ]),
                  _card(context, '入学培养', [
                    _r(context, '入学年级', i.enrollYear),
                    _r(
                      context,
                      '学制',
                      i.studyYears.isNotEmpty ? '${i.studyYears}年' : '',
                    ),
                    _r(context, '报到时间', i.enrollDate),
                    _r(context, '招生季节', i.enrollSeason),
                    _r(context, '入学方式', i.enrollMethod),
                    _r(context, '入学前学历', i.prevEducation),
                    _r(context, '培养层次', i.trainLevel),
                    _r(context, '培养方式', i.trainMode),
                    _r(context, '考生类别', i.examineeType),
                    _r(context, '录取专业', i.admittedMajor),
                  ]),
                  _card(context, '证件信息', [
                    _r(context, '身份证号', i.idCardNo),
                    _r(context, '身份证别码', i.idCardAltCode),
                    _r(context, '身份证照片', i.idPhotoPath),
                    _r(context, '身份证正面', i.idPhotoFront),
                  ]),
                  _card(context, '学籍状态', [
                    _r(context, '政治面貌', i.politicalStatus),
                    _r(context, '文化程度', i.educationLevel),
                    _r(context, '户口性质', i.residenceType),
                    _r(context, '健康状况', i.healthStatus),
                    _r(context, '考生特征', i.examineeFeature),
                  ]),

                  _card(context, '高考信息', [
                    _r(context, '考生号', i.gaokaoNo),
                    _r(context, '准考证号', i.gaokaoTicketNo),
                    _r(context, '高考总分', i.gaokaoScore),
                    _r(context, '文化成绩', i.cultureScore),
                    _r(context, '考生特长', i.examineeTalent),
                    _r(context, '生源专业', i.originMajor),
                    _r(context, '招生省市类型', i.admissionType),
                    _r(context, '培养对象', i.trainTarget),
                    _r(context, '生源来源', i.originSource),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: colGap),
            Expanded(
              child: Column(
                children: [
                  _card(context, '学籍标识', [
                    _r(context, '用户号', i.userId),
                    _r(context, '学号', i.studentId),
                    _r(context, '序号', i.serialNo),
                    _r(context, '入学号', i.enrollNo),
                  ]),
                  _card(context, '学院专业', [
                    _r(context, '院系', i.college),
                    _r(context, '专业', i.major),
                    _r(context, '专业方向', i.majorDirection),
                    _r(context, '班级', i.className),
                    _r(context, '学科门类', i.disciplineCategory),
                    _r(context, '宿舍名称', i.dormName),
                    _r(context, '宿舍信息', i.dormInfo),
                  ]),

                  _card(context, '联系方式', [
                    _r(context, '电话', i.phone),
                    _r(context, '邮箱', i.email),
                    _r(context, '通讯地址', i.address),
                    _r(context, '邮编', i.postalCode),
                    _r(context, '籍贯', i.hometown),
                    _r(context, '生源省份', i.originProvince),
                    _r(context, '生源地', i.originPlace),
                    _r(context, '生源地单位', i.originUnit),
                  ]),
                  _card(context, '家庭联系', [
                    _r(context, '联系人', i.contactPerson),
                    _r(context, '家庭联系人', i.familyContact),
                    _r(context, '家庭联系人方式', i.familyContactPhone),
                    _r(context, '宿舍电话', i.dormPhone),
                  ]),
                  _card(context, '其他信息', [
                    _r(context, '辅导员', i.advisor),
                    _r(context, '是否贫困', i.isPoor),
                    _r(context, '贫困类型', i.povertyType),
                    _r(context, '入党团时间', i.partyJoinDate),
                    _r(context, '年总收入', i.annualIncome),
                    _r(context, '人均收入', i.perCapitaIncome),
                    _r(context, '学籍卡编号', i.registryNo),
                    _r(context, '外语语种', i.foreignLanguage),
                    _r(context, '计算机等级', i.computerLevel),
                    _r(context, '所属集团', i.groupInfo),
                  ]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── 头部 ──
  Widget _header(BuildContext context, StudentInfo i) => Column(
    children: [
      CircleAvatar(
        radius: 40,
        backgroundColor: Theme.of(context).colorScheme.error,
        child: Text(
          i.name.isNotEmpty ? i.name[0] : '?',
          style: TextStyle(
            fontSize: 36,
            color: Theme.of(context).colorScheme.onError,
          ),
        ),
      ),
      const SizedBox(height: 12),
      // 名字居中，退出图标紧贴右侧
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 34), // 与右侧图标等宽，保证名字绝对居中
          Text(i.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: '',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      _dotRow(
        context,
        i.college,
        i.className,
        Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 2),
      _dotRow(
        context,
        i.userId,
        i.studentId,
        Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  // ── 点居中行 ──
  Widget _dotRow(
    BuildContext context,
    String left,
    String right,
    TextStyle? style,
  ) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            textAlign: TextAlign.end,
            style: style?.copyWith(color: color),
          ),
        ),
        Text(' · ', style: style?.copyWith(color: color)),
        Expanded(
          child: Text(
            right,
            textAlign: TextAlign.start,
            style: style?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  // ── 卡片 ──
  Widget _card(BuildContext context, String title, List<Widget> rows) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                color: Color.fromARGB(255, 239, 160, 160),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── 键值行 ──
Widget _r(BuildContext context, String label, String value) {
  final scheme = Theme.of(context).colorScheme;
  final isEmpty = value.isEmpty;
  final labelColor = isEmpty
      ? scheme.onSurfaceVariant.withOpacity(0.3)
      : scheme.onSurfaceVariant;
  final valueColor = isEmpty
      ? scheme.onSurface.withOpacity(0.25)
      : scheme.onSurface;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: TextStyle(fontSize: 14, color: labelColor)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            isEmpty ? '（无）' : value,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: 14, color: valueColor),
          ),
        ),
      ],
    ),
  );
}

/// 从仓库获取学生信息。
final _studentInfoProvider = FutureProvider<StudentInfo>((ref) async {
  final repo = await ref.watch(studentInfoRepositoryProvider.future);
  final result = await repo.getStudentInfo();
  return result.fold(
    (failure) => throw Exception(failure.message ?? '获取学生信息失败'),
    (info) => info,
  );
});
