import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

const int kRecentPhotoCount = 30;

class RecentPhotosState extends Equatable {
  const RecentPhotosState({this.expanded = false, this.loading = false, this.access, this.photos = const []});

  final bool expanded;
  final bool loading;
  final PhotoAccess? access;
  final List<RecentPhotoModel> photos;

  @override
  List<Object?> get props => [expanded, loading, access, photos];
}

class RecentPhotosCubit extends Cubit<RecentPhotosState> {
  RecentPhotosCubit(this._source) : super(const RecentPhotosState());

  final RecentPhotosDataSource _source;

  Future<void> toggle() async {
    if (state.expanded) {
      emit(RecentPhotosState(access: state.access, photos: state.photos));
      return;
    }
    emit(const RecentPhotosState(expanded: true, loading: true));
    final access = await _source.requestAccess();
    if (isClosed) return;
    if (access == PhotoAccess.denied) {
      emit(const RecentPhotosState(access: PhotoAccess.denied));
      return;
    }
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed) return;
    emit(RecentPhotosState(expanded: true, access: access, photos: photos));
  }

  Future<ComposerAttachment?> load(String id) => _source.load(id);

  Future<void> openSettings() => _source.openSettings();

  Future<void> manageLimited() async {
    await _source.manageLimited();
    final photos = await _source.latest(kRecentPhotoCount);
    if (isClosed) return;
    emit(RecentPhotosState(expanded: true, access: state.access, photos: photos));
  }
}
