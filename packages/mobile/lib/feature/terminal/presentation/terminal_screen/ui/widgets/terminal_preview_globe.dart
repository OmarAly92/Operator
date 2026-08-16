import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';

class TerminalPreviewGlobe extends StatelessWidget {
  const TerminalPreviewGlobe({
    super.key,
    required this.sessionId,
    required this.title,
    this.previewUrl,
  });

  final String sessionId;
  final String title;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) => BlocBuilder<PreviewCubit, PreviewState>(
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
                  arguments: {'sessionId': sessionId, 'title': title, 'previewUrl': previewUrl},
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
  );
}
