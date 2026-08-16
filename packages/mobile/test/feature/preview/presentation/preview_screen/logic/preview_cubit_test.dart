import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';

class _MockRepository extends Mock implements PreviewRepository {}

PreviewModel preview(String entry) =>
    PreviewModel(entry: entry, url: 'http://10.0.0.5:3011/x', authenticated: true);

void main() {
  late _MockRepository repository;

  setUp(() => repository = _MockRepository());

  PreviewCubit build({String? previewUrl}) => PreviewCubit(
    repository,
    's-1',
    previewUrl: previewUrl,
    poll: const Duration(milliseconds: 30),
  );

  test('asks the detector as soon as it is built', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview?.entry, 'dist/index.html');
    expect(cubit.loading, isFalse);
    verify(() => repository.getPreview('s-1', previewUrl: null)).called(1);
    await cubit.close();
  });

  test('passes the session preview URL through so a dev server can be found', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build(previewUrl: 'http://localhost:5173/');

    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getPreview('s-1', previewUrl: 'http://localhost:5173/')).called(1);
    await cubit.close();
  });

  test('keeps polling on the tick', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .called(greaterThan(1));
    await cubit.close();
  });

  test('a bare README is not something worth showing', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('README.md')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview, isNotNull);
    expect(cubit.hasPreview, isFalse);
    await cubit.close();
  });

  test('a generated page is worth showing', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.hasPreview, isTrue);
    await cubit.close();
  });

  test('a transient failure keeps the last good answer and records the message', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );
    await cubit.refresh();

    expect(cubit.preview?.entry, 'dist/index.html');
    expect(cubit.error, 'down');
    await cubit.close();
  });

  test('never calls the repository when the session id is empty', () async {
    final cubit = PreviewCubit(repository, '', poll: const Duration(milliseconds: 30));

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verifyNever(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')));
    expect(cubit.loading, isFalse);
    await cubit.close();
  });

  test('stops polling once closed', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    clearInteractions(repository);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verifyNever(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')));
  });

  // The preview route runs its own cubit over the same session, so the globe's
  // poller stands down instead of asking the same question twice per tick.
  test('pausing stops the tick, and resuming asks once immediately', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    cubit.pausePolling();
    expect(cubit.polling, isFalse);
    clearInteractions(repository);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    verifyNever(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')));

    cubit.resumePolling();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.polling, isTrue);
    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).called(1);
    await cubit.close();
  });

  test('resuming twice does not start a second timer', () async {
    when(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')))
        .thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    cubit.pausePolling();

    cubit.resumePolling();
    cubit.resumePolling();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    verify(() => repository.getPreview(any(), previewUrl: any(named: 'previewUrl'))).called(1);
    await cubit.close();
  });
}
