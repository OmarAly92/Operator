import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';

Future<bool> showRemoveConnectionDialog(BuildContext context, {required String name}) {
  return AppDialog.confirm(
    context,
    title: 'Remove $name?',
    message: 'This only removes the pairing from this phone. You can pair the desktop again anytime.',
    confirmLabel: 'Remove',
    destructive: true,
  );
}
