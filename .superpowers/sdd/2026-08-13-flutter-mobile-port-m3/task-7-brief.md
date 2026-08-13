### Task 7: Conversation chrome (`conversationChrome.ts` port)

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/conversation_chrome.dart`
- Test: `packages/mobile/test/feature/chat/logic/conversation_chrome_test.dart`

**Interfaces:**
- Consumes: `ConversationUsageModel`, `ConversationRateLimitsModel`, `McpServerModel` — **not yet
  written** (Task 11). This task therefore takes the four primitives it needs directly, and Task 11
  adds the model classes that carry them:
  - `enum Severity { normal, warn, critical }`
  - `class ContextReadout` — `percent (int?)`, `fillPercent (double?)`, `severity (Severity)`,
    `tokens (int)`
  - `ContextReadout? contextReadout({required int? contextUsed, required int? contextWindow, required int? totalTokens})`
  - `class QuotaWarning` — `percent (int)`, `severity (Severity)`, `resetsInSeconds (int?)`,
    `planLabel (String?)`
  - `QuotaWarning? quotaWarning({required num? primaryUsedPercent, required num? secondaryUsedPercent, int? primaryResetsInSeconds, int? secondaryResetsInSeconds, String? planLabel})`
  - `String? elapsedLabel(String? startedAt, int nowMs)`
  - `String? resetLabel(int? seconds)`
  - `String mcpServerFailureLabel({required String name, String? failureReason, String? error})`

Taking primitives rather than models keeps this module ahead of Task 11 in the build order, which
matters: it is pure presentation arithmetic and its test is the ledger's `conversationChrome`
row, which must not wait on the wire shapes.

`quotaWarning` filters out windows the daemon reports as `-1` (meaning "not reported") before
picking the worst, and returns nothing below 75%. `contextReadout`'s `fillPercent` floors at 2 so a
1%-full context is still a visible sliver rather than an empty rail.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/logic/conversation_chrome_test.dart` (ported from
`chat/conversationChrome.test.ts`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

void main() {
  group('mobile Chat conversation chrome', () {
    test('uses the same context thresholds and visible minimum as desktop', () {
      final low = contextReadout(contextUsed: 1, contextWindow: 1000, totalTokens: 1)!;
      expect(low.percent, 0);
      expect(low.fillPercent, 2);
      expect(low.severity, Severity.normal);

      expect(
        contextReadout(contextUsed: 70, contextWindow: 100, totalTokens: 70)?.severity,
        Severity.warn,
      );
      expect(
        contextReadout(contextUsed: 900, contextWindow: 1000, totalTokens: 900)?.severity,
        Severity.critical,
      );
    });

    test('falls back to total tokens when no window is reported', () {
      final unbounded = contextReadout(contextUsed: 0, contextWindow: 0, totalTokens: 4200)!;
      expect(unbounded.percent, isNull);
      expect(unbounded.tokens, 4200);
      expect(unbounded.severity, Severity.normal);
      expect(contextReadout(contextUsed: null, contextWindow: null, totalTokens: null), isNull);
    });

    test('warns on the tighter reported quota window and ignores absent ones', () {
      final warned = quotaWarning(
        primaryUsedPercent: -1,
        secondaryUsedPercent: 82,
        secondaryResetsInSeconds: 7200,
        planLabel: 'weekly',
      )!;
      expect(warned.percent, 82);
      expect(warned.severity, Severity.warn);
      expect(warned.resetsInSeconds, 7200);
      expect(warned.planLabel, 'weekly');

      expect(quotaWarning(primaryUsedPercent: 40, secondaryUsedPercent: -1), isNull);
      expect(
        quotaWarning(primaryUsedPercent: 91, secondaryUsedPercent: 80)?.severity,
        Severity.critical,
      );
      expect(quotaWarning(primaryUsedPercent: null, secondaryUsedPercent: null), isNull);
    });

    test('formats live turn and reset durations without wall-clock assumptions', () {
      expect(
        elapsedLabel('2026-08-05T00:00:00Z', DateTime.parse('2026-08-05T00:02:03Z').millisecondsSinceEpoch),
        '2m 3s',
      );
      expect(
        elapsedLabel('2026-08-05T00:00:00Z', DateTime.parse('2026-08-05T01:05:00Z').millisecondsSinceEpoch),
        '1h 5m',
      );
      expect(elapsedLabel(null, 0), isNull);
      expect(elapsedLabel('not a date', 0), isNull);
      expect(resetLabel(172800), '2d');
      expect(resetLabel(90), '2m');
      expect(resetLabel(null), isNull);
      expect(resetLabel(-1), isNull);
    });

    test('keeps both the MCP failure class and provider diagnostic', () {
      expect(
        mcpServerFailureLabel(name: 'github', failureReason: 'auth', error: 'token expired'),
        'github (auth: token expired)',
      );
      expect(mcpServerFailureLabel(name: 'github'), 'github');
    });
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/logic/conversation_chrome_test.dart`
Expected: FAIL — the library does not exist.

- [x] **Step 3: Write the implementation**

`packages/mobile/lib/feature/chat/logic/conversation_chrome.dart`:

```dart
import 'dart:math';

enum Severity { normal, warn, critical }

class ContextReadout {
  const ContextReadout({required this.severity, required this.tokens, this.percent, this.fillPercent});

  final int? percent;
  final double? fillPercent;
  final Severity severity;
  final int tokens;
}

class QuotaWarning {
  const QuotaWarning({
    required this.percent,
    required this.severity,
    this.resetsInSeconds,
    this.planLabel,
  });

  final int percent;
  final Severity severity;
  final int? resetsInSeconds;
  final String? planLabel;
}

ContextReadout? contextReadout({
  required int? contextUsed,
  required int? contextWindow,
  required int? totalTokens,
}) {
  if (contextUsed == null && contextWindow == null && totalTokens == null) return null;
  final used = contextUsed ?? 0;
  final window = contextWindow ?? 0;
  final tokens = used != 0 ? used : totalTokens ?? 0;
  if (window <= 0) return ContextReadout(severity: Severity.normal, tokens: tokens);

  final fraction = min(1, max(0, used / window)).toDouble();
  return ContextReadout(
    percent: (fraction * 100).round(),
    fillPercent: max(2, fraction * 100),
    severity: fraction >= 0.9
        ? Severity.critical
        : fraction >= 0.7
            ? Severity.warn
            : Severity.normal,
    tokens: tokens,
  );
}

QuotaWarning? quotaWarning({
  required num? primaryUsedPercent,
  required num? secondaryUsedPercent,
  int? primaryResetsInSeconds,
  int? secondaryResetsInSeconds,
  String? planLabel,
}) {
  final windows = <({num percent, int? resetsInSeconds})>[
    if (primaryUsedPercent != null && primaryUsedPercent.isFinite && primaryUsedPercent >= 0)
      (percent: primaryUsedPercent, resetsInSeconds: primaryResetsInSeconds),
    if (secondaryUsedPercent != null && secondaryUsedPercent.isFinite && secondaryUsedPercent >= 0)
      (percent: secondaryUsedPercent, resetsInSeconds: secondaryResetsInSeconds),
  ];
  if (windows.isEmpty) return null;

  final worst = windows.reduce((current, candidate) => candidate.percent > current.percent ? candidate : current);
  if (worst.percent < 75) return null;

  return QuotaWarning(
    percent: worst.percent.round(),
    severity: worst.percent >= 90 ? Severity.critical : Severity.warn,
    resetsInSeconds: worst.resetsInSeconds,
    planLabel: planLabel,
  );
}

String? elapsedLabel(String? startedAt, int nowMs) {
  if (startedAt == null) return null;
  final started = DateTime.tryParse(startedAt);
  if (started == null) return null;

  final elapsed = max(0, nowMs - started.millisecondsSinceEpoch);
  final seconds = elapsed ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String? resetLabel(int? seconds) {
  if (seconds == null || seconds < 0) return null;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${(seconds / 60).ceil()}m';
  if (seconds < 86400) return '${(seconds / 3600).ceil()}h';
  return '${(seconds / 86400).ceil()}d';
}

String mcpServerFailureLabel({required String name, String? failureReason, String? error}) {
  final details = [failureReason, error]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return details.isEmpty ? name : '$name (${details.join(': ')})';
}
```

- [x] **Step 4: Run it to verify it passes**

Run: `flutter test test/feature/chat/logic/conversation_chrome_test.dart`
Expected: PASS.

- [x] **Step 5: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 446/446 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): port conversation chrome readouts"
```

---
