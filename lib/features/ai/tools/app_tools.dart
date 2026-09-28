/// 工具集：学籍信息、App 设置（读 + 写）、页面跳转。
///
/// 这里有两个**写操作**（`update_app_setting`）与一个「给界面递按钮」的工具
/// （`open_page`），是全模块唯一会改动 App 状态的地方：
/// - 写操作走 [AiWriteGate]（用户拍板的「写操作二次确认」）；
/// - `open_page` **不自己跳转** —— 它只把「打开哪个页面」作为结果交给界面，
///   由对话页渲染一个跳转按钮。理由是用户正在读回答，凭空换页会把人踢出对话。
library;

import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';

import 'package:flutter/material.dart' show ThemeMode;

/// 查我的学籍信息（我是谁 / 哪个学院哪个专业哪个班）。
class GetStudentInfoTool extends AiTool {
  const GetStudentInfoTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_student_info',
    description:
        '查我的学籍信息：姓名、学号、学院、专业、班级、年级、辅导员、宿舍等。'
        '回答「我是哪个专业的」「我辅导员是谁」这类问题时用它。'
        '**不要**回传身份证号、家庭收入、高考分数这类敏感字段。',
    parameters: aiObjectSchema({
      'field': aiStrProp(
        '只取某一项（可选）',
        enums: ['basic', 'contact', 'dorm', 'origin'],
        fallbackHint: 'basic=基本信息（默认），contact=联系方式，dorm=宿舍，origin=生源地',
      ),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final field = (a.optStr('field') ?? 'basic').toLowerCase();
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final StudentInfo? info;
    try {
      final repo = await ctx.ref.read(studentInfoRepositoryProvider.future);
      // `getCachedStudentInfo()` 是同步的 `Either<Failure, StudentInfo?>`
      info = repo.getCachedStudentInfo().fold((_) => null, (v) => v);
    } catch (e) {
      return AiToolResult.fail('学籍信息读取失败：$e');
    }
    if (info == null) {
      return const AiToolResult.ok(
        '本地还没有学籍缓存。可以让用户先打开一次「学籍信息」页面，之后就能离线查询了。',
      );
    }

    final lines = <String>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) lines.add('$label：${value.trim()}');
    }

    switch (field) {
      case 'contact':
        add('手机', info.phone);
        add('邮箱', info.email);
        add('通讯地址', info.address);
        add('家庭联系人', info.familyContact);
        add('家庭联系电话', info.familyContactPhone);
      case 'dorm':
        add('宿舍', info.dormName);
        add('宿舍信息', info.dormInfo);
        add('宿舍电话', info.dormPhone);
      case 'origin':
        add('籍贯', info.hometown);
        add('生源省份', info.originProvince);
        add('生源地', info.originPlace);
        add('政治面貌', info.politicalStatus);
      default:
        add('姓名', info.name);
        add('学号', info.studentId.isNotEmpty ? info.studentId : info.serialNo);
        add('性别', info.gender);
        add('学院', info.college);
        add('专业', info.major);
        if (info.majorDirection.trim().isNotEmpty) add('专业方向', info.majorDirection);
        add('班级', info.className);
        add('年级', info.enrollYear);
        add('培养层次', info.trainLevel);
        add('学制', info.studyYears.isEmpty ? '' : '${info.studyYears} 年');
        add('辅导员', info.advisor);
        add('宿舍', info.dormName);
    }

    if (lines.isEmpty) {
      return AiToolResult.ok('学籍缓存里这一类信息是空的（field=$field）。');
    }
    return AiToolResult.ok(
      '${info.name} 的学籍信息（$field）：\n${lines.map((l) => '· $l').join('\n')}',
      ui: {'kind': 'studentInfo', 'field': field},
    );
  }
}

/// 读 App 设置。
class GetAppSettingsTool extends AiTool {
  const GetAppSettingsTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_app_settings',
    description:
        '读取这个 App 当前的设置项：外观模式（深色/浅色）、主页布局（宫格/侧栏）、'
        '我的校区、AI 助手（悬浮球开关、工具轮次上限、当前模型）。'
        '用户问「现在是什么设置」「我的校区设的是哪个」时用它。',
    parameters: aiObjectSchema({}),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final rows = <String>[];

    final theme = ctx.ref.read(themeModeStoreProvider).mode;
    rows.add('· 外观模式：${aiThemeModeLabel(theme)}');

    final layout = ctx.ref.read(homeLayoutStoreProvider).layout;
    rows.add('· 主页布局：${layout.label}（${layout.description}）');

