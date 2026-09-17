import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';

class _MockTerminalRepository extends Mock implements TerminalRepository {}

const _commands = [
  SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin', interactive: false),
  SlashCommandModel(name: 'context', description: 'Context grid', source: 'builtin', interactive: false),
  SlashCommandModel(name: 'model', description: 'Pick a model', source: 'builtin', interactive: true),
  SlashCommandModel(name: 'sc:analyze', description: 'Analyze', source: 'user', interactive: false),
];

void main() {
  late _MockTerminalRepository repository;
  late TextEditingController composer;

  setUp(() {
    repository = _MockTerminalRepository();
    composer = TextEditingController();
    when(() => repository.getSlashCommands(any())).thenAnswer(
      (_) async => Result.success(GlobalResponse<List<SlashCommandModel>>(data: _commands)),
    );
  });

  tearDown(() => composer.dispose());

  SlashMenuCubit build() => SlashMenuCubit(repository, composer, sessionId: 's-1');

  blocTest<SlashMenuCubit, SlashMenuState>(
    'loads the session commands with interactive ones last',
    build: build,
    expect: () => [isA<GetSlashCommandsSuccessState>()],
    verify: (cubit) {
      expect(cubit.commands.map((c) => c.name), ['compact', 'context', 'sc:analyze', 'model']);
      expect(cubit.open, isFalse);
    },
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'opens on a leading slash and filters by prefix',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/';
      composer.text = '/co';
    },
    skip: 1,
    expect: () => [
      SlashMenuChangedState(open: true, matches: [_commands[0], _commands[1], _commands[3], _commands[2]]),
      SlashMenuChangedState(open: true, matches: [_commands[0], _commands[1]]),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'falls back to a contains match when nothing starts with the query',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/analy';
    },
    skip: 1,
    expect: () => [
      SlashMenuChangedState(open: true, matches: [_commands[3]]),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'closes once the command is followed by whitespace or the slash is gone',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/compact';
      composer.text = '/compact ';
      composer.text = 'plain text';
    },
    skip: 1,
    expect: () => [
      SlashMenuChangedState(open: true, matches: [_commands[0]]),
      const SlashMenuChangedState(open: false, matches: []),
    ],
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'pick fills the composer with the command and a trailing space',
    build: build,
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/co';
      cubit.pick(_commands[1]);
    },
    verify: (cubit) {
      expect(composer.text, '/context ');
      expect(composer.selection.baseOffset, '/context '.length);
      expect(cubit.open, isFalse);
    },
  );

  blocTest<SlashMenuCubit, SlashMenuState>(
    'a failed fetch leaves the menu closed for good',
    build: () {
      when(() => repository.getSlashCommands(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'old daemon', statusCode: 501)),
      );
      return build();
    },
    act: (cubit) async {
      await Future<void>.delayed(Duration.zero);
      composer.text = '/';
    },
    expect: () => [isA<GetSlashCommandsFailureState>()],
    verify: (cubit) => expect(cubit.open, isFalse),
  );
}
