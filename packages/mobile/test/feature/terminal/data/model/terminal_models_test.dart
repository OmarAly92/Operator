import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

void main() {
  group('ShellTerminalModel', () {
    test('parses a handle', () {
      final model = ShellTerminalModel.fromJson(const {
        'handleId': 'h-1',
        'projectId': 'p-1',
        'sessionId': 's-1',
        'workingDir': '/tmp/wt',
        'title': 'Worktree shell',
        'createdAt': '2026-08-14T10:00:00Z',
      });

      expect(model.handleId, 'h-1');
      expect(model.sessionId, 's-1');
      expect(model.title, 'Worktree shell');
    });

    test('tolerates a handle with nothing but an id', () {
      final model = ShellTerminalModel.fromJson(const {'handleId': 'h-1'});
      expect(model.handleId, 'h-1');
      expect(model.workingDir, isNull);
    });

    test('reads the list envelope, missing key included', () {
      expect(
        ShellTerminalModel.listFromJson(const {
          'shellTerminals': [
            {'handleId': 'h-1'},
            {'handleId': 'h-2'},
          ],
        }).map((shell) => shell.handleId).toList(),
        ['h-1', 'h-2'],
      );
      expect(ShellTerminalModel.listFromJson(const {}), isEmpty);
    });
  });

  group('params', () {
    test('serialize exactly the daemon\'s bodies', () {
      expect(
        const OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1').toJson(),
        {'projectId': 'p-1', 'sessionId': 's-1'},
      );
      expect(const SendSessionMessageParams(message: 'hi').toJson(), {'message': 'hi'});
    });
  });
}
