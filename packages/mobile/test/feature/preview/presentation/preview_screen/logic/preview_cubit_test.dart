import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/events/sse_stream.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';

class _MockRepository extends Mock implements PreviewRepository {}

PreviewModel preview(String entry) => PreviewModel(
  entry: entry,
  url: 'http://10.0.0.5:3011/x',
  authenticated: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockRepository repository;

  setUp(() => repository = _MockRepository());

  PreviewCubit build({String? previewUrl}) => PreviewCubit(
    repository,
    's-1',
    previewUrl: previewUrl,
    poll: const Duration(milliseconds: 30),
  );

  test('asks the detector as soon as it is built', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview?.entry, 'dist/index.html');
    expect(cubit.loading, isFalse);
    verify(() => repository.getPreview('s-1', previewUrl: null)).called(1);
    await cubit.close();
  });

  test(
    'passes the session preview URL through so a dev server can be found',
    () async {
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(null));
      final cubit = build(previewUrl: 'http://localhost:5173/');

      await Future<void>.delayed(Duration.zero);

      verify(
        () =>
            repository.getPreview('s-1', previewUrl: 'http://localhost:5173/'),
      ).called(1);
      await cubit.close();
    },
  );

  test('keeps polling on the tick', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(null));
    final cubit = build();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verify(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).called(greaterThan(1));
    await cubit.close();
  });

  test('a bare README is not something worth showing', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(preview('README.md')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.preview, isNotNull);
    expect(cubit.hasPreview, isFalse);
    await cubit.close();
  });

  test('a generated page is worth showing', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(preview('dist/index.html')));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.hasPreview, isTrue);
    await cubit.close();
  });

  test(
    'a transient failure keeps the last good answer and records the message',
    () async {
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(preview('dist/index.html')));
      final cubit = build();
      await Future<void>.delayed(Duration.zero);

      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'down', statusCode: 503),
        ),
      );
      await cubit.refresh();

      expect(cubit.preview?.entry, 'dist/index.html');
      expect(cubit.error, 'down');
      await cubit.close();
    },
  );

  test('never calls the repository when the session id is empty', () async {
    final cubit = PreviewCubit(
      repository,
      '',
      poll: const Duration(milliseconds: 30),
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verifyNever(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    );
    expect(cubit.loading, isFalse);
    await cubit.close();
  });

  test('stops polling once closed', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    clearInteractions(repository);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    verifyNever(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    );
  });

  test('pausing stops the tick, and resuming asks once immediately', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    cubit.pausePolling();
    expect(cubit.polling, isFalse);
    clearInteractions(repository);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    verifyNever(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    );

    cubit.resumePolling();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.polling, isTrue);
    verify(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).called(1);
    await cubit.close();
  });

  test('resuming twice does not start a second timer', () async {
    when(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).thenAnswer((_) async => Result.success(null));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    cubit.pausePolling();

    cubit.resumePolling();
    cubit.resumePolling();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    verify(
      () => repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
    ).called(1);
    await cubit.close();
  });
  test(
    'healthy workspace streams refresh on changes without polling',
    () async {
      final events = StreamController<SseStreamEvent>();
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(null));
      final cubit = PreviewCubit(
        repository,
        's-1',
        workspaceEvents: () => events.stream,
        poll: const Duration(milliseconds: 30),
      );
      await Future<void>.delayed(Duration.zero);
      events.add(SseStreamEvent.connected);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repository);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      );
      events.add(SseStreamEvent.changed);
      await Future<void>.delayed(Duration.zero);
      verify(() => repository.getPreview('s-1', previewUrl: null)).called(1);
      await cubit.close();
      await events.close();
    },
  );

  test(
    'session URL changes are authoritative and preserve workspace subscription',
    () async {
      final events = StreamController<SseStreamEvent>();
      final sessions = StreamController<SessionModel>();
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(null));
      final cubit = PreviewCubit(
        repository,
        's-1',
        workspaceEvents: () => events.stream,
        sessionUpdates: () => sessions.stream,
      );
      await Future<void>.delayed(Duration.zero);
      sessions.add(
        const SessionModel(id: 's-1', previewUrl: 'http://localhost:3000'),
      );
      await Future<void>.delayed(Duration.zero);
      verify(
        () => repository.getPreview('s-1', previewUrl: 'http://localhost:3000'),
      ).called(1);
      sessions.add(const SessionModel(id: 's-1'));
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repository);
      events.add(SseStreamEvent.changed);
      await Future<void>.delayed(Duration.zero);
      verify(() => repository.getPreview('s-1', previewUrl: null)).called(1);
      await cubit.close();
      await events.close();
      await sessions.close();
    },
  );

  test(
    'coalesces refreshes and discards requests with an outdated URL',
    () async {
      final sessions = StreamController<SessionModel>();
      final first = Completer<Result<PreviewModel?, Failure>>();
      var calls = 0;
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) {
        calls++;
        return calls == 1
            ? first.future
            : Future.value(Result.success(preview('new.html')));
      });
      final cubit = PreviewCubit(
        repository,
        's-1',
        sessionUpdates: () => sessions.stream,
      );
      sessions.add(
        const SessionModel(id: 's-1', previewUrl: 'http://localhost:3000'),
      );
      await Future<void>.delayed(Duration.zero);
      await cubit.refresh();
      expect(calls, 1);
      first.complete(Result.success(preview('old.html')));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(cubit.preview?.entry, 'new.html');
      await cubit.close();
      await sessions.close();
    },
  );
  test(
    'retries unavailable workspace streams and stops fallback on recovery',
    () async {
      final events = StreamController<SseStreamEvent>();
      var connections = 0;
      when(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(null));
      final cubit = PreviewCubit(
        repository,
        's-1',
        poll: const Duration(milliseconds: 30),
        workspaceEvents: () {
          connections++;
          return connections == 1
              ? Stream.error(StateError('offline'))
              : events.stream;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(connections, 2);
      events.add(SseStreamEvent.connected);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repository);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verifyNever(
        () =>
            repository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      );
      await cubit.close();
      await events.close();
    },
  );
}
