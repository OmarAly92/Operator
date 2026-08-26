import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_scroll.dart';

void main() {
  group('scrollActionFor', () {
    test('routes a keyboard-scroll agent to page keys even with mouse tracking', () {
      expect(
        scrollActionFor(paneScrollsByKeyboard: true, mouseTracking: true, altBuffer: true),
        TerminalScrollAction.pageKeys,
      );
    });

    test('scrolls a plain shell locally', () {
      expect(
        scrollActionFor(paneScrollsByKeyboard: false, mouseTracking: false, altBuffer: false),
        TerminalScrollAction.localBuffer,
      );
    });

    test('reports the wheel to a mouse-tracking pane', () {
      expect(
        scrollActionFor(paneScrollsByKeyboard: false, mouseTracking: true, altBuffer: true),
        TerminalScrollAction.mouseReport,
      );
    });

    test('falls back to page keys in an alt buffer with no mouse tracking', () {
      expect(
        scrollActionFor(paneScrollsByKeyboard: false, mouseTracking: false, altBuffer: true),
        TerminalScrollAction.pageKeys,
      );
    });
  });

  group('sgrWheelReport', () {
    test('encodes wheel up as button 64 with no modifier bits', () {
      expect(sgrWheelReport(up: true), '\x1b[<64;1;1M');
    });

    test('encodes wheel down as button 65', () {
      expect(sgrWheelReport(up: false), '\x1b[<65;1;1M');
    });
  });

  group('pageKeyReport', () {
    test('pages up when scrolling toward older output', () {
      expect(pageKeyReport(up: true), '\x1b[5~');
    });

    test('pages down when scrolling toward newer output', () {
      expect(pageKeyReport(up: false), '\x1b[6~');
    });
  });

  group('WheelDivider', () {
    test('emits one report per tmux wheel step so the finger tracks 1:1', () {
      final divider = WheelDivider(step: kTmuxWheelLines);
      final emitted = [
        for (var i = 0; i < kTmuxWheelLines; i++) divider.consume(up: true),
      ];
      expect(emitted, [false, false, false, false, true]);
    });

    test('keeps the remainder so a slow drag still scrolls eventually', () {
      final divider = WheelDivider(step: 5);
      divider.consume(up: true);
      divider.consume(up: true);
      divider.consume(up: true);
      divider.consume(up: true);
      expect(divider.consume(up: true), isTrue);
      expect(divider.consume(up: true), isFalse);
    });

    test('resets the remainder when the drag reverses direction', () {
      final divider = WheelDivider(step: 5);
      divider.consume(up: true);
      divider.consume(up: true);
      divider.consume(up: true);
      divider.consume(up: true);
      expect(divider.consume(up: false), isFalse);
    });
  });
}
