import 'dart:io';

import 'package:operator_mobile/core/helpers/logging/app_logger.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:photo_manager/photo_manager.dart';

enum PhotoAccess { granted, limited, denied }

String recentPhotoAttachmentId(String assetId) => 'photo:$assetId';

abstract class RecentPhotosDataSource {
  Future<PhotoAccess> requestAccess();
  Future<List<RecentPhotoModel>> latest(int count);
  Future<ComposerAttachment?> load(String id);
  Future<void> openSettings();
  Future<void> manageLimited();
}

class RecentPhotosDataSourceImp implements RecentPhotosDataSource {
  static const int thumbnailSide = 200;
  static const int fullSide = 2048;
  static const int quality = 85;

  static const PermissionRequestOption _imagesOnly = PermissionRequestOption(
    androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: false),
  );

  @override
  Future<PhotoAccess> requestAccess() async {
    try {
      final state = await PhotoManager.requestPermissionExtend(requestOption: _imagesOnly);
      return switch (state) {
        PermissionState.authorized => PhotoAccess.granted,
        PermissionState.limited => PhotoAccess.limited,
        _ => PhotoAccess.denied,
      };
    } catch (error, stackTrace) {
      AppLogger.warning('Could not ask for photo access', exception: error, stackTrace: stackTrace);
      return PhotoAccess.denied;
    }
  }

  @override
  Future<List<RecentPhotoModel>> latest(int count) async {
    try {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
      if (albums.isEmpty) return const [];
      final assets = await albums.first.getAssetListPaged(page: 0, size: count);
      return Future.wait([
        for (final asset in assets)
          asset
              .thumbnailDataWithSize(const ThumbnailSize.square(thumbnailSide), quality: quality)
              .then((thumbnail) => RecentPhotoModel(id: asset.id, thumbnail: thumbnail)),
      ]);
    } catch (error, stackTrace) {
      AppLogger.warning('Could not list recent photos', exception: error, stackTrace: stackTrace);
      return const [];
    }
  }

  @override
  Future<ComposerAttachment?> load(String id) async {
    try {
      final asset = await AssetEntity.fromId(id);
      if (asset == null) return null;
      const size = ThumbnailSize(fullSide, fullSide);
      final option = Platform.isIOS
          ? ThumbnailOption.ios(
              size: size,
              quality: quality,
              deliveryMode: DeliveryMode.highQualityFormat,
              resizeMode: ResizeMode.exact,
            )
          : const ThumbnailOption(size: size, quality: quality);
      final bytes = await asset.thumbnailDataWithOption(option);
      if (bytes == null) return null;
      return ComposerAttachment(
        id: recentPhotoAttachmentId(id),
        name: 'photo-${id.hashCode.toUnsigned(32)}.jpg',
        mimeType: 'image/jpeg',
        bytes: bytes,
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Could not load a recent photo', exception: error, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await PhotoManager.openSetting();
    } catch (error, stackTrace) {
      AppLogger.warning('Could not open Settings for photo access', exception: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> manageLimited() async {
    try {
      await PhotoManager.presentLimited(type: RequestType.image);
    } catch (error, stackTrace) {
      AppLogger.warning('Could not present the limited photo picker', exception: error, stackTrace: stackTrace);
    }
  }
}
