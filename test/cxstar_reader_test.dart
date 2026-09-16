/// 畅想之星阅读器纯逻辑测试（签名 / 单页口令 / 模型解析）。
///
/// 口令与签名都是**逆向实测值**，线上验证记录见
/// reverse_engineering/畅想之星接口.md §7:
/// - p1 / p49 / p60 / p100 四页 PDF 用 pikepdf + pypdf 双双解密成功；
/// - 口令向量直接取自那次实测。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';
import 'package:smarter_jxufe/features/cxstar/presentation/cxstar_reader_screen.dart';

void main() {
  group('签名算法', () {
    test('md5("123456" + nonce + stime) 大写，与线上算法一致', () {
      final sign = cxstarReaderSign(nonce: 'abc', stimeSeconds: 1700000000);
      expect(sign.nonce, 'abc');
      expect(sign.stime, 1700000000);
      expect(sign.sign, '93D049F5AC10881151E309C8EF05133A');
      expect(sign.sign.length, 32);
      expect(sign.sign, sign.sign.toUpperCase());
    });

    test('默认 nonce 为 UUID v4、stime 为秒级时间戳', () {
      final sign = cxstarReaderSign();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(sign.nonce),
        isTrue,
        reason: 'nonce 应为 UUID v4',
      );
      expect(
        sign.stime,
        closeTo(DateTime.now().millisecondsSinceEpoch ~/ 1000, 5),
      );
    });

    test('toQuery 输出 nonce/stime/sign 三参数（stime 为字符串）', () {
      final query = cxstarReaderSign(nonce: 'n', stimeSeconds: 1).toQuery();
      expect(query.keys.toSet(), {'nonce', 'stime', 'sign'});
      expect(query['stime'], '1');
    });
  });

  group('单页口令', () {
    test('md5("<bookId>-<pageno>") 小写，与实测四页一致', () {
      // 实测：pikepdf 用这些口令成功打开对应页（见归档 §7.2）。
      expect(
        cxstarPdfPassword('20a7425800017dXXXX', 1),
        '81a2d0f0b7e99ec671094e4b1b8db3fb',
      );
      expect(
        cxstarPdfPassword('20a7425800017dXXXX', 49),
        '6746799b0ae16cd82cc595152f595ea7',
      );
      expect(
        cxstarPdfPassword('20a7425800017dXXXX', 60),
        '1e1105c1f4403b8a0d48abb7a276063e',
      );
      expect(
        cxstarPdfPassword('20a7425800017dXXXX', 100),
        '830e1502444910ece3d819c0bcc4a94b',
      );
    });

    test('逐页不同（不是固定口令）', () {
      final a = cxstarPdfPassword('book', 1);
      final b = cxstarPdfPassword('book', 2);
      expect(a, isNot(b));
      expect(a.length, 32);
    });
  });

  group('阅读会话解析', () {
    test('字符串数字容错 + 字段映射', () {
      final session = CxstarReadSession.fromJson({
        'title': '空间财政',
        'page': '1',
        'paragraph': 0,
        'totalPage': 242,
        'trialPage': '48',
        'logId': 'e998a59d',
        'watermark': '江西财经大学',
        'isbuy': true,
        'isBorrowMode': false,
      });
      expect(session.title, '空间财政');
      expect(session.totalPage, 242);
      expect(session.trialPage, 48);
      expect(session.logId, 'e998a59d');
      expect(session.watermark, '江西财经大学');
      expect(session.isbuy, isTrue);
      expect(session.isBorrowMode, isFalse);
    });

    test('缺字段时给安全默认值', () {
      final session = CxstarReadSession.fromJson(const {});
      expect(session.totalPage, 0);
      expect(session.page, 0);
      expect(session.watermark, '');
    });
  });

  group('目录解析', () {
    test('章级目录 + 子节点 + 可跳转判定', () {
      final nodes = [
        for (final r in const [
          {'title': '第一章 导论', 'page': 1, 'children': <dynamic>[]},
          {'title': '第二章', 'page': 0, 'children': <dynamic>[]},
          {
            'title': '第三章',
            'page': 60,
            'children': [
              {'title': '3.1 小节', 'page': 62, 'children': <dynamic>[]},
            ],
          },
        ])
          CxstarCatalogNode.fromJson(r),
      ];
      expect(nodes.length, 3);
      expect(nodes[0].jumpable, isTrue);
      expect(nodes[1].jumpable, isFalse, reason: '页码 0 不可跳');
      expect(nodes[2].children.single.title, '3.1 小节');
      expect(nodes[2].children.single.jumpable, isTrue);
    });
  });

  group('计时常量', () {
    test('心跳 60 秒（实测该间隔可持续入账）', () {
      expect(cxstarReaderHeartbeat, const Duration(seconds: 60));
      expect(cxstarReaderProgressDebounce, const Duration(seconds: 2));
    });
  });
}
