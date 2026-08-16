import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';

enum ConversationMenuAction {
  map,
  pullRequests,
  settings,
  compact,
  reloadMcp,
  rename,
  worktreeShell,
  terminalUi,
  preview,
}

class ConversationMenuResult {
  const ConversationMenuResult(this.action, {this.title});

  final ConversationMenuAction action;
  final String? title;
}

Future<ConversationMenuResult?> showConversationMenuSheet(
  BuildContext context, {
  required ConversationSnapshotModel snapshot,
  required bool compactSupported,
  required bool mcpReloadSupported,
  required bool compacting,
  required bool mcpReloading,
  required bool openingShell,
  required bool interfaceSupported,
}) {
  return showModalBottomSheet<ConversationMenuResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _ConversationMenuSheet(
      snapshot: snapshot,
      compactSupported: compactSupported,
      mcpReloadSupported: mcpReloadSupported,
      compacting: compacting,
      mcpReloading: mcpReloading,
      openingShell: openingShell,
      interfaceSupported: interfaceSupported,
    ),
  );
}

class _ConversationMenuSheet extends StatefulWidget {
  const _ConversationMenuSheet({
    required this.snapshot,
    required this.compactSupported,
    required this.mcpReloadSupported,
    required this.compacting,
    required this.mcpReloading,
    required this.openingShell,
    required this.interfaceSupported,
  });

  final ConversationSnapshotModel snapshot;
  final bool compactSupported;
  final bool mcpReloadSupported;
  final bool compacting;
  final bool mcpReloading;
  final bool openingShell;
  final bool interfaceSupported;

  @override
  State<_ConversationMenuSheet> createState() => _ConversationMenuSheetState();
}

class _ConversationMenuSheetState extends State<_ConversationMenuSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.snapshot.title ?? '',
  );
  bool _renaming = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final snapshot = widget.snapshot;
    final turnInFlight = snapshot.hasTurnInFlight;

    if (_renaming) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                'Rename conversation',
                style: AppTextStyle.style16SemiBold,
              ),
              const VerticalSpace(10),
              TextField(
                controller: _title,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppTextStyle.style14Regular.copyWith(
                  color: skin.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Conversation title',
                  filled: true,
                  fillColor: skin.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: skin.borderDefault),
                  ),
                ),
              ),
              const VerticalSpace(12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _renaming = false),
                    child: AppText(
                      'Cancel',
                      style: AppTextStyle.style13SemiBold.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _title.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            ConversationMenuResult(
                              ConversationMenuAction.rename,
                              title: _title.text.trim(),
                            ),
                          ),
                    child: AppText(
                      'Save',
                      style: AppTextStyle.style13Bold.copyWith(
                        color: skin.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: AppText('Conversation', style: AppTextStyle.style16SemiBold),
          ),
          _MenuRow(
            icon: Icons.list_alt,
            label: 'Conversation map',
            hint: 'Jump to any request and response',
            onTap: () => Navigator.of(
              context,
            ).pop(const ConversationMenuResult(ConversationMenuAction.map)),
          ),
          _MenuRow(
            icon: Icons.public,
            label: 'Open preview',
            hint: 'View a page or document generated in this worktree',
            onTap: () => Navigator.of(
              context,
            ).pop(const ConversationMenuResult(ConversationMenuAction.preview)),
          ),
          _MenuRow(
            icon: Icons.terminal,
            label: widget.openingShell ? 'Opening shell…' : 'Open worktree shell',
            hint: 'A plain terminal in this session\'s worktree',
            enabled: !widget.openingShell,
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.worktreeShell),
            ),
          ),
          _MenuRow(
            icon: Icons.swap_horiz,
            label: 'Open Terminal UI',
            hint: widget.interfaceSupported
                ? 'Keep the session, worktree and conversation; drive the agent\'s own TUI'
                : 'This agent has not declared a compatible handoff',
            enabled: widget.interfaceSupported,
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.terminalUi),
            ),
          ),
          _MenuRow(
            icon: Icons.merge_outlined,
            label: 'Pull requests',
            hint: 'Review CI, feedback and merge state',
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.pullRequests),
            ),
          ),
          _MenuRow(
            icon: Icons.tune,
            label: 'Turn settings',
            hint: 'Model, effort, approvals and provider options',
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.settings),
            ),
          ),
          if (snapshot.can('rename'))
            _MenuRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () => setState(() => _renaming = true),
            ),
          if (widget.compactSupported)
            _MenuRow(
              icon: Icons.archive_outlined,
              label: widget.compacting
                  ? 'Compacting history…'
                  : 'Compact history',
              hint: turnInFlight
                  ? 'Available after the current turn finishes'
                  : snapshot.compactedAt != null
                  ? 'Last compacted ${snapshot.compactedAt}'
                  : 'Summarize older context without changing files',
              enabled: !turnInFlight && !widget.compacting,
              onTap: () => Navigator.of(context).pop(
                const ConversationMenuResult(ConversationMenuAction.compact),
              ),
            ),
          if (widget.mcpReloadSupported)
            _MenuRow(
              icon: Icons.refresh,
              label: widget.mcpReloading
                  ? 'Reloading MCP servers…'
                  : 'Reload MCP servers',
              hint: turnInFlight
                  ? 'Available after the current turn finishes'
                  : null,
              enabled: !turnInFlight && !widget.mcpReloading,
              onTap: () => Navigator.of(context).pop(
                const ConversationMenuResult(ConversationMenuAction.reloadMcp),
              ),
            ),
          if (snapshot.usage != null)
            _InfoBox(
              title: 'Context and usage',
              body:
                  '${_tokens(snapshot.usage!.contextUsed)} / ${_tokens(snapshot.usage!.contextWindow)} context'
                  ' · ${_tokens(snapshot.usage!.inputTokens)} in · ${_tokens(snapshot.usage!.outputTokens)} out'
                  '${(snapshot.usage!.cachedTokens ?? 0) > 0 ? ' · ${_tokens(snapshot.usage!.cachedTokens)} cached' : ''}'
                  '${snapshot.usage!.cost != null ? ' · ${snapshot.usage!.currency ?? '\$'}${snapshot.usage!.cost!.toStringAsFixed(4)}' : ''}',
            ),
          if (snapshot.rateLimits != null)
            _InfoBox(
              title: snapshot.rateLimits!.planLabel ?? 'Rate limits',
              body:
                  'Primary: ${(snapshot.rateLimits!.primaryUsedPercent ?? 0).round()}% used'
                  '${(snapshot.rateLimits!.secondaryUsedPercent ?? -1) >= 0 ? ' · Secondary: ${snapshot.rateLimits!.secondaryUsedPercent!.round()}%' : ''}',
            ),
        ],
      ),
    );
  }

  String _tokens(int? value) {
    final tokens = value ?? 0;
    return tokens >= 1000
        ? '${(tokens / 1000).toStringAsFixed(tokens >= 10000 ? 0 : 1)}k'
        : '$tokens';
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap();
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: skin.borderSubtle)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: skin.textTertiary),
              const HorizontalSpace(11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(label, style: AppTextStyle.style13SemiBold),
                    if (hint != null)
                      AppText(
                        hint!,
                        style: AppTextStyle.style10Regular.copyWith(
                          color: skin.textTertiary,
                        ),
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: skin.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            title,
            style: AppTextStyle.style11Bold.copyWith(color: skin.textSecondary),
          ),
          const VerticalSpace(3),
          AppText(
            body,
            style: AppTextStyle.style10Regular.copyWith(
              color: skin.textTertiary,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
