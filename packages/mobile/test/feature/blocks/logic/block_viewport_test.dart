import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

SessionBlock _block(int seq) => SessionBlock(
  id: 'seq-$seq',
  firstSeq: seq,
  lastSeq: seq,
  kind: BlockKind.tool,
  status: BlockStatus.ok,
  title: 'Bash',
  body: 'ok',
);

void main() {
  group('pivotIndex', () {
    test('an unset pivot puts every block after the centre', () {
      expect(BlockViewport.pivotIndex([_block(4), _block(5)], null), 0);
    });

    test('splits older blocks out of the centre sliver', () {
      final blocks = [_block(1), _block(2), _block(3), _block(4)];
      expect(BlockViewport.pivotIndex(blocks, 3), 2);
    });

    test(
      'a pivot older than everything held leaves the leading sliver empty',
      () {
        expect(BlockViewport.pivotIndex([_block(7), _block(8)], 2), 0);
      },
    );

    test(
      'a pivot newer than everything held puts every block before the centre',
      () {
        expect(BlockViewport.pivotIndex([_block(1), _block(2)], 9), 2);
      },
    );

    test('an evicted pivot still splits at the same seq boundary', () {
      final afterEviction = [_block(3), _block(4), _block(5)];
      expect(BlockViewport.pivotIndex(afterEviction, 4), 1);
    });

    test('an empty window has nothing before the centre', () {
      expect(BlockViewport.pivotIndex(const [], 4), 0);
    });
  });

  group('isPinned', () {
    test('is pinned exactly at the tail', () {
      expect(BlockViewport.isPinned(1000, 1000), isTrue);
    });

    test('is pinned inside the slack', () {
      expect(BlockViewport.isPinned(980, 1000), isTrue);
    });

    test('is not pinned once scrolled clear of the slack', () {
      expect(BlockViewport.isPinned(900, 1000), isFalse);
    });

    test('an unscrollable list is pinned', () {
      expect(BlockViewport.isPinned(0, 0), isTrue);
    });

    test('a negative offset in the leading sliver is not pinned', () {
      expect(BlockViewport.isPinned(-400, 1000), isFalse);
    });
  });

  group('headerSticks', () {
    test('a block shorter than the viewport keeps its header pinned', () {
      expect(BlockViewport.headerSticks(200, 600), isTrue);
    });

    test('a block exactly as tall as the viewport still sticks', () {
      expect(BlockViewport.headerSticks(600, 600), isTrue);
    });

    test('a block taller than the viewport does not trap its own header', () {
      expect(BlockViewport.headerSticks(900, 600), isFalse);
    });
  });

  group('boundaries', () {
    test('next steps forward and stops at the last block', () {
      expect(BlockViewport.nextBoundary(0, 3), 1);
      expect(BlockViewport.nextBoundary(2, 3), isNull);
    });

    test('next from nothing selects the first block', () {
      expect(BlockViewport.nextBoundary(null, 3), 0);
    });

    test('previous steps back and stops at the first block', () {
      expect(BlockViewport.previousBoundary(2, 3), 1);
      expect(BlockViewport.previousBoundary(0, 3), isNull);
    });

    test('an empty list has no boundaries in either direction', () {
      expect(BlockViewport.nextBoundary(null, 0), isNull);
      expect(BlockViewport.previousBoundary(0, 0), isNull);
    });
  });
}
