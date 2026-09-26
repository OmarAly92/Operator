import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';

void main() {
  test('every mode has the phone label, with Ask for default', () {
    expect(kPermissionModes, ['bypass-permissions', 'auto', 'accept-edits', 'plan', 'default']);
    expect(kPermissionModes.map(permissionModeLabel), ['Bypass permissions', 'Auto', 'Accept edits', 'Plan', 'Ask']);
    expect(permissionModeLabel(null), 'Ask');
  });

  test('refusals name the reason', () {
    expect(permissionModeRefusal('SESSION_BUSY'), 'The agent is working — try again when it is idle');
    expect(permissionModeRefusal('SESSION_COMMAND_UNAVAILABLE'), 'The agent is working — try again when it is idle');
    expect(permissionModeRefusal('SESSION_AWAITING_DECISION'), 'Answer the permission request first');
    expect(permissionModeRefusal('PERMISSION_MODE_UNSUPPORTED'), "This agent can't change mode from the phone");
    expect(permissionModeRefusal('PERMISSION_MODE_UNCONFIRMED'), "The terminal didn't confirm the new mode");
    expect(permissionModeRefusal(null), "Couldn't change the permission mode");
  });
}
