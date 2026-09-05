import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/context_readout_chip.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/logic/context_readout.dart';

Widget _wrap(Widget child) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  testWidgets(
    'renders a bare token count with no bar when the window is unknown',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ContextReadoutChip(
            readout: ContextReadout.of(
              const SessionContextModel(used: 64880, window: 0),
            ),
          ),
        ),
      );

      expect(find.text('64.9k tokens'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('renders a percentage and a bar when the window is known', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ContextReadoutChip(
          readout: ContextReadout.of(
            const SessionContextModel(used: 25000, window: 200000),
          ),
        ),
      ),
    );

    expect(find.text('13%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders nothing at all when there is no observation', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ContextReadoutChip(readout: null)));

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('tokens'), findsNothing);
  });
}
