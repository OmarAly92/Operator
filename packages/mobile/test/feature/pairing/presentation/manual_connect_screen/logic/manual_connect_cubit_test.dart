import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: ''));
  });

  late _MockPairingRepository repository;
  late _MockServerConfigStore store;

  setUp(() {
    repository = _MockPairingRepository();
    store = _MockServerConfigStore();
  });

  blocTest<ManualConnectCubit, ManualConnectState>(
    'prefills from the currently-paired config',
    build: () {
      when(() => store.current).thenReturn(
        const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: true, password: 'secret12'),
      );
      return ManualConnectCubit(repository, store);
    },
    verify: (cubit) {
      expect(cubit.hostController.text, '10.0.0.5');
      expect(cubit.portController.text, '3011');
      expect(cubit.passwordController.text, 'secret12');
      expect(cubit.secure, isTrue);
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'defaults to port 3011 and secure off with nothing paired',
    build: () {
      when(() => store.current).thenReturn(null);
      return ManualConnectCubit(repository, store);
    },
    verify: (cubit) {
      expect(cubit.portController.text, '3011');
      expect(cubit.secure, isFalse);
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'trims the host and verifies before emitting success',
    build: () {
      when(() => store.current).thenReturn(null);
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return ManualConnectCubit(repository, store);
    },
    act: (cubit) {
      cubit.hostController.text = '  10.0.0.9  ';
      cubit.portController.text = '3011';
      return cubit.connect(TargetPlatform.iOS);
    },
    expect: () => [isA<ConnectLoadingState>(), isA<ConnectSuccessState>()],
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured;
      expect((captured.single as ServerConfig).host, '10.0.0.9');
    },
  );

  blocTest<ManualConnectCubit, ManualConnectState>(
    'emits a connection-failure copy when verification fails',
    build: () {
      when(() => store.current).thenReturn(null);
      when(() => repository.verifyAndConnect(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
      );
      return ManualConnectCubit(repository, store);
    },
    act: (cubit) {
      cubit.hostController.text = '10.0.0.9';
      cubit.portController.text = '3011';
      return cubit.connect(TargetPlatform.iOS);
    },
    expect: () => [isA<ConnectLoadingState>(), isA<ConnectFailureState>()],
  );
}
