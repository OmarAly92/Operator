### Task 22: The timeline

**Files:**
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`

**Interfaces:**
- Consumes: Task 13's timeline model, Task 20's widgets, Task 4's `commandOutputText`/`caretNotation`.
- Produces:
  - `class ActivityMeta` — `icon (IconData)`, `prefix (String?)`, `Color color(AppSkin, ConversationActivityModel)`
    and `ActivityMeta activityMeta(ConversationActivityModel)`
  - `List<TimelineRow> activityRuns(List<ConversationItemModel> items)` and
    `sealed class TimelineRow` with `SingleRow(item)` / `ActivitiesRow(key, activities)`
  - `String summarizeActivities(List<ConversationActivityModel>)`
  - widgets `ActivityRowWidget`, `ActivityRunWidget`, `FileChangeList`, `PlanCard`, `TurnPlanCard`,
    `ChangedFilesCard`, `TurnSummary`, `TimelineItem`, `ChatTimeline`

`activityRuns` collapses consecutive mechanics into one summarized row so agent prose stays the
visual hierarchy. Approvals, elicitations, errors, file changes, reasoning and anything carrying a
`detail.event` are never folded — those are the rows a person must actually see.

`ChatTimeline` uses a `ListView.builder` over `groupConversationByTurn`, a `GlobalKey` per group so
the conversation map can `Scrollable.ensureVisible` a specific exchange, and a tail-follow rule: it
auto-scrolls to the bottom while the user is within 120 logical pixels of it, and shows a "Latest"
button otherwise. That is the same threshold RN uses.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart';

ConversationSnapshotModel snapshot({
  List<ConversationItemModel> items = const [],
  List<ConversationTurnModel> turns = const [],
  bool hasMoreBefore = false,
  List<String> capabilities = const [],
}) =>
    ConversationSnapshotModel(
      conversationId: 'c-1',
      sessionId: 'w-1',
      harness: 'codex',
      controllerState: 'ready',
      latestSequence: 9,
      hasMoreBefore: hasMoreBefore,
      items: items,
      turns: turns,
      capabilities: capabilities,
    );

Future<void> pumpTimeline(WidgetTester tester, ConversationSnapshotModel value) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: ChatTimeline(
              snapshot: value,
              loadingOlder: false,
              onLoadOlder: () {},
              approvalPending: false,
              inputPending: false,
              onDecide: (_, __) async {},
              onResolveInput: (_, __, [___]) async {},
              onRollback: (_) async => 0,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invites the first message on an empty conversation', (tester) async {
    await pumpTimeline(tester, snapshot());
    expect(find.text('Start the conversation'), findsOneWidget);
  });

  testWidgets('renders a human message and an assistant answer differently', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: const [
        ConversationMessageModel(
            id: 'u1', sequence: 1, revision: 1, role: 'user', origin: 'human', text: 'do the thing'),
        ConversationMessageModel(
            id: 'a1', sequence: 2, revision: 1, role: 'assistant', origin: 'provider', text: 'Done.'),
      ]),
    );

    expect(find.text('do the thing'), findsOneWidget);
    expect(find.text('Done.'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('warns about an unconfirmed delivery', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: const [
        ConversationMessageModel(
          id: 'u1',
          sequence: 1,
          revision: 1,
          role: 'user',
          origin: 'human',
          text: 'hi',
          delivery: 'uncertain',
        ),
      ]),
    );
    expect(find.textContaining('Delivery unconfirmed'), findsOneWidget);
  });

  testWidgets('summarizes a run of mechanics instead of listing each one', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: [
        for (var index = 1; index <= 3; index++)
          ConversationActivityModel(
            id: 'c$index',
            turnId: 't1',
            sequence: index,
            revision: 1,
            activityKind: 'command',
            status: 'completed',
            summary: 'cat file$index.dart',
            detail: ActivityDetailModel({'command': 'cat file$index.dart'}),
          ),
      ]),
    );

    expect(find.text('Explored 3 files'), findsOneWidget);
    expect(find.textContaining('cat file1.dart'), findsNothing);
  });

  testWidgets('expands a failed activity by default', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(items: [
        ConversationActivityModel(
          id: 'c1',
          turnId: 't1',
          sequence: 1,
          revision: 1,
          activityKind: 'command',
          status: 'failed',
          summary: 'npm test',
          detail: ActivityDetailModel(const {'command': 'npm test', 'output': 'boom'}),
        ),
      ]),
    );
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('shows a turn plan with its progress count', (tester) async {
    await pumpTimeline(
      tester,
      snapshot(
        items: const [
          ConversationMessageModel(id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', text: 'go'),
        ],
        turns: const [
          ConversationTurnModel(
            id: 't1',
            state: 'completed',
            requestedAt: '2026-08-05T00:00:00Z',
            planSteps: [
              PlanStepModel(text: 'Read the code', status: 'completed'),
              PlanStepModel(text: 'Change it', status: 'pending'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets('offers rollback only when the daemon allows it', (tester) async {
    const turn = ConversationTurnModel(
      id: 't1',
      state: 'completed',
      providerTurnId: 'p1',
      requestedAt: '2026-08-05T00:00:00Z',
    );
    const item = ConversationMessageModel(
        id: 'u1', turnId: 't1', sequence: 1, revision: 1, role: 'user', text: 'go');

    await pumpTimeline(tester, snapshot(items: const [item], turns: const [turn]));
    expect(find.byIcon(Icons.settings_backup_restore), findsNothing);

    await pumpTimeline(
      tester,
      snapshot(items: const [item], turns: const [turn], capabilities: const ['rollback']),
    );
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
  });

  testWidgets('offers to load earlier messages only when there are any', (tester) async {
    await pumpTimeline(tester, snapshot(hasMoreBefore: true));
    expect(find.text('Load earlier messages'), findsOneWidget);
  });

  test('summarizes activity categories the way the desktop does', () {
    ConversationActivityModel command(String summary) => ConversationActivityModel(
          id: summary,
          sequence: 1,
          revision: 1,
          activityKind: 'command',
          status: 'completed',
          summary: summary,
        );

    expect(summarizeActivities([command('cat a'), command('rg foo')]), 'Explored 1 file, 1 search');
    expect(summarizeActivities([command('git status')]), 'Ran 1 git check');
    expect(summarizeActivities([command('npm test')]), 'Ran 1 command');
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`
Expected: FAIL — the timeline widgets do not exist.

