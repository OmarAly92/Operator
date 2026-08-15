import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_zoom.dart';

void main() {
  const box = TerminalZoomBox(content: Size(800, 1200), view: Size(400, 600));
  const minScale = 0.5;
  const overview = TerminalZoom(scale: minScale);

  test('the overview is not zoomed; anything above it is', () {
    expect(overview.isZoomed(minScale), isFalse);
    expect(const TerminalZoom(scale: 0.9).isZoomed(minScale), isTrue);
  });

  group('scaleAround', () {
    test('keeps the content under the focal point fixed', () {
      final zoomed = scaleAround(
        overview,
        scale: 1,
        focal: const Offset(200, 300),
        box: box,
        minScale: minScale,
      );

      expect(zoomed.scale, 1);
      // The point under (200,300) was content (400,600) at 0.5; at 1:1 it must
      // still land on (200,300), so the offset is 200-400 = -200.
      expect(zoomed.dx, -200);
      expect(zoomed.dy, -300);
    });

    test('clamps to the fit scale and snaps back to a flush overview', () {
      final out = scaleAround(
        const TerminalZoom(scale: 1, dx: -200, dy: -300),
        scale: 0.1,
        focal: const Offset(200, 300),
        box: box,
        minScale: minScale,
      );

      expect(out, const TerminalZoom(scale: minScale));
    });

    test('never magnifies past 1:1', () {
      final out = scaleAround(overview, scale: 4, focal: Offset.zero, box: box, minScale: minScale);
      expect(out.scale, 1);
    });
  });

  group('panBy', () {
    test('moves with the finger while zoomed', () {
      final out = panBy(const TerminalZoom(scale: 1, dx: -200, dy: -300), const Offset(30, 40), box, minScale);
      expect(out.dx, -170);
      expect(out.dy, -260);
    });

    test('never pans past the content edges', () {
      final out = panBy(const TerminalZoom(scale: 1, dx: -10, dy: -10), const Offset(500, 500), box, minScale);
      expect(out.dx, 0);
      expect(out.dy, 0);

      final far = panBy(const TerminalZoom(scale: 1, dx: -10, dy: -10), const Offset(-5000, -5000), box, minScale);
      expect(far.dx, box.view.width - box.content.width);
      expect(far.dy, box.view.height - box.content.height);
    });

    test('is inert at the overview, where the grid already fits', () {
      expect(panBy(overview, const Offset(50, 50), box, minScale), overview);
    });
  });

  group('toggleZoom', () {
    test('goes to 1:1 at the tapped point from the overview', () {
      final out = toggleZoom(overview, focal: const Offset(200, 300), box: box, minScale: minScale);
      expect(out.scale, 1);
      expect(out.dx, -200);
    });

    test('returns to a flush overview when already zoomed', () {
      final out = toggleZoom(
        const TerminalZoom(scale: 1, dx: -200, dy: -300),
        focal: const Offset(10, 10),
        box: box,
        minScale: minScale,
      );
      expect(out, const TerminalZoom(scale: minScale));
    });
  });
}
