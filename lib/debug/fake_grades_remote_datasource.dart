import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';

/// 固定数据的测试用成绩远程数据源。
///
/// 按调用次数返回预设的 HTML，用于测试成绩变更提示（diff 检测）：
///
/// | 次数 | 返回课程       | 预期 diff           |
/// |------|---------------|---------------------|
/// | 1    | a(85分)       | 无（首次，无缓存）   |
/// | 2    | a(85) + b(90) | "b 出成绩了"        |
/// | 3    | b(90)         | "a 成绩已撤回"      |
/// | 4    | b(95)         | 无（分数变化不算）   |
/// | 5+   | b(95)         | 无                   |
class FakeGradesRemoteDataSource extends GradesRemoteDataSource {
  FakeGradesRemoteDataSource()
    : super(Dio(BaseOptions(baseUrl: 'https://localhost')));

  int _callCount = 0;

  @override
  Future<String> fetchGradesHtml({
    required String jsessionId,
    required GradesQueryParams params,
  }) async {
    _callCount++;
    // ignore: avoid_print
    print('📞 FakeGrades 第 $_callCount 次调用');

    switch (_callCount) {
      case 1:
        return _buildHtml([_course('1', 'A001', 'a', '85', '3.5')]);
      case 2:
        return _buildHtml([
          _course('1', 'A001', 'a', '85', '3.5'),
          _course('2', 'B001', 'b', '90', '4.0'),
        ]);
      case 3:
        return _buildHtml([_course('1', 'B001', 'b', '90', '4.0')]);
      case 4:
        return _buildHtml([_course('1', 'B001', 'b', '95', '4.5')]);
      default:
        return _buildHtml([_course('1', 'B001', 'b', '95', '4.5')]);
    }
  }

  String _buildHtml(List<String> rows) =>
      '''
<table style="border:none"><tr><td>学年学期：2025-2026学年第1学期</td></tr></table>
<table><tbody>${rows.join()}</tbody></table>
''';

  String _course(
    String index,
    String code,
    String name,
    String score,
    String gradePoint,
  ) =>
      '<tr>'
      '<td>$index</td>'
      '<td>[$code]$name</td>'
      '<td>3</td>'
      '<td>必修</td>'
      '<td>初修</td>'
      '<td>考试</td>'
      '<td>$score</td>'
      '<td>3</td>'
      '<td>$gradePoint</td>'
      '<td>${(double.parse(score) / 10 - 5).toStringAsFixed(1)}</td>'
      '<td></td>'
      '</tr>';
}
