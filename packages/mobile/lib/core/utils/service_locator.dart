import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sl = GetIt.instance;

class ServiceLocator {
  static Future<void> init() async {
    await _coreSetup();
  }

  static Future<void> _coreSetup() async {
    final preferences = await SharedPreferences.getInstance();
    sl.registerLazySingleton<SharedPreferences>(() => preferences);
    sl.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());

    sl.registerLazySingleton<ServerConfigStore>(
      () => ServerConfigStore(sl<FlutterSecureStorage>(), sl<SharedPreferences>()),
    );
    sl.registerLazySingleton<ApiConsumer>(() => DioConsumer(sl<ServerConfigStore>()));
    sl.registerLazySingleton<NetworkStatus>(
      () => NetworkStatusImp(sl<ApiConsumer>(), sl<ServerConfigStore>()),
    );
  }
}
