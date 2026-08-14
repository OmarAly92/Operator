import 'package:equatable/equatable.dart';

class SteerConversationParams extends Equatable {
  final String text;
  final String clientMessageId;

  const SteerConversationParams({
    required this.text,
    required this.clientMessageId,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'clientMessageId': clientMessageId,
  };

  @override
  List<Object?> get props => [text, clientMessageId];
}
