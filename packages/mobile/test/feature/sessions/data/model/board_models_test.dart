import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/activity_string.dart';
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
}
