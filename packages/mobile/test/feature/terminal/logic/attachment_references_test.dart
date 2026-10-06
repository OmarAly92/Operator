import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_references.dart';

void main() {
  test('the references follow the text after a blank line, one path per line', () {
    expect(
      appendAttachmentReferences('look at this', ['.operator/attachments/attachment-aa.png', '.operator/attachments/attachment-bb.pdf']),
      'look at this\n\n'
      'Attached files (read these files in the workspace for context):\n'
      '- .operator/attachments/attachment-aa.png\n'
      '- .operator/attachments/attachment-bb.pdf',
    );
  });

  test('an attachment-only message is just the reference block', () {
    expect(
      appendAttachmentReferences('   ', ['.operator/attachments/attachment-aa.png']),
      'Attached files (read these files in the workspace for context):\n- .operator/attachments/attachment-aa.png',
    );
  });

  test('no paths leaves the message alone', () {
    expect(appendAttachmentReferences('hello', const []), 'hello');
  });
}
