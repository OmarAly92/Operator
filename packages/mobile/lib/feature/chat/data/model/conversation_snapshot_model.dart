import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

class TurnSettingsModel extends Equatable {
  final String? model;
  final String? reasoningEffort;
  final String? approvalMode;

  const TurnSettingsModel({
    this.model,
    this.reasoningEffort,
    this.approvalMode,
  });

  factory TurnSettingsModel.fromJson(Map<String, dynamic>? json) =>
      TurnSettingsModel(
        model: _present(json?['model']),
        reasoningEffort: _present(json?['reasoningEffort']),
        approvalMode: _present(json?['approvalMode']),
      );

  Map<String, dynamic> toJson() => {
    if (model != null) 'model': model,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    if (approvalMode != null) 'approvalMode': approvalMode,
  };

  TurnSettingsModel copyWith({
    String? model,
    String? reasoningEffort,
    String? approvalMode,
  }) => TurnSettingsModel(
    model: model ?? this.model,
    reasoningEffort: reasoningEffort,
    approvalMode: approvalMode ?? this.approvalMode,
  );

  static String? _present(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  @override
  List<Object?> get props => [model, reasoningEffort, approvalMode];
}

class ConversationUsageModel extends Equatable {
  final int? contextUsed;
  final int? contextWindow;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;
  final double? cost;
  final String? currency;

  const ConversationUsageModel({
    this.contextUsed,
    this.contextWindow,
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
    this.cost,
    this.currency,
  });

