import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.title,
    this.projectId,
  });

  final String sessionId;
  final String title;
  final String? projectId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ChatBodyState> _body = GlobalKey<ChatBodyState>();

  @override
  Widget build(BuildContext context) {
    final title = context.select<ChatCubit, String>(
      (cubit) => cubit.snapshot?.title ?? widget.title,
    );

    return AppScaffold(
      appBar: GlobalAppbar.sub(
        titleText: title.length > 24 ? '${title.substring(0, 22)}…' : title,
        actions: [
          IconButton(
            onPressed: () => _body.currentState?.openMenu(),
            icon: Icon(Icons.more_horiz, color: context.skin.textSecondary),
          ),
        ],
      ),
      body: ChatBody(key: _body, projectId: widget.projectId),
    );
  }
}
