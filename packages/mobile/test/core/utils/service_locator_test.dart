import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    await ServiceLocator.init();
  });

  test('resolves the core singletons', () {
    expect(sl<ApiConsumer>(), isA<ApiConsumer>());
    expect(sl<ServerConfigStore>(), isA<ServerConfigStore>());
    expect(sl<NetworkStatus>(), isA<NetworkStatus>());
  });

  test('returns the same instance for lazy singletons', () {
    expect(identical(sl<ApiConsumer>(), sl<ApiConsumer>()), isTrue);
  });
}
