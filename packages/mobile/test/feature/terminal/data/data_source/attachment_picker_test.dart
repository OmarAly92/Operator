import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';

class _MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late _MockImagePicker images;
  late List<XFile> files;
  late AttachmentPickerImp picker;

  setUpAll(() => registerFallbackValue(ImageSource.gallery));

  setUp(() {
    images = _MockImagePicker();
    files = [];
    picker = AttachmentPickerImp(images, pickFiles: () async => files, now: () => 7);
  });

  test('photos are requested as 2048 px quality 85 jpeg', () async {
    when(
      () => images.pickMultiImage(
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        limit: any(named: 'limit'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => [XFile.fromData(Uint8List.fromList([1, 2]), path: '/picked/IMG_0001.jpg')]);

    final picked = await picker.photos(limit: 5);

    verify(
      () => images.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
        limit: 5,
        requestFullMetadata: false,
      ),
    ).called(1);
    expect(picked.single.mimeType, 'image/jpeg');
    expect(picked.single.name, 'IMG_0001.jpg');
    expect(picked.single.bytes, [1, 2]);
  });

  test('one free slot picks a single photo from the library', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => XFile.fromData(Uint8List.fromList([3]), path: '/picked/one.jpg'));

    final picked = await picker.photos(limit: 1);

    expect(picked, hasLength(1));
    verify(
      () => images.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85, requestFullMetadata: false),
    ).called(1);
  });

  test('the camera is capped the same way', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => XFile.fromData(Uint8List.fromList([4]), path: '/picked/shot.jpg'));

    await picker.camera();

    verify(
      () => images.pickImage(source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 85, requestFullMetadata: false),
    ).called(1);
  });

  test('a denied camera becomes a readable failure', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenThrow(PlatformException(code: 'camera_access_denied'));

    expect(
      picker.camera(),
      throwsA(isA<AttachmentPickFailure>().having((failure) => failure.message, 'message', contains('Camera access is off'))),
    );
  });

  test('files keep their name, get a type from the extension, and never collide', () async {
    files = [
      XFile.fromData(Uint8List.fromList([5]), path: '/picked/report.pdf'),
      XFile.fromData(Uint8List.fromList([6]), path: '/picked/report.pdf'),
    ];

    final picked = await picker.files();

    expect(picked.map((file) => file.mimeType), ['application/pdf', 'application/pdf']);
    expect(picked.map((file) => file.id).toSet(), hasLength(2));
  });

  test('a cancelled camera returns nothing', () async {
    when(
      () => images.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
        requestFullMetadata: any(named: 'requestFullMetadata'),
      ),
    ).thenAnswer((_) async => null);

    expect(await picker.camera(), isEmpty);
  });
}
