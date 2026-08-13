import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/feature/orchestrator/logic/orchestrator_view.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';

OrchestratorModel link({String? id = 'proj-orchestrator', bool? hasRuntime, bool? isTerminal, String? status}) =>
    OrchestratorModel(
      id: id,
      projectId: 'proj',
      projectName: 'proj',
      status: status,
      hasRuntime: hasRuntime,
      isTerminal: isTerminal,
    );

SessionModel session({String id = 'proj-1', String projectId = 'proj', String? status}) =>
    SessionModel(id: id, projectId: projectId, status: status);

void main() {
  const dark = DarkSkin();
  const light = LightSkin();

  group('orchestratorStateOf', () {
    test('reports missing when there is no link at all', () {
      expect(orchestratorStateOf(null), OrchestratorState.missing);
      expect(orchestratorStateOf(link(id: '')), OrchestratorState.missing);
      expect(orchestratorStateOf(link(id: null)), OrchestratorState.missing);
    });

    test('reports stopped only when explicitly flagged', () {
      expect(orchestratorStateOf(link(hasRuntime: false)), OrchestratorState.stopped);
      expect(orchestratorStateOf(link(isTerminal: true)), OrchestratorState.stopped);
    });

    test('treats a link with neither flag as running', () {
      expect(orchestratorStateOf(link()), OrchestratorState.running);
    });
  });

  group('launchIntent', () {
    test('sends clean:true when restarting a running orchestrator', () {
      final intent = launchIntent(OrchestratorState.running);
      expect(intent.clean, isTrue);
      expect(intent.label.toLowerCase(), contains('restart'));
    });

    test('requires confirmation for the destructive path, and only that path', () {
      expect(launchIntent(OrchestratorState.running).confirm, isTrue);
      expect(launchIntent(OrchestratorState.stopped).confirm, isFalse);
      expect(launchIntent(OrchestratorState.missing).confirm, isFalse);
    });

    test('uses the cheap ensure when there is nothing live to retire', () {
      for (final state in [OrchestratorState.missing, OrchestratorState.stopped]) {
        expect(launchIntent(state).clean, isFalse, reason: state.name);
        expect(launchIntent(state).label.toLowerCase(), contains('start'), reason: state.name);
      }
    });
  });

  group('orchestratorStatus', () {
    test('names the two non-running states without inventing a status', () {
      expect(orchestratorStatus(dark, null).label, 'Not started');
      expect(orchestratorStatus(dark, link(isTerminal: true)).label, 'Stopped');
    });

    test('defers to the shared status vocabulary while running', () {
      expect(orchestratorStatus(dark, link(status: 'working')).label, 'Working');
      expect(orchestratorStatus(dark, link(status: 'needs_input')).label, 'Needs input');
    });

    test('falls back to Online when the daemon sent no status', () {
      expect(orchestratorStatus(dark, link()).label, 'Online');
    });

    test('takes its colours from the passed skin', () {
      expect(
        orchestratorStatus(light, link(status: 'working')).color,
        isNot(orchestratorStatus(dark, link(status: 'working')).color),
      );
    });

    test('only breathes for a live, working orchestrator', () {
      expect(orchestratorStatus(dark, link(status: 'working')).breathing, isTrue);
      expect(orchestratorStatus(dark, link(status: 'idle')).breathing, isFalse);
      expect(orchestratorStatus(dark, null).breathing, isFalse);
    });
  });

  group('workersOf', () {
    test('takes every session in the project', () {
      final all = [session(id: 'a'), session(id: 'b'), session(id: 'x', projectId: 'other')];
      expect(workersOf(all, 'proj', null).map((s) => s.id), ['a', 'b']);
    });

    test('never counts the orchestrator as one of its own workers', () {
      final all = [session(id: 'proj-orchestrator'), session(id: 'a')];
      expect(workersOf(all, 'proj', link()).map((s) => s.id), ['a']);
    });
  });

  group('zoneCounts', () {
    test('buckets by attention zone', () {
      final counts = zoneCounts([
        session(status: 'working'),
        session(status: 'working'),
        session(status: 'needs_input'),
      ]);
      expect(counts[AttentionLevel.working], 2);
      expect(counts[AttentionLevel.respond], 1);
    });

    test('is empty for no sessions', () {
      expect(zoneCounts([]), isEmpty);
    });
  });
}
