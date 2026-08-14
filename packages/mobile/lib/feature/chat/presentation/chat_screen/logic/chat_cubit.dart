import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_approval_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_conversation_title_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/steer_conversation_params.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_pages.dart';

part 'chat_state.dart';

enum ConversationAction {
  steer,
  interrupt,
  approval,
  input,
  compact,
  rollback,
  settings,
  config,
  mcp,
  rename,
}

class PendingSend extends Equatable {
  const PendingSend({
    required this.id,
    required this.text,
    this.failed = false,
    this.error,
    this.attachments,
    this.resources,
    this.requiresStaging = false,
  });

  final String id;
  final String text;
  final bool failed;
  final String? error;
  final List<ChatImageModel>? attachments;
  final List<ChatResourceModel>? resources;
  final bool requiresStaging;

  PendingSend copyWith({bool? failed, String? error, bool? requiresStaging}) =>
      PendingSend(
        id: id,
        text: text,
        failed: failed ?? this.failed,
        error: error,
        attachments: attachments,
        resources: resources,
        requiresStaging: requiresStaging ?? this.requiresStaging,
      );

  @override
  List<Object?> get props => [
    id,
    text,
    failed,
    error,
    attachments,
    resources,
    requiresStaging,
  ];
}

class ChatUnavailable extends Equatable {
  const ChatUnavailable({required this.message, this.code});

  final String? code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

class ChatCubit extends Cubit<ChatState> {
  factory ChatCubit(
    ChatRepository repository,
    String sessionId, {
    Duration configPoll = const Duration(seconds: 5),
    Duration skillPoll = const Duration(seconds: 60),
    Duration workspacePoll = const Duration(seconds: 30),
  }) => ChatCubit._(
    repository,
    sessionId,
    configPoll: configPoll,
    skillPoll: skillPoll,
    workspacePoll: workspacePoll,
  );

  ChatCubit._(
    this._repository,
    this.sessionId, {
    required this._configPoll,
    required this._skillPoll,
    required this._workspacePoll,
  }) : super(const ChatInitialState()) {
    scheduleMicrotask(() => unawaited(refresh()));
  }

  final ChatRepository _repository;
  final String sessionId;
  final Duration _configPoll;
  final Duration _skillPoll;
  final Duration _workspacePoll;

  final List<ConversationSnapshotModel> _pages = [];

  ConversationSnapshotModel? snapshot;
  bool loading = true;
  bool refreshing = false;
  bool loadingOlder = false;
  String? error;
  ChatUnavailable? unavailable;
  List<ChatModelModel> models = [];
  List<ChatConfigOptionModel> configOptions = [];
  List<ChatSkillModel> skills = [];
  WorkspacePathsModel workspace = const WorkspacePathsModel();
  List<PendingSend> pendingSends = [];
  Set<ConversationAction> pendingActions = {};
  String? actionError;
  Map<ConversationAction, String> actionErrors = {};
  Map<ConversationAction, String> actionCodes = {};

  Timer? _configTimer;
  Timer? _skillTimer;
  Timer? _workspaceTimer;
  bool _commonCatalogsStarted = false;
  bool? _providerOwnsConfig;
  String? _catalogConversationId;
  int _refreshGeneration = 0;
  int _paginationGeneration = 0;
  int _catalogGeneration = 0;
  int _commonCatalogGeneration = 0;
  int _revision = 0;

  bool get usesProviderConfig => snapshot?.can('config_options') ?? false;

  Future<void> send(
    String text, {
    List<ChatImageModel>? attachments,
    List<ChatResourceModel>? resources,
  }) async {
    if (isClosed) return;
    final pending = PendingSend(
      id: _clientMessageId(),
      text: text,
      attachments: attachments,
      resources: resources,
      requiresStaging: attachments != null && attachments.isNotEmpty,
    );
    if (pending.requiresStaging) return _stageAndDeliver(pending);
    await _deliver(pending);
  }

  Future<void> retrySend(String id) async {
    if (isClosed) return;
    for (final pending in pendingSends) {
      if (pending.id == id) {
        if (pending.requiresStaging) {
          await _stageAndDeliver(pending);
        } else {
          await _deliver(pending);
        }
        return;
      }
    }
  }

  void discardSend(String id) {
    if (isClosed) return;
    pendingSends = pendingSends.where((pending) => pending.id != id).toList();
    _emit();
  }

