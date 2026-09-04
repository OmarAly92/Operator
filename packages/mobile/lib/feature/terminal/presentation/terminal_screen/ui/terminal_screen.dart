import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_preview_globe.dart';

class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = context.read<TerminalCubit>().args;
    final title = args.title.length > 22 ? '${args.title.substring(0, 20)}...' : args.title;

    return BlocListener<TerminalCubit, TerminalState>(
      listener: (context, state) {
        if (state is TerminalClosedState) Navigator.of(context).pop();
      },
      child: AppScaffold(
        appBar: GlobalAppbar.sub(
          titleText: title,
          actions: [
            if (!args.shellOnly)
              BlocBuilder<SessionViewCubit, SessionViewState>(
                builder: (context, state) {
                  final blocks = context.read<SessionViewCubit>().mode == SessionViewMode.blocks;
                  return Semantics(
                    button: true,
                    label: blocks ? 'Show raw terminal' : 'Show blocks',
                    child: IconButton(
                      onPressed: context.read<SessionViewCubit>().toggle,
                      icon: Icon(
                        blocks ? Icons.terminal : Icons.view_agenda_outlined,
                        size: 18,
                        color: context.skin.blue,
                      ),
                    ),
                  );
                },
              ),
            if (!args.shellOnly)
              TerminalPreviewGlobe(
                sessionId: args.sessionId,
                title: args.title,
                previewUrl: args.previewUrl,
              ),
          ],
        ),
        body: const TerminalBody(),
      ),
    );
  }
}
