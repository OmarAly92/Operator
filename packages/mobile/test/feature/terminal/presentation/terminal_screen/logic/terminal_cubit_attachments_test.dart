import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/stage_session_attachments_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/staged_attachments_model.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

ComposerAttachment png(String id, {int size = 4}) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(size));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMuxClient mux;
  late _MockTerminalRepository repository;
  late TerminalCubit cubit;

  setUpAll(() {
    registerFallbackValue(const SendSessionMessageParams(message: ''));
    registerFallbackValue(const StageSessionAttachmentsParams(files: []));
  });

  setUp(() {
    mux = _MockMuxClient();
    repository = _MockTerminalRepository();
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.terminalEvents).thenAnswer((_) => const Stream<TerminalEvent>.empty());
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => repository.getSuggestion(any())).thenAnswer((_) async => Result.success(null));
    when(() => repository.getDraft(any())).thenAnswer((_) async => Result.success(null));
    cubit = TerminalCubit(
      mux,
      repository,
      _MockSessionsRepository(),
      const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session'),
    );
  });

  tearDown(() => cubit.close());

  void stubStage(List<String> paths) => when(() => repository.stageAttachments(any(), any())).thenAnswer(
    (_) async => Result.success(
      GlobalResponse(
        data: StagedAttachmentsModel(sessionId: 's-1', paths: paths),
      ),
    ),
  );

  void stubSend() =>
      when(() => repository.sendSessionMessage(any(), any())).thenAnswer((_) async => Result.success(true));

  String sentMessage() =>
      (verify(() => repository.sendSessionMessage('s-1', captureAny())).captured.last as SendSessionMessageParams)
          .message;

  test('an attachment alone stages, then sends only the reference block, then clears', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    stubSend();
    cubit.addAttachments([png('a')]);

    await cubit.send();

    final staged =
        verify(() => repository.stageAttachments('s-1', captureAny())).captured.single as StageSessionAttachmentsParams;
    expect(staged.files.map((file) => file.id), ['a']);
    expect(
      sentMessage(),
      'Attached files (read these files in the workspace for context):\n- .operator/attachments/attachment-aa.png',
    );
    expect(cubit.attachments, isEmpty);
    expect(cubit.composer.text, isEmpty);
    expect(cubit.sending, isFalse);
  });

  test('text and attachments send the text then the references', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    stubSend();
    cubit.composer.text = 'what is wrong here?';
    cubit.addAttachments([png('a')]);

    await cubit.send();

    expect(sentMessage(), startsWith('what is wrong here?\n\nAttached files'));
  });

  test('plain text never stages', () async {
    stubSend();
    cubit.composer.text = 'hello';

    await cubit.send();

    verifyNever(() => repository.stageAttachments(any(), any()));
    expect(sentMessage(), 'hello');
  });

  test('a failed stage keeps the draft, sends nothing and says why', () async {
    when(() => repository.stageAttachments(any(), any())).thenAnswer(
      (_) async => Result.failure(
        ServerFailure(error: 'x', message: 'attachment is too large', apiStatus: 'ATTACHMENT_TOO_LARGE'),
      ),
    );
    cubit.composer.text = 'see attached';
    cubit.addAttachments([png('a')]);

    await cubit.send();

    verifyNever(() => repository.sendSessionMessage(any(), any()));
    expect(cubit.composer.text, 'see attached');
    expect(cubit.attachments.single.id, 'a');
    expect(cubit.attachmentNotice, "Couldn't attach: attachment is too large");
    expect(cubit.staging, isFalse);
    expect(cubit.sending, isFalse);
  });

  test('a failed send keeps the draft and a retry reuses the staged paths', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    var sends = 0;
    when(() => repository.sendSessionMessage(any(), any())).thenAnswer((_) async {
      sends++;
      return sends == 1
          ? Result.failure(
              ServerFailure(error: 'x', message: 'another operation owns the terminal', apiStatus: 'SESSION_BUSY'),
            )
          : Result.success(true);
    });
    cubit.composer.text = 'retry me';
    cubit.addAttachments([png('a')]);

    await cubit.send();
    expect(cubit.composer.text, 'retry me');
    expect(cubit.attachments, hasLength(1));
    expect(cubit.attachmentNotice, 'Send failed: another operation owns the terminal');

    await cubit.send();

    verify(() => repository.stageAttachments(any(), any())).called(1);
    verify(() => repository.sendSessionMessage(any(), any())).called(2);
    expect(cubit.attachments, isEmpty);
  });

  test('changing the attachments after a failure stages again', () async {
    stubStage(['.operator/attachments/attachment-aa.png']);
    when(
      () => repository.sendSessionMessage(any(), any()),
    ).thenAnswer((_) async => Result.failure(ServerFailure(error: 'x', message: 'down')));
    cubit.addAttachments([png('a')]);
    await cubit.send();
    stubStage(['.operator/attachments/attachment-aa.png', '.operator/attachments/attachment-bb.png']);
    cubit.addAttachments([png('b')]);

    await cubit.send();

    verify(() => repository.stageAttachments(any(), any())).called(2);
  });

  test('a stage that returns the wrong number of paths refuses to send', () async {
    stubStage(const []);
    cubit.addAttachments([png('a')]);

    await cubit.send();

    verifyNever(() => repository.sendSessionMessage(any(), any()));
    expect(cubit.attachments, hasLength(1));
    expect(cubit.attachmentNotice, "Couldn't attach the files.");
  });

  test('staging is reported while the upload runs and editing is locked', () async {
    final upload = Completer<Result<GlobalResponse<StagedAttachmentsModel>, Failure>>();
    when(() => repository.stageAttachments(any(), any())).thenAnswer((_) => upload.future);
    stubSend();
    cubit.addAttachments([png('a')]);

    final sending = cubit.send();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.staging, isTrue);
    expect(cubit.sending, isTrue);
    cubit.removeAttachment('a');
    cubit.addAttachments([png('late')]);
    expect(cubit.attachments.map((a) => a.id), ['a']);

    upload.complete(Result.success(const GlobalResponse(data: StagedAttachmentsModel(paths: ['p']))));
    await sending;
    expect(cubit.staging, isFalse);
  });

  test('admission caps the count and reports it', () {
    cubit.addAttachments([for (var i = 0; i < 9; i++) png('f$i')]);

    expect(cubit.attachments, hasLength(8));
    expect(cubit.attachmentNotice, kTooManyFiles);
  });

  test('toggle adds then removes the same attachment', () {
    cubit.toggleAttachment(png('photo:1'));
    expect(cubit.hasAttachment('photo:1'), isTrue);
    expect(cubit.hasContent, isTrue);

    cubit.toggleAttachment(png('photo:1'));
    expect(cubit.hasAttachment('photo:1'), isFalse);
    expect(cubit.hasContent, isFalse);
  });
}
