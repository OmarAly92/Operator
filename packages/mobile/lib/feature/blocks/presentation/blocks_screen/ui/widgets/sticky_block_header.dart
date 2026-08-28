import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_card.dart';

class StickyBlock extends Equatable {
  const StickyBlock({required this.block, required this.height});

  final SessionBlock block;
  final double height;

  @override
  List<Object?> get props => [
    block.id,
    block.status,
    block.title,
    block.kind,
    height,
  ];
}

class StickyBlockHeader extends StatelessWidget {
  const StickyBlockHeader({super.key, required this.sticky});

  final ValueListenable<StickyBlock?> sticky;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StickyBlock?>(
    valueListenable: sticky,
    builder: (context, value, _) {
      if (value == null) return const SizedBox.shrink();
      final skin = context.skin;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: skin.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          border: Border.all(color: skin.borderSubtle),
        ),
        child: BlockCardHeader(block: value.block),
      );
    },
  );
}
