import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/streaming_haptics.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/tool_grouping.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/incoming_response.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/tool_group_header.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_group_status.dart';

bool _hasFollowingRailItem(List<SessionBlock> blocks, int index) {
  if (!isRailBlock(blocks[index])) return false;
  final next = index + 1;
  return next < blocks.length && isRailBlock(blocks[next]);
}

class BlockList extends StatefulWidget {
  const BlockList({
    super.key,
    required this.sessionId,
    required this.blocks,
    this.header,
    this.sticky,
    this.actionsBuilder,
    this.actionContext,
    this.onAction,
    this.collapsedIds = const {},
    this.onToggleCollapse,
    this.pinnedListenable,
    this.onRollbackTurn,
    this.canRollbackTurn,
    this.highlights = const {},
    this.activeMatchId,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
    this.onLongPressHeader,
    this.sessionActive = false,
    this.bottomInset,
    this.bottomGap = 6,
    this.topInset = 0,
    this.onStreamingHaptic,
  });

  static const double topGap = 14;

  final String sessionId;
  final List<SessionBlock> blocks;
  final bool sessionActive;
  final Widget? header;
  final ValueNotifier<StickyBlock?>? sticky;
  final ValueNotifier<bool>? pinnedListenable;
  final void Function(String turnId)? onRollbackTurn;
  final bool Function(TurnGroup group)? canRollbackTurn;
  final Widget? Function(SessionBlock block)? actionsBuilder;
  final BlockActionContext? actionContext;
  final void Function(SessionBlock block, BlockAction action)? onAction;
  final Set<String> collapsedIds;
  final void Function(String blockId)? onToggleCollapse;
  final Map<String, BlockMatch> highlights;
  final String? activeMatchId;
  final Set<String> selectedIds;
  final bool selectionMode;
  final void Function(String blockId, bool selected)? onToggleSelect;
  final void Function(String blockId)? onLongPressHeader;
  final ValueListenable<double>? bottomInset;
  final double bottomGap;
  final double topInset;
  final VoidCallback? onStreamingHaptic;

  @override
  State<BlockList> createState() => BlockListState();
}

class BlockListState extends State<BlockList> {
  final ScrollController controller = ScrollController();
  final GlobalKey centerKey = GlobalKey();
  final GlobalKey leadingKey = GlobalKey();
  final GlobalKey viewportKey = GlobalKey();

  final Set<String> _collapsedToolGroups = {};
  final Set<String> _expandedTools = {};
  final Set<String> _pendingResponses = {};
  Set<String> _settledReplies = {};
  Set<String> _unsettledReplies = {};
  Set<String> _settlingReplies = {};
  StreamingHaptics? _haptics;
  bool? _hapticsReduceMotion;
  Map<String, List<SessionBlock>> _toolGroups = {};

  int? _pivotSeq;
  bool _pinned = true;
  bool _followScheduled = false;
  bool _seeking = false;
  int _followHops = 0;
  int? _topIndex;

