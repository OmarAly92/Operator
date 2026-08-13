import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

sealed class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

final class SettingsInitialState extends SettingsState {
  const SettingsInitialState();
}

final class PingLoadingState extends SettingsState {
  const PingLoadingState();
}

final class PingSuccessState extends SettingsState {
  const PingSuccessState(this.sessionCount);

  final int sessionCount;

  @override
  List<Object?> get props => [sessionCount];
}

final class PingFailureState extends SettingsState {
  const PingFailureState(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

final class ForgetSuccessState extends SettingsState {
  const ForgetSuccessState();
}
