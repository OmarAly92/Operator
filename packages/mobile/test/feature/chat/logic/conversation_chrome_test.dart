import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';

void main() {
  group('mobile Chat conversation chrome', () {
    test('uses the same context thresholds and visible minimum as desktop', () {
      final low = contextReadout(
        contextUsed: 1,
        contextWindow: 1000,
        totalTokens: 1,
      )!;
      expect(low.percent, 0);
      expect(low.fillPercent, 2);
      expect(low.severity, Severity.normal);

      expect(
        contextReadout(
          contextUsed: 70,
          contextWindow: 100,
          totalTokens: 70,
        )?.severity,
        Severity.warn,
      );
      expect(
        contextReadout(
          contextUsed: 900,
          contextWindow: 1000,
          totalTokens: 900,
        )?.severity,
        Severity.critical,
      );
    });

    test('falls back to total tokens when no window is reported', () {
      final unbounded = contextReadout(
        contextUsed: 0,
        contextWindow: 0,
        totalTokens: 4200,
      )!;
      expect(unbounded.percent, isNull);
      expect(unbounded.tokens, 4200);
      expect(unbounded.severity, Severity.normal);
      expect(
        contextReadout(
          contextUsed: null,
          contextWindow: null,
          totalTokens: null,
        ),
        isNull,
      );
    });

    test(
      'warns on the tighter reported quota window and ignores absent ones',
      () {
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

        expect(
          quotaWarning(primaryUsedPercent: 40, secondaryUsedPercent: -1),
          isNull,
        );
        expect(
          quotaWarning(
            primaryUsedPercent: 91,
            secondaryUsedPercent: 80,
          )?.severity,
          Severity.critical,
        );
        expect(
          quotaWarning(primaryUsedPercent: null, secondaryUsedPercent: null),
          isNull,
        );
      },
    );

    test(
      'formats live turn and reset durations without wall-clock assumptions',
      () {
        expect(
          elapsedLabel(
            '2026-08-05T00:00:00Z',
            DateTime.parse('2026-08-05T00:02:03Z').millisecondsSinceEpoch,
          ),
          '2m 3s',
        );
        expect(
          elapsedLabel(
            '2026-08-05T00:00:00Z',
            DateTime.parse('2026-08-05T01:05:00Z').millisecondsSinceEpoch,
          ),
          '1h 5m',
        );
        expect(elapsedLabel(null, 0), isNull);
        expect(elapsedLabel('not a date', 0), isNull);
        expect(resetLabel(172800), '2d');
        expect(resetLabel(90), '2m');
        expect(resetLabel(null), isNull);
        expect(resetLabel(-1), isNull);
      },
    );

    test('keeps both the MCP failure class and provider diagnostic', () {
      expect(
        mcpServerFailureLabel(
          name: 'github',
          failureReason: 'auth',
          error: 'token expired',
        ),
        'github (auth: token expired)',
      );
      expect(mcpServerFailureLabel(name: 'github'), 'github');
    });
  });
}