- [x] **Step 3: Write the activity metadata and run grouping**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

const Set<String> _readCommands = {'cat', 'sed', 'nl', 'head', 'tail', 'bat', 'less', 'more', 'wc', 'jq'};
const Set<String> _searchCommands = {'rg', 'grep', 'find', 'fd', 'ls', 'tree', 'glob', 'ag'};

class ActivityMeta {
  const ActivityMeta({required this.icon, required this.color, this.prefix});

  final IconData icon;
  final String? prefix;
  final Color Function(AppSkin skin) color;
}

ActivityMeta activityMeta(ConversationActivityModel activity) {
  switch (activity.activityKind) {
    case 'command':
      return ActivityMeta(
        icon: Icons.terminal,
        color: (skin) => activity.status == 'failed' ? skin.red : skin.textTertiary,
      );
    case 'file_change':
      return ActivityMeta(icon: Icons.edit_outlined, prefix: 'Changed', color: (skin) => skin.blue);
    case 'mcp_tool':
      return ActivityMeta(
        icon: Icons.build_outlined,
        prefix: activity.detail?.server != null ? '${activity.detail!.server} ·' : 'MCP ·',
        color: (skin) => skin.purple,
      );
    case 'auto_review':
      return ActivityMeta(icon: Icons.shield_outlined, prefix: 'Reviewed', color: (skin) => skin.green);
    default:
      return ActivityMeta(icon: Icons.bolt_outlined, color: (skin) => skin.textTertiary);
  }
}

String summarizeActivities(List<ConversationActivityModel> activities) {
  var reads = 0;
  var searches = 0;
  var vcs = 0;
  var commands = 0;
  var tools = 0;
  var reviews = 0;
  var plans = 0;

  for (final activity in activities) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        tools++;
        continue;
      case 'auto_review':
        reviews++;
        continue;
      case 'plan':
        plans++;
        continue;
    }
    switch (_commandCategory(activity.detail?.command ?? activity.summary)) {
      case 'read':
        reads++;
      case 'search':
        searches++;
      case 'vcs':
        vcs++;
      default:
        commands++;
    }
  }

  final parts = <String>[
    if (reads > 0) '$reads ${reads == 1 ? 'file' : 'files'}',
    if (searches > 0) '$searches ${searches == 1 ? 'search' : 'searches'}',
    if (vcs > 0) '$vcs git ${vcs == 1 ? 'check' : 'checks'}',
    if (commands > 0) '$commands ${commands == 1 ? 'command' : 'commands'}',
    if (tools > 0) '$tools tool ${tools == 1 ? 'call' : 'calls'}',
    if (reviews > 0) '$reviews auto-${reviews == 1 ? 'decision' : 'decisions'}',
    if (plans > 0) 'updated plan',
  ];

  final verb = reads > 0 || searches > 0 ? 'Explored' : 'Ran';
  return '$verb ${parts.isEmpty ? '${activities.length} steps' : parts.join(', ')}';
}

String _commandCategory(String text) {
  final head = text.trim().split(RegExp(r'\s+')).first;
  final binary = head.substring(head.lastIndexOf('/') + 1);
  if (_readCommands.contains(binary)) return 'read';
  if (_searchCommands.contains(binary)) return 'search';
  if (binary == 'git' || binary == 'gh') return 'vcs';
  return 'run';
}
```

- [x] **Step 4: Write the activity rows**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart` — the
expandable generic row, the MCP tool row, and the auto-review row:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/ansi.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart';

