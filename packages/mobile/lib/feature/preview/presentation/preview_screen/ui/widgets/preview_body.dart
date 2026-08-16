import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart';

typedef PreviewBrowserBuilder = Widget Function(PreviewModel preview);

class PreviewBody extends StatelessWidget {
  const PreviewBody({super.key, this.browserBuilder});

  final PreviewBrowserBuilder? browserBuilder;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<PreviewCubit, PreviewState>(
      buildWhen: (previous, current) => current is PreviewReadyState,
      builder: (context, state) {
        final cubit = context.read<PreviewCubit>();

        if (cubit.loading) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLoader(),
                const VerticalSpace(11),
                AppText(
                  'Looking for a session preview…',
                  style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                ),
              ],
            ),
          );
        }

        final preview = cubit.preview;
        if (preview == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cubit.error == null ? Icons.public : Icons.warning_amber_rounded,
                    size: 24,
                    color: cubit.error == null ? skin.textTertiary : skin.red,
                  ),
                  const VerticalSpace(11),
                  AppText(
                    cubit.error == null ? 'No preview yet' : 'Could not load preview',
                    style: AppTextStyle.style17Bold,
                  ),
                  const VerticalSpace(6),
                  AppText(
                    cubit.error ??
                        'Waiting for the agent to generate a page or document. '
                            'This screen keeps checking.',
                    style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                  ),
                  const VerticalSpace(14),
                  PrimaryButton(text: 'Check again', onPressed: cubit.refresh),
                ],
              ),
            ),
          );
        }

        final builder = browserBuilder;
        if (builder != null) return builder(preview);
        return PreviewBrowser(
          preview: preview,
          onError: (message) => context.showSnackBar(message),
        );
      },
    );
  }
}
