import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/search/text_match.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/block_actions.dart';
import 'package:operator_mobile/feature/blocks/logic/block_find.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_find_bar.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_nav_controls.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_selection_bar.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/sticky_block_header.dart';

class BlocksBody extends StatefulWidget {
  const BlocksBody({super.key, this.onRerun});

  /// Fills the composer with a past prompt. Null means the screen has no
  /// composer to fill, and the re-run action is not offered at all.
  final void Function(String text)? onRerun;

  @override
  State<BlocksBody> createState() => BlocksBodyState();
}

class BlocksBodyState extends State<BlocksBody> {
  final GlobalKey<BlockListState> _listKey = GlobalKey<BlockListState>();
  final ValueNotifier<bool> _pinned = ValueNotifier<bool>(true);
  final ValueNotifier<StickyBlock?> _sticky = ValueNotifier<StickyBlock?>(null);
  final Set<String> _collapsed = <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  String? _lastSessionId;
  bool _findOpen = false;
  String _query = '';
  bool _filtering = false;
  String? _activeMatchId;
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _sticky.dispose();
    _pinned.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _syncCollapsed(String sessionId) {
    if (_lastSessionId == sessionId) return;
    _collapsed.clear();
    _selected.clear();
    _selectionMode = false;
    _findOpen = false;
    _query = '';
    _filtering = false;
    _activeMatchId = null;
    _queryController.clear();
    _lastSessionId = sessionId;
  }

  void _enterSelectionMode(String blockId) {
    setState(() {
      _selectionMode = true;
      _selected.add(blockId);
    });
    Haptics.select();
  }