String printable(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

class ActivityRowWidget extends StatelessWidget {
  const ActivityRowWidget({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        return _McpToolRow(activity: activity);
      case 'auto_review':
        return _AutoReviewRow(activity: activity);
      case 'file_change':
        return FileChangeActivity(activity: activity);
      case 'plan':
        return PlanCard(activity: activity);
      default:
        return _GenericActivityRow(activity: activity);
    }
  }
}

class _GenericActivityRow extends StatefulWidget {
  const _GenericActivityRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_GenericActivityRow> createState() => _GenericActivityRowState();
}

class _GenericActivityRowState extends State<_GenericActivityRow> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final output = commandOutputText(
      detail?.output ?? detail?.result ?? detail?.error ?? detail?.patchOutput,
    );
    final open = _override ?? activityStartsExpanded(activity);
    final expandable = output.isNotEmpty ||
        detail?.cwd != null ||
        detail?.arguments != null ||
        detail?.files != null ||
        detail?.reason != null ||
        detail?.text != null ||
        detail?.terminalInput != null;
    final meta = activityMeta(activity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _override = !open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(meta.icon, size: 13, color: meta.color(skin)),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${meta.prefix == null ? '' : '${meta.prefix} '}'
                      '${detail?.command ?? detail?.toolName ?? activity.summary}',
                      style: AppTextStyle.mono12Regular.copyWith(
                        color: activity.status == 'failed' ? skin.red : skin.textSecondary,
                      ),
                      maxLines: open ? 6 : 2,
                    ),
                  ),
                  if (activity.status == 'running')
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.orange),
                    )
                  else if (activity.status == 'cancelled')
                    AppText('stopped', style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                  if (expandable)
                    Icon(open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
                  if (detail?.reason != null || detail?.text != null)
                    AppText(
                      detail!.reason ?? detail.text!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 12,
                    ),
                  if (detail?.arguments != null) CodeOutput(value: printable(detail!.arguments)),
                  if (detail?.terminalInput != null) ...[
                    const VerticalSpace(6),
                    const DetailLabel(label: 'agent typed'),
                    CodeOutput(value: caretNotation(detail!.terminalInput!)),
                    if (detail.terminalInputTruncated)
                      const PartialNote(text: 'Operator stopped recording keystrokes at its cap; more were sent.'),
                  ],
                  if (output.isNotEmpty) CodeOutput(value: output),
                  if (detail?.outputTruncated == true || detail?.patchOutputTruncated == true)
                    const PartialNote(
                      warning: true,
                      text: 'This output is longer than Operator stores, so it stops early. '
                          'Open the worktree shell for the full run.',
                    )
                  else if (detail?.outputMayBePartial == true)
                    PartialNote(
                      text: '${detail!.outputSource == 'stream' ? 'Streamed live; the provider may have omitted the beginning.' : "The provider's rolled-up output may omit the beginning."}'
                          ' Open the worktree shell for the full run.',
                    ),
                  if (detail?.files is List) FileNameList(files: detail!.files as List<dynamic>),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _McpToolRow extends StatefulWidget {
  const _McpToolRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_McpToolRow> createState() => _McpToolRowState();
}

class _McpToolRowState extends State<_McpToolRow> {
  late bool _open = widget.activity.status == 'failed';

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final failed = widget.activity.status == 'failed' || detail?.success == false || detail?.error != null;
    final body = detail?.arguments != null ||
        detail?.result != null ||
        detail?.error != null ||
        detail?.progress != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.build_outlined, size: 13, color: failed ? skin.red : skin.purple),
                  const HorizontalSpace(8),
                  if (detail?.server != null || detail?.namespace != null)
                    AppText(
                      '${detail!.server ?? detail.namespace}/',
                      style: AppTextStyle.mono11Regular.copyWith(color: skin.purple),
                    ),
                  Expanded(
                    child: AppText(
                      detail?.toolName ?? widget.activity.summary,
                      style: AppTextStyle.mono12Regular.copyWith(color: failed ? skin.red : skin.textSecondary),
                    ),
                  ),
                  if (body)
                    Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open && body)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail?.error != null)
                    AppText(
                      detail!.error!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                      maxLines: 6,
                    ),
                  if (detail?.arguments != null) ...[
                    const DetailLabel(label: 'arguments'),
                    CodeOutput(value: printable(detail!.arguments)),
                  ],
                  if (detail?.result != null) ...[
                    const DetailLabel(label: 'result'),
                    CodeOutput(value: printable(detail!.result)),
                  ],
                  if (detail?.progress != null) ...[
                    const DetailLabel(label: 'progress'),
                    CodeOutput(value: detail!.progress!),
                    if (detail.progressTruncated)
                      const PartialNote(text: 'Progress was longer than Operator stores.'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AutoReviewRow extends StatefulWidget {
  const _AutoReviewRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_AutoReviewRow> createState() => _AutoReviewRowState();
}

class _AutoReviewRowState extends State<_AutoReviewRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final denied = (detail?.status ?? '').toLowerCase().contains('den');
    final paths = _reviewPaths(detail?.files);
    final body = detail?.rationale != null ||
        detail?.command != null ||
        detail?.cwd != null ||
        detail?.host != null ||
        detail?.decisionSource != null ||
        paths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(denied ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
                      size: 13, color: denied ? skin.red : skin.green),
                  const HorizontalSpace(8),
                  AppText(
                    denied ? 'Auto-declined' : 'Auto-approved',
                    style: AppTextStyle.style11SemiBold.copyWith(color: denied ? skin.red : skin.green),
                  ),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      widget.activity.summary,
                      style: AppTextStyle.mono12Regular.copyWith(color: skin.textSecondary),
                    ),
                  ),
                  if (detail?.riskLevel != null)
                    AppText(
                      detail!.riskLevel!,
                      style: AppTextStyle.style10Regular.copyWith(
                        color: ['high', 'critical'].contains(detail.riskLevel!.toLowerCase())
                            ? skin.red
                            : skin.textFaint,
                      ),
                    ),
                  if (body)
                    Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open && body)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    denied
                        ? 'The provider declined this on your behalf. You were not asked.'
                        : 'The provider allowed this on your behalf. You were not asked.',
                    style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                    maxLines: 3,
                  ),
                  if (detail?.rationale != null)
                    AppText(
                      detail!.rationale!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                      maxLines: 6,
                    ),
                  if (detail?.command != null) LabelValue(label: 'cmd', value: detail!.command!),
                  if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
                  if (detail?.host != null) LabelValue(label: 'host', value: detail!.host!),
                  if (paths.isNotEmpty) LabelValue(label: 'files', value: paths.join(', ')),
                  if (detail?.decisionSource != null) LabelValue(label: 'by', value: detail!.decisionSource!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _reviewPaths(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => entry is String
            ? entry
            : entry is Map && entry['path'] is String
                ? entry['path'] as String
                : null)
        .whereType<String>()
        .toList();
  }
}
```

- [x] **Step 5: Write the file-change, plan and turn-summary widgets**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart';

class FileChangeActivity extends StatefulWidget {
  const FileChangeActivity({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<FileChangeActivity> createState() => _FileChangeActivityState();
}

class _FileChangeActivityState extends State<FileChangeActivity> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final files = DiffFileModel.listFrom(detail?.files);
    final fallbackPatch = detail?.patchOutput;
    final live = widget.activity.status == 'running';
    final open = _override ?? (live && (fallbackPatch != null || files.any((file) => file.patch != null)));
    final expandable = files.isNotEmpty || fallbackPatch != null;
    final title = widget.activity.summary.isNotEmpty
        ? widget.activity.summary
        : '${files.length} changed ${files.length == 1 ? 'file' : 'files'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: expandable ? () => setState(() => _override = !open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 13, color: skin.blue),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(title, style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary)),
                ),
                if (expandable)
                  Icon(open ? Icons.expand_less : Icons.chevron_right, size: 15, color: skin.textFaint),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 21, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final file in files) FileChangeRow(file: file, live: live),
                if (fallbackPatch != null)
                  PatchBlock(patch: fallbackPatch, truncated: detail!.patchOutputTruncated),
              ],
            ),
          ),
      ],
    );
  }
}

class FileChangeRow extends StatefulWidget {
  const FileChangeRow({super.key, required this.file, this.live = false});

  final DiffFileModel file;
  final bool live;

  @override
  State<FileChangeRow> createState() => _FileChangeRowState();
}

class _FileChangeRowState extends State<FileChangeRow> {
  late bool _open = widget.live && widget.file.patch != null;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final file = widget.file;
    final mark = switch (file.status) {
      'added' => 'A',
      'deleted' => 'D',
      'renamed' => 'R',
      _ => 'M',
    };
    final color = switch (file.status) {
      'deleted' => skin.red,
      'added' => skin.green,
      _ => skin.blue,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: file.patch == null ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                AppText(mark, style: AppTextStyle.mono11Bold.copyWith(color: color)),
                const HorizontalSpace(8),
                Expanded(
                  child: AppText(
                    file.oldPath == null ? file.path : '${file.oldPath} → ${file.path}',
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.textSecondary),
                    maxLines: 2,
                  ),
                ),
                AppText(
                  '+${file.additions} −${file.deletions}',
                  style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint),
                ),
                if (file.patch != null)
                  Icon(_open ? Icons.expand_less : Icons.chevron_right, size: 13, color: skin.textFaint),
              ],
            ),
          ),
        ),
        if (_open && file.patch != null) PatchBlock(patch: file.patch!, truncated: file.patchTruncated),
      ],
    );
  }
}

class PatchBlock extends StatelessWidget {
  const PatchBlock({super.key, required this.patch, this.truncated = false});

  final String patch;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () => Clipboard.setData(ClipboardData(text: patch)),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: skin.bgColumn, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightedCodeText(code: patch, language: 'diff', style: AppTextStyle.mono11Regular),
            ),
          ),
        ),
        if (truncated)
          const PartialNote(
            warning: true,
            text: 'This patch is longer than Operator stores. The complete change remains in the worktree.',
          ),
      ],
    );
  }
}

class FileNameList extends StatelessWidget {
  const FileNameList({super.key, required this.files});

  final List<dynamic> files;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final file in files)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                '• ${file is String ? file : file.toString()}',
                style: AppTextStyle.mono11Regular.copyWith(color: context.skin.textSecondary),
                maxLines: 2,
              ),
            ),
        ],
      );
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

class PlanCard extends StatefulWidget {
  const PlanCard({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  late bool _open = widget.activity.status == 'running';

  @override
  Widget build(BuildContext context) {
    final detail = widget.activity.detail;
    return PlanShell(
      title: widget.activity.summary.isEmpty ? 'Plan updated' : widget.activity.summary,
      steps: detail?.steps ?? const [],
      explanation: detail?.explanation,
      emptyFallback: detail?.text ?? widget.activity.summary,
      open: _open,
      onToggle: () => setState(() => _open = !_open),
    );
  }
}

class PlanShell extends StatelessWidget {
  const PlanShell({
    super.key,
    required this.title,
    required this.steps,
    required this.open,
    required this.onToggle,
    this.explanation,
    this.emptyFallback,
    this.liveLabel,
  });

  final String title;
  final List<PlanStepModel> steps;
  final bool open;
  final VoidCallback onToggle;
  final String? explanation;
  final String? emptyFallback;
  final String? liveLabel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final done = steps.where((step) => step.status == 'completed').length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.borderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.checklist, size: 13, color: skin.textTertiary),
                  const HorizontalSpace(8),
                  Expanded(child: AppText(title, style: AppTextStyle.style12SemiBold)),
                  if (liveLabel != null) ...[
                    AppText(liveLabel!, style: AppTextStyle.style9Bold.copyWith(color: skin.orange)),
                    const HorizontalSpace(8),
                  ],
                  AppText(
                    '$done/${steps.length}',
                    style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 15, color: skin.textTertiary),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (explanation != null)
                    AppText(
                      explanation!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 8,
                    ),
                  for (final step in steps)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            step.status == 'completed' ? Icons.check_circle : Icons.circle_outlined,
                            size: 14,
                            color: step.status == 'completed'
                                ? skin.green
                                : step.status == 'in_progress'
                                    ? skin.orange
                                    : skin.textFaint,
                          ),
                          const HorizontalSpace(8),
                          Expanded(
                            child: AppText(
                              step.text,
                              style: AppTextStyle.style13Regular.copyWith(
                                color: step.status == 'completed' ? skin.textTertiary : skin.textPrimary,
                                decoration: step.status == 'completed'
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                              maxLines: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (steps.isEmpty && emptyFallback != null)
                    AppText(
                      emptyFallback!,
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                      maxLines: 6,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart` — the
turn's plan, changed files, state line and rollback confirmation:

