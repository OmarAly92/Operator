import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

class BlocksBody extends StatefulWidget {
  const BlocksBody({super.key});

  @override
  State<BlocksBody> createState() => _BlocksBodyState();
}

class _BlocksBodyState extends State<BlocksBody> {
  final ValueNotifier<StickyBlock?> _sticky = ValueNotifier<StickyBlock?>(null);

  @override
  void dispose() {
    _sticky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<BlocksCubit, BlocksState>(
      builder: (context, state) {
        final cubit = context.read<BlocksCubit>();

        if (state is BlocksUnsupportedState) {
          return _notice(
            context,
            'Blocks are unavailable for ${state.harness ?? 'this agent'}. Use the raw terminal instead.',
          );
        }

        final error = cubit.error;
        if (error != null && cubit.blocks.isEmpty) {
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
                  onPressed: cubit.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (cubit.blocks.isEmpty) {
          return _notice(
            context,
            cubit.loading
                ? 'Loading blocks...'
                : 'No blocks yet. They appear as the agent works.',
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: BlockList(
                sessionId: cubit.sessionId,
                blocks: cubit.blocks,
                header: _olderControl(context, cubit),
                sticky: _sticky,
              ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: StickyBlockHeader(sticky: _sticky),
            ),
          ],
        );
      },
    );
  }

  Widget? _olderControl(BuildContext context, BlocksCubit cubit) {
    if (cubit.loadingOlder) {
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
    if (!cubit.hasOlder) return null;
    return Center(
      child: TextButton(
        onPressed: cubit.loadOlder,
        child: const Text('Load older blocks'),
      ),
    );
  }

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
