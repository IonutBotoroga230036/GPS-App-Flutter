// Experience sampling notifications.
// Place at: lib/services/notification_service.dart
//
// Two things live here:
//   1. Main-isolate init: registers the plugin, creates the high-priority
//      "Questions" channel (sound + vibration), and wires notification taps
//      to a callback so the UI can open the question screen.
//   2. A helper the background isolate uses to actually show a prompt.
//
// The foreground-service notification (the silent "recording" one) is a
// SEPARATE channel set up in background_service.dart. This one is loud on
// purpose, because a triggered question needs to grab attention.

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/constants.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  /// Call once from main() in the UI isolate.
  /// [onTapPayload] receives the JSON payload of a tapped prompt notification.
  static Future<void> initMainIsolate(
      {required void Function(String payload) onTapPayload}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    await plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onTapPayload(p);
      },
    );

    // High-importance channel for questions (distinct from the service channel).
    const channel = AndroidNotificationChannel(
      AppConfig.promptChannelId,
      AppConfig.promptChannelName,
      description: 'In-session questions that need your answer.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// If the app was launched by tapping a prompt notification while it was
  /// fully closed, return that payload so we can route to the question.
  static Future<String?> launchPayload() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details!.notificationResponse?.payload;
    }
    return null;
  }
}
