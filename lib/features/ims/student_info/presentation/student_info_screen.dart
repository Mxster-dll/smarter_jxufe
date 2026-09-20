import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/auth/data/account_avatar_controller.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_avatar_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_my_field_row.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';
import 'package:smarter_jxufe/shared/widgets/account_avatar.dart';
import 'package:smarter_jxufe/design/app_states.dart';

/// 「我的」页面 —— 左右双列纵排，纯色标题背景。
class StudentInfoScreen extends ConsumerWidget {
  final bool showAppBar;

  const StudentInfoScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(_studentInfoProvider);

    final body = infoAsync.when(
      loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(
        title: '加载失败',
        error: error,
        retryIcon: false,
        onRetry: () => ref.invalidate(_studentInfoProvider),
      ),
      data: (info) => _buildContent(context, ref, info),
    );

    if (showAppBar) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的'), centerTitle: true),
        body: body,
      );
    }
    return body;
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, StudentInfo i) {
    const pad = 12.0;
    const colGap = 10.0;

    // 竹简「学生个人数据中心 › 基本信息」页的 39 项字段（一卡通号/学号/姓名/性别/出生日期/
    // 民族/政治面貌/籍贯/家庭住址/证件类型/证件号码/所属校区-单位-专业-班级/所在年级/学制/
    // 培养层次/学生身份/学生类型/是否预科生/手机号码/电子邮箱/银行账号/考生号/考生类别/
    // 通知书号/录取批次-时间-成绩-志愿-专业/预计毕业日期/毕业中学/担任职务/获得奖励/
    // 当前状态/学籍状态/宿舍地址）**全部并入下方既有卡片**，不另开「基本信息」卡
    // （用户 2026-09-19 五轮原话：「我不是要在我的页加『基本信息』卡片，而是要把原网页
    // 个人数据中心里的基本信息页整合到已有卡片，除非必要，不然不开新卡片」）。
    //
    // ⚠ 该页的**服务端取数在 2026-09-20 八轮被重新打通**：组件 `u:73ab7f26af38` 的
    // `selectArea` 是占位符 `select * from t_sys_user`，`data/search`/`data/list` 恒空，
    // 但表单真实端点 `POST /api/app/component/tsa/getFormData`（带 dataObjectId +
    // 39 项 fieldList）能回全部真值 —— 见 `DzjBasicField`。从前这些行只能用学籍缓存，
    // 所以「基本信息页有大量的信息没有并入我的页」（用户八轮原话）。
    // 现在：本地（学籍缓存）值 + 数据中心值**按表单列名对位合并**，数据中心那一份走
    // `fp(context).dzjSource` 上色，冲突则出「冲突」胶囊（用户七轮裁定）。
    final account = ref.watch(currentAccountProvider);
    final localCardNo = account.isNotEmpty ? account : i.userId;

    // 数据中心两份来源：① 基本信息表单 39 项；② 个人首页/住宿信息那一小撮
    // （姓名/一卡通号/院系/班主任/班主任电话/宿舍评分）。两份都取不到 → 空表，
    // 页面照常显示学籍缓存、不弹错误。
    final basic = ref
        .watch(dzjBasicInfoProvider)
        .maybeWhen(
          data: (m) => m,
          orElse: () => const <String, String>{},
        );
    final remote = <String, String>{
      ...ref
          .watch(dzjMyFieldsProvider)
          .maybeWhen(
            data: (m) => m,
            orElse: () => const <String, String>{},
          ),
      ...basic,
    };
    // ⚠ 本地值的键必须与行标签一致（枚举那六个用 `DzjMyField.label`，表单那 39 项用
    // `DzjBasicField.label`）—— 合并按标签对位，键写错那一行就既不上色也查不出冲突。
    final dzj = dzjMergeMap(
      dzjMergeFields(
        labels: <String>[
          for (final f in DzjMyField.values) f.label,
          for (final f in dzjBasicFields) f.label,
        ],
        local: <String, String>{
          '姓名': i.name,
          '一卡通号': localCardNo,
          '院系': i.college,
          '学号': i.studentId,
          '性别': i.gender,
          '出生日期': i.birthDate,
          '民族': i.ethnicity,
          '政治面貌': i.politicalStatus,
          '籍贯': i.hometown,
          '证件号码': i.idCardNo,
          '所属单位': i.college,
          '所属专业': i.major,
          '所属班级': i.className,
          '所在年级': i.enrollYear,
          '培养层次': i.trainLevel,
          '考生号': i.gaokaoNo,
          '考生类别': i.examineeType,
          '录取专业': i.admittedMajor,
          '手机号码': i.phone,
          '电子邮箱': i.email,
          '宿舍地址': i.dormInfo,
        },
        remote: remote,
      ),
    );

    final leftCards = <Widget>[
      _card(context, '身份信息', [
        _r(context, '姓名', i.name, dzj: dzj['姓名']),
        _r(context, '拼音', i.namePinyin),
        _r(context, '曾用名', i.formerName),
        _r(context, '性别', i.gender, dzj: dzj['性别']),
        _r(context, '民族', i.ethnicity, dzj: dzj['民族']),
        _r(context, '出生日期', i.birthDate, dzj: dzj['出生日期']),
        _r(context, '出生地', i.birthPlace),
      ]),
      _card(context, '入学培养', [
        _r(context, '入学年级', i.enrollYear, dzj: dzj['所在年级']),
        // 学制**刻意不接**数据中心那一份：本地是「4」，数据中心写「4年制」，只是措辞不同，
        // 接上去只会凭空多一枚「冲突」胶囊（其余字段照接）。
        _r(context, '学制', i.studyYears.isNotEmpty ? '${i.studyYears}年' : ''),
        _r(context, '报到时间', i.enrollDate),
        _r(context, '招生季节', i.enrollSeason),
        _r(context, '入学方式', i.enrollMethod),
        _r(context, '入学前学历', i.prevEducation),
        _r(context, '培养层次', i.trainLevel, dzj: dzj['培养层次']),
        _r(context, '培养方式', i.trainMode),
        _r(context, '考生类别', i.examineeType, dzj: dzj['考生类别']),
        _r(context, '录取专业', i.admittedMajor, dzj: dzj['录取专业']),
        _r(context, '录取时间', '', dzj: dzj['录取时间']),
        _r(context, '预计毕业日期', '', dzj: dzj['预计毕业日期']),
        _r(context, '毕业中学', '', dzj: dzj['毕业中学']),
      ]),
      _card(context, '证件信息', [
        _r(context, '身份证号', i.idCardNo, dzj: dzj['证件号码']),
        _r(context, '证件类型', '', dzj: dzj['证件类型']),
        _r(context, '身份证别码', i.idCardAltCode),
        _r(context, '身份证照片', i.idPhotoPath),
        _r(context, '身份证正面', i.idPhotoFront),
      ]),
      _card(context, '学籍状态', [
        _r(context, '政治面貌', i.politicalStatus, dzj: dzj['政治面貌']),
        _r(context, '文化程度', i.educationLevel),
        _r(context, '户口性质', i.residenceType),
        _r(context, '健康状况', i.healthStatus),
        _r(context, '考生特征', i.examineeFeature),
        _r(context, '学生身份', '', dzj: dzj['学生身份']),
        _r(context, '学生类型', '', dzj: dzj['学生类型']),
        _r(context, '是否预科生', '', dzj: dzj['是否预科生']),
        _r(context, '当前状态', '', dzj: dzj['当前状态']),
        _r(context, '学籍状态', '', dzj: dzj['学籍状态']),
      ]),
      _card(context, '高考信息', [
        // 用户 2026-09-20 点名：「数据中心-基本信息里的 考生号 / 录取批次 / 录取志愿 /
        // 毕业中学 / 录取分数好像没有加入『我的』页」——本地学籍里除考生号外都没有
        // 这几列，故整行由数据中心来（`dzj['…']`，取不到就照旧显示本地值 / 空）。
        _r(context, '考生号', i.gaokaoNo, dzj: dzj['考生号']),
        _r(context, '准考证号', i.gaokaoTicketNo),
        _r(context, '高考总分', i.gaokaoScore),
        // 录取成绩 = 表单的 `LQCJ`（实测 575，与「高考总分」是两个字段，别合并）。
        _r(context, '录取成绩', '', dzj: dzj['录取成绩']),
        _r(context, '录取批次', '', dzj: dzj['录取批次']),
        _r(context, '录取志愿', '', dzj: dzj['录取志愿']),
        _r(context, '通知书号', '', dzj: dzj['通知书号']),
        _r(context, '文化成绩', i.cultureScore),
        _r(context, '考生特长', i.examineeTalent),
        _r(context, '生源专业', i.originMajor),
        _r(context, '招生省市类型', i.admissionType),
        _r(context, '培养对象', i.trainTarget),
        _r(context, '生源来源', i.originSource),
      ]),
    ];

    final rightCards = <Widget>[
      _card(context, '学籍标识', [
        // 竹简「基本信息」页把它叫**一卡通号**（= 统一身份认证号 = 学生账号），
        // 学籍 XML 里叫「用户号」，同一个值 —— 取账号优先、学籍兜底。
        _r(context, '一卡通号', localCardNo, dzj: dzj['一卡通号']),
        _r(context, '序号', i.serialNo),
        _r(context, '学号', i.studentId, dzj: dzj['学号']),
        _r(context, '入学号', i.enrollNo),
        // 银行账号：本地没有，只有数据中心有（多为空 —— 该生就没填）。
        _r(context, '银行账号', '', dzj: dzj['银行账号']),
      ]),
      _card(context, '学院专业', [
        // 数据中心把这一项叫「所属单位」，与本地「院系」是同一个东西 —— 合并按表单列名
        // 对位（键用 '所属单位'），冲突时该行出「冲突」胶囊。
        _r(context, '院系', i.college, dzj: dzj['所属单位']),
        _r(context, '专业', i.major, dzj: dzj['所属专业']),
        _r(context, '专业方向', i.majorDirection),
        _r(context, '班级', i.className, dzj: dzj['所属班级']),
        _r(context, '学科门类', i.disciplineCategory),
        _r(context, '所属校区', '', dzj: dzj['所属校区']),
        _r(context, '宿舍名称', i.dormName),
        _r(context, '宿舍信息', i.dormInfo, dzj: dzj['宿舍地址']),
        // 宿舍评分只有数据中心有（住宿信息页），本地无对应字段。
        if (dzj['宿舍评分']?.visible ?? false)
          _r(context, '宿舍评分', '', dzj: dzj['宿舍评分']),
      ]),
      _card(context, '联系方式', [
        _r(context, '电话', i.phone, dzj: dzj['手机号码']),
        _r(context, '邮箱', i.email, dzj: dzj['电子邮箱']),
        _r(context, '通讯地址', i.address),
        _r(context, '家庭住址', '', dzj: dzj['家庭住址']),
        _r(context, '邮编', i.postalCode),
        _r(context, '籍贯', i.hometown, dzj: dzj['籍贯']),
        _r(context, '生源省份', i.originProvince),
        _r(context, '生源地', i.originPlace),
        _r(context, '生源地单位', i.originUnit),
        // 班主任 / 班主任电话同样是数据中心独有（个人首页）。
        if (dzj['班主任']?.visible ?? false)
          _r(context, '班主任', '', dzj: dzj['班主任']),
        if (dzj['班主任电话']?.visible ?? false)
          _r(context, '班主任电话', '', dzj: dzj['班主任电话']),
      ]),
      _card(context, '家庭联系', [
        _r(context, '联系人', i.contactPerson),
        _r(context, '家庭联系人', i.familyContact),
        _r(context, '家庭联系人方式', i.familyContactPhone),
        _r(context, '宿舍电话', i.dormPhone),
      ]),
      _card(context, '其他信息', [
        _r(context, '辅导员', i.advisor),
        _r(context, '担任职务', '', dzj: dzj['担任职务']),
        _r(context, '获得奖励', '', dzj: dzj['获得奖励']),
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
    ];

    return ListView(
      padding: const EdgeInsets.all(pad),
      children: [
        _header(context, ref, i),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < Breakpoints.narrow;
            if (isNarrow) {
              // 插缝排列: [L1,R1,L2,R2,L3,R3,L4,R4,L5,R5]
              final interleaved = <Widget>[];
              final maxLen = leftCards.length > rightCards.length
                  ? leftCards.length
                  : rightCards.length;
              for (int idx = 0; idx < maxLen; idx++) {
                if (idx < leftCards.length) interleaved.add(leftCards[idx]);
                if (idx < rightCards.length) interleaved.add(rightCards[idx]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: interleaved,
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: leftCards)),
                const SizedBox(width: colGap),
                Expanded(child: Column(children: rightCards)),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── 头部 ──
  Widget _header(BuildContext context, WidgetRef ref, StudentInfo i) => Column(
    children: [
      // 头像：绑定当前账号的本地图片 → 姓名首字 → 通用图标（三级回退）。
      // 点击打开「取图 / 移除」菜单；**不画相机角标**（用户 2026-09-11 裁定）。
      AccountAvatar(
        radius: 40,
        name: i.name,
        tooltip: '更换头像',
        onTap: () => _showAvatarSheet(context, ref),
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

  /// 头像操作面板：取图（相册 / 拍照）/ 移除。
  ///
  /// 图片**只存本机**并绑定到当前账号（`avatars/<卡号>.<ext>`），
  /// 不联网、不随账户同步。「拍照」只在移动端出现 —— 桌面端 image_picker
  /// 没有相机实现（见 `AccountAvatarController.isMobile`）。
  Future<void> _showAvatarSheet(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(accountAvatarProvider);
    final hasImage = controller.hasImage;
    final isMobile = controller.isMobile;

    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(isMobile ? '从相册选择' : '选择图片文件'),
              subtitle: const Text('仅存本机并绑定当前账号'),
              onTap: () => Navigator.pop(sheetContext, _AvatarAction.gallery),
            ),
            if (isMobile)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                subtitle: const Text('调用相机拍一张作为头像'),
                onTap: () => Navigator.pop(sheetContext, _AvatarAction.camera),
              ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除头像'),
                subtitle: const Text('回到「姓名首字」默认头像'),
                onTap: () => Navigator.pop(sheetContext, _AvatarAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final result = switch (action) {
      _AvatarAction.gallery => await controller.pick(),
      _AvatarAction.camera => await controller.pick(
        source: AvatarSource.camera,
      ),
      _AvatarAction.remove => await controller.clear(),
    };
    if (!context.mounted) return;

    String? message;
    if (result == AvatarActionResult.updated) {
      message = action == _AvatarAction.remove ? '头像已移除' : '头像已更新';
    } else if (result == AvatarActionResult.permissionDenied) {
      message = '没有相机权限：请在系统设置里允许本应用使用相机';
    } else if (result == AvatarActionResult.failed) {
      message = '头像操作失败，请重试';
    }
    if (message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

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
  Widget _card(BuildContext context, String title, List<Widget> rows) {
    // 卡头条带：浅色逐值不变（原来的粉 `#EFA0A0` + 黑字）；深色改为「主题红 22%
    // 叠在卡片底」+ 正文色文字 —— 用户 2026-09-17：「个人主页卡片的顶部颜色没有
    // 适配」。原来两侧都写死粉底黑字，深色下粉带刺眼、黑字也几乎看不见。
    final dark = AppColors.isDark(context);
    final bandColor = dark
        ? AppColors.statusFill(context, Theme.of(context).colorScheme.primary)
        : StatusPalette.infoBand;
    final bandTextColor = dark
        ? AppColors.textBase(context)
        : StatusPalette.infoBandInk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: AppColors.card(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: bandColor,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: bandTextColor,
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
}

// ── 键值行 ──
//
// [dzj] = 这一行在**学校个人数据中心**里的那一份（见 `dzj_my_fields.dart`）。
// 三条规则（用户 2026-09-20 七轮）：本地有值就不覆盖；本地空则用数据中心的值并**换色**；
// 两边都有且不一样 → 值还是本地那一份，尾巴上挂一枚「冲突」胶囊，点开看两份值。
// 三种形态的唯一实现 = `DzjMyFieldRow`（数据中台模块里，可单测），这里只负责喂图标。
Widget _r(
  BuildContext context,
  String label,
  String value, {
  DzjFieldMerge? dzj,
}) => DzjMyFieldRow(
  label: label,
  value: value,
  dzj: dzj,
  leadingIcon: _iconFor(label),
);

IconData? _iconFor(String label) => switch (label) {
  '姓名' => Icons.person,
  '拼音' => Icons.translate,
  '曾用名' => Icons.badge,
  '性别' => Icons.wc,
  '民族' => Icons.flag,
  '出生日期' => Icons.cake,
  '出生地' => Icons.location_on,
  '入学年级' => Icons.school,
  '学制' => Icons.timeline,
  '报到时间' => Icons.login,
  '招生季节' => Icons.wb_sunny,
  '入学方式' => Icons.how_to_reg,
  '入学前学历' => Icons.school_outlined,
  '培养层次' => Icons.trending_up,
  '培养方式' => Icons.psychology,
  '考生类别' => Icons.group,
  '录取专业' => Icons.assignment,
  '身份证号' => Icons.badge_outlined,
  '身份证别码' => Icons.key,
  '身份证照片' => Icons.photo,
  '身份证正面' => Icons.credit_card,
  '政治面貌' => Icons.account_balance,
  '文化程度' => Icons.menu_book,
  '户口性质' => Icons.home,
  '健康状况' => Icons.favorite,
  '考生特征' => Icons.emoji_events,
  '考生号' => Icons.confirmation_number,
  '准考证号' => Icons.assignment_ind,
  '高考总分' => Icons.scoreboard,
  '文化成绩' => Icons.grade,
  '考生特长' => Icons.star,
  '生源专业' => Icons.workspaces_outline,
  '招生省市类型' => Icons.map,
  '培养对象' => Icons.person_outline,
  '生源来源' => Icons.input,
  '一卡通号' => Icons.credit_card,
  '学号' => Icons.pin,
  '序号' => Icons.format_list_numbered,
  '入学号' => Icons.login,
  '院系' => Icons.account_balance_outlined,
  '专业' => Icons.work,
  '专业方向' => Icons.explore,
  '班级' => Icons.meeting_room,
  '学科门类' => Icons.category,
  '宿舍名称' => Icons.bed,
  '宿舍信息' => Icons.info,
  '电话' => Icons.phone,
  '邮箱' => Icons.email,
  '通讯地址' => Icons.location_city,
  '邮编' => Icons.markunread_mailbox,
  '籍贯' => Icons.holiday_village,
  '生源省份' => Icons.public,
  '生源地' => Icons.place,
  '生源地单位' => Icons.business,
  '联系人' => Icons.contacts,
  '家庭联系人' => Icons.family_restroom,
  '家庭联系人方式' => Icons.phone,
  '宿舍电话' => Icons.phone_in_talk,
  '辅导员' => Icons.supervisor_account,
  '是否贫困' => Icons.volunteer_activism,
  '贫困类型' => Icons.priority_high,
  '入党团时间' => Icons.event,
  '年总收入' => Icons.attach_money,
  '人均收入' => Icons.money,
  '学籍卡编号' => Icons.credit_score,
  '外语语种' => Icons.language,
  '计算机等级' => Icons.computer,
  '所属集团' => Icons.corporate_fare,
  '班主任' => Icons.supervisor_account,
  '班主任电话' => Icons.phone_in_talk,
  '宿舍评分' => Icons.star_half,
  // 用户 2026-09-20 二轮：「这些新添加的项，前面也要有 icon，要与现有项统一」
  // —— 上一轮从数据中心新接进来的行（录取时间/毕业中学/证件类型/学籍状态…）
  // 当时漏了图标，这一批补齐；`test/student_info_icons_test.dart` 会守住
  // 「页面上出现的每一行标签都必须有图标」。
  '录取时间' => Icons.event_available,
  '预计毕业日期' => Icons.event_busy,
  '毕业中学' => Icons.history_edu,
  '录取成绩' => Icons.insights,
  '录取批次' => Icons.layers,
  '录取志愿' => Icons.how_to_vote,
  '通知书号' => Icons.article,
  '证件类型' => Icons.card_membership,
  '学生身份' => Icons.person_pin,
  '学生类型' => Icons.groups,
  '是否预科生' => Icons.rule,
  '当前状态' => Icons.timelapse,
  '学籍状态' => Icons.verified_user,
  '银行账号' => Icons.account_balance_wallet,
  '所属校区' => Icons.apartment,
  '家庭住址' => Icons.house,
  '担任职务' => Icons.manage_accounts,
  '获得奖励' => Icons.workspace_premium,
  _ => null,
};

/// 从仓库获取学生信息。
final _studentInfoProvider = FutureProvider.autoDispose<StudentInfo>((
  ref,
) async {
  final repo = await ref.watch(studentInfoRepositoryProvider.future);
  final result = await repo.getStudentInfo();
  return result.fold(
    (failure) => throw ImsApiException(failure.message ?? '获取学生信息失败'),
    (info) => info,
  );
});

/// 头像面板动作。
enum _AvatarAction { gallery, camera, remove }
