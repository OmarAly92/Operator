import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  test('one thumbnail that fails leaves a placeholder and keeps the rest of the strip', () async {
    final models = await recentPhotoModels<String>(
      ['a', 'b', 'c'],
      id: (asset) => asset,
      thumbnail: (asset) async {
        if (asset == 'b') throw StateError('iCloud photo unavailable');
        return Uint8List(3);
      },
    );

    expect(models.map((model) => model.id), ['a', 'b', 'c']);
    expect(models[0].thumbnail, isNotNull);
    expect(models[1].thumbnail, isNull);
    expect(models[2].thumbnail, isNotNull);
  });

  test('a photo is fitted so its long edge is at most 2048 and its shape is kept', () {
    expect(fittedPhotoSize(4032, 3024), const ThumbnailSize(2048, 1536));
    expect(fittedPhotoSize(3024, 4032), const ThumbnailSize(1536, 2048));
    expect(fittedPhotoSize(8000, 1000), const ThumbnailSize(2048, 256));
  });

  test('a photo already within 2048 keeps its size, and an unknown size asks for the cap', () {
    expect(fittedPhotoSize(1200, 800), const ThumbnailSize(1200, 800));
    expect(fittedPhotoSize(0, 0), const ThumbnailSize(2048, 2048));
  });
}