    final campus = ctx.ref.read(myCampusStoreProvider).campus;
    rows.add('· 我的校区：${campus?.label ?? '未设置'}');

    final ai = ctx.ref.read(aiSettingsStoreProvider).settings;
    rows
      ..add('· AI 悬浮球：${ai.floatingBall ? '开启' : '关闭'}')
      ..add('· AI 工具调用轮次上限：${ai.maxToolRounds}')
      ..add(
        '· AI 当前配置：${ai.active == null ? '未配置' : '${ai.active!.name}（${ai.active!.model}）'}',
      );

    return AiToolResult.ok(
      '当前设置：\n${rows.join('\n')}',
      ui: const {'kind': 'settings'},
    );
  }
}

/// 改 App 设置（**写操作，需用户二次确认**）。
class UpdateAppSettingTool extends AiTool {
  const UpdateAppSettingTool();

  @override
  bool get mutating => true;

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'update_app_setting',
    description:
        '修改 App 的一个设置项。**只在用户明确要求改设置时调用**'
        '（如「把主页换成左侧导航栏」「开深色模式」）。'
        '调用前会弹确认框给用户点同意，用户拒绝就什么都不会发生。',
    parameters: aiObjectSchema(
      {
        'key': aiStrProp(
          '要改的设置项',
          enums: [
            'theme_mode',
            'home_layout',
            'my_campus',
            'ai_floating_ball',
            'ai_max_tool_rounds',
          ],
          fallbackHint:
              'theme_mode=外观；home_layout=主页布局；my_campus=我的校区；'
              'ai_floating_ball=AI 悬浮球开关；ai_max_tool_rounds=AI 工具轮次上限',
        ),
        'value': aiStrProp(
          '目标值',
          fallbackHint:
              'theme_mode: system/light/dark；home_layout: grid/sidebar；'
              'my_campus: jiaoqiao/qingshan/mailu/fenglin/none；'
              'ai_floating_ball: true/false；ai_max_tool_rounds: 1~12',
        ),
      },
      required: ['key', 'value'],
    ),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final key = a.str('key').toLowerCase();
    final value = a.str('value').trim();
    if (a.hasError) return AiToolResult.fail(a.errorText);

    // 先解析出「要怎么改」，解析不了就直接拒绝（不要拿灰色地带去打扰用户）
    final plan = _planChange(ctx, key, value);
    if (plan.error != null) return AiToolResult.fail(plan.error!);

    final approved = await ctx.gate.confirm(
      AiWriteRequest(
        toolName: spec.name,
        title: plan.title,
        detail: plan.detail,
        args: {'key': key, 'value': value},
      ),
    );
    if (!approved) {
      return const AiToolResult.fail('用户拒绝了这次修改，设置保持不变。不要重试，如实告知用户即可。');
    }

    try {
      await plan.apply!();
    } catch (e) {
      return AiToolResult.fail('修改失败：$e');
    }
    return AiToolResult.ok(
      '${plan.title} —— 已完成。${plan.after}',
      ui: {'kind': 'settingChanged', 'key': key, 'value': value},
    );
  }
}

class _ChangePlan {
  final String title;
  final String detail;
  final String after;
  final Future<void> Function()? apply;
  final String? error;

  const _ChangePlan({
    this.title = '',
    this.detail = '',
    this.after = '',
    this.apply,
    this.error,
  });
}

