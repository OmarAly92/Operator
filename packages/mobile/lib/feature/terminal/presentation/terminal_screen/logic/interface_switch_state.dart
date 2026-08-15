part of 'interface_switch_cubit.dart';

sealed class InterfaceSwitchState extends Equatable {
  const InterfaceSwitchState();

  @override
  List<Object?> get props => [];
}

final class InterfaceSwitchInitialState extends InterfaceSwitchState {
  const InterfaceSwitchInitialState();
}

final class InterfaceSwitchReadyState extends InterfaceSwitchState {
  const InterfaceSwitchReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
