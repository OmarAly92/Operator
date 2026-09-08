import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/typing_dots.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_action_sheet.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_question_options.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_result_section.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_status_dot.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_todo_list.dart';

/// The rail-based visual kind a block renders as (`docs/design/session_detail/
/// session_detail.md`, "ground truth extracted from the prototype"). This is
/// distinct from [BlockKind]: several [BlockKind]s share a rail treatment
/// (e.g. every non-diff [BlockKind.tool] is [RailKind.group]), and a
/// [BlockDetail] payload can retarget one further (a [FileChangeBlockDetail]
/// moves a tool/assistant block to [RailKind.diff]).
enum RailKind { user, notice, text, think, group, mcpGroup, diff, plan, permission, question }

/// True for kinds a natural header row exists for (title/meta + optional
/// chevron) — the only kinds [StickyBlockHeader] pins a summary for.
bool railKindHasHeader(RailKind kind) =>
    kind == RailKind.think ||
    kind == RailKind.group ||
    kind == RailKind.mcpGroup ||
    kind == RailKind.diff ||
    kind == RailKind.plan;

RailKind railKindOf(SessionBlock block) {
  // A `question_asked` event is assembled onto a BlockKind.notice block
  // carrying a QuestionBlockDetail (`block_assembly.dart`) — it's a
  // "waiting on you" interactive block, not a divider notice, regardless of
  // its BlockKind.
  if (block.detail is QuestionBlockDetail) return RailKind.question;
  switch (block.kind) {
    case BlockKind.prompt:
      return RailKind.user;
    case BlockKind.notice:
    case BlockKind.compaction:
      return RailKind.notice;
    case BlockKind.reasoning:
      return RailKind.think;
    case BlockKind.todo:
      return RailKind.plan;
    case BlockKind.permission:
      return RailKind.permission;
    case BlockKind.tool:
      if (block.detail is FileChangeBlockDetail) return RailKind.diff;
      if (block.detail is McpToolBlockDetail || _looksLikeMcpTool(block.toolName)) {
        return RailKind.mcpGroup;
      }
      return RailKind.group;
    case BlockKind.assistant:
      if (block.detail is FileChangeBlockDetail) return RailKind.diff;
      return RailKind.text;
  }
}

bool _looksLikeMcpTool(String? toolName) => (toolName ?? '').toLowerCase().contains('mcp');

/// Whether [block] renders on the vertical rail at all — the negative is
/// used by callers building the "does the line connect to a next item" rule.
bool isRailBlock(SessionBlock block) {
  final kind = railKindOf(block);
  return kind != RailKind.user && kind != RailKind.notice;
}

Color railNodeColor(AppSkin skin, SessionBlock block) => switch (railKindOf(block)) {
  RailKind.think => skin.textFaint,
  RailKind.diff => skin.green,
  RailKind.plan => skin.blue,
  RailKind.permission || RailKind.question => skin.amber,
  RailKind.mcpGroup => skin.purple,
  RailKind.group || RailKind.text => blockStatusColor(skin, block.status),
  RailKind.user || RailKind.notice => skin.textFaint,
};

class BlockCard extends StatelessWidget {
  const BlockCard({
    super.key,
    required this.block,
    this.actionsBuilder,
    this.actions = const [],
    this.onAction,
    this.collapsed = false,
    this.onToggleCollapse,
    this.highlight,
    this.activeMatch = false,
    this.searchMatches = const {},
    this.activeMatchId,
    this.selected = false,
    this.onToggleSelect,
    this.selectionMode = false,
    this.onLongPressHeader,
    this.hasFollowingRailItem = false,
  });

  final SessionBlock block;
  final Widget? Function(SessionBlock block)? actionsBuilder;
  final List<BlockAction> actions;
  final void Function(BlockAction action)? onAction;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final BlockMatch? highlight;
  final bool activeMatch;
  final Map<String, BlockMatch> searchMatches;
  final String? activeMatchId;
  final bool selected;
  final ValueChanged<bool>? onToggleSelect;
  final bool selectionMode;
  final VoidCallback? onLongPressHeader;

  /// Whether the next block in document order also sits on the rail, so the
  /// connecting line should be drawn down to it. See `railLine` in
  /// `docs/design/session_detail/session_detail.md`.
  final bool hasFollowingRailItem;

