import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/glass_drag_builder.dart';

void main() {
  testWidgets('a cancelled pointer ends the drag in listener mode', (tester) async {
    final seen = <Offset?>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassDragBuilder(
            builder: (context, offset, child) {
              seen.add(offset);
              return const SizedBox(width: 100, height: 100);
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(seen.last, Offset.zero);
    await gesture.cancel();
    await tester.pump();
    expect(seen.last, isNull);
  });
}
