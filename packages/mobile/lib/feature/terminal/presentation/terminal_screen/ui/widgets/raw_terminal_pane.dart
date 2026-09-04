import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';

class RawTerminalPane extends StatefulWidget {
  const RawTerminalPane({super.key});

  @override
  State<RawTerminalPane> createState() => _RawTerminalPaneState();
}

class _RawTerminalPaneState extends State<RawTerminalPane> {
  late final TerminalCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<TerminalCubit>();
    _cubit.attach();
  }

  @override
  void dispose() {
    _cubit.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<TerminalCubit, TerminalState>(
    buildWhen: (previous, current) => current is TerminalReadyState,
    builder: (context, _) {
      final cubit = context.read<TerminalCubit>();
      return Stack(
        children: [
          const Positioned.fill(child: TerminalSurface()),
          if (cubit.notFound) const Positioned.fill(child: TerminalDeadOverlay()),
        ],
      );
    },
  );
}
