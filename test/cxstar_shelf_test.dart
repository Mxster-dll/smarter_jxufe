/// 畅想之星书架解析守卫（分类树 / 书单行 / 检索高亮清洗 / 分页判定）。
///
/// fixture 取自 2026-09-14 对 `m.cxstar.com` 的真实响应（字段名原样保留，
/// 书名与简介做了缩写；`XXXX` 结尾的 id 是服务端字面值，不是脱敏）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_shelf.dart';

const String _categoriesJson = '''
{
  "clc": [
    {"id": "1826972f0000010bd3",
     "name": "A 马克思主义、列宁主义、毛泽东思想、邓小平理论",
     "icon": null, "total": "0",
     "children": [
       {"id": "1826975a00021c0bd3", "name": "A1 马克思、恩格斯著作",
        "icon": null, "total": "12", "children": []},
       {"id": "1826975b00021c1bd3", "name": "A2 列宁著作",
        "icon": null, "total": "0", "children": []}
     ]}
  ],
  "subject": [
    {"id": "1d3946fb0024f20bce", "name": "哲学", "icon": null, "total": "0", "children": []}
  ],
  "college": [
    {"id": "274cfb34000001XXXX", "name": "财税与公共管理学院",
     "icon": null, "total": "0", "children": []}
  ],
  "major": null,
  "sale": null,
  "total": "210849",
  "collegeTotal": 782,
  "majorTotal": 0,
  "collegeName": "蛟湖经典阅读",
  "majorName": null,
  "saleName": "图书分类"
}
''';

const String _bookJson = '''
{
  "id": "1ef02a7100074cXXXX",
  "title": "外国<em>财政</em>史（上册）",
  "author": "张三著",
  "publishDate": "2015.06",
  "cover": "https://p.cxstar.com/bookimage/cate1/file1ef02b84000774XXXX/1ef02b84000774XXXX_MS.jpg",
  "intro": "本书简介 &amp; 更多内容",
  "isbn": "978-7-300-21381-1",
  "publisher": "中国人民大学出版社",
  "readNum": "1234",
  "market": "国家出版基金",
  "videoCover": null
}
''';

Map<String, dynamic> _json(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

void main() {
  group('cxstarNum', () {
    test('字符串 / 数字 / 脏值', () {
      expect(cxstarNum('1234'), 1234);
      expect(cxstarNum(782), 782);
      expect(cxstarNum(' 12 '), 12);
      expect(cxstarNum(null), 0);
      expect(cxstarNum('abc'), 0);
      expect(cxstarNum(3.7), 3);
    });
  });

  group('cxstarPlainText', () {
    test('去掉检索高亮标签', () {
      expect(cxstarPlainText('外国<em>财政</em>史'), '外国财政史');
      expect(cxstarPlainText('<em>Python</em>金融实战'), 'Python金融实战');
    });

    test('还原常见实体并 trim', () {
      expect(cxstarPlainText(' 简介 &amp; 更多 '), '简介 & 更多');
      expect(cxstarPlainText('a&nbsp;b'), 'a b');
      expect(cxstarPlainText('&lt;标题&gt;'), '<标题>');
      expect(cxstarPlainText(''), '');
    });
  });

  group('CxstarCategoryNode', () {
    test('解析子节点与计数', () {
      final root = CxstarCategoryNode.fromJson(
        (_json(_categoriesJson)['clc'] as List).first as Map<String, dynamic>,
      );
      expect(root.id, '1826972f0000010bd3');
      expect(root.name, startsWith('A 马克思主义'));
      expect(root.total, 0);
      expect(root.hasChildren, isTrue);
      expect(root.children.length, 2);
      expect(root.children.first.name, 'A1 马克思、恩格斯著作');
      expect(root.children.first.total, 12);
      expect(root.children.first.hasChildren, isFalse);
    });

    test('缺字段容错', () {
      final node = CxstarCategoryNode.fromJson(const {});
      expect(node.id, '');
      expect(node.name, '');
      expect(node.hasChildren, isFalse);
    });
  });

  group('CxstarShelfCategories', () {
    test('三套体系、标签、机构别名与总册数', () {
      final categories = CxstarShelfCategories.fromJson(_json(_categoriesJson));
      expect(categories.groups.map((g) => g.key).toList(), [
        'clc',
        'subject',
        'college',
      ]);
      expect(categories.groups.map((g) => g.label).toList(), [
        '中图法',
        '学科',
        '院系',
      ]);
      expect(categories.total, 210849);
      expect(categories.venueName, '蛟湖经典阅读');
      expect(categories.groupOf('college')!.roots.first.name, '财税与公共管理学院');
      expect(categories.groupOf('major'), isNull);
    });

    test('空体系不产出分组（major / sale 为 null）', () {
      final categories = CxstarShelfCategories.fromJson({
        'clc': const [],
        'subject': const [],
        'college': const [],
      });
      expect(categories.groups, isEmpty);
      expect(categories.total, 0);
    });
  });

  group('CxstarBook', () {
    test('真实书单行映射（标题清高亮、readNum 转数字）', () {
      final book = CxstarBook.fromJson(_json(_bookJson));
      expect(book.id, '1ef02a7100074cXXXX');
      expect(book.title, '外国财政史（上册）');
      expect(book.author, '张三著');
      expect(book.publisher, '中国人民大学出版社');
      expect(book.publishDate, '2015.06');
      expect(book.isbn, '978-7-300-21381-1');
      expect(book.intro, '本书简介 & 更多内容');
      expect(book.readNum, 1234);
      expect(book.hasCover, isTrue);
    });

    test('缺作者 / 封面时不崩且 hasCover=false', () {
      final book = CxstarBook.fromJson(const {'id': 'x'});
      expect(book.title, '');
      expect(book.author, '');
      expect(book.hasCover, isFalse);
      expect(book.subtitle, '');
    });

    test('subtitle 拼接可用部分', () {
      const book = CxstarBook(
        id: 'x',
        title: 't',
        author: '某作者',
        publishDate: '2020.01',
        publisher: '某社',
      );
      expect(book.subtitle, '某作者 · 2020.01 · 某社');
      expect(
        const CxstarBook(id: 'x', title: 't', publisher: '仅出版社').subtitle,
        '仅出版社',
      );
    });
  });

  group('CxstarBookPage', () {
    test('hasMore 按「已请求条数 < 总数」判定', () {
      expect(
        const CxstarBookPage(books: [], total: 219, page: 1, size: 20).hasMore,
        isTrue,
      );
      expect(
        const CxstarBookPage(books: [], total: 219, page: 10, size: 20).hasMore,
        isTrue, // 200 < 219，还有第 11 页
      );
      expect(
        const CxstarBookPage(books: [], total: 219, page: 11, size: 20).hasMore,
        isFalse,
      );
      expect(
        const CxstarBookPage(books: [], total: 0, page: 1, size: 20).hasMore,
        isFalse,
      );
    });
  });
}
