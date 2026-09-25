import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/connection/desktop_status_line.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class HomeTitle extends StatelessWidget {
  const HomeTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(title, style: AppTextStyle.style19SemiBold.copyWith(letterSpacing: -0.3)),
      BlocBuilder<SessionsCubit, SessionsState>(
        buildWhen: (previous, current) =>
            current is SessionsInitialState || current is GetSessionsSuccessState || current is GetSessionsFailureState,
        builder: (context, state) => DesktopStatusLine(
          fetchedAt: context.read<SessionsCubit>().boardFetchedAt,
          onTap: () => Navigator.of(context).pushNamed(RoutesStrings.connections),
          onRePair: () => showRePairSheet(context),
        ),
      ),
    ],
  );
}
