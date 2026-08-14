import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

class SendMessageParams extends Equatable {
  final String text;
  final String clientMessageId;
  final List<ChatImageModel>? attachments;
  final List<ChatResourceModel>? resources;

  const SendMessageParams({
    required this.text,
    required this.clientMessageId,
    this.attachments,
    this.resources,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'clientMessageId': clientMessageId,
    if (attachments != null)
      'attachments': attachments!.map((image) => image.toJson()).toList(),
    if (resources != null)
      'resources': resources!.map((resource) => resource.toJson()).toList(),
  };

  @override
  List<Object?> get props => [text, clientMessageId, attachments, resources];
}
