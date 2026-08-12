import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/logic/harness_logo.dart';

const _allHarnesses = [
  'claude-code', 'codex', 'aider', 'opencode', 'grok', 'droid', 'amp', 'agy',
  'crush', 'cursor', 'qwen', 'copilot', 'goose', 'auggie', 'continue', 'devin',
  'cline', 'kimi', 'muse', 'kiro', 'kilocode', 'vibe', 'pi', 'autohand', 'fake',
];
const _noAsset = ['fake'];

void main() {
  group('logo registry', () {
    test('has a mark for every harness that ships one', () {
      for (final h in _allHarnesses.where((h) => !_noAsset.contains(h))) {
        expect(hasLogo(h), isTrue, reason: h);
      }
    });

    test('has no mark for the harnesses that ship none', () {
      for (final h in _noAsset) {
        expect(hasLogo(h), isFalse, reason: h);
      }
    });

    test('does not claim a mark for an unknown harness', () {
      expect(hasLogo('some-new-agent'), isFalse);
      expect(hasLogo(null), isFalse);
      expect(hasLogo('  '), isFalse);
    });

    test('is case- and whitespace-insensitive', () {
      expect(hasLogo('Claude-Code'), isTrue);
      expect(hasLogo(' codex '), isTrue);
    });

    test('matches the asset directory exactly', () {
      final dir = Directory('assets/agents');
      final onDisk = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .where((name) => name.endsWith('.png'))
          .map((name) => name.substring(0, name.length - 4))
          .toList()
        ..sort();
      final expected = kLogoKeys.toList()..sort();
      expect(onDisk, expected);
    });
  });

  group('backdropFor', () {
    test('puts a dark chip behind marks that vanish on a light card', () {
      for (final h in ['opencode', 'cursor', 'cline', 'continue', 'grok', 'copilot']) {
        expect(backdropFor(h), BackdropPolarity.needsDark, reason: h);
      }
    });

    test('puts a light chip behind marks that vanish on a dark card', () {
      for (final h in ['kilocode', 'goose', 'devin', 'droid', 'pi', 'kimi']) {
        expect(backdropFor(h), BackdropPolarity.needsLight, reason: h);
      }
    });

    test('leaves colourful marks bare', () {
      for (final h in ['claude-code', 'codex', 'amp', 'qwen', 'vibe', 'aider', 'crush', 'muse', 'kiro']) {
        expect(backdropFor(h), BackdropPolarity.neutral, reason: h);
      }
    });

    test('treats an unknown or missing harness as neutral', () {
      expect(backdropFor('some-new-agent'), BackdropPolarity.neutral);
      expect(backdropFor(null), BackdropPolarity.neutral);
    });
  });

  group('harnessInitial', () {
    test('gives the uppercase initial', () {
      expect(harnessInitial('unknown-agent'), 'U');
      expect(harnessInitial('fake'), 'F');
    });

    test('falls back to a question mark rather than rendering nothing', () {
      expect(harnessInitial(''), '?');
      expect(harnessInitial('   '), '?');
      expect(harnessInitial(null), '?');
    });
  });
}
