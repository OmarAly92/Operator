import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

class _MockDataSource extends Mock implements TerminalRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockDataSource dataSource;
  late _MockNetworkStatus network;
  late TerminalRepositoryImp repository;

  const params = OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1');

  setUpAll(() {
    registerFallbackValue(params);
    registerFallbackValue(const SendSessionMessageParams(message: ''));
  });

  setUp(() {
    dataSource = _MockDataSource();
    network = _MockNetworkStatus();
    repository = TerminalRepositoryImp(dataSource, network);
    when(() => network.isConnected).thenAnswer((_) async => true);
  });

  group('openSessionShell', () {
    // Back → Open shell must land on the same process, not leak a new PTY on
    // every visit, so an existing session-scoped handle wins.
    test('reuses the handle already open for this session', () async {
      when(() => dataSource.getShellTerminals()).thenAnswer(
        (_) async => const GlobalResponse(
          data: [
            ShellTerminalModel(handleId: 'other', sessionId: 's-other'),
            ShellTerminalModel(handleId: 'mine', sessionId: 's-1'),
          ],
        ),
      );

      final result = await repository.openSessionShell(params);

      expect(result.isSuccess, isTrue);
      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'mine');
      verifyNever(() => dataSource.openShellTerminal(any()));
    });

    test('opens a new shell when the session has none', () async {
      when(() => dataSource.getShellTerminals())
          .thenAnswer((_) async => const GlobalResponse(data: []));
      when(() => dataSource.openShellTerminal(any())).thenAnswer(
        (_) async => const GlobalResponse(data: ShellTerminalModel(handleId: 'fresh')),
      );

      final result = await repository.openSessionShell(params);

      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'fresh');
      verify(() => dataSource.openShellTerminal(params)).called(1);
    });

    test('opens a new shell when the list call fails rather than giving up', () async {
      when(() => dataSource.getShellTerminals())
          .thenThrow(ServerFailure(error: 'x', message: 'boom', statusCode: 500));
      when(() => dataSource.openShellTerminal(any())).thenAnswer(
        (_) async => const GlobalResponse(data: ShellTerminalModel(handleId: 'fresh')),
      );

      final result = await repository.openSessionShell(params);

      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'fresh');
    });

    test('fails without touching the network when offline', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.openSessionShell(params);

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.getShellTerminals());
      verifyNever(() => dataSource.openShellTerminal(any()));
    });
  });

  group('sendSessionMessage', () {
    test('returns success when the daemon accepts it', () async {
      when(() => dataSource.sendSessionMessage(any(), any())).thenAnswer((_) async {});

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isSuccess, isTrue);
    });

    // The 409 code is the whole basis for rerouting to the PTY, so the failure
    // must arrive intact rather than flattened to a message.
    test('passes the daemon code through on failure', () async {
      when(() => dataSource.sendSessionMessage(any(), any())).thenThrow(
        ServerFailure(
          error: 'x',
          message: 'answer it in the session terminal first',
          statusCode: 409,
          apiStatus: 'SESSION_AWAITING_DECISION',
        ),
      );

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isFailure, isTrue);
      result.when(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (failure) => expect(failure.apiStatus, 'SESSION_AWAITING_DECISION'),
      );
    });

    test('fails offline without calling the data source', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.sendSessionMessage(any(), any()));
    });
  });

  group('closeShellTerminal', () {
    test('returns success', () async {
      when(() => dataSource.closeShellTerminal(any())).thenAnswer((_) async {});

      expect((await repository.closeShellTerminal('h-1')).isSuccess, isTrue);
    });

    test('fails offline without calling the data source', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      expect((await repository.closeShellTerminal('h-1')).isFailure, isTrue);
      verifyNever(() => dataSource.closeShellTerminal(any()));
    });
  });
}
