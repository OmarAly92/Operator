import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) => current is NotificationsReadyState,
      builder: (context, state) {
        final unread = context.read<NotificationsCubit>().unreadCount;
        return Semantics(
          button: true,
          label: 'Notifications',
          child: IconButton(
            onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.notifications),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_none, size: 20, color: skin.textSecondary),
                if (unread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: skin.blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: AppText(
                        unread > 99 ? '99+' : '$unread',
                        style: AppTextStyle.style10Bold.copyWith(color: skin.onAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
