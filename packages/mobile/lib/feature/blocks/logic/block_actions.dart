import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

enum BlockActionKind { copyBlock, copyCommand, copyOutput, rerun, rewind }

class BlockActionContext extends Equatable {
  const BlockActionContext({
    required this.mode,
    this.capabilities = const [],
    this.canSend = false,
    this.turnInFlight = false,
    this.rollbackableTurnIds = const [],
  });

  final String mode;
  final List<String> capabilities;
  final bool canSend;
  final bool turnInFlight;
  final List<String> rollbackableTurnIds;

  @override
  List<Object?> get props => [mode, capabilities, canSend, turnInFlight, rollbackableTurnIds];
}

class BlockAction extends Equatable {
  const BlockAction({required this.kind, this.payload, this.turnId});

  final BlockActionKind kind;
  final String? payload;
  final String? turnId;

  @override
  List<Object?> get props => [kind, payload, turnId];
}

sealed class BlockActions {
  static List<BlockAction> forBlock(SessionBlock block, BlockActionContext ctx) {
    final actions = <BlockAction>[BlockAction(kind: BlockActionKind.copyBlock, payload: copyText(block))];
    final detail = block.detail;
    if (detail is ShellBlockDetail && detail.command != null && detail.command!.isNotEmpty) {
      actions.add(BlockAction(kind: BlockActionKind.copyCommand, payload: detail.command));
    }
    if (detail is ShellBlockDetail && detail.output != null && detail.output!.isNotEmpty) {
      actions.add(BlockAction(kind: BlockActionKind.copyOutput, payload: detail.output));
    } else if (block.kind == BlockKind.tool && block.body.isNotEmpty) {
      actions.add(BlockAction(kind: BlockActionKind.copyOutput, payload: block.body));
    }
    if (ctx.canSend && block.kind == BlockKind.prompt && block.body.isNotEmpty && !ctx.turnInFlight) {
      actions.add(BlockAction(kind: BlockActionKind.rerun, payload: block.body));
    }
    if (ctx.mode == 'chat' &&
        ctx.capabilities.contains('rollback') &&
        !ctx.turnInFlight &&
        block.turnId != null &&
        block.turnId!.isNotEmpty &&
        ctx.rollbackableTurnIds.contains(block.turnId)) {
      actions.add(BlockAction(kind: BlockActionKind.rewind, turnId: block.turnId));
    }
    return actions;
  }

  static String copyText(SessionBlock block) {
    final display = blockDisplay(block);
    final rendered = [display.displayName, display.summary, display.errorText]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join('\n')
        .trimRight();
    final children = block.children ?? const <SessionBlock>[];
    if (children.isEmpty) return rendered;
    return [
      rendered,
      ...children.map((child) => copyText(child).split('\n').map((line) => '  $line').join('\n')),
    ].join('\n\n');
  }

  static String blocksToText(List<SessionBlock> blocks) => blocks.map(copyText).join('\n\n');
}
