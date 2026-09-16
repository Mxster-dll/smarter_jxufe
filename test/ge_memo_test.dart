/// 分数估计 · 课程备忘录：模型容错 / 文件名与体积工具 / 私有目录 Store /
/// 压缩口径 / 导入限额 / 卡片交互。
///
/// 口径来源：用户 2026-09-15 拍板「每门课程加备忘录 + 上传图片」
/// （单块 = 文字 + 图片网格；拷进私有目录只存文件名；压到 1600px；
/// 详情页卡片 + 列表小图标；单课 20 张、单张 20MB）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:smarter_jxufe/features/score_estimate/data/ge_memo_importer.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_memo_store.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_memo.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_memo_card.dart';

/// 纯色 JPEG（[width]×[height]）。
Uint8List jpegBytes(int width, int height, {int seed = 1}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(40 + seed * 30, 90, 200));
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

/// 带 alpha 的 PNG。
Uint8List pngAlphaBytes(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(10, 200, 30, 120));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ge_memo_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File writeSource(String name, Uint8List bytes) {
    final file = File(p.join(tmp.path, name));
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('GeMemo 模型', () {
    test('空判据：纯空白文字 + 无图 = 空', () {
      expect(GeMemo.empty.isEmpty, isTrue);
      expect(const GeMemo(text: '   \n ').isEmpty, isTrue);
      expect(const GeMemo(text: '复习重点').isEmpty, isFalse);
      expect(
        const GeMemo(images: [GeMemoImage(fileName: 'a.jpg')]).isEmpty,
        isFalse,
      );
    });

    test('JSON 往返保留文字与图片属性', () {
      final memo = GeMemo(
        text: '期末考到第 5 章',
        images: [
          GeMemoImage(
            fileName: 'a.jpg',
            addedAt: 1700000000000,
            bytes: 2048,
            width: 1600,
            height: 900,
          ),
          const GeMemoImage(fileName: 'b.png'),
        ],
      );
      final back = GeMemo.fromJson(memo.toJson());
      expect(back, memo);
      expect(back.text, '期末考到第 5 章');
      expect(back.images.first.width, 1600);
      expect(back.images.first.sizeText, '2 KB');
      expect(back.images.first.pixelText, '1600×900');
    });

    test('fromJson 容错：非 Map / 缺字段 / 脏条目 / 超量', () {
      expect(GeMemo.fromJson(null), GeMemo.empty);
      expect(GeMemo.fromJson('oops'), GeMemo.empty);
      expect(GeMemo.fromJson(<String, dynamic>{}), GeMemo.empty);
      // images 里非 Map / fileName 为空的条目全部丢弃
      final dirty = GeMemo.fromJson({
        'text': 'x',
        'images': [
          42,
          {'bytes': 10},
          {'fileName': 'ok.jpg', 'bytes': 'bad', 'width': -5},
        ],
      });
      expect(dirty.text, 'x');
      expect(dirty.imageCount, 1);
      expect(dirty.images.single.fileName, 'ok.jpg');
      expect(dirty.images.single.bytes, 0);
      expect(dirty.images.single.width, 0);
      // 超过上限的条目被截断
      final many = GeMemo.fromJson({
        'images': [
          for (var i = 0; i < geMemoMaxImages + 5; i++) {'fileName': '$i.jpg'},
        ],
      });
      expect(many.imageCount, geMemoMaxImages);
    });

    test('容量：remainingSlots / isFull', () {
      final full = GeMemo(
        images: [
          for (var i = 0; i < geMemoMaxImages; i++)
            GeMemoImage(fileName: '$i.jpg'),
        ],
      );
      expect(full.isFull, isTrue);
      expect(full.remainingSlots, 0);
      expect(GeMemo.empty.remainingSlots, geMemoMaxImages);
      expect(
        const GeMemo(images: [GeMemoImage(fileName: 'a.jpg')]).remainingSlots,
        geMemoMaxImages - 1,
      );
      // 超量导入也不会变成负数
      final over = GeMemo(
        images: [
          for (var i = 0; i < geMemoMaxImages + 3; i++)
            GeMemoImage(fileName: '$i.jpg'),
        ],
      );
      expect(over.remainingSlots, 0);
    });

    test('summary 文案（列表页小图标 tooltip）', () {
      expect(geMemoSummary(GeMemo.empty), '');
      expect(geMemoSummary(const GeMemo(text: '  ')), '');
      expect(geMemoSummary(const GeMemo(text: 'a')), '备忘录：文字');
      expect(
        geMemoSummary(const GeMemo(images: [GeMemoImage(fileName: 'a.jpg')])),
        '备忘录：1 张图片',
      );
      expect(
        geMemoSummary(
          const GeMemo(
            text: 'a',
            images: [
              GeMemoImage(fileName: 'a.jpg'),
              GeMemoImage(fileName: 'b.jpg'),
            ],
          ),
        ),
        '备忘录：文字 + 2 张图片',
      );
    });
  });

  group('文件名与体积工具', () {
    test('路径片段清洗与扩展名归一', () {
      expect(geMemoSafeSegment('2000000000'), '2000000000');
      expect(geMemoSafeSegment('a/b\\c'), 'a_b_c');
      expect(geMemoSafeSegment('..'), 'none');
      expect(geMemoSafeSegment('   '), 'none');
      expect(geMemoNormalizeExt('a.JPG'), 'jpg');
      expect(geMemoNormalizeExt('no-ext'), 'png');
      expect(geMemoNormalizeExt(r'dir\a.webp'), 'webp');
      expect(geMemoNormalizeExt('a.jfif'), 'png');
    });

    test('体积文案', () {
      expect(geMemoSizeText(0), '');
      expect(geMemoSizeText(-5), '');
      expect(geMemoSizeText(500), '500 B');
      expect(geMemoSizeText(2048), '2 KB');
      expect(geMemoSizeText(2 * 1024 * 1024), '2.0 MB');
    });

    test('移动端判定（决定「拍照」入口）', () {
      expect(geMemoMobilePlatformOn('android'), isTrue);
      expect(geMemoMobilePlatformOn('iOS'), isTrue);
      expect(geMemoMobilePlatformOn('windows'), isFalse);
      expect(geMemoPickSources(mobile: false), [GeMemoPickSource.files]);
      expect(geMemoPickSources(mobile: true), [
        GeMemoPickSource.gallery,
        GeMemoPickSource.camera,
        GeMemoPickSource.files,
      ]);
    });
  });

  group('GeCourse 接入备忘录', () {
    test('JSON 往返与旧数据兼容', () {
      final course = GeCourse(
        id: 'c1',
        name: '高等数学',
        memo: const GeMemo(
          text: '笔记',
          images: [GeMemoImage(fileName: 'a.jpg', bytes: 100)],
        ),
      );
      final back = GeCourse.fromJson(course.toJson());
      expect(back.memo.text, '笔记');
      expect(back.memo.imageCount, 1);

      // 旧数据没有 memo 键 → 空备忘录，不崩
      final legacy = GeCourse.fromJson({'id': 'x', 'name': '旧课'});
      expect(legacy.memo, GeMemo.empty);
      expect(legacy.memo.isEmpty, isTrue);
      // memo 字段类型不对也不崩
      expect(GeCourse.fromJson({'id': 'x', 'memo': 7}).memo, GeMemo.empty);
    });

    test('copyWith 默认保留备忘录', () {
      const memo = GeMemo(text: 'n');
      final course = GeCourse(id: 'c1', name: 'A', memo: memo);
      expect(course.copyWith(name: 'B').memo, memo);
      expect(course.copyWith(memo: GeMemo.empty).memo, GeMemo.empty);
    });
  });

  group('GeMemoStore（私有目录）', () {
    GeMemoStore store() => GeMemoStore(Directory(p.join(tmp.path, 'ge_memos')));

    test('落盘 / 解析 / 删除', () async {
      final s = store();
      final bytes = jpegBytes(20, 10);
      final name = await s.save(
        account: '2000000000',
        courseId: 'c1',
        bytes: bytes,
        ext: 'jpg',
      );
      expect(name.endsWith('.jpg'), isTrue);
      final path = s.resolve('2000000000', 'c1', name);
      expect(path, isNotNull);
      expect(File(path!).readAsBytesSync(), bytes);

      await s.remove(account: '2000000000', courseId: 'c1', fileName: name);
      expect(s.resolve('2000000000', 'c1', name), isNull);
      // 再删一次不抛
      await s.remove(account: '2000000000', courseId: 'c1', fileName: name);
      expect(s.resolve('2000000000', 'c1', ''), isNull);
    });

    test('同扩展名多次落盘不会互相覆盖（uuid 命名）', () async {
      final s = store();
      final first = await s.save(
        account: 'a',
        courseId: 'c1',
        bytes: jpegBytes(10, 10, seed: 1),
        ext: 'jpg',
      );
      final second = await s.save(
        account: 'a',
        courseId: 'c1',
        bytes: jpegBytes(10, 10, seed: 2),
        ext: 'jpg',
      );
      expect(first, isNot(second));
      expect(s.bytesOf('a', 'c1'), greaterThan(0));
    });

    test('账号与课程互相隔离；账号里的怪字符被清洗', () async {
      final s = store();
      final name = await s.save(
        account: '22/02 513',
        courseId: 'c/1',
        bytes: jpegBytes(10, 10),
        ext: 'jpg',
      );
      // 同参数能取回（清洗是确定性的）
      expect(s.resolve('22/02 513', 'c/1', name), isNotNull);
      // 目录确实落在清洗后的名字里，没有越界
      expect(
        p.isWithin(s.directory.path, s.courseDir('22/02 513', 'c/1').path),
        isTrue,
      );
      // 别的账号 / 别的课程取不到
      expect(s.resolve('2000000000', 'c/1', name), isNull);
      expect(s.resolve('22/02 513', 'c/2', name), isNull);
    });

    test('清空课程 / 统计体积；目录不存在时不抛', () async {
      final s = store();
      expect(s.bytesOf('a', 'none'), 0);
      expect(s.resolve('a', 'none', 'x.jpg'), isNull);
      await s.removeAllOfCourse('a', 'none'); // 不抛

      await s.save(
        account: 'a',
        courseId: 'c1',
        bytes: jpegBytes(30, 30),
        ext: 'jpg',
      );
      await s.save(
        account: 'a',
        courseId: 'c2',
        bytes: jpegBytes(30, 30),
        ext: 'png',
      );
      expect(s.bytesOf('a', 'c1'), greaterThan(0));
      final c1Bytes = s.bytesOf('a', 'c1');

      await s.removeAllOfCourse('a', 'c1');
      expect(s.bytesOf('a', 'c1'), 0);
      expect(s.bytesOf('a', 'c2'), greaterThan(0)); // 别的课程不受影响
      expect(c1Bytes, greaterThan(0));

      await s.removeAllOfAccount('a');
      expect(s.bytesOf('a', 'c2'), 0);
      expect(Directory(p.join(s.directory.path, 'a')).existsSync(), isFalse);
    });
  });

  group('geMemoCompressImage（压到最长边 1600）', () {
    test('大图等比缩到最长边；宽为长边时宽度受限', () {
      final out = geMemoCompressImage(jpegBytes(2400, 1200));
      expect(out.reencoded, isTrue);
      expect(out.width, geMemoMaxEdge);
      expect(out.height, geMemoMaxEdge ~/ 2);
      expect(out.ext, 'jpg');
      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.width, geMemoMaxEdge);
      expect(decoded.height, geMemoMaxEdge ~/ 2);
      expect(out.bytes.length, lessThan(jpegBytes(2400, 1200).length));
    });

    test('高为长边时高度受限', () {
      final out = geMemoCompressImage(jpegBytes(900, 3000));
      expect(out.height, geMemoMaxEdge);
      expect(out.width, (900 * geMemoMaxEdge / 3000).round());
    });

    test('已合规且体积不大 → 字节原样保留（不二次编码）', () {
      final small = jpegBytes(800, 600);
      final out = geMemoCompressImage(small);
      expect(out.reencoded, isFalse);
      expect(identical(out.bytes, small), isTrue);
      expect(out.width, 800);
      expect(out.height, 600);
    });

    test('带 alpha 的 PNG 保持 PNG（不压成 JPEG 丢透明通道）', () {
      final out = geMemoCompressImage(pngAlphaBytes(2000, 1000));
      expect(out.ext, 'png');
      expect(out.width, geMemoMaxEdge);
      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.numChannels, 4);
    });

    test('不是图片 → FormatException（导入层记为「无法识别」）', () {
      expect(
        () => geMemoCompressImage(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('importGeMemoImages（选图 → 压缩 → 落盘）', () {
    late GeMemoStore store;
    setUp(() {
      store = GeMemoStore(Directory(p.join(tmp.path, 'memos')));
    });

    /// 同步压缩器：跳过 isolate，并把最长边压到 400 便于断言。
    GeMemoCompressed small(Uint8List bytes) =>
        geMemoCompressImage(bytes, maxEdge: 400);

    test('正常图片全部落盘，尺寸与文件名记进 GeMemoImage', () async {
      final a = writeSource('a.jpg', jpegBytes(1200, 600));
      final b = writeSource('b.png', pngAlphaBytes(500, 500));
      final result = await importGeMemoImages(
        store: store,
        account: '2000000000',
        courseId: 'c1',
        sources: [
          GeMemoSourceFile(name: 'a.jpg', path: a.path),
          GeMemoSourceFile(name: 'b.png', path: b.path),
        ],
        remainingSlots: geMemoMaxImages,
        compress: small,
      );

      expect(result.skipped, isEmpty);
      expect(result.addedCount, 2);
      expect(result.summary, '已添加 2 张');
      final first = result.added.first;
      expect(first.width, 400);
      expect(first.height, 200);
      expect(first.bytes, greaterThan(0));
      final saved = store.resolve('2000000000', 'c1', first.fileName);
      expect(saved, isNotNull);
      expect(File(saved!).lengthSync(), first.bytes);
      expect(result.added.last.fileName.endsWith('.png'), isTrue);
    });

    test('超限 / 无法识别 / 读取失败分别记不同原因', () async {
      final ok = writeSource('ok.jpg', jpegBytes(100, 100));
      // 超限的那张内容无所谓（在读取之前就被体积挡下），给足字节即可。
      final big = writeSource('big.jpg', Uint8List(4096));
      final broken = writeSource(
        'broken.jpg',
        Uint8List.fromList(List.filled(64, 7)),
      );
      // 前提断言：否则「超限」分支根本没被测到（改上限/换图后仍能自证）。
      expect(ok.lengthSync(), lessThan(1000));
      expect(big.lengthSync(), greaterThan(1000));
      final result = await importGeMemoImages(
        store: store,
        account: 'a',
        courseId: 'c1',
        sources: [
          GeMemoSourceFile(name: 'ok.jpg', path: ok.path),
          GeMemoSourceFile(name: 'big.jpg', path: big.path),
          GeMemoSourceFile(name: 'broken.jpg', path: broken.path),
          GeMemoSourceFile(name: 'ghost.jpg', path: p.join(tmp.path, 'none')),
        ],
        remainingSlots: geMemoMaxImages,
        maxBytes: 1000,
        compress: small,
      );

      // ok.jpg 正常导入；其余三张各因一种原因被跳过
      expect(result.addedCount, 1);
      expect(result.skipped.length, 3);
      expect(result.skipped[0].reason, GeMemoSkipReason.tooLarge);
      expect(result.skipped[1].reason, GeMemoSkipReason.undecodable);
      expect(result.skipped[2].reason, GeMemoSkipReason.failed);
      expect(geMemoSkipText(result.skipped[0]), contains('已跳过'));
      expect(result.summary, '已添加 1 张 · 跳过 3 张');
    });

    test('数量上限：超出 remainingSlots 的记 overLimit 且不落盘', () async {
      final sources = [
        for (var i = 0; i < 3; i++)
          GeMemoSourceFile(
            name: '$i.jpg',
            path: writeSource('$i.jpg', jpegBytes(120, 120)).path,
          ),
      ];
      final result = await importGeMemoImages(
        store: store,
        account: 'a',
        courseId: 'c1',
        sources: sources,
        remainingSlots: 1,
        compress: small,
      );
      expect(result.addedCount, 1);
      // 剩下两张都因数量上限被跳过
      expect(result.skipped.length, 2);
      expect(
        result.skipped.every((s) => s.reason == GeMemoSkipReason.overLimit),
        isTrue,
      );
      expect(result.summary, '已添加 1 张 · 跳过 2 张');
      // 只剩 1 张的位置：目录里就只有 1 个文件
      expect(store.courseDir('a', 'c1').listSync().length, 1);
    });

    test('remainingSlots = 0 → 全部跳过且不读文件', () async {
      final result = await importGeMemoImages(
        store: store,
        account: 'a',
        courseId: 'c1',
        sources: [
          GeMemoSourceFile(
            name: 'a.jpg',
            path: writeSource('a.jpg', jpegBytes(50, 50)).path,
          ),
        ],
        remainingSlots: 0,
        compress: small,
      );
      expect(result.added, isEmpty);
      expect(result.skipped.single.reason, GeMemoSkipReason.overLimit);
      expect(store.courseDir('a', 'c1').existsSync(), isFalse);
    });

    test('空选择（用户取消）→ 空结果', () async {
      final result = await importGeMemoImages(
        store: store,
        account: 'a',
        courseId: 'c1',
        sources: const [],
        remainingSlots: geMemoMaxImages,
        compress: small,
      );
      expect(result.isEmpty, isTrue);
      expect(result.summary, '没有可导入的图片');
    });
  });

  group('GeMemoCard / GeMemoBadge（界面）', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('渲染文字、张数与缩略图；缺文件出占位图', (tester) async {
      final file = writeSource('a.png', pngAlphaBytes(64, 64));
      final memo = GeMemo(
        text: '期末考到第 5 章',
        images: [
          GeMemoImage(fileName: 'a.png', bytes: file.lengthSync()),
          const GeMemoImage(fileName: 'lost.png'),
        ],
      );
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: memo,
            resolvePath: (image) =>
                image.fileName == 'a.png' ? file.path : null,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('备忘录'), findsOneWidget);
      expect(find.text('期末考到第 5 章'), findsOneWidget);
      expect(find.textContaining('2/$geMemoMaxImages 张'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget); // 只有存在的那个
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.text('添加图片'), findsOneWidget);
    });

    testWidgets('空备忘录 → 空态文案与「还没有图片」', (tester) async {
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo.empty,
            resolvePath: (_) => null,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      expect(find.text('还没有图片'), findsOneWidget);
      expect(find.textContaining('还没有图片。'), findsOneWidget);
    });

    testWidgets('文字改动回调（含初始文字回填）', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: const GeMemo(text: '原文字'),
            resolvePath: (_) => null,
            onChanged: (memo) => changes.add(memo.text),
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '新文字');
      await tester.pump();
      expect(changes.last, '新文字');
    });

    testWidgets('点「添加图片」→ 取图弹层（桌面只有文件多选）并把来源回传', (tester) async {
      GeMemoPickSource? picked;
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo.empty,
            mobile: false,
            resolvePath: (_) => null,
            onChanged: (_) {},
            onPickImages: (source) async => picked = source,
            onRemoveImage: (_) async {},
          ),
        ),
      );
      await tester.tap(find.text('添加图片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('选择图片文件'), findsOneWidget);
      expect(find.text('从相册选择'), findsNothing);
      expect(find.text('拍照'), findsNothing);

      await tester.tap(find.text('选择图片文件'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(picked, GeMemoPickSource.files);
    });

    testWidgets('移动端取图弹层有相册 / 拍照 / 文件三项', (tester) async {
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo.empty,
            mobile: true,
            resolvePath: (_) => null,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      await tester.tap(find.text('添加图片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('选择图片文件'), findsOneWidget);
      expect(find.textContaining('最多 $geMemoMaxImages 张'), findsOneWidget);
    });

    testWidgets('删除缩略图要过确认框；确认后回调该图', (tester) async {
      final file = writeSource('a.png', pngAlphaBytes(32, 32));
      final removed = <String>[];
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo(
              images: [GeMemoImage(fileName: 'a.png', bytes: 10)],
            ),
            resolvePath: (_) => file.path,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (image) async => removed.add(image.fileName),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('删除这张图片？'), findsOneWidget);

      // 先取消 → 不回调
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(removed, isEmpty);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(removed, ['a.png']);
    });

    testWidgets('点缩略图 → 大图查看器（可翻页、可删除）', (tester) async {
      final file = writeSource('a.png', pngAlphaBytes(48, 48));
      final removed = <String>[];
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: const GeMemo(
              images: [
                GeMemoImage(fileName: 'a.png', bytes: 10, width: 48, height: 48),
                GeMemoImage(fileName: 'b.png', bytes: 20),
              ],
            ),
            resolvePath: (image) =>
                image.fileName == 'a.png' ? file.path : file.path,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (image) async => removed.add(image.fileName),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(Image).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('1 / 2'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(removed, ['a.png']);
      // 还剩一张 → 视图留在查看器里
      expect(find.textContaining('1 / 1'), findsOneWidget);
    });

    testWidgets('满 20 张 → 添加入口禁用并给出提示', (tester) async {
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo(
              images: [
                for (var i = 0; i < geMemoMaxImages; i++)
                  GeMemoImage(fileName: '$i.png'),
              ],
            ),
            resolvePath: (_) => null,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('已达 $geMemoMaxImages 张上限'), findsOneWidget);
    });

    testWidgets('导入中（busy）→ 禁用添加并显示进度', (tester) async {
      await tester.pumpWidget(
        host(
          GeMemoCard(
            memo: GeMemo.empty,
            busy: true,
            resolvePath: (_) => null,
            onChanged: (_) {},
            onPickImages: (_) async {},
            onRemoveImage: (_) async {},
          ),
        ),
      );
      expect(find.text('正在导入…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });

    testWidgets('GeMemoBadge：空备忘录不占位，有内容给图标与摘要', (tester) async {
      await tester.pumpWidget(host(const GeMemoBadge(memo: GeMemo.empty)));
      expect(find.byType(Icon), findsNothing);

      await tester.pumpWidget(
        host(
          const GeMemoBadge(
            memo: GeMemo(
              text: 'x',
              images: [GeMemoImage(fileName: 'a.jpg')],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.byTooltip('备忘录：文字 + 1 张图片'), findsOneWidget);

      await tester.pumpWidget(
        host(const GeMemoBadge(memo: GeMemo(text: 'x'))),
      );
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });
  });
}
