import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

const int kRecentPhotoCount = 30;

class RecentPhotosState extends Equatable {
  const RecentPhotosState({
    this.expanded = false,
    this.loading = false,
    this.access,
    this.photos = const [],
    this.loadingIds = const {},
    this.notice,
  });

  final bool expanded;
  final bool loading;
  final PhotoAccess? access;
  final List<RecentPhotoModel> photos;
  final Set<String> loadingIds;
  final String? notice;

  RecentPhotosState copyWith({Set<String>? loadingIds, String? notice, bool clearNotice = false}) => RecentPhotosState(
    expanded: expanded,
    loading: loading,
    access: access,
    photos: photos,
    loadingIds: loadingIds ?? this.loadingIds,
    notice: clearNotice ? null : notice ?? this.notice,
  );

  @override
  List<Object?> get props => [expanded, loading, access, photos, loadingIds, notice];
}

class RecentPhotosCubit extends Cubit<RecentPhotosState> {
  RecentPhotosCubit(this._source) : super(const RecentPhotosState());

  final RecentPhotosDataSource _source;

  bool isLoading(String id) => state.loadingIds.contains(id);

  Future<void> toggle() async {
    if (state.expanded) {
      emit(RecentPhotosState(access: state.access, photos: state.photos, loadingIds: state.loadingIds));
      return;
    }
    emit(RecentPhotosState(expanded: true, loading: true, loadingIds: state.loadingIds));
    final access = await _source.requestAccess();
    if (isClosed) return;
    await _show(access);
  }

  Future<void> allowAccess() async {
    final access = await _source.requestAccess();
    if (isClosed) return;
    if (access == PhotoAccess.denied) {
      await _source.openSettings();
      return;
    }
    emit(RecentPhotosState(expanded: true, loading: true, loadingIds: state.loadingIds));
    await _show(access);
  }

  Future<void> _show(PhotoAccess access) async {
    if (access == PhotoAccess.denied) {
      emit(RecentPhotosState(access: PhotoAccess.denied, loadingIds: state.loadingIds));
      return;
    }
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed || !state.expanded) return;
    emit(RecentPhotosState(expanded: true, access: access, photos: photos, loadingIds: state.loadingIds));
  }

  Future<ComposerAttachment?> load(String id) async {
    if (isLoading(id)) return null;
    emit(state.copyWith(loadingIds: {...state.loadingIds, id}));
    try {
      return await _source.load(id);
    } finally {
      if (!isClosed) emit(state.copyWith(loadingIds: {...state.loadingIds}..remove(id)));
    }
  }

  void showNotice(String? notice) {
    if (isClosed || notice == state.notice) return;
    emit(state.copyWith(notice: notice, clearNotice: notice == null));
  }

  Future<void> manageLimited() async {
    await _source.manageLimited();
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed) return;
    emit(RecentPhotosState(expanded: true, access: state.access, photos: photos, loadingIds: state.loadingIds));
  }
}
