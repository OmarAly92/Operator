part of 'session_command_cubit.dart';

/// One data-bag shape tracks every in-flight command uniformly, rather than a
/// sealed hierarchy of mutually-exclusive per-method states — this cubit is a
/// state machine over `phases`/`models`, not a set of alternative UI states.
class SessionCommandState extends Equatable {
  final Map<String, CommandPhase> phases;
  final List<String> models;

  /// The session's activity state. It lives in the state, not only in the
  /// cubit, because enablement is derived from it: holding it privately meant
  /// a change emitted nothing and every listener kept its stale enablement.
  final String? activity;

  const SessionCommandState({this.phases = const {}, this.models = const [], this.activity});

  SessionCommandState copyWith({Map<String, CommandPhase>? phases, List<String>? models}) =>
      SessionCommandState(phases: phases ?? this.phases, models: models ?? this.models, activity: activity);

  SessionCommandState withActivity(String? next) =>
      SessionCommandState(phases: phases, models: models, activity: next);

  @override
  List<Object?> get props => [phases, models, activity];
}
