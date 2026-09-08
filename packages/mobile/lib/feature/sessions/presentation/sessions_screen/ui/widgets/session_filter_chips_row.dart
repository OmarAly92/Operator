import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_pill.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/sessions/logic/sessions_filter.dart';

/// The Agents-board filter row (`docs/design/sessions_board/sessions_board.md`):
/// horizontally-scrolling `AppPill` chips, each labelled with its live count.
class SessionFilterChipsRow extends StatelessWidget {
  const SessionFilterChipsRow({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.counts,
  });

  final SessionsFilter selected;
  final void Function(SessionsFilter filter) onSelect;
  final Map<SessionsFilter, int> counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in SessionsFilter.values) ...[
              AppPill(
                label: filter.label,
                active: filter == selected,
                count: counts[filter] ?? 0,
                onTap: () => onSelect(filter),
              ),
              if (filter != SessionsFilter.values.last) const HorizontalSpace(8),
            ],
          ],
        ),
      ),
    );
  }
}
