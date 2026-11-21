import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'sound_service.dart';

/// सभी लोकल नोटिफिकेशन यहीं से।
/// Android में चैनल का साउंड बाद में नहीं बदलता, इसलिए साउंड बदलने पर नया चैनल बनता है
/// (चैनल id में साउंड का fingerprint होता है)।
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int alarmOffset = 1000000; // अलार्म की id = टास्क id + यह संख्या
  static bool _ready = false;

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _ready = true;
  }

  static Future<bool> requestNotificationPermission() async {
    final granted = await _android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<bool> canScheduleExact() async {
    return (await _android?.canScheduleExactNotifications()) ?? true;
  }

  static Future<void> openExactAlarmSettings() async {
    await _android?.requestExactAlarmsPermission();
  }

  static int _fingerprint(String s) => s.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);

  /// स्लॉट के साउंड के हिसाब से Android details बनाता है और चैनल तैयार करता है।
  static Future<AndroidNotificationDetails> _detailsFor(String slotId) async {
    final source = await SoundService.getSource(slotId);
    final label = SoundService.slotById(slotId).label;

    AndroidNotificationSound? sound;
    if (source.startsWith('builtin:')) {
      final key = source.substring(8);
      if (key != 'default') sound = RawResourceAndroidNotificationSound('sound_$key');
    } else if (source.startsWith('file:')) {
      final uri = await SoundService.contentUriFor(source.substring(5));
      if (uri != null) sound = UriAndroidNotificationSound(uri);
    }

    final channelId = 'taskify_${slotId}_${_fingerprint(source)}';
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        label,
        description: 'Taskify $label',
        importance: Importance.max,
        playSound: true,
        sound: sound,
      ),
    );

    return AndroidNotificationDetails(
      channelId,
      label,
      channelDescription: 'Taskify $label',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: sound,
      category: AndroidNotificationCategory.reminder,
    );
  }

  static Future<void> _zoned({
    required int id,
    required String heading,
    required String body,
    required DateTime at,
    required AndroidNotificationDetails android,
  }) async {
    final when = tz.TZDateTime.from(at, tz.local);
    final details = NotificationDetails(android: android);
    try {
      await _plugin.zonedSchedule(
        id,
        heading,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Exact schedule failed, using inexact: $e');
      await _plugin.zonedSchedule(
        id,
        heading,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// [enabled] = यूनिवर्सल नोटिफिकेशन स्विच, [alarmEnabled] = टास्क के समय वाला अलार्म।
  static Future<void> scheduleTask({
    required int id,
    required String title,
    required DateTime date,
    required int startMinutes,
    required int leadMinutes,
    required bool enabled,
    required bool alarmEnabled,
  }) async {
    if (!enabled && !alarmEnabled) return;
    await init();

    final taskTime = DateTime(date.year, date.month, date.day, startMinutes ~/ 60, startMinutes % 60);
    final now = DateTime.now();

    if (enabled) {
      final alertTime = taskTime.subtract(Duration(minutes: leadMinutes));
      if (alertTime.isAfter(now)) {
        await _zoned(
          id: id,
          heading: 'Upcoming in $leadMinutes mins',
          body: title,
          at: alertTime,
          android: await _detailsFor('reminder'),
        );
      }
    }

    if (alarmEnabled && taskTime.isAfter(now)) {
      await _zoned(
        id: id + alarmOffset,
        heading: 'अभी शुरू करें',
        body: title,
        at: taskTime,
        android: await _detailsFor('alarm'),
      );
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
      await _plugin.cancel(id + alarmOffset);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> showTest() async {
    await init();
    await _plugin.show(
      999001,
      'Taskify',
      'Test notification – आपका चुना हुआ साउंड',
      NotificationDetails(android: await _detailsFor('reminder')),
    );
  }
}
