import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_row.dart';

class NotificationsBody extends StatelessWidget {
  const NotificationsBody({super.key});

  Future<void> _open(BuildContext context, NotificationModel notification) async {
    final cubit = context.read<NotificationsCubit>();
    await cubit.open(notification);
    if (!context.mounted) return;

    final target = notificationTarget(
      type: notification.type ?? '',
      sessionId: notification.sessionId,
    );
    if (target.startsWith('/session/')) {
      Navigator.of(context).pushNamed(
        RoutesStrings.session,
        arguments: {'sessionId': notification.sessionId},
      );
      return;
    }
    HomeShell.selectedTab.value = 2;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) => current is NotificationsReadyState,
      builder: (context, state) {
        final cubit = context.read<NotificationsCubit>();
        if (cubit.loading) return const Center(child: AppLoader());

        if (cubit.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cubit.error == null ? Icons.notifications_none : Icons.warning_amber_rounded,
                    size: 24,
                    color: cubit.error == null ? skin.textTertiary : skin.red,
                  ),
                  const VerticalSpace(11),
                  AppText(
                    cubit.error == null ? 'Nothing yet' : "Couldn't load notifications",
                    style: AppTextStyle.style17Bold,
                  ),
                  const VerticalSpace(6),
                  AppText(
                    cubit.error ??
                        'Alerts about agents that need you and PRs that are ready show up here.',
                    style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (metrics.pixels >= metrics.maxScrollExtent - 200) cubit.loadMore();
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: cubit.items.length + (cubit.loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => Container(
                height: 1,
                margin: const EdgeInsets.only(left: 58),
                color: skin.borderSubtle,
              ),
              itemBuilder: (context, index) {
                if (index >= cubit.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: AppLoader()),
                  );
                }
                final notification = cubit.items[index];
                return NotificationRow(
                  type: notification.type ?? '',
                  title: notification.title ?? '',
                  body: notification.body ?? '',
                  createdAt: notification.createdAt ?? '',
                  unread: notification.status == 'unread',
                  onTap: () => _open(context, notification),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
