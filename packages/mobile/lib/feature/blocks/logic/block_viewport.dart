import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

const double kTailSlack = 24;

const int kMaxFollowHops = 20;

sealed class BlockViewport {
  static int pivotIndex(List<SessionBlock> blocks, int? pivotSeq) {
    if (pivotSeq == null) return 0;
    for (var index = 0; index < blocks.length; index++) {
      if (blocks[index].firstSeq >= pivotSeq) return index;
    }
    return blocks.length;
  }

  static bool isPinned(double pixels, double maxScrollExtent) =>
      pixels >= maxScrollExtent - kTailSlack;

  static bool headerSticks(double blockHeight, double viewportHeight) =>
      blockHeight <= viewportHeight;

  static int? nextBoundary(int? current, int count) {
    if (count == 0) return null;
    if (current == null) return 0;
    final next = current + 1;
    return next >= count ? null : next;
  }

  static int? previousBoundary(int? current, int count) {
    if (count == 0 || current == null) return null;
    final previous = current - 1;
    return previous < 0 ? null : previous;
  }
}
