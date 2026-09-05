part of 'session_command_cubit.dart';

class SessionCommandState extends Equatable {
  final Map<String, CommandPhase> phases;
  final List<String> models;

  const SessionCommandState({this.phases = const {}, this.models = const []});

  SessionCommandState copyWith({Map<String, CommandPhase>? phases, List<String>? models}) =>
      SessionCommandState(phases: phases ?? this.phases, models: models ?? this.models);

  @override
  List<Object?> get props => [phases, models];
}
