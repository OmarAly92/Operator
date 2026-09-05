import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/logic/context_readout.dart';

void main() {
  test('shows a bare token count when the window is unknown', () {
    final readout = ContextReadout.of(
      const SessionContextModel(used: 64880, window: 0),
    )!;
    expect(readout.label, '64.9k tokens');
    expect(readout.percentLabel, isNull);
    expect(readout.fraction, isNull);
    expect(readout.severity, ContextSeverity.normal);
  });

  test('shows a percentage when the window is known', () {
    final readout = ContextReadout.of(
      const SessionContextModel(used: 25000, window: 200000),
    )!;
    expect(readout.percentLabel, '13%');
    expect(readout.fraction, closeTo(0.125, 0.0001));
    expect(readout.severity, ContextSeverity.normal);
  });

  test('escalates at the desktop thresholds', () {
    expect(
      ContextReadout.of(
        const SessionContextModel(used: 70, window: 100),
      )!.severity,
      ContextSeverity.warn,
    );
    expect(
      ContextReadout.of(
        const SessionContextModel(used: 90, window: 100),
      )!.severity,
      ContextSeverity.critical,
    );
    expect(
      ContextReadout.of(
        const SessionContextModel(used: 69, window: 100),
      )!.severity,
      ContextSeverity.normal,
    );
  });

  test('renders nothing when there is no observation', () {
    expect(ContextReadout.of(null), isNull);
    expect(ContextReadout.of(const SessionContextModel()), isNull);
  });
}
