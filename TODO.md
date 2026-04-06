# ReorderableTable Drag-End Animation Fix (Revised)

Status: Implementing Revised Plan...

## Information Gathered
- Complex Flutter table with drag-reorder, hover, collapsible headers.
- Headers expand/collapse via AnimatedContainers based on _hoveredRow/Col.
- Current post-drag fake hover + timer conflicts, prevents natural hover anim.

## Plan
**Goal:** Drag col2 over col3, release mouse on col3 → col2 collapses smoothly, col3 expands/highlights smoothly.
**Method:** Remove fake post-drag hover/timer. After reorder insert, immediately restore hover from mouse pos → natural independent anims.

**Detailed code updates:**
1. Remove vars: _dragEndDragType, _dragEndOriginalIndex, _postDragCollapseScheduled, _postDragCollapseTimer, _postDragCollapseDelay.
2. In _returnAnimController statusListener after insert/_initHighlightAnims: if (_lastHoverLocalPos != null) _updateHoverFromLocalOffset(_lastHoverLocalPos!); _lastHoverLocalPos = null;
3. Remove _handleDragEndHover() method entirely.
4. Remove _postDragCollapse() method.
5. Clean init/dispose/onLongPressStart/onPointerUp: remove timer references.
6. Ensure _onHover updates _lastHoverLocalPos during non-drag.

## Steps
1. [ ] Edit reorderable_table.dart - remove vars & methods, add hover restore.
2. [ ] Verify hover works post-drag via logic check.
3. [ ] Test in app: drag col2→col3 overlap, release on col3 → col2 collapse, col3 expand.
4. [ ] Update TODO, complete.

Last updated by BLACKBOXAI
