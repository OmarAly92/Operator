import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

typedef ConversationBlocksUnavailable = ({String code, String message});

sealed class ConversationBlocksState extends Equatable {
  const ConversationBlocksState();

  bool get supported =>
      error == null && unavailable == null && this is! ConversationBlocksUnsupportedState;

  bool get isReady => this is ConversationBlocksReadyState;

  String? get error => switch (this) {
    ConversationBlocksReadyState(:final error) => error,
    ConversationBlocksUnsupportedState() => null,
    ConversationBlocksInitialState() => null,
  };

  ConversationBlocksUnavailable? get unavailable => switch (this) {
    ConversationBlocksReadyState(:final unavailable) => unavailable,
    ConversationBlocksUnsupportedState(:final unavailable) => unavailable,
    ConversationBlocksInitialState() => null,
  };

  @override
  List<Object?> get props => [];
}

final class ConversationBlocksInitialState extends ConversationBlocksState {
  const ConversationBlocksInitialState();
}

final class ConversationBlocksReadyState extends ConversationBlocksState {
  const ConversationBlocksReadyState({
    required this.revision,
    required this.blocks,
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.hasOlder = false,
    this.error,
    this.unavailable,
  });

  final int revision;
  final List<SessionBlock> blocks;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool hasOlder;

  @override
  final String? error;

  @override
  final ConversationBlocksUnavailable? unavailable;

  ConversationBlocksReadyState copyWith({
    int? revision,
    List<SessionBlock>? blocks,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? hasOlder,
    String? error,
    ConversationBlocksUnavailable? unavailable,
    bool clearError = false,
    bool clearUnavailable = false,
  }) => ConversationBlocksReadyState(
    revision: revision ?? this.revision,
    blocks: blocks ?? this.blocks,
    isLoading: isLoading ?? this.isLoading,
    isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    hasOlder: hasOlder ?? this.hasOlder,
    error: clearError ? null : (error ?? this.error),
    unavailable:
        clearUnavailable ? null : (unavailable ?? this.unavailable),
  );

  @override
  List<Object?> get props => [
    revision,
    blocks,
    isLoading,
    isLoadingOlder,
    hasOlder,
    error,
    unavailable,
  ];
}

final class ConversationBlocksUnsupportedState
    extends ConversationBlocksState {
  const ConversationBlocksUnsupportedState(this.unavailable);

  @override
  final ConversationBlocksUnavailable unavailable;

  @override
  List<Object?> get props => [unavailable];
}
