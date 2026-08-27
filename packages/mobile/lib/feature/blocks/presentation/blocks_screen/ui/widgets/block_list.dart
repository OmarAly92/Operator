import 'package:flutter/material.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlockList extends StatefulWidget {
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
  });

  final String sessionId;
  final List<SessionBlock> blocks;
  final Widget? header;

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

  bool get pinned => _pinned;

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
    _scheduleFollow();
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    _pinned = BlockViewport.isPinned(
      controller.position.pixels,
      controller.position.maxScrollExtent,
    );
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
