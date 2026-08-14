part of 'terminal_cubit.dart';

sealed class TerminalState extends Equatable {
  const TerminalState();

  @override
  List<Object?> get props => [];
}

final class TerminalInitialState extends TerminalState {
  const TerminalInitialState();
}

final class TerminalReadyState extends TerminalState {
  const TerminalReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class TerminalClosedState extends TerminalState {
  const TerminalClosedState();
}
