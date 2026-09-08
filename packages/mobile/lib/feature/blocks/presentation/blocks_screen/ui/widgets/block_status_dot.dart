import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

Color blockStatusColor(AppSkin skin, BlockStatus status) => switch (status) {
  BlockStatus.running => skin.blue,
  BlockStatus.ok => skin.green,
  BlockStatus.failed => skin.red,
  BlockStatus.blocked => skin.amber,
};

class BlockStatusDot extends StatelessWidget {
  const BlockStatusDot({super.key, required this.status, this.overrideColor, this.size = 6});

  final BlockStatus status;

  /// A fixed rail-node color for kinds whose dot color is dictated by kind
  /// rather than by [status] (reasoning, plan, permission, MCP tool calls —
  /// see `docs/design/session_detail/session_detail.md`). Null keeps the
  /// existing [blockStatusColor] status→color vocabulary.
  final Color? overrideColor;

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: overrideColor ?? blockStatusColor(context.skin, status),
      shape: BoxShape.circle,
    ),
  );
}
