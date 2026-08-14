import 'package:equatable/equatable.dart';

class ChatImageModel extends Equatable {
  final String? mimeType;
  final String? data;

  const ChatImageModel({required this.mimeType, required this.data});

  Map<String, dynamic> toJson() => {'mimeType': mimeType, 'data': data};

  @override
  List<Object?> get props => [mimeType, data];
}

class ChatResourceModel extends Equatable {
  final String? uri;
  final String? name;
  final String? mimeType;
  final String? text;

  const ChatResourceModel({
    required this.uri,
    required this.name,
    this.mimeType,
    this.text,
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'name': name,
    if (mimeType != null) 'mimeType': mimeType,
    if (text != null) 'text': text,
  };

  @override
  List<Object?> get props => [uri, name, mimeType, text];
}