  void _showActionSheet(BuildContext context) {
    if (onAction == null || actions.isEmpty) return;
    Haptics.tap();
    showBlockActionSheet(context, actions).then((chosen) {
      if (chosen != null &&
          chosen.kind != BlockActionKind.copyBlock &&
          chosen.kind != BlockActionKind.copyCommand &&
          chosen.kind != BlockActionKind.copyOutput) {
        onAction!(chosen);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final kind = railKindOf(block);
    final display = blockDisplay(block);
    final parentSearch = context.dependOnInheritedWidgetOfExactType<_SearchHighlight>();
    final matches = searchMatches.isNotEmpty ? searchMatches : parentSearch?.matches ?? const <String, BlockMatch>{};
    final match = highlight ?? matches[block.id];
    final currentMatchId = activeMatchId ?? parentSearch?.activeMatchId;
    final summaryHighlight = match?.forField(BlockMatchField.summary);
    final nameHighlight = match?.forField(BlockMatchField.displayName);
    final actionsWidget = actionsBuilder?.call(block);

    final Widget core = switch (kind) {
      RailKind.user => _UserBubble(
        block: block,
        highlight: summaryHighlight,
        onLongPressHeader: onLongPressHeader,
        onLongPressBody: () => _showActionSheet(context),
      ),
      RailKind.notice => _NoticeRow(block: block),
      _ => _RailRow(
        status: block.status,
        dotColor: railNodeColor(skin, block),
        hasLine: hasFollowingRailItem,
        body: _RailBody(
          kind: kind,
          block: block,
          display: display,
          collapsed: collapsed,
          onToggleCollapse: onToggleCollapse,
          onLongPressHeader: onLongPressHeader,
          onLongPressBody: () => _showActionSheet(context),
          nameHighlight: nameHighlight,
          summaryHighlight: summaryHighlight,
          actionsBuilder: actionsBuilder,
        ),
      ),
    };

    final indent = kind == RailKind.user || kind == RailKind.notice ? 0.0 : 21.0;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        core,
        if (actionsWidget != null)
          Padding(
            padding: EdgeInsets.only(top: 6, left: indent),
            child: actionsWidget,
          ),
      ],
    );

    final selectable = selectionMode && onToggleSelect != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggleSelect!(!selected),
            child: content,
          )
        : content;

    return _SearchHighlight(
      color: activeMatch || currentMatchId == block.id ? skin.searchMatchActive : skin.searchMatch,
      matches: matches,
      activeMatchId: currentMatchId,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: selectionMode ? const EdgeInsets.all(4) : EdgeInsets.zero,
      decoration: selected
          ? BoxDecoration(
              color: skin.accentTint,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            )
          : null,
      child: selectionMode
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected ? skin.accent : skin.textTertiary,
                  ),
                ),
                Expanded(child: selectable),
              ],
            )
          : selectable,
      ),
    );
  }
}

/// The 9x9 dot + connecting line on the left margin
/// (`railCol`/`nodeStyle`/`railLine` in the design doc).
class _RailRow extends StatelessWidget {
  const _RailRow({required this.status, required this.dotColor, required this.hasLine, required this.body});

  final BlockStatus status;
  final Color dotColor;
  final bool hasLine;
  final Widget body;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: BlockStatusDot(status: status, overrideColor: dotColor, size: 9),
              ),
              if (hasLine)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 1.5,
                    color: context.skin.borderDefault,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 14), child: body)),
      ],
    ),
  );
}

/// Dispatches to the kind-specific body content for every non-user,
/// non-notice rail kind.
class _RailBody extends StatelessWidget {
  const _RailBody({
    required this.kind,
    required this.block,
    required this.display,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onLongPressHeader,
    required this.onLongPressBody,
    required this.nameHighlight,
    required this.summaryHighlight,
    required this.actionsBuilder,
  });

  final RailKind kind;
  final SessionBlock block;
  final BlockDisplay display;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onLongPressHeader;
  final VoidCallback onLongPressBody;
  final BlockMatch? nameHighlight;
  final BlockMatch? summaryHighlight;
  final Widget? Function(SessionBlock block)? actionsBuilder;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case RailKind.text:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPressHeader ?? onLongPressBody,
          child: _highlightedField(
            context: context,
            text: display.summary,
            ranges: summaryHighlight?.ranges ?? const [],
            base: AppTextStyle.style15Regular.copyWith(
              color: context.skin.textPrimary,
              height: 1.5,
            ),
            softWrap: true,
          ),
        );
      case RailKind.think:
        return _ThinkBody(
          block: block,
          display: display,
          collapsed: collapsed,
          onToggleCollapse: onToggleCollapse,
          onLongPressHeader: onLongPressHeader,
          onLongPressBody: onLongPressBody,
          nameHighlight: nameHighlight,
          summaryHighlight: summaryHighlight,
        );
      case RailKind.group:
      case RailKind.mcpGroup:
        return _GroupBody(
          block: block,
          display: display,
          isMcp: kind == RailKind.mcpGroup,
          collapsed: collapsed,
          onToggleCollapse: onToggleCollapse,
          onLongPressHeader: onLongPressHeader,
          onLongPressBody: onLongPressBody,
          nameHighlight: nameHighlight,
          summaryHighlight: summaryHighlight,
          actionsBuilder: actionsBuilder,
        );
      case RailKind.diff:
        return _DiffBody(block: block, onLongPress: onLongPressHeader ?? onLongPressBody);
      case RailKind.plan:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPressHeader ?? onLongPressBody,
          child: _PlanBody(block: block),
        );
      case RailKind.permission:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPressHeader ?? onLongPressBody,
          child: _PermissionBody(block: block),
        );
      case RailKind.question:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPressHeader ?? onLongPressBody,
          child: _QuestionBody(block: block, display: display),
        );
      case RailKind.user:
      case RailKind.notice:
        return const SizedBox.shrink();
    }
  }
}

