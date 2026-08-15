import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

void main() {
  late _MockApiConsumer apiConsumer;
  late TerminalRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = TerminalRemoteDataSourceImp(apiConsumer);
  });

  test('lists shell terminals', () async {
    when(() => apiConsumer.get(any())).thenAnswer(
      (_) async => _response({
        'shellTerminals': [
          {'handleId': 'h-1', 'sessionId': 's-1'},
        ],
      }),
    );

    final shells = (await dataSource.getShellTerminals()).data!;

    expect(shells.single.handleId, 'h-1');
    verify(() => apiConsumer.get(EndPoints.shellTerminals)).called(1);
  });

  test('opens a shell with the project and session in the body', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _response({
        'shellTerminal': {'handleId': 'h-9', 'title': 'Worktree shell'},
      }),
    );

    final shell = (await dataSource.openShellTerminal(
      const OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1'),
    )).data!;

    expect(shell.handleId, 'h-9');
    final captured = verify(
      () => apiConsumer.post(EndPoints.shellTerminals, body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'projectId': 'p-1', 'sessionId': 's-1'});
  });

  test('closes a shell by handle', () async {
    when(() => apiConsumer.delete(any())).thenAnswer((_) async => _response(null));

    await dataSource.closeShellTerminal('h-9');

    verify(() => apiConsumer.delete(EndPoints.shellTerminal('h-9'))).called(1);
  });

  test('sends a message to the harness route, not the conversation route', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => _response(null));

    await dataSource.sendSessionMessage('s-1', const SendSessionMessageParams(message: 'go'));

    final captured = verify(
      () => apiConsumer.post(EndPoints.sessionSend('s-1'), body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'message': 'go'});
  });

  test('reads the interface-transition status', () async {
    when(() => apiConsumer.get(any())).thenAnswer(
      (_) async => _response({
        'supported': true,
        'targetMode': 'chat',
        'transition': {'id': 't-1', 'phase': 'draining'},
      }),
    );

    final status = (await dataSource.getInterfaceTransition('s-1')).data!;

    expect(status.supported, isTrue);
    expect(status.transition?.phase, 'draining');
    verify(() => apiConsumer.get(EndPoints.sessionInterfaceTransition('s-1'))).called(1);
  });

  test('starts a transition and unwraps the transition envelope', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _response({
        'transition': {'id': 't-2', 'phase': 'requested'},
      }),
    );

    final transition = (await dataSource.startInterfaceTransition(
      's-1',
      const StartInterfaceTransitionParams(targetMode: 'chat', policy: 'drain'),
    )).data!;

    expect(transition.id, 't-2');
    final captured = verify(
      () => apiConsumer.post(
        EndPoints.sessionInterfaceTransition('s-1'),
        body: captureAny(named: 'body'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'targetMode': 'chat', 'policy': 'drain'});
  });

  test('cancels a transition', () async {
    when(() => apiConsumer.delete(any())).thenAnswer((_) async => _response(null));

    await dataSource.cancelInterfaceTransition('s-1');

    verify(() => apiConsumer.delete(EndPoints.sessionInterfaceTransition('s-1'))).called(1);
  });
}
