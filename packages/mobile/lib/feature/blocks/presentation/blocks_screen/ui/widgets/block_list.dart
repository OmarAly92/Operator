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

  @override
  void initState() {
    super.initState();
    _adoptPivot();
  }

  @override
  void didUpdateWidget(BlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) _pivotSeq = null;
    _adoptPivot();
  }

  void _adoptPivot() {
    if (_pivotSeq != null || widget.blocks.isEmpty) return;
    _pivotSeq = widget.blocks.first.firstSeq;
  }

  @override
  void dispose() {
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