```dart
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
  bool _planOpen = false;
  bool _filesOpen = false;
  bool _confirming = false;
  bool _rollingBack = false;
  String? _rollbackError;

  @override
  void initState() {
    super.initState();
    _planOpen = widget.turn.state == 'running';
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final duration = _elapsed(turn.startedAt ?? turn.requestedAt, turn.completedAt);
    final settled = !turn.isInFlight;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.hasPlan)
            PlanShell(
              title: 'Plan',
              steps: turn.planSteps,
              explanation: turn.planExplanation,
              open: _planOpen,
              liveLabel: turn.state == 'running' ? 'STILL CHANGING' : null,
              onToggle: () => setState(() => _planOpen = !_planOpen),
            ),
          if (turn.diffFiles.isNotEmpty) _changedFiles(context),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: skin.borderSubtle)),
              const HorizontalSpace(10),
              AppText(
                turn.rolledBack ? 'ROLLED BACK' : (turn.state ?? '').toUpperCase(),
                style: AppTextStyle.style9Bold.copyWith(
                  color: turn.state == 'failed' ? skin.red : skin.textFaint,
                  letterSpacing: 0.8,
                ),
              ),
              if (duration != null) ...[
                const HorizontalSpace(8),
                AppText(duration, style: AppTextStyle.mono10Regular.copyWith(color: skin.textFaint)),
              ],
              if (widget.onRollback != null && settled && turn.providerTurnId != null && !turn.rolledBack) ...[
                const HorizontalSpace(8),
                InkWell(
                  onTap: () => setState(() => _confirming = true),
                  child: Icon(Icons.settings_backup_restore, size: 15, color: skin.textTertiary),
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
          if (_confirming) _confirmation(context),
        ],
      ),
    );
  }

  Widget _changedFiles(BuildContext context) {
    final skin = context.skin;
    final turn = widget.turn;
    final additions = turn.diffFiles.fold<int>(0, (sum, file) => sum + file.additions);
    final deletions = turn.diffFiles.fold<int>(0, (sum, file) => sum + file.deletions);

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
            onTap: () => setState(() => _filesOpen = !_filesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: skin.textTertiary),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${turn.diffFiles.length} changed ${turn.diffFiles.length == 1 ? 'file' : 'files'}',
                      style: AppTextStyle.style12SemiBold,
                    ),
                  ),
                  if (turn.state == 'running')
                    AppText('GROWING', style: AppTextStyle.style9Bold.copyWith(color: skin.orange)),
                  const HorizontalSpace(8),
                  AppText('+$additions', style: AppTextStyle.mono11Regular.copyWith(color: skin.green)),
                  const HorizontalSpace(5),
                  AppText('−$deletions', style: AppTextStyle.mono11Regular.copyWith(color: skin.red)),
                  Icon(_filesOpen ? Icons.expand_less : Icons.expand_more, size: 15, color: skin.textTertiary),
                ],
              ),
            ),
          ),
          if (_filesOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final file in turn.diffFiles) FileChangeRow(file: file),
                  if (turn.diffTruncated)
                    const PartialNote(
                      warning: true,
                      text: 'This turn changed more files than Operator lists here. '
                          'Open the worktree shell for the complete diff.',
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
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
            style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
            maxLines: 3,
          ),
          const VerticalSpace(10),
          Row(
            children: [
              ChatActionButton(
                label: 'Cancel',
                enabled: !_rollingBack,
                onPressed: () => setState(() {
                  _rollbackError = null;
                  _confirming = false;
                }),
              ),
              const HorizontalSpace(8),
              ChatActionButton(
                label: _rollingBack ? 'Rolling back…' : 'Roll back',
                danger: true,
                enabled: !_rollingBack,
                onPressed: () async {
                  setState(() {
                    _rollingBack = true;
                    _rollbackError = null;
                  });
                  try {
                    await widget.onRollback!(widget.turn.id);
                    if (mounted) setState(() => _confirming = false);
                  } catch (error) {
                    if (mounted) setState(() => _rollbackError = error.toString());
                  } finally {
                    if (mounted) setState(() => _rollingBack = false);
                  }
                },
              ),
            ],
          ),
          if (_rollbackError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _rollbackError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
        ],
      ),
    );
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
}
```