  Future<void> steer(String text) => _runAction(
    ConversationAction.steer,
    () => _repository.steer(
      sessionId,
      SteerConversationParams(text: text, clientMessageId: _clientMessageId()),
    ),
  );

  Future<void> interrupt() => _runAction(
    ConversationAction.interrupt,
    () => _repository.interrupt(sessionId),
  );

  Future<void> resolveApproval(String requestId, String decisionId) =>
      _runAction(
        ConversationAction.approval,
        () => _repository.resolveApproval(
          sessionId,
          ResolveApprovalParams(requestId: requestId, decisionId: decisionId),
        ),
      );

  Future<void> resolveInput(
    String requestId,
    String action, [
    Map<String, dynamic>? content,
  ]) => _runAction(
    ConversationAction.input,
    () => _repository.resolveInput(
      sessionId,
      ResolveInputParams(
        requestId: requestId,
        action: action,
        content: content,
      ),
    ),
  );

  Future<void> compact() => _runAction(
    ConversationAction.compact,
    () => _repository.compact(sessionId),
  );

  Future<int> rollback(String turnId) async {
    var discarded = 0;
    await _runAction(ConversationAction.rollback, () async {
      final result = await _repository.rollbackTurn(
        sessionId,
        RollbackTurnParams(turnId: turnId),
      );
      discarded = result.getOrDefault(0);
      return result.isSuccess
          ? Result<bool, Failure>.success(true)
          : result.asFailure<bool>();
    }, resetHistoricalPages: true);
    return discarded;
  }

  Future<void> chooseSettings(TurnSettingsModel settings) => _runAction(
    ConversationAction.settings,
    () => _repository.setSettings(sessionId, settings),
  );

  Future<void> setConfigOption(SetConfigOptionParams params) =>
      _runAction(ConversationAction.config, () async {
        final catalogGeneration = _catalogGeneration;
        final conversationId = snapshot?.conversationId;
        final providerOwnsConfig = usesProviderConfig;
        final result = await _repository.setConfigOption(sessionId, params);
        final ownsCurrentCatalog =
            !isClosed &&
            catalogGeneration == _catalogGeneration &&
            conversationId == snapshot?.conversationId &&
            providerOwnsConfig == usesProviderConfig;
        if (ownsCurrentCatalog) {
          result.when(
            onSuccess: (response) {
              configOptions = response.data ?? configOptions;
            },
            onFailure: (_) {},
          );
        }
        return result.isSuccess
            ? Result<bool, Failure>.success(true)
            : result.asFailure<bool>();
      });

  Future<void> reloadMcp() => _runAction(
    ConversationAction.mcp,
    () => _repository.reloadMcpServers(sessionId),
  );

  Future<void> rename(String title) => _runAction(
    ConversationAction.rename,
    () => _repository.setTitle(
      sessionId,
      SetConversationTitleParams(title: title),
    ),
  );

  Future<void> resumeAgent() async {
    if (isClosed) return;
    actionError = null;
    _emit();
    final result = await _repository.resumeAgent(sessionId);
    if (isClosed) return;
    if (result.isSuccess) {
      await refresh();
      return;
    }
    late Failure failure;
    result.when(onSuccess: (_) {}, onFailure: (value) => failure = value);
    actionError = conversationActionError(failure);
    _emit();
  }

  Future<void> refresh() async {
    if (isClosed) return;
    final generation = ++_refreshGeneration;
    refreshing = true;
    _emit();

    final result = await _repository.getConversationPage(sessionId);
    if (isClosed || generation != _refreshGeneration) return;

    result.when(
      onSuccess: (response) => _applyRefreshSuccess(response.data),
      onFailure: _applyRefreshFailure,
    );

    loading = false;
    refreshing = false;
    _emit();
  }

  void _applyRefreshSuccess(ConversationSnapshotModel? live) {
    if (live != null) _replaceLivePage(live);
    unavailable = null;
    error = null;
    _reconcileCatalogs();
  }

  void _applyRefreshFailure(Failure failure) {
    final code = conversationErrorCode(failure);
    final message = conversationActionError(failure);
    if (code != null && kPermanentConversationCodes.contains(code)) {
      unavailable = ChatUnavailable(code: code, message: message);
      error = null;
      _stopCatalogs();
    } else {
      error = message;
    }
  }

