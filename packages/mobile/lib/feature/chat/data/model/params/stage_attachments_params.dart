import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

class StageAttachmentsParams extends Equatable {
  final List<ChatImageModel> attachments;

  const StageAttachmentsParams({required this.attachments});

  Map<String, dynamic> toJson() => {
    'attachments': attachments.map((image) => image.toJson()).toList(),
  };

  @override
  List<Object?> get props => [attachments];
}
