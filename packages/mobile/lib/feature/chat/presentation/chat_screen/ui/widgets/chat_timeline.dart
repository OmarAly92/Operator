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
    final target = widget.jumpToSequence;
    if (target != null && target != oldWidget.jumpToSequence) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
      return;
    }
    if (_followsTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTail());
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
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: groups.length + 1,
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
      key: anchor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in activityRuns(group.items))
            switch (row) {
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
          if (group.turn != null)
            TurnSummary(
              turn: group.turn!,
              onRollback: canRollbackTurn(widget.snapshot, group.turn!)
                  ? widget.onRollback
                  : null,
            ),
        ],
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
