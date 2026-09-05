import 'package:equatable/equatable.dart';

class SessionDecisionParams extends Equatable {
  final String requestId;
  final String behavior;

  const SessionDecisionParams({required this.requestId, required this.behavior});

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'behavior': behavior,
  };

  @override
  List<Object?> get props => [requestId, behavior];
}
