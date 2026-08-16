import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';

class PushRegistrar {
  const PushRegistrar(this._repository, this._store, this._tokens);

  final NotificationRepository _repository;
  final PushRegistrationStore _store;
  final PushTokenSource _tokens;

  Future<PushStatus> status() async {
    final permission = await _tokens.permissionStatus();
    final registration = await _store.load();
    return PushStatus(
      supported: permission.supported,
      granted: permission.granted,
      canAskAgain: permission.canAskAgain,
      registered: registration != null,
    );
  }

  Future<PushRegisterResult> register(ServerConfig? config, {required bool ask}) async {
    if (!hasServer(config)) return const PushNotRegistered(PushRegisterFailure.notPaired);
    if (!_tokens.supported) return const PushNotRegistered(PushRegisterFailure.unsupported);

    final permission = await _tokens.permissionStatus();
    final granted = permission.granted ||
        (ask && permission.canAskAgain && await _tokens.requestPermission());
    if (!granted) return const PushNotRegistered(PushRegisterFailure.denied);

    await _flushPending();

    final prior = await _store.load();
    if (prior != null && !prior.sameDaemon(config!)) {
      await _unregisterOrQueue(prior);
    }

    final token = await _tokens.getToken();
    if (token == null || token.isEmpty) {
      return const PushNotRegistered(PushRegisterFailure.notConfigured);
    }

    final result = await _repository.registerPushDevice(
      RegisterPushDeviceParams(
        token: token,
        platform: _tokens.platform,
        deviceName: await _tokens.deviceName(),
      ),
    );

    int? statusCode;
    var failed = false;
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) {
        failed = true;
        statusCode = failure.statusCode;
      },
    );
    if (failed) {
      return PushNotRegistered(classifyServerFailure(statusCode), statusCode: statusCode);
    }

    await _store.save(PushRegistration.of(token, config!));
    return PushRegistered(token);
  }

  /// Clears the active registration first: the device is disconnecting, so it is
  /// no longer registered regardless of whether the call below lands. The retry
  /// is tracked in the pending queue instead.
  Future<void> unregister() async {
    final registration = await _store.load();
    await _store.clear();
    if (registration == null) return;
    await _unregisterOrQueue(registration);
    await _flushPending();
  }

  Future<void> _unregisterOrQueue(PushRegistration registration) async {
    final result = await _repository.unregisterPushDevice(
      registration.token,
      target: registration.config,
    );
    var failed = false;
    result.when(onSuccess: (_) {}, onFailure: (_) => failed = true);
    if (failed) await _store.queuePending(registration);
  }

  Future<void> _flushPending() async {
    final queued = await _store.pending();
    if (queued.isEmpty) return;
    final stillPending = <PushRegistration>[];
    for (final registration in queued) {
      final result = await _repository.unregisterPushDevice(
        registration.token,
        target: registration.config,
      );
      result.when(onSuccess: (_) {}, onFailure: (_) => stillPending.add(registration));
    }
    await _store.savePending(stillPending);
  }
}