  factory ConversationUsageModel.fromJson(Map<String, dynamic> json) =>
      ConversationUsageModel(
        contextUsed: (json['contextUsed'] as num?)?.toInt(),
        contextWindow: (json['contextWindow'] as num?)?.toInt(),
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        cachedTokens: (json['cachedTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        cost: (json['cost'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
      );

  @override
  List<Object?> get props => [
    contextUsed,
    contextWindow,
    inputTokens,
    outputTokens,
    cachedTokens,
    totalTokens,
    cost,
    currency,
  ];
}

class ConversationRateLimitsModel extends Equatable {
  final num? primaryUsedPercent;
  final num? secondaryUsedPercent;
  final int? primaryResetsInSeconds;
  final int? secondaryResetsInSeconds;
  final String? planLabel;

  const ConversationRateLimitsModel({
    this.primaryUsedPercent,
    this.secondaryUsedPercent,
    this.primaryResetsInSeconds,
    this.secondaryResetsInSeconds,
    this.planLabel,
  });

  factory ConversationRateLimitsModel.fromJson(Map<String, dynamic> json) =>
      ConversationRateLimitsModel(
        primaryUsedPercent: json['primaryUsedPercent'] as num?,
        secondaryUsedPercent: json['secondaryUsedPercent'] as num?,
        primaryResetsInSeconds: (json['primaryResetsInSeconds'] as num?)
            ?.toInt(),
        secondaryResetsInSeconds: (json['secondaryResetsInSeconds'] as num?)
            ?.toInt(),
        planLabel: json['planLabel'] as String?,
      );

  @override
  List<Object?> get props => [
    primaryUsedPercent,
    secondaryUsedPercent,
    primaryResetsInSeconds,
    secondaryResetsInSeconds,
    planLabel,
  ];
}

class ConversationAccountModel extends Equatable {
  final String? authMode;
  final String? planLabel;
  final String? reauthRequiredAt;
  final String? reauthReason;

  const ConversationAccountModel({
    this.authMode,
    this.planLabel,
    this.reauthRequiredAt,
    this.reauthReason,
  });

  factory ConversationAccountModel.fromJson(Map<String, dynamic> json) =>
      ConversationAccountModel(
        authMode: json['authMode'] as String?,
        planLabel: json['planLabel'] as String?,
        reauthRequiredAt: json['reauthRequiredAt'] as String?,
        reauthReason: json['reauthReason'] as String?,
      );

  @override
  List<Object?> get props => [
    authMode,
    planLabel,
    reauthRequiredAt,
    reauthReason,
  ];
}

class ConversationThreadStateModel extends Equatable {
  final String? status;
  final List<String> waitingOn;
  final String? archivedAt;
  final String? closedAt;

  const ConversationThreadStateModel({
    this.status,
    this.waitingOn = const [],
    this.archivedAt,
    this.closedAt,
  });

  factory ConversationThreadStateModel.fromJson(Map<String, dynamic> json) =>
      ConversationThreadStateModel(
        status: json['status'] as String?,
        waitingOn: (json['waitingOn'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        archivedAt: json['archivedAt'] as String?,
        closedAt: json['closedAt'] as String?,
      );

  @override
  List<Object?> get props => [status, waitingOn, archivedAt, closedAt];
}

class McpServerModel extends Equatable {
  final String? name;
  final String? status;
  final String? error;
  final String? failureReason;

  const McpServerModel({
    this.name,
    this.status,
    this.error,
    this.failureReason,
  });

  factory McpServerModel.fromJson(Map<String, dynamic> json) => McpServerModel(
    name: json['name'] as String?,
    status: json['status'] as String?,
    error: json['error'] as String?,
    failureReason: json['failureReason'] as String?,
  );

  bool get isBroken => status == 'failed' || status == 'cancelled';

  @override
  List<Object?> get props => [name, status, error, failureReason];
}

class ModelRerouteModel extends Equatable {
  final String? fromModel;
  final String? toModel;
  final String? reason;
  final String? at;

  const ModelRerouteModel({this.fromModel, this.toModel, this.reason, this.at});

  factory ModelRerouteModel.fromJson(Map<String, dynamic> json) =>
      ModelRerouteModel(
        fromModel: json['fromModel'] as String?,
        toModel: json['toModel'] as String?,
        reason: json['reason'] as String?,
        at: json['at'] as String?,
      );

  @override
  List<Object?> get props => [fromModel, toModel, reason, at];
}

class ConversationSnapshotModel extends Equatable {
  final String? conversationId;
  final String? sessionId;
  final String? harness;
  final String? mode;
  final String? controllerState;
  final String? controllerError;
  final int latestSequence;
  final int oldestSequence;
  final bool hasMoreBefore;
  final List<ConversationTurnModel> turns;
  final List<ConversationItemModel> items;
  final TurnSettingsModel settings;
  final String? title;
  final ConversationUsageModel? usage;
  final ConversationRateLimitsModel? rateLimits;
  final String? compactedAt;
  final ModelRerouteModel? modelReroute;
  final ConversationAccountModel? account;
  final ConversationThreadStateModel? threadState;
  final List<McpServerModel> mcpServers;
  final List<String> capabilities;

  const ConversationSnapshotModel({
    this.conversationId,
    this.sessionId,
    this.harness,
    this.mode,
    this.controllerState,
    this.controllerError,
    this.latestSequence = 0,
    this.oldestSequence = 0,
    this.hasMoreBefore = false,
    this.turns = const [],
    this.items = const [],
    this.settings = const TurnSettingsModel(),
    this.title,
    this.usage,
    this.rateLimits,
    this.compactedAt,
    this.modelReroute,
    this.account,
    this.threadState,
    this.mcpServers = const [],
    this.capabilities = const [],
  });

  factory ConversationSnapshotModel.fromJson(Map<String, dynamic> json) {
    final controller = json['controller'];
    final latestSequence = (json['latestSequence'] as num?)?.toInt() ?? 0;
    final items =
        <ConversationItemModel>[
          ...(json['messages'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ConversationMessageModel.fromJson),
          ...(json['activities'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ConversationActivityModel.fromJson),
        ]..sort(
          (left, right) => (left.sequence ?? 0).compareTo(right.sequence ?? 0),
        );

    return ConversationSnapshotModel(
      conversationId: json['conversationId'] as String?,
      sessionId: json['sessionId'] as String?,
      harness: json['harness'] as String?,
      mode: json['mode'] as String?,
      controllerState: controller is String
          ? controller
          : controller is Map<String, dynamic>
          ? controller['state'] as String?
          : null,
      controllerError: controller is Map<String, dynamic>
          ? controller['error'] as String?
          : json['controllerError'] as String?,
      latestSequence: latestSequence,
      oldestSequence:
          (json['oldestSequence'] as num?)?.toInt() ?? latestSequence + 1,
      hasMoreBefore: json['hasMoreBefore'] == true,
      turns: (json['turns'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationTurnModel.fromJson)
          .toList(),
      items: items,
      settings: TurnSettingsModel.fromJson(
        json['settings'] is Map<String, dynamic>
            ? json['settings'] as Map<String, dynamic>
            : null,
      ),
      title: json['title'] as String?,
      usage: json['usage'] is Map<String, dynamic>
          ? ConversationUsageModel.fromJson(
              json['usage'] as Map<String, dynamic>,
            )
          : null,
      rateLimits: json['rateLimits'] is Map<String, dynamic>
          ? ConversationRateLimitsModel.fromJson(
              json['rateLimits'] as Map<String, dynamic>,
            )
          : null,
      compactedAt: json['compactedAt'] as String?,
      modelReroute: json['modelReroute'] is Map<String, dynamic>
          ? ModelRerouteModel.fromJson(
              json['modelReroute'] as Map<String, dynamic>,
            )
          : null,
      account: json['account'] is Map<String, dynamic>
          ? ConversationAccountModel.fromJson(
              json['account'] as Map<String, dynamic>,
            )
          : null,
      threadState: json['threadState'] is Map<String, dynamic>
          ? ConversationThreadStateModel.fromJson(
              json['threadState'] as Map<String, dynamic>,
            )
          : null,
      mcpServers: (json['mcpServers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(McpServerModel.fromJson)
          .toList(),
      capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  ConversationSnapshotModel copyWith({
    int? oldestSequence,
    bool? hasMoreBefore,
    List<ConversationItemModel>? items,
    List<ConversationTurnModel>? turns,
  }) => ConversationSnapshotModel(
    conversationId: conversationId,
    sessionId: sessionId,
    harness: harness,
    mode: mode,
    controllerState: controllerState,
    controllerError: controllerError,
    latestSequence: latestSequence,
    oldestSequence: oldestSequence ?? this.oldestSequence,
    hasMoreBefore: hasMoreBefore ?? this.hasMoreBefore,
    turns: turns ?? this.turns,
    items: items ?? this.items,
    settings: settings,
    title: title,
    usage: usage,
    rateLimits: rateLimits,
    compactedAt: compactedAt,
    modelReroute: modelReroute,
    account: account,
    threadState: threadState,
    mcpServers: mcpServers,
    capabilities: capabilities,
  );

  bool can(String capability) => capabilities.contains(capability);

  ConversationTurnModel? get activeTurn {
    for (final turn in turns) {
      if (turn.state == 'running') return turn;
    }
    for (final turn in turns) {
      if (turn.state == 'queued') return turn;
    }
    return null;
  }

  ConversationTurnModel? turnForItem(ConversationItemModel item) {
    if (item.turnId == null) return null;
    for (final turn in turns) {
      if (turn.id == item.turnId) return turn;
    }
    return null;
  }

  List<McpServerModel> get brokenMcpServers =>
      mcpServers.where((server) => server.isBroken).toList();

  bool get hasTurnInFlight => turns.any((turn) => turn.isInFlight);

  bool get hasPendingRequest => items.any(
    (item) =>
        item is ConversationActivityModel &&
        item.isPending &&
        (item.activityKind == 'approval' || item.activityKind == 'user_input'),
  );

  @override
  List<Object?> get props => [
    conversationId,
    sessionId,
    harness,
    mode,
    controllerState,
    controllerError,
    latestSequence,
    oldestSequence,
    hasMoreBefore,
    turns,
    items,
    settings,
    title,
    usage,
    rateLimits,
    compactedAt,
    modelReroute,
    account,
    threadState,
    mcpServers,
    capabilities,
  ];
}