- [x] **Step 6: Write the run grouping, the item renderer and the list**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart` — the
collapsed run, its subagent tree, and `activityRuns`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';

export 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart'
    show summarizeActivities;

sealed class TimelineRow {
  const TimelineRow(this.key);

  final String key;
}

final class SingleRow extends TimelineRow {
  const SingleRow(super.key, this.item);

  final ConversationItemModel item;
}

final class ActivitiesRow extends TimelineRow {
  ActivitiesRow(super.key, this.activities);

  final List<ConversationActivityModel> activities;
}

List<TimelineRow> activityRuns(List<ConversationItemModel> items) {
  final rows = <TimelineRow>[];
  for (final item in items) {
    final runnable = item is ConversationActivityModel &&
        item.activityKind != 'approval' &&
        item.activityKind != 'user_input' &&
        item.activityKind != 'error' &&
        item.activityKind != 'file_change' &&
        item.activityKind != 'reasoning' &&
        item.detail?.event == null;
    final previous = rows.isEmpty ? null : rows.last;

    if (runnable && previous is ActivitiesRow && previous.activities.first.turnId == item.turnId) {
      previous.activities.add(item);
    } else if (runnable) {
      rows.add(ActivitiesRow('run-${item.sequence}', [item]));
    } else {
      rows.add(SingleRow(item.itemKey, item));
    }
  }
  return rows;
}

class ActivityRunWidget extends StatefulWidget {
  const ActivityRunWidget({super.key, required this.activities});

  final List<ConversationActivityModel> activities;

  @override
  State<ActivityRunWidget> createState() => _ActivityRunWidgetState();
}

class _ActivityRunWidgetState extends State<ActivityRunWidget> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final hierarchy = activityHierarchy(widget.activities);
    if (widget.activities.length == 1 && hierarchy.first.children.isEmpty) {
      return ActivityRowWidget(activity: widget.activities.single);
    }

    final running = widget.activities.any((activity) => activity.status == 'running');
    final failed = widget.activities.where((activity) => activity.status == 'failed').length;
    final cancelled = widget.activities.where((activity) => activity.status == 'cancelled').length;
    final streaming = widget.activities
        .any((activity) => activity.status == 'running' && activity.detail?.output != null);
    final open = _override ?? streaming;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _override = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      summarizeActivities(widget.activities),
                      style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                    ),
                  ),
                  if (failed > 0)
                    AppText('$failed failed', style: AppTextStyle.style10Regular.copyWith(color: skin.red)),
                  if (cancelled > 0)
                    AppText('$cancelled stopped',
                        style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                  if (running)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.textTertiary),
                    ),
                  Icon(open ? Icons.expand_more : Icons.chevron_right, size: 15, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final node in hierarchy) _ActivityTree(node: node)],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityTree extends StatelessWidget {
  const _ActivityTree({required this.node});

  final ActivityNode node;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActivityRowWidget(activity: node.activity),
          if (node.children.isNotEmpty) _NestedAgentRun(nodes: node.children),
        ],
      );
}

class _NestedAgentRun extends StatefulWidget {
  const _NestedAgentRun({required this.nodes});

  final List<ActivityNode> nodes;

  @override
  State<_NestedAgentRun> createState() => _NestedAgentRunState();
}

class _NestedAgentRunState extends State<_NestedAgentRun> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final count = countActivityNodes(widget.nodes);
    final running = activityNodesRunning(widget.nodes);

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: skin.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 12, color: skin.textTertiary),
                  const HorizontalSpace(6),
                  Expanded(
                    child: AppText(
                      'SUBAGENT · $count ${count == 1 ? 'STEP' : 'STEPS'}',
                      style: AppTextStyle.style9Bold.copyWith(color: skin.textTertiary, letterSpacing: 0.7),
                    ),
                  ),
                  if (running)
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: skin.textTertiary),
                    ),
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 12, color: skin.textFaint),
                ],
              ),
            ),
          ),
          if (_open)
            for (final child in widget.nodes) _ActivityTree(node: child),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart` — one
