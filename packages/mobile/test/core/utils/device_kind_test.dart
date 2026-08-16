import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/device_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPhysicalDevice', () {
    test('reports false when the platform plugin is unavailable', () async {
      expect(await isPhysicalDevice(), isFalse);
    });
  });
}
