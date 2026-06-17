import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/user.dart';

/// 「我的」页面 —— 左右双列纵排，空值灰色。
class StudentInfoScreen extends ConsumerWidget {
  const StudentInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(_userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: true),
      body: userAsync.when(
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
                onPressed: () => ref.invalidate(_userProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (user) => _buildContent(context, user),
      ),
    );
  }

  Widget _buildContent(BuildContext context, User u) {
    const pad = 12.0;
    const colGap = 10.0;

    return ListView(
      padding: const EdgeInsets.all(pad),
      children: [
        _header(context, u),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  _card(context, '基本信息', [
                    _r('姓名', u.xm),
                    _r('拼音', u.xmpy),
                    _r('曾用名', u.cym),
                    _r('性别', u.xb),
                    _r('民族', u.mz),
                    _r('出生日期', u.csrq),
                    _r('出生地', u.csd),
                    _r('身份证号', u.sfzjh),
                    _r('身份证别码', u.sfzbm),
                    _r('政治面貌', u.zzmm),
                    _r('文化程度', u.whcd),
                    _r('户口性质', u.hkxz),
                    _r('健康状况', u.jkzk),
                    _r('考生特征', u.kstz),
                  ]),
                  _card(context, '学院专业', [
                    _r('院系', u.yxb),
                    _r('专业', u.zymc),
                    _r('专业方向', u.zyfxmc),
                    _r('班级', u.bjmc),
                    _r('学科门类', u.xkml),
                    _r('宿舍名称', u.ss_mc),
                    _r('宿舍信息', u.ssxx),
                  ]),
                  _card(context, '高考信息', [
                    _r('考生号', u.gkksh),
                    _r('准考证号', u.gkzkzh),
                    _r('高考总分', u.gkzs),
                    _r('文化成绩', u.whcj),
                    _r('考生特长', u.kstc),
                    _r('生源专业', u.syzy),
                    _r('招生省市类型', u.zzsqlx),
                    _r('培养对象', u.pydx),
                    _r('生源来源', u.srly),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: colGap),
            Expanded(
              child: Column(
                children: [
                  _card(context, '学籍信息', [
                    _r('用户号', u.yhxh),
                    _r('学号', u.xh),
                    _r('入学号', u.rxh),
                    _r('入学年级', u.rxnj),
                    _r('学制', u.xz.isNotEmpty ? '${u.xz}年' : ''),
                    _r('报到时间', u.bdtime),
                    _r('招生季节', u.zsjj),
                    _r('入学方式', u.rxfs),
                    _r('入学前学历', u.rxqxl),
                    _r('培养层次', u.pycc),
                    _r('培养方式', u.pyfs),
                    _r('考生类别', u.kslb),
                    _r('录取专业', u.lqzy),
                  ]),
                  _card(context, '联系方式', [
                    _r('电话', u.dh),
                    _r('邮箱', u.dzyx),
                    _r('通讯地址', u.txdz),
                    _r('邮编', u.yzbm),
                    _r('籍贯', u.jg),
                    _r('生源省份', u.sysf),
                    _r('生源地', u.syd),
                    _r('生源地单位', u.sydw),
                    _r('联系人', u.lxr),
                    _r('家庭联系人', u.jtlxr),
                    _r('家庭联系人方式', u.jtlxrfs),
                    _r('宿舍电话', u.ssdh),
                  ]),
                  _card(context, '其他信息', [
                    _r('辅导员', u.fdy),
                    _r('备注', u.bz),
                    _r('是否贫困', u.sfpk),
                    _r('贫困类型', u.jtpklx),
                    _r('入党团时间', u.rdtsj),
                    _r('年总收入', u.nzsr),
                    _r('人均收入', u.rjsr),
                    _r('学籍卡编号', u.xjkbh),
                    _r('外语语种', u.wyyz),
                    _r('计算机等级', u.jsjdj),
                    _r('所属集团', u.ssjt),
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
  Widget _header(BuildContext context, User u) => Column(
    children: [
      CircleAvatar(
        radius: 40,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          u.xm.isNotEmpty ? u.xm[0] : '?',
          style: TextStyle(
            fontSize: 36,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(u.xm, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(
        '${u.yxb} · ${u.bjmc}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  // ── 卡片 ──
  Widget _card(BuildContext context, String title, List<Widget> rows) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                ...rows,
              ],
            ),
          ),
        ),
      );
}

// ── 键值行 ──
Widget _r(String label, String value) {
  final isEmpty = value.isEmpty;
  final color = isEmpty ? Colors.grey.shade400 : Colors.grey.shade700;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: TextStyle(fontSize: 13, color: color)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            isEmpty ? '（无）' : value,
            style: TextStyle(
              fontSize: 13,
              color: isEmpty ? Colors.grey.shade300 : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 从仓库获取学生信息。
final _userProvider = FutureProvider<User>((ref) async {
  final repo = await ref.watch(studentInfoRepositoryProvider.future);
  final result = await repo.getUser();
  return result.fold(
    (failure) => throw Exception(failure.message ?? '获取学生信息失败'),
    (user) => user,
  );
});
