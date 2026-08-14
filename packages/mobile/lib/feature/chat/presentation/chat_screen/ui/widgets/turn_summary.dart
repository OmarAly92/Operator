import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart';

class TurnSummary extends StatefulWidget {
  const TurnSummary({super.key, required this.turn, this.onRollback});

  final ConversationTurnModel turn;
  final Future<int> Function(String turnId)? onRollback;

  @override
  State<TurnSummary> createState() => _TurnSummaryState();
}

class _TurnSummaryState extends State<TurnSummary> {
  bool _confirming = false;
  bool _rollingBack = false;
  String? _rollbackError;

  bool get _rollbackAvailable {
    final turn = widget.turn;
    return widget.onRollback != null &&
        !turn.isInFlight &&
        turn.id != null &&
        turn.providerTurnId != null &&
        turn.rolledBack != true;
  }

  @override
  void didUpdateWidget(TurnSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_confirming && !_rollbackAvailable) {
      _confirming = false;
      _rollbackError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final duration = _elapsed(
      turn.startedAt ?? turn.requestedAt,
      turn.completedAt,
    );
    final rollbackAvailable = _rollbackAvailable;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.hasPlan) TurnPlanCard(turn: turn),
          if (turn.diffFiles.isNotEmpty) ChangedFilesCard(turn: turn),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: skin.borderSubtle)),
              const HorizontalSpace(10),
              AppText(
                turn.rolledBack == true
                    ? 'ROLLED BACK'
                    : (turn.state ?? '').toUpperCase(),
                style: AppTextStyle.style9Bold.copyWith(
                  color: turn.state == 'failed' ? skin.red : skin.textFaint,
                  letterSpacing: 0.8,
                ),
              ),
              if (duration != null) ...[
                const HorizontalSpace(8),
                AppText(
                  duration,
                  style: AppTextStyle.mono10Regular.copyWith(
                    color: skin.textFaint,
                  ),
                ),
              ],
              if (rollbackAvailable) ...[
                const HorizontalSpace(8),
                InkWell(
                  onTap: () => setState(() => _confirming = true),
                  child: Icon(
                    Icons.settings_backup_restore,
                    size: 15,
                    color: skin.textTertiary,
                  ),
                ),
              ],
              const HorizontalSpace(10),
              Expanded(child: Container(height: 1, color: skin.borderSubtle)),
            ],
          ),
          if (turn.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppText(
                turn.errorMessage!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 6,
              ),
            ),
          if (_confirming && rollbackAvailable)
            _RollbackConfirmation(
              rollingBack: _rollingBack,
              rollbackError: _rollbackError,
              onCancel: _cancelRollback,
              onConfirm: _rollback,
            ),
        ],
      ),
    );
  }

  void _cancelRollback() {
    setState(() {
      _rollbackError = null;
      _confirming = false;
    });
  }

  Future<void> _rollback() async {
    final onRollback = widget.onRollback;
    final turnId = widget.turn.id;
    if (_rollingBack ||
        !_rollbackAvailable ||
        onRollback == null ||
        turnId == null) {
      return;
    }
    setState(() {
      _rollingBack = true;
      _rollbackError = null;
    });
    try {
      await onRollback(turnId);
      if (mounted) setState(() => _confirming = false);
    } catch (error) {
      if (mounted) setState(() => _rollbackError = error.toString());
    } finally {
      if (mounted) setState(() => _rollingBack = false);
    }
  }
}

class TurnPlanCard extends StatefulWidget {
  const TurnPlanCard({super.key, required this.turn});

  final ConversationTurnModel turn;

  @override
  State<TurnPlanCard> createState() => _TurnPlanCardState();
}

class _TurnPlanCardState extends State<TurnPlanCard> {
  late bool _open = widget.turn.state == 'running';

  @override
  Widget build(BuildContext context) => PlanShell(
    title: 'Plan',
    steps: widget.turn.planSteps,
    explanation: widget.turn.planExplanation,
    open: _open,
    liveLabel: widget.turn.state == 'running' ? 'STILL CHANGING' : null,
    onToggle: () => setState(() => _open = !_open),
  );
}

class ChangedFilesCard extends StatefulWidget {
  const ChangedFilesCard({super.key, required this.turn});

  final ConversationTurnModel turn;

  @override
  State<ChangedFilesCard> createState() => _ChangedFilesCardState();
}

class _ChangedFilesCardState extends State<ChangedFilesCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final additions = turn.diffFiles.fold<int>(
      0,
      (sum, file) => sum + (file.additions ?? 0),
    );
    final deletions = turn.diffFiles.fold<int>(
      0,
      (sum, file) => sum + (file.deletions ?? 0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: skin.textTertiary,
                  ),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${turn.diffFiles.length} changed ${turn.diffFiles.length == 1 ? 'file' : 'files'}',
                      style: AppTextStyle.style12SemiBold,
                    ),
                  ),
                  if (turn.state == 'running')
                    AppText(
                      'GROWING',
                      style: AppTextStyle.style9Bold.copyWith(
                        color: skin.orange,
                      ),
                    ),
                  const HorizontalSpace(8),
                  AppText(
                    '+$additions',
                    style: AppTextStyle.mono11Regular.copyWith(
                      color: skin.green,
                    ),
                  ),
                  const HorizontalSpace(5),
                  AppText(
                    '−$deletions',
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.red),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: skin.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileChangeList(files: turn.diffFiles),
                if (turn.diffTruncated == true)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(11, 0, 11, 8),
                    child: PartialNote(
                      warning: true,
                      text:
                          'This turn changed more files than Operator lists here. '
                          'Open the worktree shell for the complete diff.',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RollbackConfirmation extends StatelessWidget {
  const _RollbackConfirmation({
    required this.rollingBack,
    required this.onCancel,
    required this.onConfirm,
    this.rollbackError,
  });

  final bool rollingBack;
  final String? rollbackError;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'Make the agent forget this turn and everything after it?',
            style: AppTextStyle.style13SemiBold,
            maxLines: 3,
          ),
          const VerticalSpace(4),
          AppText(
            'Files stay changed. Only conversation memory is rolled back, and this cannot be undone.',
            style: AppTextStyle.style12Regular.copyWith(
              color: skin.textSecondary,
            ),
            maxLines: 3,
          ),
          const VerticalSpace(10),
          Row(
            children: [
              ChatActionButton(
                label: 'Cancel',
                enabled: !rollingBack,
                onPressed: onCancel,
              ),
              const HorizontalSpace(8),
              ChatActionButton(
                label: rollingBack ? 'Rolling back…' : 'Roll back',
                danger: true,
                enabled: !rollingBack,
                onPressed: onConfirm,
              ),
            ],
          ),
          if (rollbackError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                rollbackError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
        ],
      ),
    );
  }
}

String? _elapsed(String? start, String? end) {
  if (start == null || end == null) return null;
  final from = DateTime.tryParse(start);
  final to = DateTime.tryParse(end);
  if (from == null || to == null) return null;
  final seconds = to.difference(from).inSeconds;
  if (seconds < 0) return null;
  return seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m ${seconds % 60}s';
}
