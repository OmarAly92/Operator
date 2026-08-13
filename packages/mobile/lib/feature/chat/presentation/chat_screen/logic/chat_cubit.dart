import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/workspace_paths_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_pages.dart';

part 'chat_state.dart';

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
