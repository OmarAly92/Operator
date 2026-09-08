import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

class BlockNavControls extends StatelessWidget {
  const BlockNavControls({
    super.key,
    required this.onLatest,
    required this.showLatest,
  });

  final VoidCallback onLatest;
  final bool showLatest;

  @override
  Widget build(BuildContext context) {
    if (!showLatest) return const SizedBox.shrink();
    final skin = context.skin;
    return Semantics(
      button: true,
      label: 'Jump to latest',
      child: Tooltip(
        message: 'Jump to latest',
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onLatest,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: skin.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.arrow_downward, size: 22, color: skin.onAccent),
          ),
        ),
      ),
    );
  }
}