conversation row: user bubble, origin report, assistant prose, system signals, or an activity. It
delegates approvals and elicitations to Task 22's cards.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart';

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.item,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
  });

  final ConversationItemModel item;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(String requestId, String action, [Map<String, dynamic>? content]) onResolveInput;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    if (item is ConversationMessageModel) {
      final message = item as ConversationMessageModel;
      if (message.role == 'user' && message.origin == 'human') {
        final delivery = _deliveryCopy(message.delivery);
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: skin.bgElevated,
              border: Border.all(color: skin.borderDefault),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
                bottomLeft: Radius.circular(17),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  message.text,
                  style: AppTextStyle.style16Regular.copyWith(color: skin.textPrimary, height: 1.4),
                ),
                if (delivery != null) ...[
                  const VerticalSpace(5),
                  AppText(delivery, style: AppTextStyle.style10Regular.copyWith(color: skin.amber), maxLines: 2),
                ],
              ],
            ),
          ),
        );
      }
      if (message.role == 'user') return _OriginMessage(message: message);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.senderLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: AppText(
                  message.senderLabel!,
                  style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary),
                ),
              ),
            ChatMarkdown(
              text: message.text.isEmpty && message.streaming ? '…' : message.text,
              streaming: message.streaming,
            ),
            if (!message.streaming && message.text.isNotEmpty)
              InkWell(
                onTap: () => Clipboard.setData(ClipboardData(text: message.text)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_outlined, size: 12, color: skin.textFaint),
                      const HorizontalSpace(5),
                      AppText('Copy', style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final activity = item as ConversationActivityModel;
    if (activity.activityKind == 'approval') {
      return ApprovalCard(activity: activity, busy: approvalPending, onDecide: onDecide);
    }
    if (activity.activityKind == 'user_input') {
      return UserInputCard(activity: activity, busy: inputPending, onResolve: onResolveInput);
    }
    if (activity.activityKind == 'system' && activity.detail?.event == 'compaction') {
      return _CompactionMarker(activity: activity);
    }
    if (activity.activityKind == 'system' && activity.detail?.event == 'steer') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: skin.tintBlue,
            border: Border.all(color: skin.borderSubtle),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText('STEERED',
                  style: AppTextStyle.style9Bold.copyWith(color: skin.blue, letterSpacing: 1)),
              const VerticalSpace(3),
              SelectableText(
                activity.detail?.text ?? activity.summary,
                style: AppTextStyle.style16Regular.copyWith(color: skin.textPrimary),
              ),
            ],
          ),
        ),
      );
    }
    if (activity.detail?.event == 'model.rerouted') {
      return _SystemSignal(
        icon: Icons.shuffle,
        title: 'Answered by ${activity.detail?.toModel ?? 'another model'}',
        detail: activity.detail?.fromModel != null
            ? 'Instead of ${activity.detail!.fromModel}'
                '${activity.detail!.reason == null ? '' : ' · ${activity.detail!.reason}'}'
            : activity.detail?.reason,
      );
    }
    if (activity.detail?.event == 'auth.reauth_required') {
      return _SystemSignal(
        icon: Icons.key_outlined,
        danger: true,
        title: 'The provider asked you to sign in again',
        detail: activity.detail?.reason,
      );
    }
    if (activity.activityKind == 'error') return _ErrorActivity(activity: activity);
    return ActivityRowWidget(activity: activity);
  }

  String? _deliveryCopy(String? state) {
    switch (state) {
      case 'queued':
        return 'Queued — sends when the agent finishes';
      case 'sending':
        return 'Sending…';
      case 'uncertain':
        return 'Delivery unconfirmed — check the conversation before retrying';
      case 'failed':
        return 'Not sent';
      default:
        return null;
    }
  }
}

