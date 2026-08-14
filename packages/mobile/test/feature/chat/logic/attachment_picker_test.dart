import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';

class _MockXFile extends Mock implements XFile {}

void main() {
  late _MockXFile file;

  setUp(() {
    file = _MockXFile();
  });

  test('rejects an oversized image before reading its bytes', () async {
    when(() => file.mimeType).thenReturn('image/png');
    when(() => file.length()).thenAnswer((_) async => 10 * 1024 * 1024 + 1);

    await expectLater(
      imageAttachmentFromFile(file),
      throwsA(
        isA<AttachmentPickerException>().having(
          (error) => error.message,
          'message',
          'Each image must be under 10 MB.',
        ),
      ),
    );
    verify(() => file.length()).called(1);
    verifyNever(() => file.readAsBytes());
  });

  test('rejects an oversized text file before reading its contents', () async {
    when(() => file.name).thenReturn('notes.txt');
    when(() => file.length()).thenAnswer((_) async => 500001);

    await expectLater(
      textAttachmentFromFile(file),
      throwsA(
        isA<AttachmentPickerException>().having(
          (error) => error.message,
          'message',
          'notes.txt is larger than 500 KB. Reference a worktree file with @ instead.',
        ),
      ),
    );
    verify(() => file.length()).called(1);
    verifyNever(() => file.readAsString());
  });
}
