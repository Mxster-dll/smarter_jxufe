// 体测「非查询时段」提示 单测。
//
// 实测（2026-09-11 02:2x，非开放时段）接口返回的是**纯文本**而非 JSON：
//   `允许学校学生成绩查询的时间为:9:00:00~21:00:00。`
// 页面要把这段原文照显为提示，且**不得**在 App 里硬编码时段 —— 故这里
// 守的是「形状判定」（非 JSON、非 HTML、短文本 → 提示）而非具体措辞。

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';

void main() {
  test('非查询时段的纯文本提示 → 原样返回（真实抓包文案）', () {
    const body = '允许学校学生成绩查询的时间为:9:00:00~21:00:00。';
    expect(ticePlainNotice(body), body);
  });

  test('首尾空白被去掉，换时段/换措辞同样识别（不依赖固定时间串）', () {
    expect(
      ticePlainNotice('  体测成绩查询每日 8:30 至 20:30 开放，其余时间请稍后再试  '),
      '体测成绩查询每日 8:30 至 20:30 开放，其余时间请稍后再试',
    );
  });

  test('JSON 对象 / 数组不是提示', () {
    expect(ticePlainNotice('{"result":"1","data":{}}'), isNull);
    expect(ticePlainNotice('[1,2,3]'), isNull);
    expect(ticePlainNotice('  {"result":"0","message":"该生成绩尚未上传(含免测)"}'), isNull);
  });

  test('空响应 / HTML 错误页 / 超长正文 → 不作为提示（走解析错误）', () {
    expect(ticePlainNotice(''), isNull);
    expect(ticePlainNotice('   \n  '), isNull);
    expect(ticePlainNotice('<html><body>502 Bad Gateway</body></html>'), isNull);
    expect(ticePlainNotice('x' * 301), isNull);
    expect(ticePlainNotice('x' * 300), isNotNull);
  });
}
