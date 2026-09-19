part of 'session_command_cubit.dart';

/// One data-bag shape tracks every in-flight command uniformly, rather than a
/// sealed hierarchy of mutually-exclusive per-method states — this cubit is a
/// state machine over `phases`/`models`, not a set of alternative UI states.
class SessionCommandState extends Equatable {
  final Map<String, CommandPhase> phases;
  final List<String> models;
  final List<SessionModelOptionModel> modelOptions;
  final bool modelsLoading;
  final String? currentModel;
  final ContextReadoutData? contextReadout;

  /// The session's activity state. It lives in the state, not only in the
  /// cubit, because enablement is derived from it: holding it privately meant
  /// a change emitted nothing and every listener kept its stale enablement.
  final String? activity;
  final PendingInteractionModel? pendingInteraction;

  const SessionCommandState({
    this.phases = const {},
    this.models = const [],
    this.modelOptions = const [],
    this.modelsLoading = false,
    this.currentModel,
    this.activity,
    this.contextReadout,
    this.pendingInteraction,
  });

  SessionCommandState copyWith({
    Map<String, CommandPhase>? phases,
    List<String>? models,
    List<SessionModelOptionModel>? modelOptions,
    bool? modelsLoading,
    String? currentModel,
  }) => SessionCommandState(
    phases: phases ?? this.phases,
    models: models ?? this.models,
    modelOptions: modelOptions ?? this.modelOptions,
    modelsLoading: modelsLoading ?? this.modelsLoading,
    currentModel: currentModel ?? this.currentModel,
    activity: activity,
    contextReadout: contextReadout,
    pendingInteraction: pendingInteraction,
  );

  SessionCommandState withActivity(String? next) => SessionCommandState(
    phases: phases,
    models: models,
    modelOptions: modelOptions,
    modelsLoading: modelsLoading,
    currentModel: currentModel,
    activity: next,
    contextReadout: contextReadout,
    pendingInteraction: pendingInteraction,
  );

  SessionCommandState withContextReadout(ContextReadoutData? next) =>
      SessionCommandState(
        phases: phases,
        models: models,
        modelOptions: modelOptions,
        modelsLoading: modelsLoading,
        currentModel: currentModel,
        activity: activity,
        contextReadout: next,
        pendingInteraction: pendingInteraction,
      );

  SessionCommandState withPendingInteraction(PendingInteractionModel? next) =>
      SessionCommandState(
        phases: phases,
        models: models,
        modelOptions: modelOptions,
        modelsLoading: modelsLoading,
        currentModel: currentModel,
        activity: activity,
        contextReadout: contextReadout,
        pendingInteraction: next,
      );

  @override
  List<Object?> get props => [
    phases,
    models,
    modelOptions,
    modelsLoading,
    currentModel,
    activity,
    contextReadout,
    pendingInteraction,
  ];
}
