import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      (call) async => call.method == 'read' ? null : <String, String>{},
    );
    await sl.reset();
    await ServiceLocator.init();
    await sl<ServerConfigStore>().save(
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
    );
  });

  test('resolves the core singletons', () {
    expect(sl<ApiConsumer>(), isA<ApiConsumer>());
    expect(sl<ServerConfigStore>(), isA<ServerConfigStore>());
    expect(sl<NetworkStatus>(), isA<NetworkStatus>());
  });

  test('returns the same instance for lazy singletons', () {
    expect(identical(sl<ApiConsumer>(), sl<ApiConsumer>()), isTrue);
  });

  test('resolves the pairing and sessions singletons', () async {
    await sl<ServerConfigStore>().save(
      const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
    );
    expect(sl<PairingRepository>(), isA<PairingRepository>());
    expect(sl<SessionsRepository>(), isA<SessionsRepository>());
    expect(sl<MuxClient>(), isA<MuxClient>());
  });
}
