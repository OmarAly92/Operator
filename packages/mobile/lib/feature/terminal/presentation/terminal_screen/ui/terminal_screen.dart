import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';

class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocListener<TerminalCubit, TerminalState>(
        listener: (context, state) {
          if (state is TerminalClosedState) Navigator.of(context).pop();
        },
        child: const AppScaffold(
          resizeToAvoidBottomInset: false,
          body: TerminalBody(),
        ),
      );
}
