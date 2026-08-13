import 'package:equatable/equatable.dart';

class ResolveApprovalParams extends Equatable {
  final String requestId;
  final String decisionId;

  const ResolveApprovalParams({
    required this.requestId,
    required this.decisionId,
  });

  Map<String, dynamic> toJson() => {'decisionId': decisionId};

  @override
  List<Object?> get props => [requestId, decisionId];
}
