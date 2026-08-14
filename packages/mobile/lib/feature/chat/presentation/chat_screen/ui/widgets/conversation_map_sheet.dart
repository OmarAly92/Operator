import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';

Future<int?> showConversationMapSheet(
  BuildContext context, {
  required List<ConversationMarker> markers,
}) {
  final skin = context.skin;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Conversation map',
                        style: AppTextStyle.style17SemiBold,
                      ),
                      AppText(
                        '${markers.length} ${markers.length == 1 ? 'exchange' : 'exchanges'}',
                        style: AppTextStyle.style10Regular.copyWith(
                          color: skin.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Icon(Icons.close, size: 19, color: skin.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: markers.isEmpty
                ? Center(
                    child: AppText(
                      'No conversation entries yet.',
                      style: AppTextStyle.style13Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: markers.length,
                    itemBuilder: (context, index) {
                      final marker = markers[index];
                      return InkWell(
                        onTap: () =>
                            Navigator.of(sheetContext).pop(marker.sequence),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(
                                  top: 5,
                                  right: 12,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: switch (marker.state) {
                                    'failed' => skin.red,
                                    'running' => skin.orange,
                                    _ => skin.blue,
                                  },
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 13),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: AppText(
                                              marker.title,
                                              style:
                                                  AppTextStyle.style13SemiBold,
                                              maxLines: 2,
                                            ),
                                          ),
                                          if (marker.state != null)
                                            AppText(
                                              marker.state!.toUpperCase(),
                                              style: AppTextStyle.style9Regular
                                                  .copyWith(
                                                    color: skin.textFaint,
                                                    letterSpacing: 0.6,
                                                  ),
                                            ),
                                        ],
                                      ),
                                      if (marker.detail != null) ...[
                                        const VerticalSpace(4),
                                        AppText(
                                          marker.detail!,
                                          style: AppTextStyle.style11Regular
                                              .copyWith(
                                                color: skin.textTertiary,
                                              ),
                                          maxLines: 3,
                                        ),
                                      ],
                                    ],
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
        ],
      ),
    ),
  );
}
