part of 'manual_connect_cubit.dart';

sealed class ManualConnectState extends Equatable {
  const ManualConnectState();

  @override
  List<Object?> get props => [];
}

final class ManualConnectInitialState extends ManualConnectState {
  const ManualConnectInitialState();
}

final class SecureToggledState extends ManualConnectState {
  const SecureToggledState(this.secure);

  final bool secure;

  @override
  List<Object?> get props => [secure];
}

final class ConnectLoadingState extends ManualConnectState {
  const ConnectLoadingState();
}

final class ConnectSuccessState extends ManualConnectState {
  const ConnectSuccessState();
}

final class ConnectFailureState extends ManualConnectState {
  const ConnectFailureState(this.copy);

  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [copy];
}