/// A single-line, ellipsized preview of a reasoning block's body for its
/// collapsed header, so a reader can glance at what the agent was thinking
/// without expanding the block.
String _reasoningPreview(String body) {
  final firstLine = body.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => '').trim();
  const maxLength = 140;
  return firstLine.length > maxLength ? '${firstLine.substring(0, maxLength)}…' : firstLine;
}

class _ThinkBody extends StatelessWidget {
  const _ThinkBody({
    required this.block,
    required this.display,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onLongPressHeader,
    required this.onLongPressBody,
    required this.nameHighlight,
    required this.summaryHighlight,
  });

  final SessionBlock block;
  final BlockDisplay display;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onLongPressHeader;
  final VoidCallback onLongPressBody;
  final BlockMatch? nameHighlight;
  final BlockMatch? summaryHighlight;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleCollapse,
      onLongPress: onLongPressHeader,
      child: Row(
        children: [
          Expanded(
            child: _highlightedField(
              context: context,
              text: display.displayName,
              ranges: nameHighlight?.ranges ?? const [],
              base: AppTextStyle.style13Medium.copyWith(color: skin.textTertiary),
            ),
          ),
          if (onToggleCollapse != null)
            Icon(
              collapsed ? Icons.expand_more : Icons.expand_less,
              size: 16,
              color: skin.textTertiary,
            ),
        ],
      ),
    );

    if (collapsed) {
      final preview = _reasoningPreview(display.summary);
      if (preview.isEmpty) return header;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppText(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPressBody,
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: skin.borderSubtle, width: 2)),
            ),
            child: _highlightedField(
              context: context,
              text: display.summary,
              ranges: summaryHighlight?.ranges ?? const [],
              base: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary, height: 1.5),
              softWrap: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// The bordered command/output container (`cmdCard`) shared by the
