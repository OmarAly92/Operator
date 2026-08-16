import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<NotificationsCubit, NotificationsState>(
    listener: (context, state) {},
    child: AppScaffold(
      appBar: GlobalAppbar.sub(
        titleText: 'Notifications',
        actions: [
          BlocBuilder<NotificationsCubit, NotificationsState>(
            buildWhen: (previous, current) => current is NotificationsReadyState,
            builder: (context, state) {
              final cubit = context.read<NotificationsCubit>();
              if (cubit.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () {
                  Haptics.tap();
                  cubit.markAllRead();
                },
                child: AppText(
                  'Mark all read',
                  style: AppTextStyle.style15SemiBold.copyWith(color: context.skin.blue),
                ),
              );
            },
          ),
        ],
      ),
      body: const NotificationsBody(),
    ),
  );
}
