import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

Future<void> showSessionActionsSheet(BuildContext context, SessionModel session) {
  final cubit = context.read<SessionsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => BlocProvider.value(value: cubit, child: SessionActionsSheet(session: session)),
  );
}

class SessionActionsSheet extends StatelessWidget {
  const SessionActionsSheet({super.key, required this.session});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final terminated = session.isTerminated == true || session.status == 'terminated';
    final cubit = context.read<SessionsCubit>();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: AppText(sessionTitle(session), style: AppTextStyle.style14SemiBold),
            subtitle: AppText(session.id ?? '', style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
          ),
          if (terminated)
            ListTile(
              leading: Icon(Icons.replay, color: skin.accent),
              title: const AppText('Restore'),
              onTap: () {
                Haptics.tap();
                Navigator.of(context).pop();
                cubit.restore(session.id!);
              },
            )
          else
            ListTile(
              leading: Icon(Icons.stop_circle_outlined, color: skin.red),
              title: AppText('Kill', style: AppTextStyle.style14Regular.copyWith(color: skin.red)),
              onTap: () async {
                Haptics.tap();
                final confirmed = await AppDialog.confirm(
                  context,
                  title: 'Kill session?',
                  message: 'This stops ${session.id}.',
                  confirmLabel: 'Kill',
                  destructive: true,
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                if (confirmed) cubit.kill(session.id!);
              },
            ),
        ],
      ),
    );
  }
}