  Future<void> loadOlder() async {
    if (isClosed) return;
    final current = snapshot;
    if (current == null || !current.hasMoreBefore || loadingOlder) return;
    final conversationId = current.conversationId;
    final cursor = current.oldestSequence;
    final generation = ++_paginationGeneration;

    loadingOlder = true;
    _emit();

    final result = await _repository.getConversationPage(
      sessionId,
      beforeSequence: cursor,
    );
    if (isClosed) return;
    final live = snapshot;
    final isCurrentRequest =
        generation == _paginationGeneration &&
        live?.conversationId == conversationId &&
        live?.oldestSequence == cursor;
    if (!isCurrentRequest) {
      loadingOlder = false;
      _emit();
      return;
    }

    result.when(
      onSuccess: (response) {
        final older = response.data;
        if (older != null) {
          _pages.add(older);
          _mergePages();
        }
      },
      onFailure: (failure) => error = conversationActionError(failure),
    );

    loadingOlder = false;
    _emit();
  }

  void _replaceLivePage(ConversationSnapshotModel live) {
    _paginationGeneration += 1;
    final previous = _pages.isEmpty ? null : _pages.first;
    if (previous?.conversationId != null &&
        previous!.conversationId != live.conversationId) {
      final retainedPages = discardHistoricalPages(_pages);
      _pages
        ..clear()
        ..addAll(retainedPages);
      _pages[0] = live;
    } else if (_pages.isEmpty) {
      _pages.add(live);
    } else {
      _pages[0] = live;
    }
    _mergePages();
  }

  void _mergePages() => snapshot = mergeConversationPages(_pages);

  void _reconcileCatalogs() {
    final current = snapshot;
    if (isClosed || unavailable != null || current == null) return;

    if (!_commonCatalogsStarted) {
      _startCommonCatalogs();
    }

    final providerOwnsConfig = usesProviderConfig;
    final conversationChanged =
        _catalogConversationId != current.conversationId;
    final ownershipChanged = _providerOwnsConfig != providerOwnsConfig;
    if (!conversationChanged && !ownershipChanged) return;

    _switchProviderCatalog(
      conversationId: current.conversationId,
      providerOwnsConfig: providerOwnsConfig,
    );
  }

  void _startCommonCatalogs() {
    _commonCatalogsStarted = true;
    unawaited(_loadSkills());
    unawaited(_loadWorkspace());
    _skillTimer = Timer.periodic(_skillPoll, (_) => unawaited(_loadSkills()));
    _workspaceTimer = Timer.periodic(
      _workspacePoll,
      (_) => unawaited(_loadWorkspace()),
    );
  }

  void _switchProviderCatalog({
    required String? conversationId,
    required bool providerOwnsConfig,
  }) {
    _catalogConversationId = conversationId;
    _providerOwnsConfig = providerOwnsConfig;
    _catalogGeneration += 1;
    _configTimer?.cancel();
    _configTimer = null;

    if (providerOwnsConfig) {
      models = [];
      unawaited(_loadConfigOptions());
      _configTimer = Timer.periodic(
        _configPoll,
        (_) => unawaited(_loadConfigOptions()),
      );
    } else {
      configOptions = [];
      unawaited(_loadModels());
    }
  }

