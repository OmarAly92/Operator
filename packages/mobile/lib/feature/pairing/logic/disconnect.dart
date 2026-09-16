import 'package:operator_mobile/core/api/server_config_store.dart';

Future<void> forgetServer(ServerConfigStore store) => store.clear();
