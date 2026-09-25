import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart';

class _MockManualConnectCubit extends MockCubit<ManualConnectState> implements ManualConnectCubit {}

void main() {
  testWidgets('a successful connect shows the success step, then returns true after the hold', (tester) async {
    final cubit = _MockManualConnectCubit();
    when(() => cubit.hostController).thenReturn(TextEditingController());
    when(() => cubit.passwordController).thenReturn(TextEditingController());
    when(() => cubit.secure).thenReturn(false);
    whenListen(
      cubit,
      Stream<ManualConnectState>.fromIterable([const ConnectSuccessState('MacBook')]),
      initialState: const ManualConnectInitialState(),
    );
    bool? result;

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => BlocProvider<ManualConnectCubit>.value(
                        value: cubit,
                        child: const ManualConnectScreen(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('MacBook'), findsOneWidget);
    expect(result, isNull);

    await tester.pump(AppMotion.pairingSuccessHold);
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