class _OriginMessage extends StatefulWidget {
  const _OriginMessage({required this.message});

  final ConversationMessageModel message;

  @override
  State<_OriginMessage> createState() => _OriginMessageState();
}

class _OriginMessageState extends State<_OriginMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final message = widget.message;
    final long = message.text.length > 600;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: skin.borderStrong, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.podcasts, size: 11, color: skin.textTertiary),
              const HorizontalSpace(5),
              AppText(
                message.senderLabel ?? (message.origin == 'automation' ? 'Automation' : 'Operator'),
                style: AppTextStyle.style10Bold.copyWith(color: skin.textTertiary, letterSpacing: 0.7),
              ),
            ],
          ),
          const VerticalSpace(5),
          if (long && _expanded)
            ChatMarkdown(text: message.text)
          else
            SelectableText(
              message.text,
              maxLines: long ? 5 : null,
              style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary, height: 1.45),
            ),
          if (long)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.chevron_right, size: 12, color: skin.blue),
                    const HorizontalSpace(4),
                    AppText(
                      _expanded ? 'Hide report' : 'Show full report',
                      style: AppTextStyle.style11SemiBold.copyWith(color: skin.blue),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SystemSignal extends StatelessWidget {
  const _SystemSignal({required this.icon, required this.title, this.detail, this.danger = false});

  final IconData icon;
  final String title;
  final String? detail;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: danger ? skin.red : skin.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: danger ? skin.red : skin.textTertiary),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: AppTextStyle.style11SemiBold.copyWith(color: danger ? skin.red : skin.textPrimary),
                  maxLines: 2,
                ),
                if (detail != null)
                  AppText(detail!, style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary), maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorActivity extends StatelessWidget {
  const _ErrorActivity({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final body = activity.detail?.error ?? activity.detail?.message;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: skin.tintRed),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: skin.red),
          const HorizontalSpace(9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  activity.summary.isEmpty ? 'Agent error' : activity.summary,
                  style: AppTextStyle.style12SemiBold,
                  maxLines: 2,
                ),
                if (body != null)
                  SelectableText(
                    body,
                    style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactionMarker extends StatelessWidget {
  const _CompactionMarker({required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final after = activity.detail?.tokensAfter;
    final window = activity.detail?.contextWindow;
    final reclaimed = activity.detail?.tokensReclaimed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
          const HorizontalSpace(10),
          Icon(Icons.archive_outlined, size: 12, color: skin.textFaint),
          const HorizontalSpace(6),
          AppText(
            'HISTORY COMPACTED'
            '${reclaimed == null ? '' : '  −${formatTokens(reclaimed)}'}'
            '${after != null && window != null && window > 0 ? '  ${(after / window * 100).round()}% FULL' : ''}',
            style: AppTextStyle.style9Bold.copyWith(color: skin.textFaint, letterSpacing: 0.8),
          ),
          const HorizontalSpace(10),
          Expanded(child: Container(height: 1, color: skin.borderSubtle)),
        ],
      ),
    );
  }
}

