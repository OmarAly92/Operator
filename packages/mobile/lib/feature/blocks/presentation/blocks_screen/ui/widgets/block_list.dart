import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

class BlockList extends StatefulWidget {
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
    this.sticky,
    this.pinnedListenable,
  });

  final String sessionId;
  final List<SessionBlock> blocks;
  final Widget? header;
  final ValueNotifier<StickyBlock?>? sticky;
  final ValueNotifier<bool>? pinnedListenable;

  @override
  State<BlockList> createState() => BlockListState();
}

class BlockListState extends State<BlockList> {
  final ScrollController controller = ScrollController();
  final GlobalKey centerKey = GlobalKey();
  final GlobalKey leadingKey = GlobalKey();
  final GlobalKey viewportKey = GlobalKey();

  int? _pivotSeq;
  bool _pinned = true;
  bool _followScheduled = false;
  int _followHops = 0;
  int? _topIndex;

  bool get pinned => _pinned;
  int? get topBlockIndex => _topIndex;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onScroll);
    _adoptPivot();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(BlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) {
      _pivotSeq = null;
      _pinned = true;
    }
    _adoptPivot();
    if (_pinned) _scheduleFollow();
  }

  void _adoptPivot() {
    if (_pivotSeq != null || widget.blocks.isEmpty) return;
    _pivotSeq = widget.blocks.first.firstSeq;
  }

  void jumpToLatest() {
    _pinned = true;
    widget.pinnedListenable?.value = true;
    _scheduleFollow();
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    _pinned = BlockViewport.isPinned(
      controller.position.pixels,
      controller.position.maxScrollExtent,
    );
    widget.pinnedListenable?.value = _pinned;
    _updateSticky();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSticky();
    });
  }

  double? _viewportTopDelta(int index) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final pivot = BlockViewport.pivotIndex(widget.blocks, _pivotSeq);

    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final sliverIndex = sliver.indexOf(child);
        final blockIndex = key == leadingKey
            ? pivot - 1 - sliverIndex
            : pivot + sliverIndex;
        if (blockIndex == index) {
          return child.localToGlobal(Offset.zero).dy - top;
        }
        child = sliver.childAfter(child);
      }
    }
    return null;
  }

  void scrollBlockIntoView(int index) {
    if (!controller.hasClients) return;
    final delta = _viewportTopDelta(index);
    if (delta == null) return;
    final position = controller.position;
    controller.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void scrollToBoundary({required bool forward}) {
    if (!controller.hasClients) return;
    final current = _topIndex;
    if (forward) {
      final target = BlockViewport.nextBoundary(current, widget.blocks.length);
      if (target != null) scrollBlockIntoView(target);
      return;
    }
    if (current == null) return;
    final delta = _viewportTopDelta(current);
    if (delta != null && delta < -1) {
      scrollBlockIntoView(current);
      return;
    }
    final target = BlockViewport.previousBoundary(
      current,
      widget.blocks.length,
    );
    if (target != null) scrollBlockIntoView(target);
  }

  void _updateSticky() {
    final notifier = widget.sticky;
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      _topIndex = null;
      notifier?.value = null;
      return;
    }

    final top = viewport.localToGlobal(Offset.zero).dy + 0.5;
    final pivot = BlockViewport.pivotIndex(widget.blocks, _pivotSeq);

    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final childTop = child.localToGlobal(Offset.zero).dy;
        final height = child.size.height;
        if (childTop <= top && childTop + height > top) {
          final sliverIndex = sliver.indexOf(child);
          final blockIndex = key == leadingKey
              ? pivot - 1 - sliverIndex
              : pivot + sliverIndex;
          if (blockIndex < 0 || blockIndex >= widget.blocks.length) {
            _topIndex = null;
            notifier?.value = null;
            return;
          }
          _topIndex = blockIndex;
          notifier?.value =
              BlockViewport.headerSticks(height, viewport.size.height)
              ? StickyBlock(block: widget.blocks[blockIndex], height: height)
              : null;
          return;
        }
        child = sliver.childAfter(child);
      }
    }

    _topIndex = null;
    notifier?.value = null;
  }

  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    _followHops = 0;
    WidgetsBinding.instance.scheduleFrame();
    _followStep();
  }

  void _followStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !controller.hasClients ||
          !_pinned ||
          _followHops >= kMaxFollowHops) {
        _followScheduled = false;
        return;
      }
      final extent = controller.position.maxScrollExtent;
      if ((controller.position.pixels - extent).abs() < 0.5) {
        _followScheduled = false;
        return;
      }
      _followHops++;
      controller.jumpTo(extent);
      _followStep();
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onScroll);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSticky();
    });
    final blocks = widget.blocks;
    final pivot = BlockViewport.pivotIndex(blocks, _pivotSeq);
    final header = widget.header;

    return SizedBox.expand(
      key: viewportKey,
      child: CustomScrollView(
        controller: controller,
        center: centerKey,
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
          SliverList.builder(
            key: leadingKey,
            itemCount: pivot,
            itemBuilder: (context, index) {
              final block = blocks[pivot - 1 - index];
              return BlockCard(key: ValueKey(block.id), block: block);
            },
          ),
          SliverList.builder(
            key: centerKey,
            itemCount: blocks.length - pivot,
            itemBuilder: (context, index) {
              final block = blocks[pivot + index];
              return BlockCard(key: ValueKey(block.id), block: block);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ],
      ),
    );
  }
}
