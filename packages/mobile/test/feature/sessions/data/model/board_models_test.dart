import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';

void main() {
  group('activityString', () {
    test('accepts a bare string', () {
      expect(activityString('editing'), 'editing');
    });

    test('reads the state out of an object', () {
      expect(activityString({'state': 'blocked'}), 'blocked');
    });

    test('treats empty and unknown shapes as absent', () {
      expect(activityString(''), isNull);
      expect(activityString({'state': ''}), isNull);
      expect(activityString(null), isNull);
      expect(activityString(7), isNull);
    });
  });

  group('ProjectModel', () {
    test('parses the fields the picker renders', () {
      final project = ProjectModel.fromJson({
        'id': 'my-app_98d163a851',
        'name': 'My App',
        'kind': 'single_repo',
        'sessionPrefix': 'ma',
      });
      expect(project.id, 'my-app_98d163a851');
      expect(project.name, 'My App');
      expect(project.kind, 'single_repo');
      expect(project.sessionPrefix, 'ma');
    });

    test('drops a kind the app does not know', () {
      expect(ProjectModel.fromJson({'id': 'a', 'kind': 'something_new'}).kind, isNull);
      expect(ProjectModel.fromJson({'id': 'a'}).kind, isNull);
    });

    test('keeps every kind the app does know', () {
      for (final kind in ['single_repo', 'workspace', 'scratch']) {
        expect(ProjectModel.fromJson({'id': 'a', 'kind': kind}).kind, kind);
      }
    });
  });

  group('OrchestratorModel', () {
    test('derives both lifecycle flags from isTerminated', () {
      final live = OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'});
      expect(live.hasRuntime, isTrue);
      expect(live.isTerminal, isFalse);

      final dead = OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p', 'isTerminated': true});
      expect(dead.hasRuntime, isFalse);
      expect(dead.isTerminal, isTrue);
    });

    test('takes the project name from the caller and falls back to the id', () {
      expect(
        OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'}, projectName: 'My App').projectName,
        'My App',
      );
      expect(OrchestratorModel.fromJson({'id': 'o1', 'projectId': 'p'}).projectName, 'p');
    });

    test('narrows mode to chat or tui', () {
      expect(OrchestratorModel.fromJson({'id': 'o', 'mode': 'chat'}).mode, 'chat');
      expect(OrchestratorModel.fromJson({'id': 'o', 'mode': 'tui'}).mode, 'tui');
      expect(OrchestratorModel.fromJson({'id': 'o'}).mode, 'tui');
    });

    test('unwraps an object-shaped activity', () {
      expect(
        OrchestratorModel.fromJson({'id': 'o', 'activity': {'state': 'blocked'}}).activity,
        'blocked',
      );
    });
  });
}