  void _toggleSelected(String blockId, bool value) {
    setState(() {
      if (value) {
        _selected.add(blockId);
      } else {
        _selected.remove(blockId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  void _onAction(SessionBlock block, BlockAction action) {
    if (action.kind != BlockActionKind.rerun) return;
    final payload = action.payload;
    final onRerun = widget.onRerun;
    if (payload != null && onRerun != null) onRerun(payload);
  }

  void openFind() {
    setState(() {
      _findOpen = true;
    });
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _query = '';
      _activeMatchId = null;
      _queryController.clear();
    });
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _activeMatchId = null;
    });
  }

  void _toggleFilter(bool value) {
    setState(() {
      _filtering = value;
    });
  }

  void _nextMatch(List<BlockMatch> matches) {
    if (matches.isEmpty) return;
    setState(() {
      _activeMatchId = BlockFind.nextMatchId(
        matches,
        _activeMatchId,
        forward: true,
      );
    });
  }

  void _previousMatch(List<BlockMatch> matches) {
    if (matches.isEmpty) return;
    setState(() {
      _activeMatchId = BlockFind.nextMatchId(
        matches,
        _activeMatchId,
        forward: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<BlocksCubit, BlocksState>(
      builder: (context, state) {
        final cubit = context.read<BlocksCubit>();

        if (state is BlocksUnsupportedState) {
          return _notice(
            context,
            'Blocks are unavailable for ${state.harness ?? 'this agent'}. Use the raw terminal instead.',
          );
        }

        final error = cubit.error;
        if (error != null && cubit.blocks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  error,
                  style: AppTextStyle.style12Regular.copyWith(
                    color: skin.attention,
                  ),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: cubit.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (cubit.blocks.isEmpty) {
          return _notice(
            context,
            cubit.loading
                ? 'Loading blocks...'
                : 'No blocks yet. They appear as the agent works.',
          );
        }

        _syncCollapsed(cubit.sessionId);
        final actionContext = BlockActionContext(
          mode: 'tui',
          canSend: widget.onRerun != null,
        );
        final allBlocks = cubit.blocks;
        final matches = _query.trim().isEmpty
            ? const <BlockMatch>[]
            : BlockFind.matches(allBlocks, _query);
        final filterResult = _filtering
            ? BlockFind.filter(allBlocks, _query, findContextBlocks)
            : BlockFilterResult(
                blocks: allBlocks,
                matchIds: const {},
                hiddenCount: 0,
              );
        final visibleBlocks = _filtering ? filterResult.blocks : allBlocks;
        final activeMatch = _activeMatchId == null
            ? null
            : matches.firstWhere(
                (match) => match.blockId == _activeMatchId,
                orElse: () => BlockMatch(
                  blockId: '',
                  field: BlockMatchField.displayName,
                  score: const MatchScore(tier: 0, offset: 0),
                  ranges: const <MatchRange>[],
                ),
              );
        final highlight = (activeMatch != null && activeMatch.blockId.isNotEmpty)
            ? activeMatch
            : null;
        final currentIndex = (highlight == null)
            ? 0
            : matches.indexWhere((match) => match.blockId == _activeMatchId) + 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (highlight == null) return;
          final list = _listKey.currentState;
          if (list == null) return;
          final index = visibleBlocks.indexWhere(
            (block) => block.id == _activeMatchId,
          );
          if (index >= 0) list.scrollBlockIntoView(index);
        });

        return PopScope(
          canPop: !_selectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (_selectionMode) _exitSelectionMode();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    if (_findOpen)
                      BlockFindBar(
                        queryController: _queryController,
                        onQueryChanged: _onQueryChanged,
                        onNext: () => _nextMatch(matches),
                        onPrevious: () => _previousMatch(matches),
                        onClose: _closeFind,
                        onToggleFilter: _toggleFilter,
                        currentIndex: currentIndex,
                        totalMatches: matches.length,
                        filtering: _filtering,
                        hiddenCount: filterResult.hiddenCount,
                      ),
                    Expanded(
                      child: BlockList(
                        key: _listKey,
                        sessionId: cubit.sessionId,
                        blocks: visibleBlocks,
                        header: _olderControl(context, cubit),
                        sticky: _sticky,
                        pinnedListenable: _pinned,
                        actionContext: actionContext,
                        onAction: _onAction,
                        collapsedIds: _collapsed,
                        onToggleCollapse: (id) => setState(() {
                          if (!_collapsed.add(id)) _collapsed.remove(id);
                        }),
                        highlights: highlight == null
                            ? const <String, BlockMatch>{}
                            : <String, BlockMatch>{highlight.blockId: highlight},
                        selectedIds: _selected,
                        selectionMode: _selectionMode,
                        onToggleSelect: _toggleSelected,
                        onLongPressHeader: _selectionMode
                            ? null
                            : _enterSelectionMode,
                      ),
                    ),
                    if (_selectionMode)
                      BlockSelectionBar(
                        selectedIds: _selected,
                        documentOrder: visibleBlocks,
                        onCancel: _exitSelectionMode,
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: IgnorePointer(child: StickyBlockHeader(sticky: _sticky)),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _pinned,
                  builder: (context, pinned, _) => _selectionMode
                      ? const SizedBox.shrink()
                      : BlockNavControls(
                          onPrevious: () => _listKey.currentState
                              ?.scrollToBoundary(forward: false),
                          onNext: () => _listKey.currentState
                              ?.scrollToBoundary(forward: true),
                          onLatest: () => _listKey.currentState?.jumpToLatest(),
                          showLatest: !pinned,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _olderControl(BuildContext context, BlocksCubit cubit) {
    if (cubit.loadingOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AppText(
          'Loading older blocks...',
          style: AppTextStyle.style11Regular.copyWith(
            color: context.skin.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!cubit.hasOlder) return null;
    return Center(
      child: TextButton(
        onPressed: cubit.loadOlder,
        child: const Text('Load older blocks'),
      ),
    );
  }

  Widget _notice(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AppText(
        message,
        style: AppTextStyle.style12Regular.copyWith(
          color: context.skin.textTertiary,
        ),
        maxLines: 4,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