_ChangePlan _planChange(AiToolContext ctx, String key, String value) {
  switch (key) {
    case 'theme_mode':
      final mode = _themeModeOf(value);
      if (mode == null) {
        return const _ChangePlan(error: 'value 只能是 system / light / dark。');
      }
      return _ChangePlan(
        title: '切换外观模式',
        detail: '把「外观」改成「${aiThemeModeLabel(mode)}」',
        after: '现在外观为「${aiThemeModeLabel(mode)}」。',
        apply: () => ctx.ref.read(themeModeStoreProvider).save(mode),
      );

    case 'home_layout':
      final layout = _homeLayoutOf(value);
      if (layout == null) {
        return const _ChangePlan(error: 'value 只能是 grid（宫格）或 sidebar（左侧导航栏）。');
      }
      return _ChangePlan(
        title: '切换主页布局',
        detail: '把「主页布局」改成「${layout.label}」'
            '${layout == HomeLayout.sidebar ? '（仅电脑端宽窗口生效，手机端仍是宫格）' : ''}',
        after: '主页布局现在为「${layout.label}」。',
        apply: () => ctx.ref.read(homeLayoutStoreProvider).save(layout),
      );

    case 'my_campus':
      final campus = value.toLowerCase() == 'none' || value == '未设置'
          ? null
          : MyCampus.fromName(value);
      if (campus == null && value.toLowerCase() != 'none' && value != '未设置') {
        return const _ChangePlan(
          error: 'value 只能是 jiaoqiao / qingshan / mailu / fenglin / none。',
        );
      }
      final name = campus?.label ?? '未设置';
      return _ChangePlan(
        title: '修改「我的校区」',
        detail: '把「我的校区」设为「$name」',
        after: '我的校区现在是「$name」。',
        apply: () => ctx.ref.read(myCampusStoreProvider).save(campus),
      );

    case 'ai_floating_ball':
      final on = _boolOf(value);
      if (on == null) return const _ChangePlan(error: 'value 只能是 true 或 false。');
      return _ChangePlan(
        title: '${on ? '开启' : '关闭'} AI 悬浮球',
        detail: '把 AI 助手的全局悬浮球${on ? '打开' : '关掉'}',
        after: 'AI 悬浮球已${on ? '开启' : '关闭'}。',
        apply: () => ctx.ref.read(aiSettingsStoreProvider).setFloatingBall(on),
      );

    case 'ai_max_tool_rounds':
      final rounds = int.tryParse(value);
      if (rounds == null || rounds < 1 || rounds > 12) {
        return const _ChangePlan(error: 'value 要填 1~12 之间的整数。');
      }
      return _ChangePlan(
        title: '调整 AI 工具调用轮次',
        detail: '把「一次提问最多几轮工具调用」设为 $rounds',
        after: '工具轮次上限已设为 $rounds。',
        apply: () => ctx.ref.read(aiSettingsStoreProvider).setMaxToolRounds(rounds),
      );
  }
  return const _ChangePlan(
    error: '不认识的设置项。只支持 theme_mode / home_layout / my_campus / '
        'ai_floating_ball / ai_max_tool_rounds。',
  );
}

/// 给用户一个「打开某个页面」的按钮（**不自己跳转**）。
class OpenPageTool extends AiTool {
  const OpenPageTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'open_page',
    description:
        '在回答里给用户附一个「打开某页面」的按钮。'
        '当用户问的东西在 App 里有对应页面（成绩、课表、规章制度、分数估计、综测、'
        '材料库、志愿时长、电费、校园网…）时，顺手调用它，用户点一下就能跳过去。'
        '它**不会**替你跳转，也不会改变任何数据。',
    parameters: aiObjectSchema(
      {
        'page': aiStrProp('页面名称，如「成绩」「课表」「规章制度」「综测」「分数估计」'),
      },
      required: ['page'],
    ),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final page = a.str('page');
    if (a.hasError) return AiToolResult.fail(a.errorText);

    // 唯一条目表就是首页服务目录（宫格与侧栏共用同一份），按名字找
    final entries = homeServiceEntries(push: (_) {});
    final exact = entries.where((e) => e.title == page).toList();
    final loose = exact.isNotEmpty
        ? exact
        : [
            for (final e in entries)
              if (e.title.contains(page) || page.contains(e.title)) e,
          ];
    if (loose.isEmpty) {
      final titles = entries.map((e) => e.title).join('、');
      return AiToolResult.fail('App 里没有叫「$page」的页面。可选：$titles');
    }
    final entry = loose.first;
    return AiToolResult.ok(
      '已为用户准备好「${entry.title}」页面的跳转按钮（用户点击后才会打开）。',
      ui: {'kind': 'navigate', 'title': entry.title},
    );
  }
}

// ────────────────────────────── 解析助手 ──────────────────────────────

String aiThemeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

ThemeMode? _themeModeOf(String raw) => switch (raw.toLowerCase()) {
  'system' || '跟随系统' || '自动' => ThemeMode.system,
  'light' || '浅色' || '亮色' => ThemeMode.light,
  'dark' || '深色' || '暗色' => ThemeMode.dark,
  _ => null,
};

HomeLayout? _homeLayoutOf(String raw) => switch (raw.toLowerCase()) {
  'grid' || '宫格' || '宫格视图' => HomeLayout.grid,
  'sidebar' || '侧栏' || '左侧导航栏' => HomeLayout.sidebar,
  _ => null,
};

bool? _boolOf(String raw) => switch (raw.toLowerCase()) {
  'true' || '1' || 'yes' || 'on' || '开' || '开启' => true,
  'false' || '0' || 'no' || 'off' || '关' || '关闭' => false,
  _ => null,
};
