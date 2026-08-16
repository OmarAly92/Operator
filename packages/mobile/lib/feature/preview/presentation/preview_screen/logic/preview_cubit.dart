import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

part 'preview_state.dart';

class PreviewCubit extends Cubit<PreviewState> {
  factory PreviewCubit(
    PreviewRepository repository,
    String sessionId, {
    String? previewUrl,
    Duration poll = const Duration(seconds: 5),
  }) => PreviewCubit._(repository, sessionId, previewUrl: previewUrl, poll: poll);

  PreviewCubit._(
    this._repository,
    this.sessionId, {
    required this.previewUrl,
    required this._poll,
  }) : super(const PreviewInitialState()) {
    unawaited(refresh());
    _timer = Timer.periodic(_poll, (_) => unawaited(refresh()));
  }

  final PreviewRepository _repository;
  final String sessionId;
  final String? previewUrl;
  final Duration _poll;

  PreviewModel? preview;
  bool loading = true;
  String? error;

  Timer? _timer;
  int _revision = 0;

  bool get hasPreview => preview != null && previewWorthShowing(preview!.entry);

  Future<void> refresh() async {
    if (isClosed) return;
    final result = await _repository.getPreview(sessionId, previewUrl: previewUrl);
    if (isClosed) return;
    result.when(
      onSuccess: (value) {
        preview = value;
        error = null;
      },
      onFailure: (failure) => error = failure.message,
    );
    loading = false;
    emit(PreviewReadyState(++_revision));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