  bool get pinned => _pinned;
  int? get topBlockIndex => _topIndex;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onScroll);
    widget.bottomInset?.addListener(_onInsetChanged);
    _adoptPivot();
    _scheduleFollow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_haptics != null && _hapticsReduceMotion == reduceMotion) return;
    _hapticsReduceMotion = reduceMotion;
    _haptics = StreamingHaptics(
      fire: () => (widget.onStreamingHaptic ?? Haptics.select)(),
      clock: () => SchedulerBinding.instance.currentSystemFrameTimeStamp,
      reduceMotion: reduceMotion,
    );
  }

  void _onInsetChanged() {
    if (_pinned && !_seeking) _scheduleFollow();
  }

  @override
  void didUpdateWidget(BlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bottomInset != oldWidget.bottomInset) {
      oldWidget.bottomInset?.removeListener(_onInsetChanged);
      widget.bottomInset?.addListener(_onInsetChanged);
    }
    if (widget.sessionId != oldWidget.sessionId) {
      _collapsedToolGroups.clear();
      _expandedTools.clear();
      _pendingResponses.clear();
      _unsettledReplies = {};
      _settlingReplies = {};
      _pivotSeq = null;
      _topIndex = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.sticky?.value = null;
        _setPinned(true);
      });
    } else if (_pinned && oldWidget.blocks.isNotEmpty) {
      final previousTail = oldWidget.blocks.last.firstSeq;
      for (final block in widget.blocks) {
        if (block.kind == BlockKind.assistant && block.firstSeq > previousTail && _isFresh(block)) {
          _pendingResponses.add(block.id);
        }
      }
    }
    if (widget.sessionId == oldWidget.sessionId) _trackStreaming(oldWidget.blocks);
    _adoptPivot();
    if (_pinned && !_seeking) _scheduleFollow();
  }

  bool _isFresh(SessionBlock block) {
    final raw = block.createdAt;
    if (raw == null) return true;
    final created = DateTime.tryParse(raw);
    if (created == null) return false;
    return DateTime.now().difference(created) < AppMotion.freshReplyWindow;
  }

  SessionBlock? _latestAssistant(List<SessionBlock> blocks) {
    for (var index = blocks.length - 1; index >= 0; index--) {
      if (blocks[index].kind == BlockKind.assistant) return blocks[index];
    }
    return null;
  }

  void _trackStreaming(List<SessionBlock> previousBlocks) {
    final haptics = _haptics;
    if (haptics == null || !widget.sessionActive || previousBlocks.isEmpty) return;
    final latest = _latestAssistant(widget.blocks);
    if (latest == null) return;
    final previous = _latestAssistant(previousBlocks);
    if (previous == null || previous.id != latest.id) {
      if (latest.firstSeq > previousBlocks.last.firstSeq) haptics.onStreamStart();
      return;
    }
    if (latest.body.length > previous.body.length) haptics.onTextGrew();
  }

  void _trackReplyMeta(List<TurnGroup> groups) {
    final settled = <String>{};
    final unsettled = <String>{};
    if (!widget.selectionMode) {
      for (final group in groups) {
        final reply = group.blocks.lastWhere(
          (block) => railKindOf(block) == RailKind.text && block.body.trim().isNotEmpty,
          orElse: () => group.blocks.first,
        );
        if (railKindOf(reply) != RailKind.text) continue;
        if (group.running || reply.status == BlockStatus.running) {
          unsettled.add(reply.id);
        } else {
          settled.add(reply.id);
        }
      }
    }
    _settlingReplies = settled.where(_unsettledReplies.contains).toSet();
    _settledReplies = settled;
    _unsettledReplies = unsettled;
  }

  void _adoptPivot() {
    if (_pivotSeq != null || widget.blocks.isEmpty) return;
    _pivotSeq = widget.blocks.first.firstSeq;
  }

  void jumpToLatest() {
    _setPinned(true);
    _scheduleFollow();
  }

  Future<void> animateToLatest() async {
    if (!controller.hasClients || MediaQuery.disableAnimationsOf(context)) {
      _seeking = false;
      jumpToLatest();
      return;
    }
    _seeking = true;
    _setPinned(true);
    final target = controller.position.maxScrollExtent;
    await controller.animateTo(target, duration: AppMotion.jumpToLatest, curve: AppMotion.easeOut);
    if (!mounted || !_seeking) return;
    _seeking = false;
    if (!controller.hasClients) return;
    final position = controller.position;
    final arrived =
        (position.pixels - target).abs() < 1 || BlockViewport.isPinned(position.pixels, position.maxScrollExtent);
    if (arrived) {
      jumpToLatest();
    } else {
      _onScroll();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_seeking) return;
    _seeking = false;
    _onScroll();
  }

  void _setPinned(bool pinned) {
    _pinned = pinned;
    widget.pinnedListenable?.value = pinned;
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    if (!_seeking) {
      _setPinned(
        BlockViewport.isPinned(
          controller.position.pixels,
          controller.position.maxScrollExtent,
        ),
      );
    }
    _updateSticky();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSticky();
    });
  }

  RenderBox? _renderedBlock(int index) {
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
        if (blockIndex == index) return child;
        child = sliver.childAfter(child);
      }
    }
    return null;
  }

  double? _viewportTopDelta(int index) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    final block = _renderedBlock(index);
    if (viewport is! RenderBox || !viewport.hasSize || block == null) {
      return null;
    }
    final top = viewport.localToGlobal(Offset.zero).dy + widget.topInset;
    return block.localToGlobal(Offset.zero).dy - top;
  }

  double? _viewportBottomDelta(int index) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    final block = _renderedBlock(index);
    if (viewport is! RenderBox || !viewport.hasSize || block == null) {
      return null;
    }
    final top = viewport.localToGlobal(Offset.zero).dy + widget.topInset;
    return block.localToGlobal(Offset(0, block.size.height)).dy - top;
  }

  void scrollBlockIntoView(int index) {
    if (!controller.hasClients) return;
    final tools = _toolGroups[widget.blocks[index].id];
    if (tools != null && tools.length > 1 && _collapsedToolGroups.contains(tools.first.id)) {
      index = widget.blocks.indexWhere((block) => block.id == tools.first.id);
    }
    var delta = _viewportTopDelta(index);
    final current = _topIndex;
    if (delta == null &&
        current != null &&
        _nextVisibleBoundary(current) == index) {
      delta = _viewportBottomDelta(current);
    }
    if (delta == null) return;
    final position = controller.position;
    controller.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  int? _nextVisibleBoundary(int? index) {
    final tools = index == null ? null : _toolGroups[widget.blocks[index].id];
    final boundary = tools != null && tools.length > 1 && _collapsedToolGroups.contains(tools.first.id)
        ? widget.blocks.indexWhere((block) => block.id == tools.last.id)
        : index;
    return BlockViewport.nextBoundary(boundary, widget.blocks.length);
  }

  void scrollToBoundary({required bool forward}) {
    if (!controller.hasClients) return;
    final current = _topIndex;
    if (forward) {
      final target = _nextVisibleBoundary(current);
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

    final top = viewport.localToGlobal(Offset.zero).dy + widget.topInset + 0.5;
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
          final tools = _toolGroups[widget.blocks[blockIndex].id];
          final collapsedGroup = tools != null && tools.length > 1 && _collapsedToolGroups.contains(tools.first.id);
          notifier?.value =
              !collapsedGroup && BlockViewport.headerSticks(height, viewport.size.height)
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
    widget.bottomInset?.removeListener(_onInsetChanged);
    controller.dispose();
    _haptics = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSticky();
    });
    final blocks = widget.blocks;
    final groups = groupBlocksByTurn(blocks, sessionActive: widget.sessionActive);
    _trackReplyMeta(groups);
    final groupEndingByBlockId = <String, TurnGroup>{
      for (final group in groups) group.blocks.last.id: group,
    };
    final pivot = BlockViewport.pivotIndex(blocks, _pivotSeq);
    final header = widget.header;
    _toolGroups = widget.selectionMode || widget.highlights.isNotEmpty
        ? const <String, List<SessionBlock>>{}
        : groupConsecutiveTools(blocks, pivot: pivot);

    final lead = widget.topInset > 0 ? widget.topInset + BlockList.topGap : 0.0;
    return SizedBox.expand(
      key: viewportKey,
      child: LayoutBuilder(
        builder: (context, constraints) => Listener(
          onPointerDown: _onPointerDown,
          child: CustomScrollView(
            controller: controller,
            anchor: constraints.maxHeight > 0 ? (lead / constraints.maxHeight).clamp(0.0, 1.0) : 0,
            center: centerKey,
            slivers: [
              if (widget.topInset > 0) SliverToBoxAdapter(child: SizedBox(height: widget.topInset)),
              if (header != null) SliverToBoxAdapter(child: header),
              const SliverToBoxAdapter(child: SizedBox(height: BlockList.topGap)),
              SliverList.builder(
                key: leadingKey,
                itemCount: pivot,
                itemBuilder: (context, index) {
                  final blockIndex = pivot - 1 - index;
                  final block = blocks[blockIndex];
                  return _toolOrBlock(
                    block,
                    _toolGroups[block.id],
                    groupEndingByBlockId[block.id],
                    _hasFollowingRailItem(blocks, blockIndex),
                  );
                },
              ),
              SliverList.builder(
                key: centerKey,
                itemCount: blocks.length - pivot,
                itemBuilder: (context, index) {
                  final blockIndex = pivot + index;
                  final block = blocks[blockIndex];
                  return _toolOrBlock(
                    block,
                    _toolGroups[block.id],
                    groupEndingByBlockId[block.id],
                    _hasFollowingRailItem(blocks, blockIndex),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: widget.bottomInset == null
                    ? SizedBox(height: widget.bottomGap)
                    : ValueListenableBuilder<double>(
                        valueListenable: widget.bottomInset!,
                        builder: (context, inset, _) => SizedBox(height: inset + widget.bottomGap),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolOrBlock(SessionBlock block, List<SessionBlock>? tools, TurnGroup? group, bool hasFollowingRailItem) {
    if (tools == null) return _blockWithGroupStatus(block, group, hasFollowingRailItem);
    if (tools.length == 1) {
      return Padding(
        key: ValueKey(block.id),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _toolCard(block, group, first: true, last: true),
      );
    }
    final groupId = tools.first.id;
    final expanded = !_collapsedToolGroups.contains(groupId);
    final status = block.id != groupId
        ? BlockStatus.ok
        : tools.any((tool) => tool.status == BlockStatus.failed)
        ? BlockStatus.failed
        : tools.any((tool) => tool.status == BlockStatus.running)
        ? BlockStatus.running
        : BlockStatus.ok;
    return Column(
      key: ValueKey(block.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.id == groupId)
          ToolGroupHeader(
            count: tools.length,
            failedCount: tools.where((tool) => tool.status == BlockStatus.failed).length,
            status: status,
            expanded: expanded,
            onLongPress: widget.onLongPressHeader == null ? null : () => widget.onLongPressHeader!(groupId),
            onTap: () => setState(() {
              if (!_collapsedToolGroups.add(groupId)) _collapsedToolGroups.remove(groupId);
            }),
          ),
        if (expanded)
          _toolCard(block, group, first: block.id == groupId, last: block.id == tools.last.id)
        else if (group != null)
          _blockWithGroupStatus(block, group, false, showCard: false),
      ],
    );
  }

  Widget _toolCard(SessionBlock block, TurnGroup? group, {required bool first, required bool last}) {
    final border = BorderSide(color: context.skin.borderSubtle);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.skin.bgSurface,
        borderRadius: BorderRadius.vertical(
          top: first ? const Radius.circular(10) : Radius.zero,
          bottom: last ? const Radius.circular(10) : Radius.zero,
        ),
        border: Border(left: border, right: border, bottom: border, top: first ? border : BorderSide.none),
      ),
      child: _blockWithGroupStatus(block, group, false, compactTool: true),
    );
  }

  Widget _blockWithGroupStatus(
    SessionBlock block,
    TurnGroup? group,
    bool hasFollowingRailItem, {
    bool compactTool = false,
    bool showCard = true,
  }) {
    final ctx = widget.actionContext;
    final actions = ctx == null ? const <BlockAction>[] : BlockActions.forBlock(block, ctx);
    final card = BlockCard(
      block: block,
      actionsBuilder: widget.actionsBuilder,
      actions: actions,
      onAction: widget.onAction == null
          ? null
          : (action) => widget.onAction!(block, action),
      collapsed: compactTool
          ? !_expandedTools.contains(block.id)
          : widget.collapsedIds.contains(block.id) && !widget.highlights.containsKey(block.id),
      onToggleCollapse: compactTool
          ? () => setState(() {
              if (!_expandedTools.add(block.id)) _expandedTools.remove(block.id);
            })
          : widget.onToggleCollapse == null
          ? null
          : () => widget.onToggleCollapse!(block.id),
      highlight: widget.highlights[block.id],
      activeMatch: widget.activeMatchId == block.id,
      searchMatches: widget.highlights,
      activeMatchId: widget.activeMatchId,
      selected: widget.selectedIds.contains(block.id),
      onToggleSelect: widget.onToggleSelect == null
          ? null
          : (value) => widget.onToggleSelect!(block.id, value),
      selectionMode: widget.selectionMode,
      onLongPressHeader: widget.onLongPressHeader == null
          ? null
          : () => widget.onLongPressHeader!(block.id),
      hasFollowingRailItem: hasFollowingRailItem,
      showReplyMeta: _settledReplies.contains(block.id),
      animateReplyMeta: _settlingReplies.remove(block.id),
    );
    return Column(
      key: ValueKey(block.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCard)
          if (block.kind == BlockKind.assistant)
            IncomingResponse(
              blockId: block.id,
              animate: _pendingResponses.remove(block.id),
              child: card,
            )
          else
            card,
        if (group != null && widget.canRollbackTurn?.call(group) == true)
          TurnGroupStatus(
            group: group,
            onRollback: widget.onRollbackTurn == null || widget.canRollbackTurn == null
                ? null
                : (widget.canRollbackTurn!(group) ? widget.onRollbackTurn : null),
          ),
      ],
    );
  }
}
