import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';

part 'slash_menu_state.dart';

class SlashMenuCubit extends Cubit<SlashMenuState> {
  SlashMenuCubit(this._repository, this.composer, {required this.sessionId}) : super(const SlashMenuInitialState()) {
    composer.addListener(_onComposerChanged);
    getSlashCommands();
  }

  final TerminalRepository _repository;
  final TextEditingController composer;
  final String sessionId;

  List<SlashCommandModel> commands = const [];
  List<SlashCommandModel> matches = const [];
  String query = '';
  bool open = false;

  Future<void> getSlashCommands() async {
    emit(const GetSlashCommandsLoadingState());
    final result = await _repository.getSlashCommands(sessionId);
    if (isClosed) return;
    result.when(
      onSuccess: (response) {
        final listed = (response.data ?? const []).where((command) => (command.name ?? '').isNotEmpty);
        commands = [
          ...listed.where((command) => command.interactive != true),
          ...listed.where((command) => command.interactive == true),
        ];
        emit(const GetSlashCommandsSuccessState());
        _onComposerChanged();
      },
      onFailure: (failure) => emit(GetSlashCommandsFailureState(failure: failure)),
    );
  }

  void pick(SlashCommandModel command) {
    final text = '/${command.name} ';
    composer.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _onComposerChanged() {
    final text = composer.text;
    final isCommandPrefix = text.startsWith('/') && !text.contains(RegExp(r'\s'));
    final nextQuery = isCommandPrefix ? text.substring(1).toLowerCase() : '';
    final nextMatches = isCommandPrefix ? _match(nextQuery) : const <SlashCommandModel>[];
    final nextOpen = isCommandPrefix && nextMatches.isNotEmpty;
    if (nextOpen == open && nextQuery == query && _sameList(nextMatches, matches)) return;
    query = nextQuery;
    matches = nextMatches;
    open = nextOpen;
    if (!isClosed) emit(SlashMenuChangedState(open: open, matches: matches));
  }

  List<SlashCommandModel> _match(String q) {
    if (q.isEmpty) return commands;
    final byPrefix = commands.where((c) => c.name!.toLowerCase().startsWith(q)).toList();
    if (byPrefix.isNotEmpty) return byPrefix;
    return commands.where((c) => c.name!.toLowerCase().contains(q)).toList();
  }

  bool _sameList(List<SlashCommandModel> a, List<SlashCommandModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<void> close() {
    composer.removeListener(_onComposerChanged);
    return super.close();
  }
}
