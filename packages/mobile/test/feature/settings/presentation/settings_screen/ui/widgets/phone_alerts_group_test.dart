import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/widgets/phone_alerts_group.dart';

class _MockRepo extends Mock implements NotificationRepository {}

void main() {
  late _MockRepo repo;

  setUp(() => repo = _MockRepo());

  Future<PhoneAlertsCubit> pump(WidgetTester tester) async {
    final cubit = PhoneAlertsCubit(repo, launch: (_) async => true, copy: (_) async {}, ntfyDeepLink: false);
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BlocProvider<PhoneAlertsCubit>.value(value: cubit, child: const PhoneAlertsGroup()),
              ),
            ),
          ),
        ),
      ),
    );
    await cubit.load();
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('a failed load shows that the desktop could not be reached, not that Connect Mobile is off', (
    tester,
  ) async {
    when(
      () => repo.getPhoneAlerts(),
    ).thenAnswer((_) async => Result.failure(ServerFailure(error: 'timeout', message: 'Connection timed out')));
    await pump(tester);
    expect(find.text("Couldn't reach the desktop: Connection timed out"), findsOneWidget);
    expect(find.text('Off — Connect Mobile is off on the desktop'), findsNothing);
  });

  testWidgets('a failed subscribe shows the failure message', (tester) async {
    when(
      () => repo.getPhoneAlerts(),
    ).thenAnswer((_) async => Result.success(const PhoneAlertStatusModel(enabled: true, claimed: false)));
    when(() => repo.subscribePhoneAlerts()).thenAnswer(
      (_) async => Result.failure(
        ServerFailure(error: 'conflict', message: 'phone alerts need Connect Mobile to be on', statusCode: 409),
      ),
    );
    await pump(tester);
    expect(find.text('Not subscribed yet'), findsOneWidget);
    await tester.tap(find.text('Subscribe on this phone'));
    await tester.pumpAndSettle();
    expect(find.text('phone alerts need Connect Mobile to be on'), findsOneWidget);
    expect(find.text('Not subscribed yet'), findsNothing);
  });
}
