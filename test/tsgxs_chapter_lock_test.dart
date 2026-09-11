import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 章节顺序解锁的领域约定(实测 2026-09-11):
/// 上一章未通过时,后续章节地图服务端 302 到 `/html/401.html` → 只能得到 id,
/// 故用 [TsgxsChapter.locked] 占位,保证首页章节列表始终可渲染。
void main() {
  group('TsgxsChapter 顺序解锁', () {
    test('locked 占位章:无标题/无节点,不可闯关', () {
      const c = TsgxsChapter.locked('7f6d456b-2372-4b80-8e5a-0f6bf8e0ed82');
      expect(c.locked, isTrue);
      expect(c.nodes, isEmpty);
      expect(c.isVisitAll, isFalse);
      expect(c.canStartExam, isFalse);
    });

    test('locked 占位章标题按序号兜底', () {
      const c = TsgxsChapter.locked('x');
      expect(c.displayTitle(0), '第 1 章');
      expect(c.displayTitle(4), '第 5 章');
    });

    test('已解锁章:标题优先于序号兜底,线索学完且 examinations=1 可闯关', () {
      const c = TsgxsChapter(
        id: 'x',
        title: '图书馆概况',
        isVisitAll: true,
        examinations: 1,
        nodes: [],
      );
      expect(c.locked, isFalse);
      expect(c.canStartExam, isTrue);
      expect(c.displayTitle(0), '图书馆概况');
    });

    test('线索未学完(examinations=1 但 isVisitAll=false)不可闯关', () {
      const c = TsgxsChapter(
        id: 'x',
        title: 't',
        isVisitAll: false,
        examinations: 1,
        nodes: [],
      );
      expect(c.canStartExam, isFalse);
    });

    test('locked 章即使线索/考点状态满足也不可闯关', () {
      const c = TsgxsChapter(
        id: 'x',
        title: '',
        isVisitAll: true,
        examinations: 1,
        nodes: [],
        locked: true,
      );
      expect(c.canStartExam, isFalse);
    });

    test('examinations=2(链式下一章)不可闯关', () {
      const c = TsgxsChapter(
        id: 'x',
        title: 't',
        isVisitAll: true,
        examinations: 2,
        nodes: [],
      );
      expect(c.canStartExam, isFalse);
    });
  });
}