  Future<void> _loadModels() async {
    if (isClosed || unavailable != null || usesProviderConfig) return;
    final generation = _catalogGeneration;
    final result = await _repository.getModels(sessionId);
    if (isClosed ||
        unavailable != null ||
        generation != _catalogGeneration ||
        usesProviderConfig) {
      return;
    }
    result.when(
      onSuccess: (response) {
        models = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadConfigOptions() async {
    if (isClosed || unavailable != null || !usesProviderConfig) return;
    final generation = _catalogGeneration;
    final result = await _repository.getConfigOptions(sessionId);
    if (isClosed ||
        unavailable != null ||
        generation != _catalogGeneration ||
        !usesProviderConfig) {
      return;
    }
    result.when(
      onSuccess: (response) {
        configOptions = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadSkills() async {
    if (isClosed || unavailable != null) return;
    final generation = _commonCatalogGeneration;
    final result = await _repository.getSkills(sessionId);
    if (isClosed ||
        unavailable != null ||
        generation != _commonCatalogGeneration) {
      return;
    }
    result.when(
      onSuccess: (response) {
        skills = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadWorkspace() async {
    if (isClosed || unavailable != null) return;
    final generation = _commonCatalogGeneration;
    final result = await _repository.getWorkspacePaths(sessionId);
    if (isClosed ||
        unavailable != null ||
        generation != _commonCatalogGeneration) {
      return;
    }
    result.when(
      onSuccess: (response) {
        workspace = response.data ?? const WorkspacePathsModel();
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _deliver(PendingSend pending) async {
    if (isClosed) return;
    pendingSends = _upsertPending(
      pendingSends,
      pending.copyWith(failed: false),
    );
    _emit();

    final result = await _repository.sendMessage(
      sessionId,
      SendMessageParams(
        text: pending.text,
        clientMessageId: pending.id,
        attachments: pending.attachments,
        resources: pending.resources,
      ),
    );
    if (isClosed) return;

    if (result.isSuccess) {
      pendingSends = pendingSends
          .where((item) => item.id != pending.id)
          .toList();
      await refresh();
      return;
    }

    late Failure failure;
    result.when(onSuccess: (_) {}, onFailure: (value) => failure = value);
    pendingSends = _upsertPending(
      pendingSends,
      pending.copyWith(failed: true, error: conversationActionError(failure)),
    );
    _emit();
  }

  Future<void> _stageAndDeliver(PendingSend pending) async {
    if (isClosed) return;
    pendingSends = _upsertPending(
      pendingSends,
      pending.copyWith(failed: false),
    );
    _emit();
    final stagingResult = await _repository.stageAttachments(
      sessionId,
      StageAttachmentsParams(attachments: pending.attachments!),
    );
    if (isClosed) return;

    List<String>? paths;
    Failure? stagingFailure;
    stagingResult.when(
      onSuccess: (stagedPaths) => paths = stagedPaths,
      onFailure: (failure) => stagingFailure = failure,
    );
    if (stagingFailure != null) {
      pendingSends = _upsertPending(
        pendingSends,
        pending.copyWith(
          failed: true,
          error: conversationActionError(stagingFailure!),
        ),
      );
      _emit();
      return;
    }

    await _deliver(
      PendingSend(
        id: pending.id,
        text: _withAttachmentReferences(pending.text, paths!),
        attachments: snapshot?.can('images') ?? false
            ? pending.attachments
            : null,
        resources: pending.resources,
      ),
    );
  }

  Future<void> _runAction(
    ConversationAction kind,
    Future<Result<bool, Failure>> Function() action, {
    bool resetHistoricalPages = false,
  }) async {
    if (isClosed) return;
    pendingActions = {...pendingActions, kind};
    actionError = null;
    actionErrors = {...actionErrors}..remove(kind);
    actionCodes = {...actionCodes}..remove(kind);
    _emit();

    try {
      final result = await action();
      if (isClosed) return;

      if (result.isSuccess) {
        if (resetHistoricalPages) {
          _paginationGeneration += 1;
          final retainedPages = discardHistoricalPages(_pages);
          _pages
            ..clear()
            ..addAll(retainedPages);
          _mergePages();
        }
        await refresh();
        return;
      }

      late Failure failure;
      result.when(onSuccess: (_) {}, onFailure: (value) => failure = value);
      final message = conversationActionError(failure);
      actionError = message;
      actionErrors = {...actionErrors, kind: message};
      final code = conversationErrorCode(failure);
      if (code != null) actionCodes = {...actionCodes, kind: code};
    } finally {
      if (!isClosed) {
        pendingActions = {...pendingActions}..remove(kind);
        _emit();
      }
    }
  }

  static List<PendingSend> _upsertPending(
    List<PendingSend> items,
    PendingSend next,
  ) {
    final index = items.indexWhere((item) => item.id == next.id);
    if (index < 0) return [...items, next];
    return [...items]..[index] = next;
  }

  static String _clientMessageId() =>
      'mobile-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
      '${Random().nextInt(1 << 32).toRadixString(36)}';

  static String _withAttachmentReferences(String text, List<String> paths) {
    if (paths.isEmpty) return text;
    final references = paths.map((path) => '- $path').join('\n');
    final trimmed = text.trim();
    return '$trimmed${trimmed.isEmpty ? '' : '\n\n'}'
        'Attached files are available in the worktree:\n$references';
  }

  void _emit() {
    if (!isClosed) emit(ChatReadyState(++_revision));
  }

  void _stopCatalogs() {
    _catalogGeneration += 1;
    _commonCatalogGeneration += 1;
    _configTimer?.cancel();
    _skillTimer?.cancel();
    _workspaceTimer?.cancel();
    _configTimer = null;
    _skillTimer = null;
    _workspaceTimer = null;
    _commonCatalogsStarted = false;
    _providerOwnsConfig = null;
    _catalogConversationId = null;
  }

  @override
  Future<void> close() {
    _stopCatalogs();
    return super.close();
  }
}
