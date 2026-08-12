part of 'pairing_scan_cubit.dart';

sealed class PairingScanState extends Equatable {
  const PairingScanState();

  @override
  List<Object?> get props => [];
}

final class PairingScanInitialState extends PairingScanState {
  const PairingScanInitialState();
}

final class VerifyLoadingState extends PairingScanState {
  const VerifyLoadingState();
}

final class VerifySuccessState extends PairingScanState {
  const VerifySuccessState();
}

final class VerifyFailureState extends PairingScanState {
  const VerifyFailureState(this.copy);

  final ConnectionErrorCopy copy;

  @override
  List<Object?> get props => [copy];
}
