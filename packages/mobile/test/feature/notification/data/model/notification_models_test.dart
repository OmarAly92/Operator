import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/mark_notification_read_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';

void main() {
  test('parses one record and tolerates a record with nothing but an id', () {
    final full = NotificationModel.fromJson(const {
      'id': 'n-1',
      'sessionId': 's-1',
      'projectId': 'p-1',
      'prUrl': 'https://github.com/o/r/pull/7',
      'type': 'needs_input',
      'title': 'Agent needs you',
      'body': 'Approve the plan',
      'status': 'unread',
      'createdAt': '2026-08-15T10:00:00Z',
    });

    expect(full.id, 'n-1');
    expect(full.type, 'needs_input');
    expect(full.status, 'unread');
    expect(NotificationModel.fromJson(const {'id': 'n-2'}).body, isNull);
  });

  test('reads the page envelope, missing keys included', () {
    final page = NotificationPageModel.fromJson(const {
      'notifications': [
        {'id': 'n-1'},
        {'id': 'n-2'},
      ],
      'nextCursor': 'c-2',
      'unreadCount': 3,
    });

    expect(page.notifications.map((item) => item.id), ['n-1', 'n-2']);
    expect(page.nextCursor, 'c-2');
    expect(page.unreadCount, 3);

    final empty = NotificationPageModel.fromJson(const {});
    expect(empty.notifications, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(empty.unreadCount, 0);
  });

  test("serialises exactly the daemon's query and bodies", () {
    expect(
      const GetNotificationsParams(status: 'all', limit: 50, cursor: 'c-1').toJson(),
      {'status': 'all', 'limit': 50, 'cursor': 'c-1'},
    );
    expect(const GetNotificationsParams().toJson(), isEmpty);
    expect(const MarkNotificationReadParams().toJson(), {'status': 'read'});
    expect(
      const RegisterPushDeviceParams(token: 't-1', platform: 'ios', deviceName: 'iPhone').toJson(),
      {'token': 't-1', 'platform': 'ios', 'deviceName': 'iPhone'},
    );
    expect(const RegisterPushDeviceParams(token: 't-1').toJson(), {'token': 't-1'});
  });
}
