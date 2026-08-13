part of 'pull_request_cubit.dart';

sealed class PullRequestState extends Equatable {
  const PullRequestState();

  @override
  List<Object?> get props => [];
}

final class PullRequestInitialState extends PullRequestState {
  const PullRequestInitialState();
}

final class PullRequestReadyState extends PullRequestState {
  const PullRequestReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
