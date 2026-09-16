part of 'connections_cubit.dart';

sealed class ConnectionsState extends Equatable {
  const ConnectionsState();

  @override
  List<Object?> get props => [];
}

final class ConnectionsInitialState extends ConnectionsState {
  const ConnectionsInitialState();
}

final class DesktopsUpdatedState extends ConnectionsState {
  const DesktopsUpdatedState(this.desktops);

  final List<DesktopModel> desktops;

  @override
  List<Object?> get props => [desktops];
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

final class ConnectFailureState extends ConnectionsState {
  const ConnectFailureState(this.id, this.copy);

  final String id;
  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [id, copy.title, copy.message];
}

final class LastDesktopRemovedState extends ConnectionsState {
  const LastDesktopRemovedState();
}
