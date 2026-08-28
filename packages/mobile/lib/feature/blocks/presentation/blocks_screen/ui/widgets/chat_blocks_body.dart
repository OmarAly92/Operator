import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';

class ChatBlocksBody extends StatefulWidget {
  const ChatBlocksBody({
    super.key,
    required this.sessionId,
    required this.repository,
  });

  final String sessionId;
  final ChatRepository repository;

  @override
  State<ChatBlocksBody> createState() => _ChatBlocksBodyState();
}

class _ChatBlocksBodyState extends State<ChatBlocksBody> {
  final GlobalKey<BlockListState> _listKey = GlobalKey<BlockListState>();
  final ValueNotifier<bool> _pinned = ValueNotifier<bool>(true);
  final ValueNotifier<StickyBlock?> _sticky = ValueNotifier<StickyBlock?>(null);

  @override
  void dispose() {
    _sticky.dispose();
    _pinned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<ConversationBlocksCubit, ConversationBlocksState>(
      builder: (context, state) {
        final cubit = context.read<ConversationBlocksCubit>();
        final unavailable = state.unavailable;
        final snapshot = cubit.snapshot;

        if (state is ConversationBlocksUnsupportedState) {
          return _unavailable(context, unavailable!.message);
        }

        if (state is ConversationBlocksReadyState) {
          final error = state.error;
          if (error != null && state.blocks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    error,
                    style: AppTextStyle.style12Regular.copyWith(
                      color: skin.attention,
                    ),
                    maxLines: 3,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => cubit.refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (unavailable != null) {
            return _unavailable(context, unavailable.message);
          }

          if (state.blocks.isEmpty) {
            return _notice(
              context,
              state.isLoading
                  ? 'Loading blocks...'
                  : 'No blocks yet. They appear as the agent works.',
            );
          }

          final permissionKinds = _permissionKinds(snapshot?.items);
          final capabilities = snapshot?.capabilities ?? const <String>[];
          final hasInFlightTurn = snapshot?.turns.any(
                (turn) =>
                    turn.state == 'running' || turn.state == 'queued',
              ) ??
              false;
          final canApprove = capabilities.contains('approve');
          final canElicit = capabilities.contains('elicitation');
          final canRollback = capabilities.contains('rollback');

          void onApprove(String requestId, String decisionId) {
            if (!canApprove) return;
            unawaited(
              widget.repository.resolveApproval(
                widget.sessionId,
                ResolveApprovalParams(requestId: requestId, decisionId: decisionId),
              ),
            );
          }

          void onDecline(String requestId, String decisionId) {
            if (!canApprove) return;
            unawaited(
              widget.repository.resolveApproval(
                widget.sessionId,
                ResolveApprovalParams(requestId: requestId, decisionId: decisionId),
              ),
            );
          }

          void onAnswer(String requestId) {
            if (!canElicit) return;
            unawaited(
              widget.repository.resolveInput(
                widget.sessionId,
                ResolveInputParams(requestId: requestId, action: 'accept'),
              ),
            );
          }

          void onRollbackTurn(String turnId) {
            if (!canRollback) return;
            if (snapshot == null) return;
            final turn = snapshot.turns.firstWhere(
              (turn) => turn.id == turnId,
              orElse: () => const ConversationTurnModel(id: ''),
            );
            if (turn.id == null || turn.id!.isEmpty) return;
            if (turn.state == 'running' || turn.state == 'queued') return;
            if (turn.rolledBack == true) return;
            if (turn.providerTurnId == null || turn.providerTurnId!.isEmpty) return;
            unawaited(
              widget.repository.rollbackTurn(
                widget.sessionId,
                RollbackTurnParams(turnId: turnId),
              ),
            );
          }

          bool canRollbackTurnGroup(TurnGroup group) {
            if (!canRollback) return false;
            if (hasInFlightTurn) return false;
            if (group.turnId == null) return false;
            if (snapshot == null) return false;
            final turn = snapshot.turns.firstWhere(
              (turn) => turn.id == group.turnId,
              orElse: () => const ConversationTurnModel(id: ''),
            );
            if (turn.id == null || turn.id!.isEmpty) return false;
            if (turn.state == 'running' || turn.state == 'queued') return false;
            if (turn.rolledBack == true) return false;
            if (turn.providerTurnId == null || turn.providerTurnId!.isEmpty) return false;
            return true;
          }

          return Stack(
            children: [
              Positioned.fill(
                child: BlockList(
                  key: _listKey,
                  sessionId: widget.sessionId,
                  blocks: state.blocks,
                  header: _olderControl(context, state),
                  sticky: _sticky,
                  pinnedListenable: _pinned,
                  permissionKinds: permissionKinds,
                  onApprove: canApprove ? onApprove : null,
                  onDecline: canApprove ? onDecline : null,
                  onAnswer: canElicit ? onAnswer : null,
                  onRollbackTurn: canRollback ? onRollbackTurn : null,
                  canRollbackTurn: canRollback ? canRollbackTurnGroup : null,
                ),
              ),
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: StickyBlockHeader(sticky: _sticky),
                ),
              ),
            ],
          );
        }

        return _notice(context, 'Loading blocks...');
      },
    );
  }

  Map<String, BlockPermissionKind>? _permissionKinds(List<ConversationItemModel>? items) {
    if (items == null || items.isEmpty) return null;
    final map = <String, BlockPermissionKind>{};
    for (final item in items) {
      if (item is! ConversationActivityModel) continue;
      if (item.id == null) continue;
      if (item.activityKind == 'approval') {
        map[item.id!] = BlockPermissionKind.approval;
      } else if (item.activityKind == 'user_input') {
        map[item.id!] = BlockPermissionKind.userInput;
      }
    }
    return map.isEmpty ? null : map;
  }

  Widget? _olderControl(BuildContext context, ConversationBlocksReadyState state) {
    if (state.isLoadingOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AppText(
          'Loading older blocks...',
          style: AppTextStyle.style11Regular.copyWith(
            color: context.skin.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!state.hasOlder) return null;
    final cubit = context.read<ConversationBlocksCubit>();
    return Center(
      child: TextButton(
        onPressed: cubit.loadOlder,
        child: const Text('Load older blocks'),
      ),
    );
  }

  Widget _unavailable(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(
          color: context.skin.textTertiary,
        ),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _notice(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(
          color: context.skin.textTertiary,
        ),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
