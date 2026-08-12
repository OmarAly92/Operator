import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';

const _skin = DarkSkin();

void main() {
  group('statusVisual', () {
    test('marks a working session as breathing', () {
      final v = statusVisual(_skin, 'working');
      expect(v.label, 'Working');
      expect(v.color, _skin.orange);
      expect(v.breathing, isTrue);
    });

    test('marks needs_input distinctly from working', () {
      final v = statusVisual(_skin, 'needs_input');
      expect(v.label, 'Needs input');
      expect(v.color, _skin.amber);
      expect(v.breathing, isFalse);
    });

    test('marks a killed or terminated session as terminated', () {
      expect(statusVisual(_skin, 'killed').label, 'Terminated');
      expect(statusVisual(_skin, 'terminated').label, 'Terminated');
      expect(statusVisual(_skin, 'killed').color, _skin.textFaint);
    });

    test('marks merged as done and green', () {
      final v = statusVisual(_skin, 'merged');
      expect(v.label, 'Merged');
      expect(v.color, _skin.green);
    });

    test('falls back to the raw status string for an unrecognised value', () {
      expect(statusVisual(_skin, 'made_up_status').label, 'made_up_status');
      expect(statusVisual(_skin, null).label, 'unknown');
    });
  });
}
