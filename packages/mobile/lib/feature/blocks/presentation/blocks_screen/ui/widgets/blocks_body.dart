import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class BlocksBody extends StatefulWidget {
  const BlocksBody({super.key});

  @override
  State<BlocksBody> createState() => _BlocksBodyState();
}

class _BlocksBodyState extends State<BlocksBody> {
  final ScrollController _controller = ScrollController();

  bool get _pinned {
    if (!_controller.hasClients) return true;
    return _controller.position.pixels >= _controller.position.maxScrollExtent - 24;
  }

  void _followTail() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _controller.dispose();
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
                  style: AppTextStyle.style12Regular.copyWith(color: skin.attention),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: cubit.refresh, child: const Text('Retry')),
              ],
            ),
          );
        }

        if (cubit.blocks.isEmpty) {
          return _notice(
            context,
            cubit.loading ? 'Loading blocks...' : 'No blocks yet. They appear as the agent works.',
          );
        }

        final pinned = _pinned;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pinned && mounted) _followTail();
        });

        final header = cubit.loadingOlder || cubit.hasOlder;

        return ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: cubit.blocks.length + (header ? 1 : 0),
          itemBuilder: (context, index) {
            if (header && index == 0) {
              if (cubit.loadingOlder) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AppText(
                    'Loading older blocks...',
                    style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Center(
                child: TextButton(
                  onPressed: cubit.loadOlder,
                  child: const Text('Load older blocks'),
                ),
              );
            }
            final block = cubit.blocks[index - (header ? 1 : 0)];
            return BlockCard(key: ValueKey(block.id), block: block);
          },
        );
      },
    );
  }

  Widget _notice(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(color: context.skin.textTertiary),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
