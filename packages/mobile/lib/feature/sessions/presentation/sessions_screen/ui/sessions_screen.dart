import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<SessionsCubit, SessionsState>(
    listener: (context, state) {
      if (state is KillFailureState) context.showSnackBar('Kill failed: ${state.failure.message}');
      if (state is RestoreFailureState) context.showSnackBar('Restore failed: ${state.failure.message}');
    },
    child: Scaffold(
      backgroundColor: context.skin.bgBase,
      appBar: GlobalAppbar.main(
        backgroundColor: context.skin.bgChrome,
        hasBorder: true,
        title: AppText('Agents', style: AppTextStyle.style19SemiBold.copyWith(letterSpacing: -0.3)),
        actions: const [NotificationBell()],
      ),
      body: const SessionsBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.skin.accent,
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.spawn),
        child: Icon(Icons.add, color: context.skin.onAccent, size: 24),
      ),
    ),
  );
}
