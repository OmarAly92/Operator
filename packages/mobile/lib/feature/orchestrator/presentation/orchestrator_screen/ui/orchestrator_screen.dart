import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/ui/widgets/orchestrator_body.dart';

class OrchestratorScreen extends StatelessWidget {
  const OrchestratorScreen({super.key, required this.onOpenBoard});

  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<OrchestratorCubit>(),
    child: Scaffold(
      backgroundColor: context.skin.bgBase,
      appBar: const GlobalAppbar.main(titleText: 'Orchestrator'),
      body: OrchestratorBody(onOpenBoard: onOpenBoard),
    ),
  );
}
