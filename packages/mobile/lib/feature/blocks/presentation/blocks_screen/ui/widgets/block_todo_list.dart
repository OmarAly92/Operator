import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class BlockTodoList extends StatelessWidget {
  const BlockTodoList({super.key, required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final items = _parse(body);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: AppText(
          body,
          style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
          maxLines: 200,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.done ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: item.done ? skin.green : skin.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppText(
                      item.text,
                      style: AppTextStyle.style12Regular.copyWith(
                        color: item.done ? skin.textTertiary : skin.textPrimary,
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodoItem {
  const _TodoItem(this.text, this.done);

  final String text;
  final bool done;
}

List<_TodoItem> _parse(String body) {
  if (body.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final raw = decoded['todos'];
  if (raw is! List) return const [];
  final items = <_TodoItem>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final text = entry['content'] as String?;
    if (text == null || text.isEmpty) continue;
    items.add(_TodoItem(text, entry['status'] == 'completed'));
  }
  return items;
}
