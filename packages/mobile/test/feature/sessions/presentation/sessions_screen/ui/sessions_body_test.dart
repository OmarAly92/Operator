import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  testWidgets('groups sessions into their board sections with a stat header', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: const BoardSnapshot(
            sessions: [
              SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
              SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you', status: 'needs_input'),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
              child: const Scaffold(body: SessionsBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Working one'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
  });
}
