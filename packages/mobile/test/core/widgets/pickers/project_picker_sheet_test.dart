import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

void main() {
  void phone(WidgetTester tester, {double keyboard = 0}) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
  }

  Widget host(AppSkin skin, void Function(BuildContext context) open) => SkinScope(
        skin: skin,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(onPressed: () => open(context), child: const Text('Open')),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('search narrows projects and a filtered pick returns that project id', (tester) async {
    phone(tester);
    String? picked;
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showProjectPickerSheet(
          context,
          projects: const [
            ProjectModel(id: 'p-web', name: 'Website', sessionPrefix: 'web'),
            ProjectModel(id: 'p-op', name: 'Operator', sessionPrefix: 'op'),
          ],
          selected: kAllProjects,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Active project'), findsOneWidget);
    expect(find.text('All projects'), findsOneWidget);
    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'oper');
    await tester.pumpAndSettle();
    expect(find.text('All projects'), findsNothing);
    expect(find.text('Website'), findsNothing);
    await tester.tap(find.text('Operator'));
    await tester.pumpAndSettle();
    expect(picked, 'p-op');
  });

  testWidgets('matches on the session prefix too', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) => showProjectPickerSheet(
          context,
          projects: const [
            ProjectModel(id: 'p-web', name: 'Website', sessionPrefix: 'web'),
            ProjectModel(id: 'p-op', name: 'Operator', sessionPrefix: 'op'),
          ],
          selected: 'p-web',
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppSheet.searchFieldKey), 'WEB');
    await tester.pumpAndSettle();
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Operator'), findsNothing);
  });

  testWidgets('tapping a project with a null id closes the sheet with no value', (tester) async {
    phone(tester);
    String? picked = 'unset';
    await tester.pumpWidget(
      host(
        const LightSkin(),
        (context) async => picked = await showProjectPickerSheet(
          context,
          projects: const [ProjectModel(id: null, name: 'Untitled', sessionPrefix: 'untitled')],
          selected: kAllProjects,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.byKey(AppSheet.surfaceKey), findsNothing);
  });

  testWidgets('the project picker opens as a large sheet', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(const LightSkin(), (context) => showProjectPickerSheet(context, projects: const [], selected: kAllProjects)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(AppSheet.surfaceKey)).height, moreOrLessEquals(796, epsilon: 0.5));
    expect(find.textContaining('No projects yet'), findsOneWidget);
  });
}
