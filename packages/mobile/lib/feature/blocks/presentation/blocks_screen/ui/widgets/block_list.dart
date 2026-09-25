import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/streaming_haptics.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/block_viewport.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/tool_grouping.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_fold.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/incoming_response.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/thinking_row.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/tool_group_header.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_fold_row.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/turn_group_status.dart';

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
    this.trailing,
    this.trailingShown = false,
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
  final Widget? trailing;
  final bool trailingShown;

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
  final Set<String> _expandedTurns = {};
  Map<String, TurnFold> _foldOfBlock = {};
  Map<String, TurnFold> _foldAnchors = {};
  bool _thinking = false;
  Duration? _followUntil;
  Duration? _revealUntil;
  final Map<String, Duration> _foldMotion = {};
  final Set<String> _opening = {};
  List<int> _leadingItems = const [];
  List<int> _centerItems = const [];
  Map<String, int> _leadingSlots = const {};
  Map<String, int> _centerSlots = const {};
  bool _motionSweepScheduled = false;
  bool _built = false;

  int? _pivotSeq;
  int? _groupPivotSeq;
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
    _syncFolds();
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
      _expandedTurns.clear();
      _foldMotion.clear();
      _opening.clear();
      _pendingResponses.clear();
      _unsettledReplies = {};
      _settlingReplies = {};
      _pivotSeq = null;
      _groupPivotSeq = null;
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
    final revealed = _revealActiveMatch(oldWidget);
    final reshaped = _syncFolds();
    if (revealed) {
      _holdDuringDisclosure();
    } else if (reshaped) {
      _holdDuringDisclosure(anchorId: _readingAnchor());
    } else if (!setEquals(widget.collapsedIds, oldWidget.collapsedIds)) {
      _holdDuringDisclosure(anchorId: _changedCollapse(oldWidget));
    }
    if (widget.trailingShown != oldWidget.trailingShown) _holdDuringDisclosure();
    if (_pinned && !_seeking) _scheduleFollow();
  }

  String? _readingAnchor() {
    final top = _topIndex;
    if (top == null || top >= widget.blocks.length) return null;
    final block = widget.blocks[top];
    if (!_folded(block.id)) return block.id;
    for (var index = top + 1; index < widget.blocks.length; index++) {
      final next = widget.blocks[index];
      if (_folded(next.id)) continue;
      if (_renderedBlock(index) != null) return next.id;
      break;
    }
    final fold = _foldOfBlock[block.id];
    return fold?.anchorId;
  }

  String? _changedCollapse(BlockList oldWidget) {
    for (final id in widget.collapsedIds.difference(oldWidget.collapsedIds)) {
      return id;
    }
    for (final id in oldWidget.collapsedIds.difference(widget.collapsedIds)) {
      return id;
    }
    return null;
  }

  bool _revealActiveMatch(BlockList oldWidget) {
    final id = widget.activeMatchId;
    if (id == null || id == oldWidget.activeMatchId || widget.selectionMode) return false;
    final groups = groupBlocksByTurn(widget.blocks, sessionActive: widget.sessionActive);
    for (final fold in turnFolds(groups)) {
      if (fold.hiddenIds.contains(id) && _expandedTurns.add(fold.id)) {
        _startOpening(fold.id);
        _revealUntil = _now + AppMotion.disclosure + _settleSlack;
        return true;
      }
    }
    return false;
  }

  bool _syncFolds() {
    final groups = groupBlocksByTurn(widget.blocks, sessionActive: widget.sessionActive);
    final folds = widget.selectionMode ? const <TurnFold>[] : turnFolds(groups);
    final thinking = widget.sessionActive && !widget.selectionMode && showsThinking(groups);
    final foldOfBlock = <String, TurnFold>{
      for (final fold in folds)
        for (final id in fold.hiddenIds) id: fold,
    };
    final changed = thinking != _thinking || !setEquals(foldOfBlock.keys.toSet(), _foldOfBlock.keys.toSet());
    final previous = {for (final fold in _foldOfBlock.values) fold.id};
    final settling = [
      for (final fold in folds)
        if (_built && !previous.contains(fold.id) && !_expandedTurns.contains(fold.id)) fold.id,
    ];
    _thinking = thinking;
    _foldOfBlock = foldOfBlock;
    _foldAnchors = {for (final fold in folds) fold.anchorId: fold};
    _pendingResponses.removeWhere(_folded);
    for (final id in settling) {
      _foldMotion[id] = _now + AppMotion.disclosure + _settleSlack;
    }
    if (settling.isNotEmpty) _scheduleMotionSweep();
    return changed;
  }

  void _startOpening(String foldId) {
    _opening.add(foldId);
    _foldMotion[foldId] = _now + AppMotion.disclosure + _settleSlack;
    _scheduleMotionSweep();
  }

  void _scheduleMotionSweep() {
    if (_motionSweepScheduled) return;
    _motionSweepScheduled = true;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _motionSweepScheduled = false;
      if (!mounted) return;
      final now = _now;
      final expired = [
        for (final entry in _foldMotion.entries)
          if (now >= entry.value) entry.key,
      ];
      if (expired.isNotEmpty) {
        setState(() {
          expired.forEach(_foldMotion.remove);
          _opening.removeAll(expired);
        });
      }
      if (_foldMotion.isNotEmpty) _scheduleMotionSweep();
    });
  }

  bool _shown(String blockId) {
    final fold = _foldOfBlock[blockId];
    if (fold == null || !_folded(blockId)) return true;
    return fold.anchorId == blockId || _foldMotion.containsKey(fold.id);
  }

  bool _folded(String blockId) {
    final fold = _foldOfBlock[blockId];
    return fold != null && !_expandedTurns.contains(fold.id);
  }

  List<bool> _followingRail(List<SessionBlock> blocks) {
    final following = List<bool>.filled(blocks.length, false);
    bool? nextIsRail;
    for (var index = blocks.length - 1; index >= 0; index--) {
      final rail = isRailBlock(blocks[index]);
      following[index] = rail && nextIsRail == true;
      if (!_folded(blocks[index].id)) nextIsRail = rail;
    }
    return following;
  }

  static const Duration _settleSlack = Duration(milliseconds: 48);

  Duration get _now => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  void _toggleTurn(TurnFold fold) {
    _holdDuringDisclosure(anchorId: fold.anchorId);
    setState(() {
      if (_expandedTurns.add(fold.id)) {
        _startOpening(fold.id);
      } else {
        _expandedTurns.remove(fold.id);
        _opening.remove(fold.id);
        _foldMotion[fold.id] = _now + AppMotion.disclosure + _settleSlack;
        _scheduleMotionSweep();
      }
    });
  }

  void _holdDuringDisclosure({String? anchorId}) {
    if (_pinned || _seeking) {
      _followUntil = _now + AppMotion.disclosure + _settleSlack;
      if (!_seeking) _scheduleFollow();
      return;
    }
    if (anchorId != null) _repivotAt(anchorId);
  }

  void _repivotAt(String blockId) {
    if (!controller.hasClients || controller.position.isScrollingNotifier.value) return;
    final index = widget.blocks.indexWhere((block) => block.id == blockId);
    final viewport = viewportKey.currentContext?.findRenderObject();
    final delta = index < 0 ? null : _viewportTopDelta(index);
    if (delta == null || viewport is! RenderBox || !viewport.hasSize) return;
    final lead = widget.topInset > 0 ? widget.topInset + BlockList.topGap : 0.0;
    final anchor = viewport.size.height > 0 ? (lead / viewport.size.height).clamp(0.0, 1.0) * viewport.size.height : 0.0;
    _pivotSeq = widget.blocks[index].firstSeq;
    controller.position.correctPixels(anchor - delta - widget.topInset);
  }

  bool _isFresh(SessionBlock block) {
    final raw = block.createdAt;
    if (raw == null) return true;
    final created = DateTime.tryParse(raw);
    if (created == null) return true;
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
    if (!TickerMode.valuesOf(context).enabled) return;
    final latest = _latestAssistant(widget.blocks);
    if (latest == null) return;
    final previous = _latestAssistant(previousBlocks);
    if (previous == null || previous.id != latest.id) {
      final live = latest.status == BlockStatus.running || _isFresh(latest);
      if (live && latest.firstSeq > previousBlocks.last.firstSeq) haptics.onStreamStart();
      return;
    }
    if (latest.body.length > previous.body.length) haptics.onTextGrew();
  }

  void _trackReplyMeta(List<TurnGroup> groups) {
    final settled = <String>{};
    final unsettled = <String>{};
    if (!widget.selectionMode) {
      for (final group in groups) {
        final reply = finalReplyOf(group.blocks);
        if (reply == null) continue;
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
    _groupPivotSeq = _pivotSeq;
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
    _followUntil = null;
    _revealUntil = null;
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

  int _blockAt(GlobalKey key, int sliverIndex) {
    final items = key == leadingKey ? _leadingItems : _centerItems;
    return sliverIndex >= 0 && sliverIndex < items.length ? items[sliverIndex] : -1;
  }

  RenderBox? _renderedBlock(int index) {
    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final blockIndex = _blockAt(key, sliver.indexOf(child));
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
    final id = widget.blocks[index].id;
    _alignBlock(index);
    final until = _revealUntil;
    if (until == null) return;
    if (_now >= until) {
      _revealUntil = null;
      return;
    }
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = widget.blocks.indexWhere((block) => block.id == id);
      if (next >= 0) scrollBlockIntoView(next);
    });
  }

  void _alignBlock(int index) {
    final fold = _foldOfBlock[widget.blocks[index].id];
    if (fold != null && _folded(fold.anchorId)) {
      if (_expandedTurns.add(fold.id)) {
        _startOpening(fold.id);
        _revealUntil = _now + AppMotion.disclosure + _settleSlack;
        setState(() {});
      }
      index = widget.blocks.indexWhere((block) => block.id == fold.anchorId);
    }
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
    var boundary = tools != null && tools.length > 1 && _collapsedToolGroups.contains(tools.first.id)
        ? widget.blocks.indexWhere((block) => block.id == tools.last.id)
        : index;
    final fold = boundary == null ? null : _foldOfBlock[widget.blocks[boundary].id];
    if (fold != null && _folded(fold.anchorId)) {
      boundary = widget.blocks.indexWhere((block) => block.id == fold.hiddenIds.last);
    }
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

    for (final key in [leadingKey, centerKey]) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) continue;
      RenderBox? child = sliver.firstChild;
      while (child != null) {
        final childTop = child.localToGlobal(Offset.zero).dy;
        final height = child.size.height;
        if (childTop <= top && childTop + height > top) {
          final blockIndex = _blockAt(key, sliver.indexOf(child));
          if (blockIndex < 0 || blockIndex >= widget.blocks.length) {
            _topIndex = null;
            notifier?.value = null;
            return;
          }
          _topIndex = blockIndex;
          final tools = _toolGroups[widget.blocks[blockIndex].id];
          final collapsedGroup = tools != null && tools.length > 1 && _collapsedToolGroups.contains(tools.first.id);
          notifier?.value =
              !collapsedGroup && !_folded(widget.blocks[blockIndex].id) && BlockViewport.headerSticks(height, viewport.size.height)
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
      final until = _followUntil;
      final holding = until != null && _now < until;
      if (!holding) _followUntil = null;
      if (!mounted ||
          !controller.hasClients ||
          !_pinned ||
          (!holding && _followHops >= kMaxFollowHops)) {
        _followScheduled = false;
        return;
      }
      final extent = controller.position.maxScrollExtent;
      if ((controller.position.pixels - extent).abs() < 0.5) {
        if (!holding) {
          _followScheduled = false;
          return;
        }
        WidgetsBinding.instance.scheduleFrame();
        _followStep();
        return;
      }
      if (holding) {
        WidgetsBinding.instance.scheduleFrame();
      } else {
        _followHops++;
      }
      controller.jumpTo(extent);
      _followStep();
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onScroll);
    widget.bottomInset?.removeListener(_onInsetChanged);
    controller.dispose();
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
        : groupConsecutiveTools(blocks, pivot: BlockViewport.pivotIndex(blocks, _groupPivotSeq));
    _built = true;
    final followingRail = _followingRail(blocks);
    _leadingItems = [
      for (var index = pivot - 1; index >= 0; index--)
        if (_shown(blocks[index].id)) index,
    ];
    _centerItems = [
      for (var index = pivot; index < blocks.length; index++)
        if (_shown(blocks[index].id)) index,
    ];
    _leadingSlots = {for (var slot = 0; slot < _leadingItems.length; slot++) 'slot-${blocks[_leadingItems[slot]].id}': slot};
    _centerSlots = {for (var slot = 0; slot < _centerItems.length; slot++) 'slot-${blocks[_centerItems[slot]].id}': slot};
    final leadingItems = _leadingItems;
    final centerItems = _centerItems;
    final leadingSlots = _leadingSlots;
    final centerSlots = _centerSlots;
    Widget itemAt(int blockIndex) {
      final block = blocks[blockIndex];
      return KeyedSubtree(
        key: ValueKey<String>('slot-${block.id}'),
        child: _item(block, _toolGroups[block.id], groupEndingByBlockId[block.id], followingRail[blockIndex]),
      );
    }

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
                itemCount: leadingItems.length,
                findChildIndexCallback: (key) => key is ValueKey<String> ? leadingSlots[key.value] : null,
                itemBuilder: (context, index) => itemAt(leadingItems[index]),
              ),
              SliverList.builder(
                key: centerKey,
                itemCount: centerItems.length,
                findChildIndexCallback: (key) => key is ValueKey<String> ? centerSlots[key.value] : null,
                itemBuilder: (context, index) => itemAt(centerItems[index]),
              ),
              SliverToBoxAdapter(
                child: Disclosure(expanded: _thinking, child: const ThinkingRow()),
              ),
              SliverToBoxAdapter(
                child: Disclosure(
                  expanded: widget.trailingShown && widget.trailing != null,
                  child: widget.trailing ?? const SizedBox.shrink(),
                ),
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

  Widget _item(SessionBlock block, List<SessionBlock>? tools, TurnGroup? group, bool hasFollowingRailItem) {
    final content = _toolOrBlock(block, tools, hasFollowingRailItem);
    final status = group != null && widget.canRollbackTurn?.call(group) == true ? _turnStatus(group) : null;
    if (!foldableInTurn(block)) {
      if (status == null) return content;
      return Column(
        key: ValueKey('item-${block.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [content, status],
      );
    }
    final fold = _foldAnchors[block.id];
    return Column(
      key: ValueKey('item-${block.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Disclosure(
          expanded: fold != null,
          child: fold == null
              ? const SizedBox.shrink()
              : TurnFoldRow(
                  key: ValueKey('turn-fold-${fold.id}'),
                  label: fold.label,
                  expanded: _expandedTurns.contains(fold.id),
                  onTap: () => _toggleTurn(fold),
                ),
        ),
        Disclosure(
          expanded: !_folded(block.id),
          initiallyExpanded: _opening.contains(_foldOfBlock[block.id]?.id) ? false : null,
          child: content,
        ),
        ?status,
      ],
    );
  }

  Widget _toolOrBlock(SessionBlock block, List<SessionBlock>? tools, bool hasFollowingRailItem) {
    if (tools == null) return _blockCard(block, hasFollowingRailItem);
    if (tools.length == 1) {
      return Padding(
        key: ValueKey(block.id),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _toolCard(block, first: true, last: true),
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
            onTap: () {
              setState(() {
                if (!_collapsedToolGroups.add(groupId)) _collapsedToolGroups.remove(groupId);
              });
              _holdDuringDisclosure(anchorId: groupId);
            },
          ),
        Disclosure(
          expanded: expanded,
          child: _toolCard(block, first: block.id == groupId, last: block.id == tools.last.id),
        ),
      ],
    );
  }

  Widget _toolCard(SessionBlock block, {required bool first, required bool last}) {
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
      child: _blockCard(block, false, compactTool: true),
    );
  }

  Widget _turnStatus(TurnGroup group) => TurnGroupStatus(
    group: group,
    onRollback: widget.onRollbackTurn == null || widget.canRollbackTurn == null
        ? null
        : (widget.canRollbackTurn!(group) ? widget.onRollbackTurn : null),
  );

  Widget _blockCard(SessionBlock block, bool hasFollowingRailItem, {bool compactTool = false}) {
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
          ? () {
              setState(() {
                if (!_expandedTools.add(block.id)) _expandedTools.remove(block.id);
              });
              _holdDuringDisclosure(anchorId: block.id);
            }
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
    if (block.kind != BlockKind.assistant) return KeyedSubtree(key: ValueKey(block.id), child: card);
    return IncomingResponse(
      key: ValueKey(block.id),
      blockId: block.id,
      animate: _pendingResponses.remove(block.id),
      child: card,
    );
  }
}
