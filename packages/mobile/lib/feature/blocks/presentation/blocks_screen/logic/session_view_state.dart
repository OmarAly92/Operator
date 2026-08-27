part of 'session_view_cubit.dart';

sealed class SessionViewState extends Equatable {
  const SessionViewState();

  @override
  List<Object?> get props => [];
}

final class SessionViewReadyState extends SessionViewState {
  const SessionViewReadyState(this.mode);

  final SessionViewMode mode;

  @override
  List<Object?> get props => [mode];
}
