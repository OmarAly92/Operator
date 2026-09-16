import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockStore extends Mock implements ServerConfigStore {}

const _a = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: false);
const _b = DesktopModel(id: 'b', name: 'iMac', host: '10.0.0.6', port: '3011', secure: false, isActive: false);
const _config = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'pw');

void main() {
  late _MockDesktops desktops;
  late _MockRemote remote;
  late _MockStore store;
  late StreamController<List<DesktopModel>> list;

  setUpAll(() {
    registerFallbackValue(_config);
    registerFallbackValue(const RenameDesktopParams(id: '', name: ''));
  });

  setUp(() {
    desktops = _MockDesktops();
    remote = _MockRemote();
    store = _MockStore();
    list = StreamController<List<DesktopModel>>.broadcast();
    when(() => desktops.watchDesktops()).thenAnswer((_) => list.stream);
  });

  tearDown(() => list.close());

  ConnectionsCubit build() => ConnectionsCubit(desktops, remote, store);

  blocTest<ConnectionsCubit, ConnectionsState>(
    'mirrors the repository stream into desktops',
    build: build,
    act: (_) => list.add([_a, _b]),
    expect: () => [
      const DesktopsUpdatedState([_a, _b]),
    ],
    verify: (cubit) => expect(cubit.desktops, [_a, _b]),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'connectTo identifies with the stored password, activates, sets the store',
    build: build,
    setUp: () {
      when(() => desktops.passwordFor('a')).thenAnswer((_) async => Result.success('pw'));
      when(() => remote.identify(_config)).thenAnswer((_) async => const DesktopIdentityModel(name: 'Mac'));
      when(() => desktops.activate('a')).thenAnswer((_) async => Result.success(null));
    },
    seed: () => const DesktopsUpdatedState([_a]),
    act: (cubit) {
      cubit.desktops = [_a];
      return cubit.connectTo('a', TargetPlatform.iOS);
    },
    expect: () => [const ConnectLoadingState('a'), const ConnectSuccessState('a')],
    verify: (_) => verifyInOrder([
      () => remote.identify(_config),
      () => desktops.activate('a'),
      () => store.set(_config),
    ]),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'a 401 surfaces the rotated-password copy on that row',
    build: build,
    setUp: () {
      when(() => desktops.passwordFor('a')).thenAnswer((_) async => Result.success('pw'));
      when(() => remote.identify(any())).thenThrow(
        ServerFailure<Map<String, dynamic>>(error: 'x', message: 'bad', statusCode: 401),
      );
    },
    act: (cubit) {
      cubit.desktops = [_a];
      return cubit.connectTo('a', TargetPlatform.iOS);
    },
    expect: () => [
      const ConnectLoadingState('a'),
      isA<ConnectFailureState>().having((s) => s.copy.title, 'title', 'Your desktop rejected the password'),
    ],
    verify: (cubit) {
      expect(cubit.errors['a'], isNotNull);
      verifyNever(() => desktops.activate(any()));
      verifyNever(() => store.set(any()));
    },
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'removing the active desktop clears the store; removing the last one signals it',
    build: build,
    setUp: () {
      when(() => desktops.remove('a')).thenAnswer((_) async => Result.success(null));
    },
    act: (cubit) async {
      cubit.desktops = [_a.copyWithActive(true)];
      await cubit.remove('a');
      list.add(const []);
    },
    expect: () => [const DesktopsUpdatedState([]), const LastDesktopRemovedState()],
    verify: (_) => verify(() => store.clear()).called(1),
  );

  blocTest<ConnectionsCubit, ConnectionsState>(
    'rename forwards to the repository',
    build: build,
    setUp: () => when(() => desktops.rename(any())).thenAnswer((_) async => Result.success(null)),
    act: (cubit) => cubit.rename('a', 'Studio'),
    expect: () => <ConnectionsState>[],
    verify: (_) {
      final params = verify(() => desktops.rename(captureAny())).captured.single as RenameDesktopParams;
      expect(params.name, 'Studio');
    },
  );
}
