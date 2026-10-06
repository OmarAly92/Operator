import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart';

class _MockPairingScanCubit extends MockCubit<PairingScanState> implements PairingScanCubit {}

void main() {
  testWidgets('pairing from onboarding through the success step leaves only the board on the stack', (tester) async {
    final cubit = _MockPairingScanCubit();
    when(() => cubit.fromOnboarding).thenReturn(true);
    whenListen(
      cubit,
      Stream<PairingScanState>.fromIterable([const VerifySuccessState('MacBook')]),
      initialState: const PairingScanInitialState(),
    );

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            initialRoute: '/onboarding-stub',
            routes: {
              '/onboarding-stub': (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.pairingScan),
                  child: const Text('go to pairing'),
                ),
              ),
              RoutesStrings.pairingScan: (context) => BlocProvider<PairingScanCubit>.value(
                value: cubit,
                child: const PairingScanScreen(),
              ),
              RoutesStrings.sessions: (context) => const Scaffold(body: Text('BOARD')),
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go to pairing'));
    await tester.pumpAndSettle();

    expect(find.text('go to pairing'), findsNothing);
    expect(find.text('BOARD'), findsNothing);

    await tester.pump(AppMotion.pairingSuccessHold);
    await tester.pumpAndSettle();

    expect(find.text('BOARD'), findsOneWidget);
    expect(find.text('go to pairing'), findsNothing);
    expect(Navigator.of(tester.element(find.text('BOARD'))).canPop(), isFalse);
  });

  testWidgets('the manual entry link uses the text-safe accent color on light', (tester) async {
    final cubit = _MockPairingScanCubit();
    when(() => cubit.fromOnboarding).thenReturn(false);
    whenListen(cubit, const Stream<PairingScanState>.empty(), initialState: const PairingScanInitialState());

    await tester.pumpWidget(
      SkinScope(
        skin: const LightSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: BlocProvider<PairingScanCubit>.value(value: cubit, child: const PairingScanScreen()),
          ),
        ),
      ),
    );
    await tester.pump();

    final link = tester.widget<AppText>(find.byWidgetPredicate((w) => w is AppText && w.text == 'Enter manually'));
    expect(link.style?.color, const LightSkin().accentText);
  });
}
