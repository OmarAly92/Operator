import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';

class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  Future<void> _requestSwitch(BuildContext context) async {
    final switchCubit = context.read<InterfaceSwitchCubit>();
    if (!switchCubit.supported) {
      context.showSnackBar(
        switchCubit.reason ??
            switchCubit.error ??
            'This agent has not declared a compatible native conversation handoff.',
      );
      return;
    }
    if (!context.read<TerminalCubit>().notFound) {
      final choice = await showInterfaceSwitchSheet(
        context,
        targetLabel: 'Chat',
        waitingOnInput: false,
      );
      if (choice == null) return;
      await switchCubit.start('chat', choice == InterfaceSwitchChoice.drain ? 'drain' : 'interrupt');
      return;
    }
    await switchCubit.start('chat', 'drain');
  }

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
              BlocProvider<PreviewCubit>(
                create: (_) => sl<PreviewCubit>(param1: args.sessionId, param2: null),
                child: Builder(
                  builder: (context) => BlocBuilder<PreviewCubit, PreviewState>(
                    buildWhen: (previous, current) => current is PreviewReadyState,
                    builder: (context, state) {
                      final ready = context.read<PreviewCubit>().hasPreview;
                      return Semantics(
                        button: true,
                        label: 'Open preview',
                        child: IconButton(
                          onPressed: () => ready
                              ? Navigator.of(context).pushNamed(
                                  RoutesStrings.preview,
                                  arguments: {'sessionId': args.sessionId, 'title': args.title},
                                )
                              : context.showSnackBar(
                                  'No preview yet — waiting for the agent to generate a page '
                                  'or document.',
                                ),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.public, size: 18, color: context.skin.textSecondary),
                              if (ready)
                                Positioned(
                                  right: -1,
                                  top: -1,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: context.skin.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (!args.shellOnly)
              Semantics(
                button: true,
                label: 'Open Chat interface',
                child: IconButton(
                  onPressed: () => _requestSwitch(context),
                  icon: Icon(Icons.chat_bubble_outline, size: 18, color: context.skin.blue),
                ),
              ),
          ],
        ),
        body: const TerminalBody(),
      ),
    );
  }
}
