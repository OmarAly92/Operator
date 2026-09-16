import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

Future<void> forgetServer(DesktopsRepository desktops, ServerConfigStore store) async {
  try {
    await desktops.deactivate();
  } finally {
    store.clear();
  }
}
