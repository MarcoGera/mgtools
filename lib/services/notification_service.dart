import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/hub_item.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _foregroundTimer;
  final Set<String> _notifiedInSession = {};
  void Function(HubItem item)? onInAppReminderTriggered;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linuxSettings =
          LinuxInitializationSettings(defaultActionName: 'Открыть уведомление');

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _plugin.initialize(settings);

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init warning: $e');
    }
  }

  int _idFromUuid(String id) => id.hashCode & 0x7FFFFFFF;

  Future<void> scheduleReminder(HubItem item) async {
    if (!_initialized) await init();
    await cancelReminder(item.id);

    if (item.isDeleted ||
        item.isCompleted ||
        item.reminderAt == null ||
        item.reminderAt!.isBefore(DateTime.now())) {
      return;
    }

    try {
      final scheduledDate = tz.TZDateTime.from(item.reminderAt!, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'mgtools_reminders_channel',
        'Напоминания MGtools',
        channelDescription: 'Уведомления о задачах, заметках и закладках MGtools',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
        ticker: 'Напоминание MGtools',
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.critical,
        ),
      );

      await _plugin.zonedSchedule(
        _idFromUuid(item.id),
        'MGtools: ${item.title}',
        item.content.isNotEmpty
            ? item.content
            : (item.url ?? 'Откройте MGtools для просмотра'),
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Schedule reminder error/fallback: $e');
    }
  }

  Future<void> showNow(HubItem item) async {
    if (!_initialized) await init();
    try {
      const androidDetails = AndroidNotificationDetails(
        'mgtools_reminders_channel',
        'Напоминания MGtools',
        channelDescription: 'Уведомления о задачах, заметках и закладках MGtools',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(
            urgency: LinuxNotificationUrgency.critical),
      );
      await _plugin.show(
        _idFromUuid('${item.id}_now'),
        '⏰ MGtools: ${item.title}',
        item.content.isNotEmpty ? item.content : 'Напоминание сработало',
        details,
      );
    } catch (e) {
      debugPrint('Show now notification error: $e');
    }
  }

  Future<void> cancelReminder(String itemId) async {
    try {
      await _plugin.cancel(_idFromUuid(itemId));
    } catch (_) {}
  }

  void startForegroundWatcher(List<HubItem> Function() getItems) {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      for (final item in getItems()) {
        if (item.isDeleted || item.isCompleted || item.reminderAt == null) {
          continue;
        }
        final diff = now.difference(item.reminderAt!).inSeconds;
        if (diff >= 0 && diff <= 90 && !_notifiedInSession.contains(item.id)) {
          _notifiedInSession.add(item.id);
          onInAppReminderTriggered?.call(item);
          showNow(item);
        }
      }
    });
  }

  void dispose() {
    _foregroundTimer?.cancel();
  }
}
