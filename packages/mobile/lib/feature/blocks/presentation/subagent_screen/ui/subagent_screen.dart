import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';

class SubagentScreen extends StatelessWidget {
  const SubagentScreen({super.key, required this.sessionId, required this.agentId, required this.detail, this.parentTitle});

  final String sessionId;
  final String? agentId;
  final AgentBlockDetail? detail;
  final String? parentTitle;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final title = detail?.description ?? detail?.agentType ?? 'Agent';
    final subtitle = [detail?.agentType, detail?.resolvedModel ?? detail?.model, detail?.status]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
    return Scaffold(
      backgroundColor: skin.bgBase,
      appBar: GlobalAppbar.sub(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parentTitle != null)
              AppText('↩ $parentTitle', style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary)),
            AppText(title, style: AppTextStyle.style15SemiBold.copyWith(color: skin.textPrimary)),
            if (subtitle.isNotEmpty) AppText(subtitle, style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
          ],
        ),
      ),
      body: agentId == null
          ? Center(
              child: AppText("Waiting for the agent's transcript", style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
            )
          : BlocBuilder<BlocksCubit, BlocksState>(builder: (context, _) => const BlocksBody()),
    );
  }
}