String formatTokens(int value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
    : '$value';
```

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart';

class ChatTimeline extends StatefulWidget {
  const ChatTimeline({
    super.key,
    required this.snapshot,
    required this.loadingOlder,
    required this.onLoadOlder,
    required this.approvalPending,
    required this.inputPending,
    required this.onDecide,
    required this.onResolveInput,
    required this.onRollback,
    this.jumpToSequence,
    this.onJumpHandled,
  });

  final ConversationSnapshotModel snapshot;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;
  final bool approvalPending;
  final bool inputPending;
  final Future<void> Function(String requestId, String decisionId) onDecide;
  final Future<void> Function(String requestId, String action, [Map<String, dynamic>? content]) onResolveInput;
  final Future<int> Function(String turnId) onRollback;
  final int? jumpToSequence;
  final VoidCallback? onJumpHandled;

  @override
  State<ChatTimeline> createState() => _ChatTimelineState();
}

class _ChatTimelineState extends State<ChatTimeline> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _anchors = {};
  bool _followsTail = true;
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final follows = _controller.position.maxScrollExtent - _controller.offset < 120;
    if (follows != _followsTail) setState(() {
      _followsTail = follows;
      _showJump = !follows;
    });
  }

  @override
  void didUpdateWidget(ChatTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followsTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
    final target = widget.jumpToSequence;
    if (target != null && target != oldWidget.jumpToSequence) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
    }
  }

  void _jumpTo(int sequence) {
    final groups = groupConversationByTurn(widget.snapshot);
    for (final group in groups) {
      if (group.anchor != sequence) continue;
      final anchor = _anchors[group.key]?.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(anchor, duration: const Duration(milliseconds: 250), alignment: 0.18);
      }
      break;
    }
    widget.onJumpHandled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final items = readableConversationItems(widget.snapshot);
    final groups = groupConversationByTurn(widget.snapshot, items);

    if (groups.isEmpty) {
      return Container(
        color: skin.bgBase,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: skin.tintBlue, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_outline, size: 20, color: skin.blue),
            ),
            const VerticalSpace(12),
            AppText(
              widget.snapshot.controllerState == 'connecting'
                  ? 'Connecting to the agent…'
                  : 'Start the conversation',
              style: AppTextStyle.style17SemiBold,
              maxLines: 2,
            ),
            const VerticalSpace(6),
            AppText(
              'This ${widget.snapshot.harness ?? 'agent'} session works in its own Operator worktree. '
              'Ask it to inspect, change, test, or explain anything there.',
              style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
              textAlign: TextAlign.center,
              maxLines: 4,
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Container(
          color: skin.bgBase,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (widget.snapshot.hasMoreBefore) {
                  return Center(
                    child: TextButton(
                      onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
                      child: AppText(
                        widget.loadingOlder ? 'Loading history…' : 'Load earlier messages',
                        style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
                      ),
                    ),
                  );
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AppText(
                      'BEGINNING OF CONVERSATION',
                      style: AppTextStyle.style10Regular.copyWith(color: skin.textFaint, letterSpacing: 1),
                    ),
                  ),
                );
              }

              final group = groups[index - 1];
              final anchor = _anchors.putIfAbsent(group.key, GlobalKey.new);
              return KeyedSubtree(
                key: anchor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in activityRuns(group.items))
                      switch (row) {
                        ActivitiesRow(:final activities) => ActivityRunWidget(activities: activities),
                        SingleRow(:final item) => TimelineItem(
                            item: item,
                            approvalPending: widget.approvalPending,
                            inputPending: widget.inputPending,
                            onDecide: widget.onDecide,
                            onResolveInput: widget.onResolveInput,
                          ),
                      },
                    if (group.turn != null)
                      TurnSummary(
                        turn: group.turn!,
                        onRollback: canRollbackTurn(widget.snapshot, group.turn!) ? widget.onRollback : null,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_showJump)
          Positioned(
            right: 14,
            bottom: 12,
            child: Material(
              color: skin.bgElevated,
              shape: StadiumBorder(side: BorderSide(color: skin.borderStrong)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  setState(() {
                    _followsTail = true;
                    _showJump = false;
                  });
                  _controller.animateTo(
                    _controller.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_downward, size: 14, color: skin.textPrimary),
                      const HorizontalSpace(6),
                      AppText('Latest', style: AppTextStyle.style11Bold),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [x] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`
Expected: PASS. `timeline_item.dart` imports Task 21's `ApprovalCard` and `UserInputCard`; if they
are missing, that task was skipped.

- [x] **Step 8: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 551/551 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): render the chat timeline"
```

---
