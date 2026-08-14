import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart';

ConversationActivityModel request({
  required String kind,
  String status = 'pending',
  String? requestId = 'req-1',
  Map<String, dynamic> detail = const {},
  String summary = 'Run rm -rf build',
}) => ConversationActivityModel(
  id: 'a-1',
  sequence: 1,
  revision: 1,
  activityKind: kind,
  status: status,
  summary: summary,
  requestId: requestId,
  detail: ActivityDetailModel(detail),
);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ApprovalCard', () {
    testWidgets('offers each decision and reports the chosen one', (
      tester,
    ) async {
      final chosen = <String>[];
      await pump(
        tester,
        ApprovalCard(
          activity: request(
            kind: 'approval',
            detail: const {
              'command': 'rm -rf build',
              'cwd': '/w',
              'decisions': [
                {'id': 'accept', 'label': 'Allow once'},
                {'id': 'deny', 'label': 'Deny'},
              ],
            },
          ),
          busy: false,
          onDecide: (requestId, decisionId) async =>
              chosen.add('$requestId:$decisionId'),
        ),
      );

      expect(find.text('Approval required'), findsOneWidget);
      expect(find.text('rm -rf build'), findsOneWidget);
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();
      expect(chosen, ['req-1:accept']);
    });

    testWidgets(
      'says so when the provider offered nothing Operator can present',
      (tester) async {
        await pump(
          tester,
          ApprovalCard(
            activity: request(kind: 'approval'),
            busy: false,
            onDecide: (_, _) async {},
          ),
        );
        expect(find.textContaining('offered no decisions'), findsOneWidget);
      },
    );

    testWidgets('keeps a resolved approval for the record', (tester) async {
      await pump(
        tester,
        ApprovalCard(
          activity: request(kind: 'approval', status: 'resolved'),
          busy: false,
          onDecide: (_, _) async {},
        ),
      );
      expect(find.text('Approval resolved'), findsOneWidget);
      expect(find.textContaining('kept for the record'), findsOneWidget);
    });

    testWidgets('cannot answer an approval with no provider identity', (
      tester,
    ) async {
      await pump(
        tester,
        ApprovalCard(
          activity: request(kind: 'approval', requestId: null),
          busy: false,
          onDecide: (_, _) async {},
        ),
      );

      expect(find.textContaining('no provider identity'), findsOneWidget);
      expect(find.text('Allow once'), findsNothing);
    });
  });

  group('UserInputCard', () {
    testWidgets('submits the form once every required field is filled', (
      tester,
    ) async {
      Map<String, dynamic>? submitted;
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            summary: 'Sign in',
            detail: const {
              'inputMode': 'form',
              'message': 'Paste a token',
              'schema': {
                'title': 'Credentials',
                'required': ['token'],
                'properties': {
                  'token': {'type': 'string', 'title': 'Token', 'minLength': 4},
                },
              },
            },
          ),
          busy: false,
          onResolve: (requestId, action, [content]) async =>
              submitted = content,
        ),
      );

      expect(find.text('Credentials'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Complete Token'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 4 characters'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(submitted, {'token': 'abcd'});
    });

    testWidgets('reports only the first missing required field by its title', (
      tester,
    ) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            detail: const {
              'inputMode': 'form',
              'schema': {
                'required': ['api_token', 'account_key'],
                'properties': {
                  'api_token': {'type': 'string', 'title': 'API token'},
                  'account_key': {'type': 'string', 'title': 'Account key'},
                },
              },
            },
          ),
          busy: false,
          onResolve: (_, _, [_]) async {},
        ),
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Complete API token before continuing'),
        findsOneWidget,
      );
      expect(find.textContaining('account_key'), findsNothing);
      expect(
        find.text('Complete Account key before continuing.'),
        findsNothing,
      );
    });

    testWidgets('humanizes the first missing required field without a title', (
      tester,
    ) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            detail: const {
              'inputMode': 'form',
              'schema': {
                'required': ['backup_code', 'token'],
                'properties': {
                  'backup_code': {'type': 'string'},
                  'token': {'type': 'string', 'title': 'Token'},
                },
              },
            },
          ),
          busy: false,
          onResolve: (_, _, [_]) async {},
        ),
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Complete Backup code before continuing'),
        findsOneWidget,
      );
      expect(find.textContaining('backup_code'), findsNothing);
    });

    testWidgets('renders an unreachable Open link action for an unsafe URL', (
      tester,
    ) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(
            kind: 'user_input',
            detail: const {'inputMode': 'url', 'url': 'javascript:alert(1)'},
          ),
          busy: false,
          onResolve: (_, _, [_]) async {},
        ),
      );
      expect(find.textContaining('unsafe or invalid URL'), findsOneWidget);
      expect(find.text('Open link'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is InkWell && widget.onTap == null,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('cannot answer a request with no provider identity', (
      tester,
    ) async {
      await pump(
        tester,
        UserInputCard(
          activity: request(kind: 'user_input', requestId: null),
          busy: false,
          onResolve: (_, _, [_]) async {},
        ),
      );
      expect(find.textContaining('no provider identity'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });
  });
}
