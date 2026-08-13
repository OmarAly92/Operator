import 'package:equatable/equatable.dart';

class ResolveInputParams extends Equatable {
  final String requestId;
  final String action;
  final Map<String, dynamic>? content;

  const ResolveInputParams({
    required this.requestId,
    required this.action,
    this.content,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    if (content != null) 'content': content,
  };

  @override
  List<Object?> get props => [requestId, action, content];
}
