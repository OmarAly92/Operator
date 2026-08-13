import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  ChatCubit(
    this._repository,
    this.sessionId, {
    this.configPoll = const Duration(seconds: 5),
    this.skillPoll = const Duration(seconds: 60),
    this.workspacePoll = const Duration(seconds: 30),
  }) : super(const ChatInitialState()) {
    scheduleMicrotask(() => unawaited(refresh()));
  }

  final ChatRepository _repository;
  final String sessionId;
  final Duration configPoll;
  final Duration skillPoll;
  final Duration workspacePoll;

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
  bool _catalogsStarted = false;
  int _revision = 0;

  bool get usesProviderConfig => snapshot?.can('config_options') ?? false;

  Future<void> refresh() async {
    refreshing = true;
    _emit();

    final result = await _repository.getConversationPage(sessionId);
    if (isClosed) return;

    result.when(
      onSuccess: (response) {
        final live = response.data;
        if (live != null) _replaceLivePage(live);
        unavailable = null;
        error = null;
      },
      onFailure: (failure) {
        final code = conversationErrorCode(failure);
        final message = conversationActionError(failure);
        if (code != null && kPermanentConversationCodes.contains(code)) {
          unavailable = ChatUnavailable(code: code, message: message);
        } else {
          error = message;
        }
      },
    );

    loading = false;
    refreshing = false;
    _emit();
    _startCatalogs();
  }

  Future<void> loadOlder() async {
    final current = snapshot;
    if (current == null || !current.hasMoreBefore || loadingOlder) return;

    loadingOlder = true;
    _emit();

    final result = await _repository.getConversationPage(
      sessionId,
      beforeSequence: current.oldestSequence,
    );
    if (isClosed) return;

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

  void _startCatalogs() {
    if (_catalogsStarted || unavailable != null || snapshot == null) return;
    _catalogsStarted = true;

    unawaited(_loadCatalogs());
    if (usesProviderConfig) {
      _configTimer = Timer.periodic(
        configPoll,
        (_) => unawaited(_loadConfigOptions()),
      );
    }
    _skillTimer = Timer.periodic(skillPoll, (_) => unawaited(_loadSkills()));
    _workspaceTimer = Timer.periodic(
      workspacePoll,
      (_) => unawaited(_loadWorkspace()),
    );
  }

  Future<void> _loadCatalogs() async {
    await Future.wait([
      if (usesProviderConfig) _loadConfigOptions() else _loadModels(),
      _loadSkills(),
      _loadWorkspace(),
    ]);
  }

  Future<void> _loadModels() async {
    final result = await _repository.getModels(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        models = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadConfigOptions() async {
    final result = await _repository.getConfigOptions(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        configOptions = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadSkills() async {
    final result = await _repository.getSkills(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        skills = response.data ?? const [];
        _emit();
      },
      onFailure: (_) {},
    );
  }

  Future<void> _loadWorkspace() async {
    final result = await _repository.getWorkspacePaths(sessionId);
    if (isClosed) return;
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

  @override
  Future<void> close() {
    _configTimer?.cancel();
    _skillTimer?.cancel();
    _workspaceTimer?.cancel();
    return super.close();
  }
}
