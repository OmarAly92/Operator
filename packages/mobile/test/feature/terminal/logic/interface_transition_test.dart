import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';

void main() {
  group('interfaceTransitionIsActive', () {
    test('covers every in-flight phase', () {
      for (final phase in const [
        'requested',
        'preflighting',
        'draining',
        'source_stopping',
        'source_stopped',
        'target_starting',
        'activating',
      ]) {
        expect(interfaceTransitionIsActive(phase), isTrue, reason: phase);
      }
    });

    test('is false once the transition settles, and for no transition at all', () {
      for (final phase in const ['completed', 'failed', 'cancelled', 'recovery_required']) {
        expect(interfaceTransitionIsActive(phase), isFalse, reason: phase);
      }
      expect(interfaceTransitionIsActive(null), isFalse);
      expect(interfaceTransitionIsActive('nonsense'), isFalse);
    });
  });

  group('interfaceTransitionIsCancellable', () {
    test('allows cancelling only before the source controller is stopped', () {
      expect(interfaceTransitionIsCancellable('requested'), isTrue);
      expect(interfaceTransitionIsCancellable('preflighting'), isTrue);
      expect(interfaceTransitionIsCancellable('draining'), isTrue);
      expect(interfaceTransitionIsCancellable('source_stopping'), isFalse);
      expect(interfaceTransitionIsCancellable('activating'), isFalse);
      expect(interfaceTransitionIsCancellable(null), isFalse);
    });
  });

  group('interfaceTransitionLabel', () {
    test('explains what is happening in each phase', () {
      expect(interfaceTransitionLabel('draining'), startsWith('Waiting for the current terminal turn'));
      expect(interfaceTransitionLabel('source_stopping'), startsWith('Stopping the terminal controller'));
      expect(interfaceTransitionLabel('source_stopped'), contains('worktree and native conversation are unchanged'));
      expect(interfaceTransitionLabel('target_starting'), startsWith('Resuming the same native conversation'));
      expect(interfaceTransitionLabel('activating'), 'Opening the Chat interface.');
    });

    test('falls back to the preflight sentence for an unknown or absent phase', () {
      const fallback = 'Checking that Chat can resume this agent\'s native conversation.';
      expect(interfaceTransitionLabel(null), fallback);
      expect(interfaceTransitionLabel('requested'), fallback);
      expect(interfaceTransitionLabel('nonsense'), fallback);
    });
  });
}
