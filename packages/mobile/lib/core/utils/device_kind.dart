import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

Future<bool> isPhysicalDevice() async {
  final plugin = DeviceInfoPlugin();
  try {
    if (Platform.isIOS) return (await plugin.iosInfo).isPhysicalDevice;
    if (Platform.isAndroid) return (await plugin.androidInfo).isPhysicalDevice;
    return false;
  } catch (_) {
    return false;
  }
}
