import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';

Future<void> forgetServer(ServerConfigStore store) async {
  try {
    await store.clear();
  } finally {
    await CacheHelper.remove(CacheKeys.onboardingSkipped);
  }
}
