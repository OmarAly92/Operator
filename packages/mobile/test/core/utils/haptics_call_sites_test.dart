import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> fired = <String>[];

  setUp(() {
    fired.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        fired.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
  });

  Widget host(Widget child) => SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
        ),
      );

  group('PrimaryButton haptics', () {
    testWidgets('a normal press taps', (tester) async {
      await tester.pumpWidget(host(PrimaryButton(text: 'Go', onPressed: () {})));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a destructive press warns instead', (tester) async {
      await tester.pumpWidget(
        host(PrimaryButton(text: 'Kill', isDestructive: true, onPressed: () {})),
      );
      await tester.tap(find.text('Kill'));
      await tester.pump();
      expect(fired, ['warning']);
    });

    testWidgets('a disabled button fires nothing', (tester) async {
      await tester.pumpWidget(host(const PrimaryButton(text: 'Go', onPressed: null)));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, isEmpty);
    });
  });
}
