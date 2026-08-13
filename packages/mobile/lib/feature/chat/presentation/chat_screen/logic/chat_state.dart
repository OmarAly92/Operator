part of 'chat_cubit.dart';

sealed class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

final class ChatInitialState extends ChatState {
  const ChatInitialState();
}

final class ChatReadyState extends ChatState {
  const ChatReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
