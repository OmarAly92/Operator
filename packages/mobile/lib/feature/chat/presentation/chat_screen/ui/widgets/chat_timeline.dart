import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart';

class ChatTimeline extends StatefulWidget {
  const ChatTimeline({
    super.key,
    required this.snapshot,
    required this.loadingOlder,
    required this.onLoadOlder,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
    required this.onRollback,
    this.jumpToSequence,
    this.onJumpHandled,
  });

  final ConversationSnapshotModel snapshot;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(
    String requestId,
    String action, [
    Map<String, dynamic>? content,
  ])
  onResolveInput;
  final Future<int> Function(String turnId) onRollback;
  final int? jumpToSequence;
  final VoidCallback? onJumpHandled;

  @override
  State<ChatTimeline> createState() => _ChatTimelineState();
}

class _ChatTimelineState extends State<ChatTimeline> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final Map<String, GlobalKey> _anchors = {};
  bool _followsTail = true;
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    if (widget.jumpToSequence != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpTo(widget.jumpToSequence!),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTail());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibleAnchor = _followsTail
        ? null
        : _prependedVisibleAnchor(oldWidget.snapshot);
    final target = widget.jumpToSequence;
    if (target != null && target != oldWidget.jumpToSequence) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
      return;
    }
    if (_followsTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTail());
    } else if (visibleAnchor != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreVisibleAnchor(visibleAnchor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final items = readableConversationItems(widget.snapshot);
    final groups = groupConversationByTurn(widget.snapshot, items);

    if (groups.isEmpty) return _emptyConversation(context);

    return Stack(
      children: [
        Container(
          color: skin.bgBase,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onScrollMetrics,
            child: ListView.builder(
              key: _listKey,
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: groups.length + 1,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final index = groups.indexWhere(
                  (group) => group.key == key.value,
                );
                return index < 0 ? null : index + 1;
              },
              itemBuilder: (context, index) {
                if (index == 0) return _historyHeader(context);
                return _conversationGroup(groups[index - 1]);
              },
            ),
          ),
        ),
        if (_showJump) _LatestButton(onPressed: _followLatest),
      ],
    );
  }

  Widget _emptyConversation(BuildContext context) {
    final skin = context.skin;
    return Container(
      color: skin.bgBase,
      child: Column(
        children: [
          if (widget.snapshot.hasMoreBefore) _historyHeader(context),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: skin.tintBlue,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: skin.blue,
                      ),
                    ),
                    const VerticalSpace(12),
                    AppText(
                      widget.snapshot.controllerState == 'connecting'
                          ? 'Connecting to the agent…'
                          : 'Start the conversation',
                      style: AppTextStyle.style17SemiBold,
                      maxLines: 2,
                    ),
                    const VerticalSpace(6),
                    AppText(
                      'This ${widget.snapshot.harness ?? 'agent'} session works in its own Operator worktree. '
                      'Ask it to inspect, change, test, or explain anything there.',
                      style: AppTextStyle.style13Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyHeader(BuildContext context) {
    final skin = context.skin;
    if (widget.snapshot.hasMoreBefore) {
      return Center(
        child: TextButton(
          onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
          child: AppText(
            widget.loadingOlder ? 'Loading history…' : 'Load earlier messages',
            style: AppTextStyle.style12Regular.copyWith(
              color: skin.textTertiary,
            ),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppText(
          'BEGINNING OF CONVERSATION',
          style: AppTextStyle.style10Regular.copyWith(
            color: skin.textFaint,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _conversationGroup(ConversationGroup group) {
    final anchor = _anchors.putIfAbsent(group.key, GlobalKey.new);
    return KeyedSubtree(
      key: ValueKey(group.key),
      child: KeyedSubtree(
        key: anchor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in activityRuns(group.items))
              KeyedSubtree(
                key: ValueKey(row.key),
                child: switch (row) {
                  ActivitiesRow(:final activities) => ActivityRunWidget(
                    activities: activities,
                  ),
                  SingleRow(:final item) => TimelineItem(
                    item: item,
                    approvalPending: widget.approvalPending,
                    inputPending: widget.inputPending,
                    onDecide: widget.onDecide,
                    onResolveInput: widget.onResolveInput,
                  ),
                },
              ),
            if (group.turn != null)
              TurnSummary(
                turn: group.turn!,
                onRollback: canRollbackTurn(widget.snapshot, group.turn!)
                    ? widget.onRollback
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final follows = _controller.position.extentAfter < 120;
    if (follows == _followsTail) return;
    setState(() {
      _followsTail = follows;
      _showJump = !follows;
    });
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (_followsTail && notification.metrics.extentAfter > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTail());
    }
    return false;
  }

  _VisibleAnchor? _prependedVisibleAnchor(
    ConversationSnapshotModel oldSnapshot,
  ) {
    final anchor = _captureVisibleAnchor(oldSnapshot);
    if (anchor == null) return null;
    final oldGroups = groupConversationByTurn(oldSnapshot);
    final newGroups = groupConversationByTurn(widget.snapshot);
    final oldIndex = oldGroups.indexWhere((group) => group.key == anchor.key);
    final newIndex = newGroups.indexWhere((group) => group.key == anchor.key);
    return newIndex > oldIndex ? anchor : null;
  }

  _VisibleAnchor? _captureVisibleAnchor(ConversationSnapshotModel snapshot) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return null;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final listBottom = listTop + listBox.size.height;
    for (final group in groupConversationByTurn(snapshot)) {
      final box = _anchors[group.key]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > listTop && top < listBottom) {
        return _VisibleAnchor(
          group.key,
          top - listTop,
          _controller.position.pixels,
          _controller.position.maxScrollExtent,
        );
      }
    }
    return null;
  }

  void _restoreVisibleAnchor(_VisibleAnchor anchor) {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final estimatedOffset =
        anchor.offset + position.maxScrollExtent - anchor.maxScrollExtent;
    _controller.jumpTo(
      estimatedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _alignVisibleAnchor(anchor),
    );
  }

  void _alignVisibleAnchor(_VisibleAnchor anchor) {
    if (!mounted || !_controller.hasClients) return;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorBox = _anchors[anchor.key]?.currentContext?.findRenderObject();
    if (listBox == null || anchorBox is! RenderBox || !anchorBox.attached) {
      return;
    }
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final currentTop = anchorBox.localToGlobal(Offset.zero).dy - listTop;
    final position = _controller.position;
    final offset = (position.pixels + currentTop - anchor.top).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.jumpTo(offset.toDouble());
  }

  void _jumpTo(int sequence, [int attempt = 0]) {
    if (!mounted) return;
    final groups = groupConversationByTurn(widget.snapshot);
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      if (group.anchor != sequence) continue;
      final followsTail = index == groups.length - 1;
      if (attempt == 0 && followsTail != _followsTail) {
        setState(() {
          _followsTail = followsTail;
          _showJump = !followsTail;
        });
      }
      final anchor = _anchors[group.key]?.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 250),
          alignment: 0.18,
        );
        widget.onJumpHandled?.call();
        return;
      }
      if (_controller.hasClients && attempt < 4) {
        final fraction = index / (groups.length - 1).clamp(1, groups.length);
        final offset = _controller.position.maxScrollExtent * fraction;
        _controller.jumpTo(offset);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpTo(sequence, attempt + 1),
        );
        return;
      }
      widget.onJumpHandled?.call();
      return;
    }
    widget.onJumpHandled?.call();
  }

  void _followLatest() {
    setState(() {
      _followsTail = true;
      _showJump = false;
    });
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _jumpToTail() {
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }
}

final class _VisibleAnchor {
  const _VisibleAnchor(this.key, this.top, this.offset, this.maxScrollExtent);

  final String key;
  final double top;
  final double offset;
  final double maxScrollExtent;
}

class _LatestButton extends StatelessWidget {
  const _LatestButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Positioned(
      right: 14,
      bottom: 12,
      child: Material(
        color: skin.bgElevated,
        shape: StadiumBorder(side: BorderSide(color: skin.borderStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward, size: 14, color: skin.textPrimary),
                const HorizontalSpace(6),
                AppText('Latest', style: AppTextStyle.style11Bold),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
