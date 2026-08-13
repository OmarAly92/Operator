part of 'spawn_cubit.dart';

sealed class SpawnState extends Equatable {
  const SpawnState();

  @override
  List<Object?> get props => [];
}

final class SpawnInitialState extends SpawnState {
  const SpawnInitialState();
}

final class CatalogLoadingState extends SpawnState {
  const CatalogLoadingState();
}

final class CatalogReadyState extends SpawnState {
  const CatalogReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class CatalogFailureState extends SpawnState {
  const CatalogFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class SpawnLoadingState extends SpawnState {
  const SpawnLoadingState();
}

final class SpawnSuccessState extends SpawnState {
  const SpawnSuccessState(this.session);

  final SessionModel session;

  @override
  List<Object?> get props => [session];
}

final class SpawnFailureState extends SpawnState {
  const SpawnFailureState(this.failure, {required this.chatUnavailable});

  final Failure failure;
  final bool chatUnavailable;

  @override
  List<Object?> get props => [failure, chatUnavailable];
}

final class SpawnValidationFailureState extends SpawnState {
  const SpawnValidationFailureState(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
