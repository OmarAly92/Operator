part of 'notifications_cubit.dart';

sealed class NotificationsState extends Equatable {
  const NotificationsState();

  @override
  List<Object?> get props => [];
}

final class NotificationsInitialState extends NotificationsState {
  const NotificationsInitialState();
}

final class NotificationsReadyState extends NotificationsState {
  const NotificationsReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
