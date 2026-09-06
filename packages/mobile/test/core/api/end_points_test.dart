import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';

void main() {
  group('session and terminal endpoints', () {
    test('address the daemon session routes', () {
      expect(EndPoints.events, '/api/v1/events');
      expect(EndPoints.sessionAttachments('w-1'), '/api/v1/sessions/w-1/attachments');
      expect(EndPoints.sessionWorkspaceFiles('w-1'), '/api/v1/sessions/w-1/workspace/files');
      expect(EndPoints.sessionResumeAgent('w-1'), '/api/v1/sessions/w-1/resume-agent');
    });

    test('builds the terminal paths', () {
      expect(EndPoints.shellTerminals, '/api/v1/shell-terminals');
      expect(EndPoints.shellTerminal('handle 1'), '/api/v1/shell-terminals/handle%201');
      expect(EndPoints.sessionSend('sess-1'), '/api/v1/sessions/sess-1/send');
    });
  });

  test('builds the notification and push paths', () {
    expect(EndPoints.notifications, '/api/v1/notifications');
    expect(EndPoints.notification('n 1'), '/api/v1/notifications/n%201');
    expect(EndPoints.notificationsReadAll, '/api/v1/notifications/read-all');
    expect(EndPoints.pushDevices, '/api/v1/push/devices');
    expect(EndPoints.pushDevice('ExponentPushToken[a b]'), '/api/v1/push/devices/ExponentPushToken%5Ba%20b%5D');
  });

  test('builds the preview paths, escaping every entry segment', () {
    expect(EndPoints.sessionPreview('s-1'), '/api/v1/sessions/s-1/preview');
    expect(
      EndPoints.sessionPreviewFile('s-1', 'dist/my page/index.html'),
      '/api/v1/sessions/s-1/preview/files/dist/my%20page/index.html',
    );
  });
}
