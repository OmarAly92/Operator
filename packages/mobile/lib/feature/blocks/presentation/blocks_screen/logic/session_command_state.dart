part of 'session_command_cubit.dart';

/// One data-bag shape tracks every in-flight command uniformly, rather than a
/// sealed hierarchy of mutually-exclusive per-method states — this cubit is a
/// state machine over `phases`/`models`, not a set of alternative UI states.
class SessionCommandState extends Equatable {
  final Map<String, CommandPhase> phases;
  final List<String> models;

  const SessionCommandState({this.phases = const {}, this.models = const []});

  SessionCommandState copyWith({Map<String, CommandPhase>? phases, List<String>? models}) =>
      SessionCommandState(phases: phases ?? this.phases, models: models ?? this.models);

  @override
  List<Object?> get props => [phases, models];
}
