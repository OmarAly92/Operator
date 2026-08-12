import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';

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
    when(() => store.current).thenReturn(null);
  });

  blocTest<PairingScanCubit, PairingScanState>(
    'rejects a non-Operator QR code without calling the repository',
    build: () => PairingScanCubit(repository, store, fromOnboarding: false),
    act: (cubit) => cubit.onScan('not json', TargetPlatform.iOS),
    expect: () => [isA<VerifyFailureState>()],
    verify: (_) => verifyNever(() => repository.verifyAndConnect(any())),
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'verifies a valid payload and emits success',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}', TargetPlatform.iOS),
    expect: () => [isA<VerifyLoadingState>(), isA<VerifySuccessState>()],
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'carries over the currently-paired password when the QR omits one',
    build: () {
      when(() => store.current).thenReturn(
        const ServerConfig(host: 'old-host', httpPort: '3011', secure: true, password: 'old-pass'),
      );
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011"}', TargetPlatform.iOS),
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured;
      final target = captured.single as ServerConfig;
      expect(target.password, 'old-pass');
      expect(target.secure, isTrue);
    },
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'emits a failure copy and allows retrying after a rejected password',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
      );
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) async {
      await cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"wrong"}', TargetPlatform.iOS);
      await cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"right"}', TargetPlatform.iOS);
    },
    verify: (_) => verify(() => repository.verifyAndConnect(any())).called(2),
  );
}
