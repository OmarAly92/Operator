import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

class ChatBlocksBody extends StatefulWidget {
  const ChatBlocksBody({super.key, required this.sessionId});

  final String sessionId;

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
