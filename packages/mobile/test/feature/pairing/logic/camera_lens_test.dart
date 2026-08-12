import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/camera_lens.dart';

void main() {
  const triple = ['Back Camera', 'Back Dual Wide Camera', 'Back Telephoto Camera', 'Back Triple Camera', 'Back Ultra Wide Camera'];

  group('pickNormalLens', () {
    test('picks the plain 1x lens over the ultra-wide and the virtual devices', () {
      expect(pickNormalLens(triple), kNormalLens);
    });

    test('picks it on a dual-camera phone too', () {
      expect(pickNormalLens(['Back Camera', 'Back Dual Wide Camera', 'Back Ultra Wide Camera']), kNormalLens);
    });

    test('picks it on a single-camera phone', () {
      expect(pickNormalLens(['Back Camera']), kNormalLens);
    });

    test('returns null for an empty list', () {
      expect(pickNormalLens(const []), isNull);
    });

    test('returns null when every lens is a specialised optic', () {
      expect(pickNormalLens(['Back Ultra Wide Camera', 'Back Triple Camera']), isNull);
    });

    group('non-English devices, where the exact name will not match', () {
      test('prefers the unqualified lens by name length', () {
        final german = ['Rückkamera', 'Ultraweitwinkel-Rückkamera', 'Tele-Rückkamera'];
        expect(pickNormalLens(german), 'Rückkamera');
      });

      test('still drops virtual devices in other locales', () {
        final fr = ['Appareil arrière', 'Appareil arrière triple', 'Appareil arrière ultra grand-angle'];
        expect(pickNormalLens(fr), 'Appareil arrière');
      });
    });
  });
}
