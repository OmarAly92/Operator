import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';

import '../../../../helpers/connection_harness.dart';

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late ConnectionHarness connection;
  late _MockPairingRepository repository;
  final notified = <String>[];

  setUpAll(() => registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: '')));

  setUp(() async {
    connection = ConnectionHarness();
    repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(kTestDesktop);
    await sl.reset();
    sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
      (mode, _) => ManualConnectCubit(repository, store, mode: mode),
    );
    notified.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        notified.add(call.arguments as String);
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
    await sl.reset();
    await connection.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}')),
            home: BlocProvider<ConnectionCubit>.value(
              value: connection.cubit,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(onPressed: () => showRePairSheet(context), child: const Text('open')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the desktop and shows its host, with an empty password', (tester) async {
    connection.report(ConnectionOutcome.auth);
    await open(tester);

    expect(find.text('Re-pair Mac'), findsOneWidget);
    expect(find.descendant(of: find.byKey(RePairForm.hostKey), matching: find.text('10.0.0.5')), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
  });

  testWidgets('a good password reconnects and closes the sheet', (tester) async {
    when(() => repository.verifyAndConnect(any())).thenAnswer(
      (_) async => Result.success(const DesktopModel(id: 'd-1', name: 'Mac')),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'fresh-password');
    await tester.tap(find.byKey(RePairForm.reconnectKey));
    await tester.pumpAndSettle();

    final target = verify(() => repository.verifyAndConnect(captureAny())).captured.single as ServerConfig;
    expect(target.password, 'fresh-password');
    expect(target.host, '10.0.0.5');
    expect(find.byType(RePairForm), findsNothing);
    expect(notified, ['success']);
  });

  testWidgets('a wrong password keeps the sheet open with the reason', (tester) async {
    when(() => repository.verifyAndConnect(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'bad', statusCode: 401)),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'still-wrong');
    await tester.tap(find.byKey(RePairForm.reconnectKey));
    await tester.pumpAndSettle();

    expect(find.byType(RePairForm), findsOneWidget);
    expect(find.text('Your desktop rejected the password'), findsOneWidget);
    expect(notified, ['warning']);
  });

  testWidgets('Scan the code instead closes the sheet and opens the scanner', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(RePairForm.scanKey));
    await tester.pumpAndSettle();

    expect(find.text('route /pair'), findsOneWidget);
  });
}
