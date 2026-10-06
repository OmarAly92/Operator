import 'dart:async';
import 'dart:typed_data';

import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class FakeRecentPhotos implements RecentPhotosDataSource {
  PhotoAccess access = PhotoAccess.granted;
  List<RecentPhotoModel> photos = [RecentPhotoModel(id: '1', thumbnail: Uint8List(4))];
  int? requested;
  int settings = 0;
  int manages = 0;
  int loads = 0;
  int accessRequests = 0;
  ComposerAttachment? Function(String id)? loadResult;
  Completer<void>? loadGate;
  Completer<void>? latestGate;

  @override
  Future<PhotoAccess> requestAccess() async {
    accessRequests++;
    return access;
  }

  @override
  Future<List<RecentPhotoModel>> latest(int count) async {
    requested = count;
    await latestGate?.future;
    return photos;
  }

  @override
  Future<ComposerAttachment?> load(String id) async {
    loads++;
    await loadGate?.future;
    final result = loadResult;
    if (result != null) return result(id);
    return ComposerAttachment(id: recentPhotoAttachmentId(id), name: 'photo-$id.jpg', mimeType: 'image/jpeg', bytes: Uint8List(2));
  }

  @override
  Future<void> openSettings() async => settings++;

  @override
  Future<void> manageLimited() async => manages++;
}
