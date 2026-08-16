import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_body.dart';

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => BlocListener<PreviewCubit, PreviewState>(
    listener: (context, state) {},
    child: AppScaffold(
      appBar: GlobalAppbar.sub(
        titleText: title,
        actions: [
          Semantics(
            button: true,
            label: 'Reload preview',
            child: IconButton(
              onPressed: context.read<PreviewCubit>().refresh,
              icon: Icon(Icons.refresh, size: 18, color: context.skin.textSecondary),
            ),
          ),
        ],
      ),
      body: const PreviewBody(),
    ),
  );
}
