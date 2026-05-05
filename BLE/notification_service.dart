import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum TransmitStatus {
  success,
  failed,
  timeout,
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    const initSettings = InitializationSettings(
      iOS: darwinSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));

    _initialized = true;
  }

  static Future<void> showTransmitResult({
    required String deviceName,
    required TransmitStatus status,
    required String message,
  }) async {
    String title;

    switch (status) {
      case TransmitStatus.success:
        title = '$deviceName transmit complete';
        break;
      case TransmitStatus.failed:
        title = '$deviceName transmit failed';
        break;
      case TransmitStatus.timeout:
        title = '$deviceName transmit timed out';
        break;
    }

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: message,
      notificationDetails: details,
    );
  }

  static Future<void> showSummaryNotification({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> scheduleThreeDailyNotifications() async {}

  static Future<void> showTransmitSuccess({
    required String deviceName,
    required String message,
  }) async {
    await showTransmitResult(
      deviceName: deviceName,
      status: TransmitStatus.success,
      message: message,
    );
  }

  static Future<void> showTransmitFailure({
    required String deviceName,
    required String message,
  }) async {
    await showTransmitResult(
      deviceName: deviceName,
      status: TransmitStatus.failed,
      message: message,
    );
  }
}
