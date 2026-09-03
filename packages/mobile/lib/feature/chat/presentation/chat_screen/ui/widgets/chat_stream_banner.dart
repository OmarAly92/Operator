import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class ChatStreamBanner extends StatelessWidget {
  const ChatStreamBanner({
    super.key,
    required this.status,
    required this.initial,
  });

  final Stream<EventStreamStatus> status;
  final EventStreamStatus initial;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return StreamBuilder<EventStreamStatus>(
      stream: status,
      initialData: initial,
      builder: (context, snapshot) {
        if (snapshot.data != EventStreamStatus.reconnecting) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: skin.bgSubtle,
          child: AppText(
            'Not receiving updates — reconnecting',
            style: AppTextStyle.style11Regular.copyWith(color: skin.amber),
          ),
        );
      },
    );
  }
}
