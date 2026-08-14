import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';

class _MockTerminalRepository extends Mock implements TerminalRepository {}

GlobalResponse<InterfaceTransitionStatusModel> _status({
  bool supported = true,
  String? phase,
  String? reason,
}) => GlobalResponse(
  data: InterfaceTransitionStatusModel(
    supported: supported,
    targetMode: 'chat',
    reason: reason,
    transition: phase == null
        ? null
        : InterfaceTransitionModel(id: 't-1', sessionId: 's-1', phase: phase),
  ),
);

void main() {
  late _MockTerminalRepository repository;

  setUpAll(() => registerFallbackValue(
        const StartInterfaceTransitionParams(targetMode: 'chat', policy: 'drain'),
      ));

  setUp(() => repository = _MockTerminalRepository());

  InterfaceSwitchCubit build({VoidCallback? onSettled}) => InterfaceSwitchCubit(
    repository,
    's-1',
    onSettled: onSettled,
    activePoll: const Duration(milliseconds: 5),
    idlePoll: const Duration(seconds: 30),
  );

  test('reads support and the current phase on construction', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.supported, isTrue);
    expect(cubit.phase, 'draining');
    expect(cubit.active, isTrue);
    expect(cubit.cancellable, isTrue);
    await cubit.close();
  });

  test('reports an unsupported session with the daemon\'s reason', () async {
    when(() => repository.getInterfaceTransition('s-1')).thenAnswer(
      (_) async => Result.success(_status(supported: false, reason: 'No chat driver.')),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.supported, isFalse);
    expect(cubit.reason, 'No chat driver.');
    expect(cubit.active, isFalse);
    await cubit.close();
  });

  test('surfaces a poll failure without dropping what it already knew', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    when(() => repository.getInterfaceTransition('s-1')).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'offline')),
    );
    await cubit.refresh();

    expect(cubit.error, 'offline');
    expect(cubit.phase, 'draining');
    await cubit.close();
  });

  test('fires onSettled exactly once when a transition finishes', () async {
    var settled = 0;
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'completed')));

    final cubit = build(onSettled: () => settled++);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.refresh();
    await cubit.refresh();

    expect(settled, 1);
    await cubit.close();
  });

  test('starts a transition and adopts the returned phase immediately', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status()));
    when(() => repository.startInterfaceTransition('s-1', any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(data: InterfaceTransitionModel(id: 't-1', phase: 'requested')),
      ),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.start('chat', 'interrupt');

    final captured = verify(
      () => repository.startInterfaceTransition('s-1', captureAny()),
    ).captured.last as StartInterfaceTransitionParams;
    expect(captured.policy, 'interrupt');
    expect(cubit.phase, 'requested');
    expect(cubit.starting, isFalse);
    await cubit.close();
  });

  test('keeps the terminal usable when starting fails', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status()));
    when(() => repository.startInterfaceTransition('s-1', any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'busy', statusCode: 409)),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.start('chat', 'drain');

    expect(cubit.error, 'busy');
    expect(cubit.active, isFalse);
    await cubit.close();
  });

  test('cancels and re-reads the status', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));
    when(() => repository.cancelInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(true));

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.cancel();

    verify(() => repository.cancelInterfaceTransition('s-1')).called(1);
    expect(cubit.cancelling, isFalse);
    await cubit.close();
  });

  test('does not poll at all for a session-less shell', () async {
    final cubit = InterfaceSwitchCubit(repository, '', idlePoll: const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    verifyNever(() => repository.getInterfaceTransition(any()));
    expect(cubit.supported, isFalse);
    await cubit.close();
  });
}
