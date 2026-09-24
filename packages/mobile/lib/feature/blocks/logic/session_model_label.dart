import 'package:operator_mobile/feature/blocks/logic/model_label.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

String? sessionModelLabel({required String? currentModel, required List<SessionBlock> blocks}) {
  if (currentModel != null) return currentModel;
  for (final block in blocks.reversed) {
    final model = block.model;
    if (model != null && model.isNotEmpty) return formatModelLabel(model);
  }
  return null;
}