/// command-group and diff bodies.
class _CmdCard extends StatelessWidget {
  const _CmdCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, color: skin.borderSubtle),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7), child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _GroupBody extends StatelessWidget {
  const _GroupBody({
    required this.block,
    required this.display,
    required this.isMcp,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onLongPressHeader,
    required this.onLongPressBody,
    required this.nameHighlight,
    required this.summaryHighlight,
    required this.actionsBuilder,
  });

  final SessionBlock block;
  final BlockDisplay display;
  final bool isMcp;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onLongPressHeader;
  final VoidCallback onLongPressBody;
  final BlockMatch? nameHighlight;
  final BlockMatch? summaryHighlight;
  final Widget? Function(SessionBlock block)? actionsBuilder;

  String? get _meta {
    if (block.status == BlockStatus.running) return isMcp ? 'mcp · running' : 'running';
    if (isMcp) return 'mcp';
    final error = block.errorType ?? '';
    return error.isEmpty ? null : error;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final meta = _meta;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleCollapse,
      onLongPress: onLongPressHeader,
      child: Row(
        children: [
          Expanded(
            child: _highlightedField(
              context: context,
              text: display.displayName,
              ranges: nameHighlight?.ranges ?? const [],
              base: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary),
            ),
          ),
          if (meta != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AppText(meta, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
            ),
          if (onToggleCollapse != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: skin.textTertiary,
              ),
            ),
        ],
      ),
    );

    if (collapsed) return header;

    final detail = block.detail;
    final cmdLines = <Widget>[];
    if (detail is ShellBlockDetail && (detail.command ?? '').isNotEmpty) {
      cmdLines.add(
        AppText(
          detail.command!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.mono11p5Regular.copyWith(color: skin.textPrimary),
        ),
      );
      if ((detail.output ?? '').isNotEmpty) {
        final failed = detail.exitCode != null && detail.exitCode != 0;
        cmdLines.add(
          AppText(
            detail.output!,
            style: AppTextStyle.mono11p5Regular.copyWith(color: failed ? skin.red : skin.textPrimary),
            maxLines: 400,
          ),
        );
      }
    } else if (display.summary.isNotEmpty) {
      cmdLines.add(
        _highlightedField(
          context: context,
          text: display.summary,
          ranges: summaryHighlight?.ranges ?? const [],
          base: AppTextStyle.mono11p5Regular.copyWith(color: skin.textSecondary),
          softWrap: true,
        ),
      );
    }

    final children = block.children ?? const <SessionBlock>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (cmdLines.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPressBody,
            child: _CmdCard(children: cmdLines),
          ),
        ],
        if (block.detail is QuestionBlockDetail)
          BlockQuestionOptions(
            questions: (block.detail! as QuestionBlockDetail).questions,
            interactionId: block.interactionId,
          ),
        if ((block.result ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: BlockResultSection(result: block.result!),
          ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++)
                  BlockCard(
                    key: ValueKey('child-${children[i].id}'),
                    block: children[i],
                    actionsBuilder: actionsBuilder,
                    hasFollowingRailItem: i < children.length - 1,
                  ),
              ],
            ),
          ),
        if (display.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AppText(display.errorText!, style: AppTextStyle.style10Regular.copyWith(color: skin.red)),
          ),
        if (block.redacted)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AppText(
              'Secrets were redacted from this output',
              style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
            ),
          ),
        if (block.truncatedLines > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AppText(
              '...(truncated)... ${block.truncatedLines} more lines — open Raw for the rest',
              style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
              maxLines: 2,
            ),
          ),
        if (block.status == BlockStatus.running) ...[
          const SizedBox(height: 6),
          _RunningRow(block: block),
        ],
      ],
    );
  }
}

class _DiffBody extends StatelessWidget {
  const _DiffBody({required this.block, required this.onLongPress});

  final SessionBlock block;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final files = (block.detail as FileChangeBlockDetail).files ?? const <BlockFileChange>[];
    final additions = files.fold<int>(0, (sum, file) => sum + (file.additions ?? 0));
    final deletions = files.fold<int>(0, (sum, file) => sum + (file.deletions ?? 0));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  'Patched ${files.length} ${files.length == 1 ? 'file' : 'files'}',
                  style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary),
                ),
              ),
              AppText('+$additions', style: AppTextStyle.mono11Regular.copyWith(color: skin.green)),
              const SizedBox(width: 6),
              AppText('-$deletions', style: AppTextStyle.mono11Regular.copyWith(color: skin.red)),
            ],
          ),
          const SizedBox(height: 6),
          _CmdCard(
            children: [
              for (final file in files)
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        file.path ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.mono11p5Regular.copyWith(color: skin.textPrimary),
                      ),
                    ),
                    AppText(
                      '+${file.additions ?? 0} -${file.deletions ?? 0}',
                      style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final steps = parsePlanSteps(block.body);
    final done = steps.where((step) => step.status == PlanStepStatus.done).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppText('Plan', style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary)),
            if (steps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppText(
                  '$done of ${steps.length} done',
                  style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        BlockTodoList(body: block.body),
      ],
    );
  }
}

