part of 'blocks_cubit.dart';

sealed class BlocksState extends Equatable {
  const BlocksState();

  @override
  List<Object?> get props => [];
}

final class BlocksInitialState extends BlocksState {
  const BlocksInitialState();
}

final class BlocksReadyState extends BlocksState {
  const BlocksReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class BlocksUnsupportedState extends BlocksState {
  const BlocksUnsupportedState(this.harness);

  final String? harness;

  @override
  List<Object?> get props => [harness];
}
