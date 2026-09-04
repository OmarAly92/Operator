import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_state.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

void main() {
  late _MockOrchestratorRepository repository;

  setUpAll(() => registerFallbackValue(
      const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat')));

  setUp(() {
    repository = _MockOrchestratorRepository();
  });

  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'reports the launched orchestrator',
    build: () {
      when(() => repository.launch(any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
      );
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: false),
    expect: () => [
      isA<LaunchLoadingState>().having((s) => s.projectId, 'projectId', 'p').having((s) => s.clean, 'clean', isFalse),
      isA<LaunchSuccessState>().having((s) => s.link.id, 'link.id', 'o1'),
    ],
  );

  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'carries the clean flag on the loading state so a retry can reuse it',
    build: () {
      when(() => repository.launch(any())).thenAnswer(
        (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
      );
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: true),
    expect: () => [
      isA<LaunchLoadingState>().having((s) => s.clean, 'clean', isTrue),
      isA<LaunchSuccessState>(),
    ],
  );

  blocTest<OrchestratorCubit, OrchestratorLaunchState>(
    'reports a launch failure',
    build: () {
      when(() => repository.launch(any()))
          .thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'boom')));
      return OrchestratorCubit(repository);
    },
    act: (cubit) => cubit.launch('p', clean: false),
    expect: () => [
      isA<LaunchLoadingState>(),
      isA<LaunchFailureState>().having((s) => s.failure.message, 'failure.message', 'boom'),
    ],
  );

  test('sends the clean flag it is given', () async {
    when(() => repository.launch(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const OrchestratorModel(id: 'o1'))),
    );
    final cubit = OrchestratorCubit(repository);

    await cubit.launch('p', clean: true);

    final params = verify(() => repository.launch(captureAny())).captured.single
        as LaunchOrchestratorParams;
    expect(params.clean, isTrue);
    expect(params.projectId, 'p');
    await cubit.close();
  });
}