class _PermissionBody extends StatelessWidget {
  const _PermissionBody({required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: skin.tintAmber,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'Agent wants to run a command',
            style: AppTextStyle.style13SemiBold.copyWith(color: skin.amber),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: skin.bgSurface,
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: AppText(
              block.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.mono11p5Regular.copyWith(color: skin.green),
            ),
          ),
          const SizedBox(height: 8),
          if (block.interactionId != null)
            Row(
              children: [
                Expanded(
                  child: BlockActionButton(
                    label: 'Deny',
                    primary: false,
                    onTap: () => context.read<SessionCommandCubit>().decide(block.interactionId!, 'deny'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 14,
                  child: BlockActionButton(
                    label: 'Allow once',
                    primary: true,
                    onTap: () => context.read<SessionCommandCubit>().decide(block.interactionId!, 'allow'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Visual parity with the mockup's third button only: the
                  // daemon's decision contract (backend/internal/session_manager/
                  // decision.go) accepts only "allow"/"deny" — there is no
                  // "always allow" behavior to send, so this button is
                  // deliberately non-functional rather than sending a
                  // behavior string the daemon would reject.
                  child: BlockActionButton(label: 'Always', primary: false, onTap: () {}, disabled: true),
                ),
              ],
            )
          else
            AppText(
              'Answer in the terminal',
              style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// A "waiting on you" question block (`question_asked`,
/// `block.detail is QuestionBlockDetail`) — not modeled by the prototype,
/// which has no equivalent state, so it keeps the amber "needs input" node
/// color from [railNodeColor] and a plain title + [BlockQuestionOptions]
/// body rather than inventing a mockup treatment for it.
class _QuestionBody extends StatelessWidget {
  const _QuestionBody({required this.block, required this.display});

  final SessionBlock block;
  final BlockDisplay display;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(display.displayName, style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary)),
        const SizedBox(height: 6),
        BlockQuestionOptions(
          questions: (block.detail! as QuestionBlockDetail).questions,
          interactionId: block.interactionId,
        ),
      ],
    );
  }
}

class _RunningRow extends StatelessWidget {
  const _RunningRow({required this.block});

  final SessionBlock block;

  String get _commandText {
    final detail = block.detail;
    if (detail is ShellBlockDetail && (detail.command ?? '').isNotEmpty) return detail.command!;
    final firstLine = block.body.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    return firstLine.isNotEmpty ? firstLine : block.title;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    SessionCommandCubit? cubit;
    try {
      cubit = context.read<SessionCommandCubit>();
    } on ProviderNotFoundException {
      cubit = null;
    }
    return Row(
      children: [
        TypingDots(color: skin.orange, dotSize: 4, gap: 3),
        const SizedBox(width: 8),
        Expanded(
          child: AppText(
            _commandText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.mono12Regular.copyWith(color: skin.orange),
          ),
        ),
        if (cubit != null)
          GestureDetector(
            onTap: cubit.enabled('stop') ? () => cubit!.run('stop') : null,
            child: AppText('Stop', style: AppTextStyle.style12SemiBold.copyWith(color: skin.red)),
          ),
      ],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.block});

  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final label = (block.body.isNotEmpty ? block.body : block.title).toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AppText(
              label,
              style: AppTextStyle.mono10Regular.copyWith(color: skin.textTertiary, letterSpacing: 0.5),
            ),
          ),
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.block,
    required this.highlight,
    required this.onLongPressHeader,
    required this.onLongPressBody,
  });

  final SessionBlock block;
  final BlockMatch? highlight;
  final VoidCallback? onLongPressHeader;
  final VoidCallback onLongPressBody;

  String get _timestamp {
    final raw = block.createdAt;
    if (raw == null) return 'now';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'now';
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPressBody,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (MediaQuery.of(context).size.width - 32) * 0.78),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: skin.bgElevatedHover,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: _highlightedField(
                  context: context,
                  text: block.body,
                  ranges: highlight?.ranges ?? const [],
                  base: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary, height: 1.4),
                  softWrap: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            key: ValueKey('bubble-timestamp-${block.id}'),
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPressHeader,
            child: AppText(
              _timestamp,
              style: AppTextStyle.mono10p5Regular.copyWith(color: skin.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

Text _highlightedField({
  required BuildContext context,
  required String text,
  required List<MatchRange> ranges,
  required TextStyle base,
  bool softWrap = false,
}) {
  if (ranges.isEmpty) {
    return Text(text, style: base, softWrap: softWrap);
  }
  final skin = context.skin;
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final range in ranges) {
    final start = range.start.clamp(0, text.length);
    final end = (range.start + range.length).clamp(0, text.length);
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start), style: base));
    }
    if (end > start) {
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: base.copyWith(backgroundColor: context.dependOnInheritedWidgetOfExactType<_SearchHighlight>()?.color ?? skin.searchMatch),
        ),
      );
    }
    cursor = end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return Text.rich(
    TextSpan(children: spans),
    softWrap: softWrap,
    style: base,
  );
}

class BlockActionButton extends StatelessWidget {
  const BlockActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.primary,
    this.disabled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final foreground = disabled
        ? skin.textFaint
        : primary
        ? skin.onAccent
        : skin.textPrimary;
    return Material(
      color: primary && !disabled ? skin.accent : skin.bgElevated,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: primary && !disabled ? null : Border.all(color: skin.borderSubtle),
          ),
          child: AppText(label, style: AppTextStyle.style12SemiBold.copyWith(color: foreground)),
        ),
      ),
    );
  }
}

class _SearchHighlight extends InheritedWidget {
  const _SearchHighlight({required this.color, required this.matches, required this.activeMatchId, required super.child});

  final Color color;
  final Map<String, BlockMatch> matches;
  final String? activeMatchId;

  @override
  bool updateShouldNotify(_SearchHighlight oldWidget) => oldWidget.color != color || oldWidget.matches != matches || oldWidget.activeMatchId != activeMatchId;
}
