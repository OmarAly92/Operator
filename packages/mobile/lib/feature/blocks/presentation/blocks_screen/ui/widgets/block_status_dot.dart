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
  const BlockStatusDot({super.key, required this.status});

  final BlockStatus status;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: blockStatusColor(context.skin, status),
      shape: BoxShape.circle,
    ),
  );
}
