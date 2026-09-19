import 'package:equatable/equatable.dart';

class SessionDecisionParams extends Equatable {
  final String requestId;
  final String? behavior;
  final String? option;

  const SessionDecisionParams({required this.requestId, this.behavior, this.option});

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'behavior': ?behavior,
    'option': ?option,
  };

  @override
  List<Object?> get props => [requestId, behavior, option];
}
