part of 'sessions_cubit.dart';

sealed class SessionsState extends Equatable {
  const SessionsState();

  @override
  List<Object?> get props => [];
}

final class SessionsInitialState extends SessionsState {
  const SessionsInitialState();
}

final class GetSessionsLoadingState extends SessionsState {
  const GetSessionsLoadingState();
}

final class GetSessionsSuccessState extends SessionsState {
  const GetSessionsSuccessState();
}

final class GetSessionsFailureState extends SessionsState {
  const GetSessionsFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class KillFailureState extends SessionsState {
  const KillFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class RestoreFailureState extends SessionsState {
  const RestoreFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
