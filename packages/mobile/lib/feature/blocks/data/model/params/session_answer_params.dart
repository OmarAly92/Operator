import 'package:equatable/equatable.dart';

/// Selections are option LABEL text, one group per question, never row indices:
/// the harness inserts synthetic rows ("Type something.", "Chat about this")
/// that the transcript's option list never knew about, so a positional index
/// lands on the wrong row. The daemon resolves each label against the menu
/// actually on screen.
class SessionAnswerParams extends Equatable {
  final String requestId;
  final List<List<String>> selections;

  const SessionAnswerParams({required this.requestId, required this.selections});

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'selections': selections,
  };

  @override
  List<Object?> get props => [requestId, selections];
}
