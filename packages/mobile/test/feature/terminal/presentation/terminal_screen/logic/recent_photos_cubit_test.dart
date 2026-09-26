import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart';

import '../../../fake_recent_photos.dart';

void main() {
  late FakeRecentPhotos source;

  setUp(() => source = FakeRecentPhotos());

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'expanding with access loads the latest 30 photos',
    build: () => RecentPhotosCubit(source),
    act: (cubit) => cubit.toggle(),
    expect: () => [
      const RecentPhotosState(expanded: true, loading: true),
      RecentPhotosState(expanded: true, access: PhotoAccess.granted, photos: source.photos),
    ],
    verify: (_) => expect(source.requested, kRecentPhotoCount),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'denied access collapses the row and never lists photos',
    build: () => RecentPhotosCubit(source..access = PhotoAccess.denied),
    act: (cubit) => cubit.toggle(),
    expect: () => [
      const RecentPhotosState(expanded: true, loading: true),
      const RecentPhotosState(access: PhotoAccess.denied),
    ],
    verify: (_) => expect(source.requested, isNull),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'limited access still lists the photos it may see, and manage reloads them',
    build: () => RecentPhotosCubit(source..access = PhotoAccess.limited),
    act: (cubit) async {
      await cubit.toggle();
      source.photos = [RecentPhotoModel(id: '2', thumbnail: Uint8List(1))];
      await cubit.manageLimited();
    },
    skip: 2,
    expect: () => [
      RecentPhotosState(expanded: true, access: PhotoAccess.limited, photos: [RecentPhotoModel(id: '2', thumbnail: Uint8List(1))]),
    ],
    verify: (_) => expect(source.manages, 1),
  );

  blocTest<RecentPhotosCubit, RecentPhotosState>(
    'toggling an open row collapses it without asking again',
    build: () => RecentPhotosCubit(source),
    seed: () => RecentPhotosState(expanded: true, access: PhotoAccess.granted, photos: source.photos),
    act: (cubit) => cubit.toggle(),
    expect: () => [RecentPhotosState(access: PhotoAccess.granted, photos: source.photos)],
    verify: (_) => expect(source.requested, isNull),
  );
}
