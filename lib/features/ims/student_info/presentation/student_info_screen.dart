import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';

/// 「我的」页面 —— 左右双列纵排，纯色标题背景。
class StudentInfoScreen extends ConsumerWidget {
  const StudentInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(_studentInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: true),
      body: infoAsync.when(
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
      ),
    );
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
                    _r('姓名', i.name),
                    _r('拼音', i.namePinyin),
                    _r('曾用名', i.formerName),
                    _r('性别', i.gender),
                    _r('民族', i.ethnicity),
                    _r('出生日期', i.birthDate),
                    _r('出生地', i.birthPlace),
                  ]),
                  _card(context, '入学培养', [
                    _r('入学年级', i.enrollYear),
                    _r('学制', i.studyYears.isNotEmpty ? '${i.studyYears}年' : ''),
                    _r('报到时间', i.enrollDate),
                    _r('招生季节', i.enrollSeason),
                    _r('入学方式', i.enrollMethod),
                    _r('入学前学历', i.prevEducation),
                    _r('培养层次', i.trainLevel),
                    _r('培养方式', i.trainMode),
                    _r('考生类别', i.examineeType),
                    _r('录取专业', i.admittedMajor),
                  ]),
                  _card(context, '证件信息', [
                    _r('身份证号', i.idCardNo),
                    _r('身份证别码', i.idCardAltCode),
                    _r('身份证照片', i.idPhotoPath),
                    _r('身份证正面', i.idPhotoFront),
                  ]),
                  _card(context, '学籍状态', [
                    _r('政治面貌', i.politicalStatus),
                    _r('文化程度', i.educationLevel),
                    _r('户口性质', i.residenceType),
                    _r('健康状况', i.healthStatus),
                    _r('考生特征', i.examineeFeature),
                  ]),

                  _card(context, '高考信息', [
                    _r('考生号', i.gaokaoNo),
                    _r('准考证号', i.gaokaoTicketNo),
                    _r('高考总分', i.gaokaoScore),
                    _r('文化成绩', i.cultureScore),
                    _r('考生特长', i.examineeTalent),
                    _r('生源专业', i.originMajor),
                    _r('招生省市类型', i.admissionType),
                    _r('培养对象', i.trainTarget),
                    _r('生源来源', i.originSource),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: colGap),
            Expanded(
              child: Column(
                children: [
                  _card(context, '学籍标识', [
                    _r('用户号', i.userId),
                    _r('学号', i.studentId),
                    _r('序号', i.serialNo),
                    _r('入学号', i.enrollNo),
                  ]),
                  _card(context, '学院专业', [
                    _r('院系', i.college),
                    _r('专业', i.major),
                    _r('专业方向', i.majorDirection),
                    _r('班级', i.className),
                    _r('学科门类', i.disciplineCategory),
                    _r('宿舍名称', i.dormName),
                    _r('宿舍信息', i.dormInfo),
                  ]),

                  _card(context, '联系方式', [
                    _r('电话', i.phone),
                    _r('邮箱', i.email),
                    _r('通讯地址', i.address),
                    _r('邮编', i.postalCode),
                    _r('籍贯', i.hometown),
                    _r('生源省份', i.originProvince),
                    _r('生源地', i.originPlace),
                    _r('生源地单位', i.originUnit),
                  ]),
                  _card(context, '家庭联系', [
                    _r('联系人', i.contactPerson),
                    _r('家庭联系人', i.familyContact),
                    _r('家庭联系人方式', i.familyContactPhone),
                    _r('宿舍电话', i.dormPhone),
                  ]),
                  _card(context, '其他信息', [
                    _r('辅导员', i.advisor),
                    _r('是否贫困', i.isPoor),
                    _r('贫困类型', i.povertyType),
                    _r('入党团时间', i.partyJoinDate),
                    _r('年总收入', i.annualIncome),
                    _r('人均收入', i.perCapitaIncome),
                    _r('学籍卡编号', i.registryNo),
                    _r('外语语种', i.foreignLanguage),
                    _r('计算机等级', i.computerLevel),
                    _r('所属集团', i.groupInfo),
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
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          i.name.isNotEmpty ? i.name[0] : '?',
          style: TextStyle(
            fontSize: 36,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(i.name, style: Theme.of(context).textTheme.headlineSmall),
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
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
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
Widget _r(String label, String value) {
  final isEmpty = value.isEmpty;
  final color = isEmpty ? Colors.grey.shade400 : Colors.grey.shade700;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: TextStyle(fontSize: 14, color: color)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            isEmpty ? '（无）' : value,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 14,
              color: isEmpty ? Colors.grey.shade300 : null,
            ),
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
