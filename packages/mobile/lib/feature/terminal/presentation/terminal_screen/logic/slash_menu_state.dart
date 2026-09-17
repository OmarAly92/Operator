part of 'slash_menu_cubit.dart';

sealed class SlashMenuState extends Equatable {
  const SlashMenuState();

  @override
  List<Object?> get props => [];
}

final class SlashMenuInitialState extends SlashMenuState {
  const SlashMenuInitialState();
}

final class GetSlashCommandsLoadingState extends SlashMenuState {
  const GetSlashCommandsLoadingState();
}

final class GetSlashCommandsSuccessState extends SlashMenuState {
  const GetSlashCommandsSuccessState();
}

final class GetSlashCommandsFailureState extends SlashMenuState {
  const GetSlashCommandsFailureState({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class SlashMenuChangedState extends SlashMenuState {
  const SlashMenuChangedState({required this.open, required this.matches});

  final bool open;
  final List<SlashCommandModel> matches;

  @override
  List<Object?> get props => [open, matches];
}
