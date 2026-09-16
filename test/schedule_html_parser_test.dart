/// 课表 HTML 解析器的**空页边界**守卫（2026-09-15 加）。
///
/// 现场：学期选择器可以翻到未来学期（如 262 = 2026-2027 第二学期），该学期课表**还没发布**时
/// 教务返回的是**不含任何表格的空页**，旧解析器一律
/// `throw Exception('期望有1个 table，但找到了0个 table')`
/// → 课表页显示「加载失败」而不是既定的「课表还没出来 / 暂无课表数据」（口径见 AGENTS §9）。
///
/// 但不能把「会话失效」也一起吞掉：失效页（547 字节 `<script>alert('温馨提示：凭证已失效…')`）
/// **同样没有表格**，一旦返回空列表，「失效」就被伪装成「没数据」——这正是 2026-09-15
/// 修过的那个坑，所以空页分支必须先过 [jwSessionExpired]。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/schedule_html_parser.dart';

/// 实测形态：会话失效时教务返回的整页（UTF-8，547 字节）。
const String _expiredPage =
    '<script>alert(\'温馨提示：凭证已失效，请重新登录!\');'
    'window.location.href=\'../login.jsp\';</script>';

void main() {
  final parser = ScheduleHtmlParser();

  group('课表空页（该学期未发布）', () {
    test('没有任何 table → 返回空列表，不抛异常', () {
      const emptyPage = '<html><body><div class="content">'
          '<span>没有检索到记录！</span></div></body></html>';
      expect(parser.parse(emptyPage), isEmpty);
    });

    test('纯空白页 / 骨架页也不抛', () {
      expect(parser.parse(''), isEmpty);
      expect(
        parser.parse('<table></table>' * 0 + '<div>课表</div>'),
        isEmpty,
      );
    });

    test('会话失效页仍然抛错（不能被伪装成「没数据」）', () {
      expect(() => parser.parse(_expiredPage), throwsA(isA<Exception>()));
      // 「请重新登录」也算失效判据。
      expect(
        () => parser.parse('<html>请重新登录</html>'),
        throwsA(isA<Exception>()),
      );
    });

    test('多于一个 table 仍然抛错（页面结构真的变了）', () {
      expect(
        () => parser.parse('<table><tr><td>a</td></tr></table>'
            '<table><tr><td>b</td></tr></table>'),
        throwsA(isA<Exception>()),
      );
    });

    test('正常单表页面照旧解析出行（回归保护）', () {
      // 列数与真实课表一致（12 列，少于 12 会被解析器跳过）；
      // 列 2 = [课程代码]课程名，列 10 = 上课时间地点。
      final rows = List.generate(12, (i) => '<td>c$i</td>').toList();
      rows[2] = '<td>[1014300174]计算机网络</td>';
      rows[6] = '<td>[1200400772]史希平</td>';
      rows[10] = '<td>2-17周 三[3-4] 麦三教3407(70)(麦庐园校区)</td>';
      final html = '<table><tr class="H">${'<td>h</td>' * 2}</tr>'
          '<tr>${rows.join()}</tr></table>';
      final entries = parser.parse(html);
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.courseName, '计算机网络');
      expect(entry.classTimes, isNotEmpty);
      expect(entry.classTimes.first.startWeek, 2);
      expect(entry.classTimes.first.endWeek, 17);
    });
  });
}
