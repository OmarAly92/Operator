part of 'connection_cubit.dart';

sealed class AppConnectionState extends Equatable {
  const AppConnectionState({this.desktopName});

  final String? desktopName;

  AppConnectionState withName(String? name);

  @override
  List<Object?> get props => [desktopName];
}

final class ConnectionConnectingState extends AppConnectionState {
  const ConnectionConnectingState({super.desktopName});

  @override
  ConnectionConnectingState withName(String? name) => ConnectionConnectingState(desktopName: name);
}

final class ConnectionOnlineState extends AppConnectionState {
  const ConnectionOnlineState({required this.updatedAt, super.desktopName});

  final DateTime updatedAt;

  @override
  ConnectionOnlineState withName(String? name) => ConnectionOnlineState(updatedAt: updatedAt, desktopName: name);

  @override
  List<Object?> get props => [updatedAt, desktopName];
}

final class ConnectionOfflineState extends AppConnectionState {
  const ConnectionOfflineState({required this.reason, this.lastSeenAt, super.desktopName});

  final ConnectionFailure reason;
  final DateTime? lastSeenAt;

  @override
  ConnectionOfflineState withName(String? name) =>
      ConnectionOfflineState(reason: reason, lastSeenAt: lastSeenAt, desktopName: name);

  @override
  List<Object?> get props => [reason, lastSeenAt, desktopName];
}

final class ConnectionAuthFailedState extends AppConnectionState {
  const ConnectionAuthFailedState({required this.episode, super.desktopName});

  final int episode;

  @override
  ConnectionAuthFailedState withName(String? name) => ConnectionAuthFailedState(episode: episode, desktopName: name);

  @override
  List<Object?> get props => [episode, desktopName];
}
