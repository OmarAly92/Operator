import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

void main() {
  late _MockSessionsRepository repository;
  late _MockServerConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
    store = _MockServerConfigStore();
  });

  blocTest<SettingsCubit, SettingsState>(
    'reports the session count on a successful test',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.success(GlobalResponse(
          data: const BoardSnapshot(sessions: [SessionModel(id: 'a'), SessionModel(id: 'b')]),
        )),
      );
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.testConnection(),
    expect: () => [
      isA<PingLoadingState>(),
      isA<PingSuccessState>().having((s) => s.sessionCount, 'sessionCount', 2),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'reports a failed test',
    build: () {
      when(() => repository.getBoard()).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 401)),
      );
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.testConnection(),
    expect: () => [isA<PingLoadingState>(), isA<PingFailureState>()],
  );

  blocTest<SettingsCubit, SettingsState>(
    'clears the saved server on forget',
    build: () {
      when(() => store.clear()).thenAnswer((_) async {});
      return SettingsCubit(repository, store);
    },
    act: (cubit) => cubit.forget(),
    expect: () => [isA<ForgetSuccessState>()],
    verify: (_) => verify(() => store.clear()).called(1),
  );
}
