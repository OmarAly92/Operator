part of 'connections_cubit.dart';

sealed class ConnectionsState extends Equatable {
  const ConnectionsState();

  @override
  List<Object?> get props => [];
}

final class ConnectionsInitialState extends ConnectionsState {
  const ConnectionsInitialState();
}

final class ConnectLoadingState extends ConnectionsState {
  const ConnectLoadingState(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class ConnectSuccessState extends ConnectionsState {
  const ConnectSuccessState(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class AddConnectionSuccessState extends ConnectionsState {
  const AddConnectionSuccessState();
}

final class UpdateConnectionSuccessState extends ConnectionsState {
  const UpdateConnectionSuccessState();
}

final class RemoveConnectionSuccessState extends ConnectionsState {
  const RemoveConnectionSuccessState();
}
