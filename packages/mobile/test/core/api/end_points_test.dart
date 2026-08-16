import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';

void main() {
  group('conversation endpoints', () {
    test('address the daemon conversation routes', () {
      expect(EndPoints.events, '/api/v1/events');
      expect(EndPoints.sessionConversation('w-1'), '/api/v1/sessions/w-1/conversation');
      expect(EndPoints.conversationMessages('w-1'), '/api/v1/sessions/w-1/conversation/messages');
      expect(EndPoints.conversationSteer('w-1'), '/api/v1/sessions/w-1/conversation/steer');
      expect(EndPoints.conversationInterrupt('w-1'), '/api/v1/sessions/w-1/conversation/interrupt');
      expect(EndPoints.conversationCompact('w-1'), '/api/v1/sessions/w-1/conversation/compact');
      expect(EndPoints.conversationModels('w-1'), '/api/v1/sessions/w-1/conversation/models');
      expect(EndPoints.conversationSkills('w-1'), '/api/v1/sessions/w-1/conversation/skills');
      expect(EndPoints.conversationSettings('w-1'), '/api/v1/sessions/w-1/conversation/settings');
      expect(EndPoints.conversationTitle('w-1'), '/api/v1/sessions/w-1/conversation/title');
      expect(EndPoints.conversationMcpReload('w-1'), '/api/v1/sessions/w-1/conversation/mcp/reload');
      expect(EndPoints.conversationConfigOptions('w-1'), '/api/v1/sessions/w-1/conversation/config-options');
      expect(
        EndPoints.conversationConfigOption('w-1', 'fast'),
        '/api/v1/sessions/w-1/conversation/config-options/fast',
      );
      expect(
        EndPoints.conversationApprovalResolve('w-1', 'req-1'),
        '/api/v1/sessions/w-1/conversation/approvals/req-1/resolve',
      );
      expect(
        EndPoints.conversationInputResolve('w-1', 'req-1'),
        '/api/v1/sessions/w-1/conversation/inputs/req-1/resolve',
      );
      expect(
        EndPoints.conversationTurnRollback('w-1', 't-1'),
        '/api/v1/sessions/w-1/conversation/turns/t-1/rollback',
      );
      expect(EndPoints.sessionAttachments('w-1'), '/api/v1/sessions/w-1/attachments');
      expect(EndPoints.sessionWorkspaceFiles('w-1'), '/api/v1/sessions/w-1/workspace/files');
      expect(EndPoints.sessionResumeAgent('w-1'), '/api/v1/sessions/w-1/resume-agent');
    });

    test('builds the terminal paths', () {
      expect(EndPoints.shellTerminals, '/api/v1/shell-terminals');
      expect(EndPoints.shellTerminal('handle 1'), '/api/v1/shell-terminals/handle%201');
      expect(EndPoints.sessionSend('sess-1'), '/api/v1/sessions/sess-1/send');
      expect(
        EndPoints.sessionInterfaceTransition('sess-1'),
        '/api/v1/sessions/sess-1/interface-transition',
      );
    });

    test('escape identifiers so a slash cannot forge a route', () {
      expect(EndPoints.sessionConversation('a/b'), '/api/v1/sessions/a%2Fb/conversation');
      expect(
        EndPoints.conversationApprovalResolve('w-1', 'req 1/x'),
        '/api/v1/sessions/w-1/conversation/approvals/req%201%2Fx/resolve',
      );
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
