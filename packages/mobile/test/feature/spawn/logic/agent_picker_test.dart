import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

AgentInfo agent(String id, {String? label, String? authStatus}) =>
    AgentInfo(id: id, label: label ?? id, authStatus: authStatus);

AgentCatalog catalog({
  List<AgentInfo> supported = const [],
  List<AgentInfo> installed = const [],
  List<AgentInfo> authorized = const [],
}) => AgentCatalog(supported: supported, installed: installed, authorized: authorized);

void main() {
  group('availabilityOf', () {
    test('reports an agent that is installed and authorized', () {
      final c = catalog(installed: [agent('codex')], authorized: [agent('codex')]);
      expect(availabilityOf(agent('codex'), c), AgentAvailability.authorized);
    });

    test('accepts authStatus as proof of authorization', () {
      final c = catalog(installed: [agent('codex', label: 'Codex', authStatus: 'authorized')]);
      expect(availabilityOf(agent('codex'), c), AgentAvailability.authorized);
    });

    test('reports a missing install', () {
      expect(availabilityOf(agent('goose'), catalog()), AgentAvailability.needsInstall);
    });

    test('reports an explicit refusal as needing auth', () {
      final c = catalog(installed: [agent('cursor', authStatus: 'unauthorized')]);
      expect(availabilityOf(agent('cursor'), c), AgentAvailability.needsAuth);
    });

    test('treats an absent or unknown authStatus as unknown, not unauthorized', () {
      expect(availabilityOf(agent('amp'), catalog(installed: [agent('amp')])),
          AgentAvailability.authUnknown);
      expect(
        availabilityOf(agent('amp'), catalog(installed: [agent('amp', authStatus: 'unknown')])),
        AgentAvailability.authUnknown,
      );
    });
  });

  group('isSelectable', () {
    test('allows an agent whose auth state is unknown', () {
      expect(isSelectable(AgentAvailability.authUnknown), isTrue);
    });

    test('allows an authorized agent', () {
      expect(isSelectable(AgentAvailability.authorized), isTrue);
    });

    test('refuses an uninstalled or explicitly unauthorized agent', () {
      expect(isSelectable(AgentAvailability.needsAuth), isFalse);
      expect(isSelectable(AgentAvailability.needsInstall), isFalse);
    });
  });

  group('statusLabel', () {
    test('says nothing about a healthy agent', () {
      expect(statusLabel(AgentAvailability.authorized), '');
    });

    test('names each problem', () {
      expect(statusLabel(AgentAvailability.authUnknown), 'Auth unknown');
      expect(statusLabel(AgentAvailability.needsAuth), 'Needs auth');
      expect(statusLabel(AgentAvailability.needsInstall), 'Needs install');
    });
  });

  group('rankAgents', () {
    test('orders usable agents above unusable ones', () {
      final c = catalog(
        supported: [agent('goose'), agent('cursor'), agent('amp'), agent('codex')],
        installed: [agent('codex'), agent('cursor', authStatus: 'unauthorized'), agent('amp')],
        authorized: [agent('codex')],
      );
      expect(rankAgents(c).map((a) => a.id), ['codex', 'amp', 'cursor', 'goose']);
    });

    test('breaks ties by priority, not alphabetically', () {
      const ids = ['aider', 'claude-code', 'codex'];
      final c = catalog(
        supported: ids.map(agent).toList(),
        installed: ids.map(agent).toList(),
        authorized: ids.map(agent).toList(),
      );
      expect(rankAgents(c).map((a) => a.id), ['claude-code', 'codex', 'aider']);
    });

    test('falls back to the label for agents outside the priority list', () {
      const ids = ['zed', 'kiro', 'droid'];
      final c = catalog(
        supported: ids.map(agent).toList(),
        installed: ids.map(agent).toList(),
        authorized: ids.map(agent).toList(),
      );
      expect(rankAgents(c).map((a) => a.id), ['droid', 'kiro', 'zed']);
    });

    test('carries the status and selectability onto each row', () {
      final ranked = rankAgents(catalog(supported: [agent('goose')])).single;
      expect(ranked.status, 'Needs install');
      expect(ranked.selectable, isFalse);
    });

    test('returns nothing for an absent catalog', () {
      expect(rankAgents(null), isEmpty);
      expect(rankAgents(catalog()), isEmpty);
    });
  });

  group('defaultAgent', () {
    test('preselects the best usable agent', () {
      final c = catalog(
        supported: [agent('goose'), agent('codex')],
        installed: [agent('codex')],
        authorized: [agent('codex')],
      );
      expect(defaultAgent(rankAgents(c)), 'codex');
    });

    test('preselects nothing when no agent is usable', () {
      final c = catalog(supported: [agent('goose'), agent('aider')]);
      expect(defaultAgent(rankAgents(c)), isNull);
    });
  });
}
