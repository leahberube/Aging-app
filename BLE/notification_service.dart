import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
    );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    _initialized = true;
  }

  static Future<void> scheduleThreeDailyNotifications() async {
    await init();

    await _notifications.cancelAll();

    await _scheduleDailyNotification(
      id: 1,
      title: 'Sensor Sync',
      body: 'Open the app to transmit stored data.',
      hour: 9,
      minute: 0,
    );

    await _scheduleDailyNotification(
      id: 2,
      title: 'Sensor Sync',
      body: 'Open the app to transmit stored data.',
      hour: 14,
      minute: 0,
    );

    await _scheduleDailyNotification(
      id: 3,
      title: 'Sensor Sync',
      body: 'Open the app to transmit stored data.',
      hour: 20,
      minute: 0,
    );
  }

  static Future<void> _scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}