import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/resolve_input_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/send_message_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';
import 'package:operator_mobile/feature/chat/data/model/params/stage_attachments_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

void main() {
  late _MockApiConsumer apiConsumer;
  late ChatRemoteDataSource dataSource;

  Response<dynamic> jsonResponse(Map<String, dynamic> body) =>
      Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        data: body,
      );

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = ChatRemoteDataSourceImp(apiConsumer);
    when(
      () => apiConsumer.post(
        any(),
        body: any(named: 'body'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => jsonResponse(const {}));
    when(
      () => apiConsumer.patch(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => jsonResponse(const {}));
    when(
      () => apiConsumer.put(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => jsonResponse(const {}));
  });

  group('getConversationPage', () {
    test(
      'asks for a full page and omits the cursor on the live page',
      () async {
        when(
          () => apiConsumer.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async => jsonResponse({
            'conversationId': 'c-1',
            'latestSequence': 4,
            'controller': 'ready',
          }),
        );

        final page = await dataSource.getConversationPage('w-1');

        expect(page.data, isA<ConversationSnapshotModel>());
        expect(page.data!.conversationId, 'c-1');
        final captured =
            verify(
                  () => apiConsumer.get(
                    EndPoints.sessionConversation('w-1'),
                    queryParameters: captureAny(named: 'queryParameters'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured, {'limit': 200});
      },
    );

    test('sends beforeSequence when paging backwards', () async {
      when(
        () => apiConsumer.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async =>
            jsonResponse(const {'latestSequence': 4, 'controller': 'ready'}),
      );

      await dataSource.getConversationPage('w-1', beforeSequence: 12);

      final captured =
          verify(
                () => apiConsumer.get(
                  any(),
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured, {'limit': 200, 'beforeSequence': 12});
    });
  });

  group('writes', () {
    test('posts a message with its client id and attachments', () async {
      await dataSource.sendMessage(
        'w-1',
        const SendMessageParams(
          text: 'hello',
          clientMessageId: 'mobile-1',
          attachments: [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
        ),
      );

      final captured =
          verify(
                () => apiConsumer.post(
                  EndPoints.conversationMessages('w-1'),
                  body: captureAny(named: 'body'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['text'], 'hello');
      expect(captured['clientMessageId'], 'mobile-1');
      expect(captured['attachments'], [
        {'mimeType': 'image/png', 'data': 'AAA'},
      ]);
      expect(captured.containsKey('resources'), isFalse);
    });

    test('resolves an input request with its action and content', () async {
      await dataSource.resolveInput(
        'w-1',
        const ResolveInputParams(
          requestId: 'req-1',
          action: 'accept',
          content: {'token': 'x'},
        ),
      );

      final captured =
          verify(
                () => apiConsumer.post(
                  EndPoints.conversationInputResolve('w-1', 'req-1'),
                  body: captureAny(named: 'body'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured, {
        'action': 'accept',
        'content': {'token': 'x'},
      });
    });

    test('reports how many turns a rollback discarded', () async {
      when(
        () => apiConsumer.post(
          any(),
          body: any(named: 'body'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => jsonResponse(const {'turnsDiscarded': 3}));

      expect(
        await dataSource.rollbackTurn(
          'w-1',
          const RollbackTurnParams(turnId: 't-1'),
        ),
        3,
      );
      verify(
        () => apiConsumer.post(
          EndPoints.conversationTurnRollback('w-1', 't-1'),
          body: any(named: 'body'),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test(
      'patches a provider config option and returns the refreshed catalog',
      () async {
        when(
          () => apiConsumer.patch(any(), body: any(named: 'body')),
        ).thenAnswer(
          (_) async => jsonResponse({
            'options': [
              {
                'id': 'fast',
                'name': 'Fast mode',
                'type': 'boolean',
                'currentBoolean': true,
                'choices': <dynamic>[],
              },
            ],
          }),
        );

        final options = await dataSource.setConfigOption(
          'w-1',
          const SetConfigOptionParams(optionId: 'fast', enabled: true),
        );

        expect(options.data!.single.id, 'fast');
        expect(options.data!.single.currentBoolean, isTrue);
        final captured =
            verify(
                  () => apiConsumer.patch(
                    EndPoints.conversationConfigOption('w-1', 'fast'),
                    body: captureAny(named: 'body'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured, {'enabled': true});
      },
    );

    test('sends a select config option as a value', () async {
      when(
        () => apiConsumer.patch(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => jsonResponse(const {'options': <dynamic>[]}));

      await dataSource.setConfigOption(
        'w-1',
        const SetConfigOptionParams(optionId: 'model', value: 'opus'),
      );

      final captured =
          verify(
                () => apiConsumer.patch(any(), body: captureAny(named: 'body')),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured, {'value': 'opus'});
    });

    test(
      'gives attachment staging a minute rather than the twelve-second budget',
      () async {
        when(
          () => apiConsumer.post(
            any(),
            body: any(named: 'body'),
            options: any(named: 'options'),
          ),
        ).thenAnswer(
          (_) async => jsonResponse(const {
            'paths': ['/w/a.png'],
          }),
        );

        final paths = await dataSource.stageAttachments(
          'w-1',
          const StageAttachmentsParams(
            attachments: [ChatImageModel(mimeType: 'image/png', data: 'AAA')],
          ),
        );

        expect(paths, ['/w/a.png']);
        final options =
            verify(
                  () => apiConsumer.post(
                    EndPoints.sessionAttachments('w-1'),
                    body: any(named: 'body'),
                    options: captureAny(named: 'options'),
                  ),
                ).captured.single
                as Options;
        expect(options.receiveTimeout, const Duration(seconds: 60));
        expect(options.sendTimeout, const Duration(seconds: 60));
      },
    );
  });

  group('catalogs', () {
    test(
      'reads models, skills and config options, tolerating an empty daemon',
      () async {
        when(
          () => apiConsumer.get(EndPoints.conversationModels('w-1')),
        ).thenAnswer(
          (_) async => jsonResponse({
            'models': [
              {
                'id': 'opus',
                'displayName': 'Opus',
                'default': true,
                'efforts': ['low', 'high'],
              },
            ],
          }),
        );
        when(
          () => apiConsumer.get(EndPoints.conversationSkills('w-1')),
        ).thenAnswer(
          (_) async => jsonResponse({
            'skills': [
              {'name': 'review', 'displayName': 'Review', 'source': 'plugin'},
            ],
          }),
        );
        when(
          () => apiConsumer.get(EndPoints.conversationConfigOptions('w-1')),
        ).thenAnswer((_) async => jsonResponse(const {}));

        final models = await dataSource.getModels('w-1');
        expect(models.data!.single.id, 'opus');
        expect(models.data!.single.isDefault, isTrue);
        expect(models.data!.single.efforts, ['low', 'high']);

        final skills = await dataSource.getSkills('w-1');
        expect(skills.data!.single.name, 'review');
        expect(skills.data!.single.source, 'plugin');

        expect((await dataSource.getConfigOptions('w-1')).data, isEmpty);
      },
    );

    test('keeps workspace truncation and drops deleted files', () async {
      when(
        () => apiConsumer.get(EndPoints.sessionWorkspaceFiles('w-1')),
      ).thenAnswer(
        (_) async => jsonResponse({
          'files': [
            {'path': 'src/app.ts', 'status': 'modified'},
            {'path': 'old.ts', 'status': 'deleted'},
          ],
          'truncated': true,
        }),
      );

      final workspace = await dataSource.getWorkspacePaths('w-1');
      expect(workspace.data!.paths, ['src/app.ts']);
      expect(workspace.data!.truncated, isTrue);
    });
  });
}
