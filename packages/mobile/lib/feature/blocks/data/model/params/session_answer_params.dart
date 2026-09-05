import 'package:equatable/equatable.dart';

class SessionAnswerParams extends Equatable {
  final String requestId;
  final List<List<int>> selections;

  const SessionAnswerParams({required this.requestId, required this.selections});

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'selections': selections,
  };

  @override
  List<Object?> get props => [requestId, selections];
}
