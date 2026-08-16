import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart';

class _MockRepository extends Mock implements PreviewRepository {}

void main() {
  late _MockRepository repository;
  late List<PreviewModel> rendered;

  setUp(() {
    repository = _MockRepository();
    rendered = [];
  });

  Future<PreviewCubit> pump(WidgetTester tester) async {
    final cubit = PreviewCubit(repository, 's-1', poll: const Duration(hours: 1));
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<PreviewCubit>.value(
                value: cubit,
                child: PreviewBody(
                  browserBuilder: (preview) {
                    rendered.add(preview);
                    return AppText('browser:${preview.url}');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('waits while the detector is still looking', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return Result.success(null);
      },
    );
    final cubit = PreviewCubit(repository, 's-1', poll: const Duration(hours: 1));
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<PreviewCubit>.value(value: cubit, child: const PreviewBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Looking for a session preview…'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await cubit.close();
  });

  testWidgets('explains that nothing has been generated yet', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));

    final cubit = await pump(tester);

    expect(find.text('No preview yet'), findsOneWidget);
    expect(rendered, isEmpty);
    await cubit.close();
  });

  testWidgets('reports a detector failure instead of an empty screen', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );

    final cubit = await pump(tester);

    expect(find.text('Could not load preview'), findsOneWidget);
    expect(find.text('down'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('checking again re-asks the detector', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));

    final cubit = await pump(tester);
    clearInteractions(repository);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).called(1);
    await cubit.close();
  });

  testWidgets('renders the browser at the resolved URL', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(
          entry: 'dist/index.html',
          url: 'http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html',
          authenticated: true,
        ),
      ),
    );

    final cubit = await pump(tester);

    expect(rendered.single.authenticated, isTrue);
    expect(
      find.text('browser:http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html'),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('shows a README preview when asked directly, even though the dot stays off', (
    tester,
  ) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(entry: 'README.md', url: 'http://10.0.0.5:3011/x', authenticated: true),
      ),
    );

    final cubit = await pump(tester);

    expect(cubit.hasPreview, isFalse);
    expect(rendered, hasLength(1));
    await cubit.close();
  });

  testWidgets('never hands the Bearer header to an external dev server', (tester) async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.success(
        const PreviewModel(entry: '10.0.0.5', url: 'http://10.0.0.5:5173/', authenticated: false),
      ),
    );

    final cubit = await pump(tester);

    expect(rendered.single.authenticated, isFalse);
    await cubit.close();
  });
}
