import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class StatusVisual {
  const StatusVisual({required this.color, required this.label, this.breathing = false});

  final Color color;
  final String label;
  final bool breathing;
}

StatusVisual statusVisual(AppSkin skin, String? status) {
  switch (status) {
    case 'spawning':
      return StatusVisual(color: skin.blue, label: 'Starting');
    case 'working':
      return StatusVisual(color: skin.orange, label: 'Working', breathing: true);
    case 'detecting':
      return StatusVisual(color: skin.orange, label: 'Detecting', breathing: true);
    case 'needs_input':
      return StatusVisual(color: skin.amber, label: 'Needs input');
    case 'changes_requested':
      return StatusVisual(color: skin.amber, label: 'Changes req.');
    case 'stuck':
      return StatusVisual(color: skin.red, label: 'Stuck');
    case 'errored':
      return StatusVisual(color: skin.red, label: 'Crashed');
    case 'ci_failed':
      return StatusVisual(color: skin.red, label: 'CI failed');
    case 'pr_open':
      return StatusVisual(color: skin.textSecondary, label: 'PR open');
    case 'review_pending':
      return StatusVisual(color: skin.textSecondary, label: 'In review');
    case 'approved':
      return StatusVisual(color: skin.green, label: 'Approved');
    case 'mergeable':
      return StatusVisual(color: skin.green, label: 'Mergeable');
    case 'merged':
      return StatusVisual(color: skin.green, label: 'Merged');
    case 'done':
      return StatusVisual(color: skin.green, label: 'Done');
    case 'idle':
      return StatusVisual(color: skin.textTertiary, label: 'Idle');
    case 'no_signal':
      return StatusVisual(color: skin.textTertiary, label: 'No signal');
    case 'exited':
      return StatusVisual(color: skin.red, label: 'Exited');
    case 'draft':
      return StatusVisual(color: skin.textSecondary, label: 'Draft PR');
    case 'unknown':
      return StatusVisual(color: skin.textTertiary, label: 'Unknown');
    case 'cleanup':
      return StatusVisual(color: skin.textTertiary, label: 'Cleanup');
    case 'killed':
    case 'terminated':
      return StatusVisual(color: skin.textFaint, label: 'Terminated');
    default:
      return StatusVisual(color: skin.textTertiary, label: status ?? 'unknown');
  }
}

/// The status chip's tinted background (`docs/design/sessions_board/
/// sessions_board.md`): matched to the status color, falling back to
/// `bgSubtle` for the neutral-colored statuses that have no dedicated tint.
Color statusChipTint(AppSkin skin, Color statusColor) {
  if (statusColor == skin.blue) return skin.tintBlue;
  if (statusColor == skin.orange) return skin.tintOrange;
  if (statusColor == skin.amber) return skin.tintAmber;
  if (statusColor == skin.red) return skin.tintRed;
  if (statusColor == skin.green) return skin.tintGreen;
  if (statusColor == skin.purple) return skin.tintPurple;
  return skin.bgSubtle;
}
