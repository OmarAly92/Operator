import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';

class _MockRepository extends Mock implements NotificationRepository {}

class _MemorySecureStorage implements PushSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeTokenSource implements PushTokenSource {
  _FakeTokenSource({this.token = 't-new', this.granted = true, this.supported = true});

  String? token;
  bool granted;

  @override
  final bool supported;

  @override
  String get platform => 'ios';

  @override
  Future<String?> deviceName() async => 'iPhone';

  @override
  Future<String?> getToken() async => token;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<PushStatus> permissionStatus() async => PushStatus(
    supported: supported,
    granted: granted,
    canAskAgain: true,
    registered: false,
  );
}

const ServerConfig current = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

const ServerConfig other = ServerConfig(
  host: '10.0.0.9',
  httpPort: '3011',
  secure: false,
  password: 'other-secret',
);

const PushRegistration oldRegistration = PushRegistration(
  token: 't-old',
  host: '10.0.0.9',
  httpPort: '3011',
  secure: false,
  password: 'other-secret',
);

void main() {
  late _MockRepository repository;
  late _MemorySecureStorage storage;
  late PushRegistrationStore store;

  setUpAll(() {
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
    registerFallbackValue(current);
  });

  setUp(() {
    repository = _MockRepository();
    storage = _MemorySecureStorage();
    store = PushRegistrationStore(storage);
    when(() => repository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    when(() => repository.unregisterPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
  });

  PushRegistrar registrar({PushTokenSource? tokens}) =>
      PushRegistrar(repository, store, tokens ?? _FakeTokenSource());

  test('refuses to spend the permission prompt when no daemon is paired', () async {
    final result = await registrar().register(null, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.notPaired));
    verifyNever(() => repository.registerPushDevice(any(), target: any(named: 'target')));
  });

  test('reports unsupported before asking for anything on a device that cannot push', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(supported: false),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.unsupported));
  });

  test('reports denied when permission is refused', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(granted: false),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.denied));
  });

  test('reports notConfigured when the build cannot mint a token', () async {
    final result = await registrar(
      tokens: _FakeTokenSource(token: null),
    ).register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.notConfigured));
  });

  test('registers the token and persists the daemon it registered with', () async {
    final result = await registrar().register(current, ask: true);

    expect(result, const PushRegistered('t-new'));
    final saved = await store.load();
    expect(saved!.token, 't-new');
    expect(saved.host, '10.0.0.5');
    expect(saved.password, 'secret12');
    final captured = verify(
      () => repository.registerPushDevice(captureAny(), target: any(named: 'target')),
    ).captured.single as RegisterPushDeviceParams;
    expect(captured.toJson(), {'token': 't-new', 'platform': 'ios', 'deviceName': 'iPhone'});
  });

  test('unregisters from the previous daemon before registering with a new one', () async {
    await storage.write(kPushRegistrationKey, jsonEncode(oldRegistration.toJson()));

    await registrar().register(current, ask: true);

    verify(() => repository.unregisterPushDevice('t-old', target: oldRegistration.config))
        .called(1);
  });

  test('does not unregister when the daemon has not changed', () async {
    await registrar().register(current, ask: true);
    clearInteractions(repository);

    await registrar().register(current, ask: true);

    verifyNever(() => repository.unregisterPushDevice(any(), target: any(named: 'target')));
  });

  test('queues an unregister the old daemon refused, and retries it on the next register',
      () async {
    await storage.write(kPushRegistrationKey, jsonEncode(oldRegistration.toJson()));
    when(() => repository.unregisterPushDevice('t-old', target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: -6)),
    );

    await registrar().register(current, ask: true);
    expect((await store.pending()).single.token, 't-old');

    when(() => repository.unregisterPushDevice('t-old', target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    await registrar().register(other, ask: true);

    expect(await store.pending(), isEmpty);
  });

  test('classifies a daemon rejection instead of blaming the build', () async {
    when(() => repository.registerPushDevice(any(), target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 401)),
    );

    final result = await registrar().register(current, ask: true);

    expect(result, const PushNotRegistered(PushRegisterFailure.serverAuth, statusCode: 401));
    expect(await store.load(), isNull);
  });

  test('unregistering clears the active registration even when the daemon is unreachable',
      () async {
    await registrar().register(current, ask: true);
    when(() => repository.unregisterPushDevice(any(), target: any(named: 'target'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: -6)),
    );

    await registrar().unregister();

    expect(await store.load(), isNull);
    expect((await store.pending()).single.token, 't-new');
  });

  // A permanently dead daemon must not grow the queue forever, but the cap has
  // to keep the NEWEST entries: those are the daemons most likely still able to
  // push to this device.
  test('the pending queue keeps the newest entries when it overflows', () async {
    for (var i = 0; i < kMaxPendingUnregister + 3; i++) {
      await store.queuePending(
        PushRegistration(
          token: 't-$i',
          host: '10.0.0.$i',
          httpPort: '3011',
          secure: false,
          password: 'p',
        ),
      );
    }

    final queued = await store.pending();

    expect(queued, hasLength(kMaxPendingUnregister));
    expect(queued.first.token, 't-3');
    expect(queued.last.token, 't-${kMaxPendingUnregister + 2}');
  });
}
