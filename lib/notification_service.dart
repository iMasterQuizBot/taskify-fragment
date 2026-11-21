import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// सभी लोकल नोटिफिकेशन की एक ही जगह।
/// Android में चैनल का साउंड बदला नहीं जा सकता, इसलिए हर साउंड का अलग चैनल है।
class NotificationSound {
  final String key;
  final String label;
  final String? rawName; // res/raw में फ़ाइल का नाम (बिना extension)
  final String? assetPath; // preview के लिए asset path (assets/ के बाद से)

  const NotificationSound(this.key, this.label, this.rawName, this.assetPath);

  String get channelId => 'taskify_v2_$key';
}

const List<NotificationSound> notificationSounds = [
  NotificationSound('default', 'System Default', null, null),
  NotificationSound('chime', 'Chime', 'sound_chime', 'sounds/sound_chime.wav'),
  NotificationSound('bell', 'Bell', 'sound_bell', 'sounds/sound_bell.wav'),
  NotificationSound('beep', 'Beep', 'sound_beep', 'sounds/sound_beep.wav'),
  NotificationSound('alarm', 'Alarm', 'sound_alarm', 'sounds/sound_alarm.wav'),
];

NotificationSound notificationSoundFor(String key) {
  return notificationSounds.firstWhere(
    (s) => s.key == key,
    orElse: () => notificationSounds.first,
  );
}

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// पुराना नाम `flutterLocalNotificationsPlugin` बाकी कोड में वैसे ही चले।
FlutterLocalNotificationsPlugin get flutterLocalNotificationsPlugin => _plugin;

class NotificationService {
  static bool _ready = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final impl = _android;
    if (impl != null) {
      for (final s in notificationSounds) {
        await impl.createNotificationChannel(
          AndroidNotificationChannel(
            s.channelId,
            'Task Reminders (${s.label})',
            description: 'Task start reminders',
            importance: Importance.max,
            playSound: true,
            sound: s.rawName == null ? null : RawResourceAndroidNotificationSound(s.rawName!),
          ),
        );
      }
    }
    _ready = true;
  }

  /// Android 13+ पर नोटिफिकेशन की अनुमति माँगता है। बिना इसके कोई नोटिफिकेशन नहीं दिखता।
  static Future<bool> requestNotificationPermission() async {
    final granted = await _android?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Android 12+ पर exact alarm की अनुमति। अगर नहीं है तो सिस्टम सेटिंग खोलता है।
  static Future<bool> canScheduleExact() async {
    return (await _android?.canScheduleExactNotifications()) ?? true;
  }

  static Future<void> openExactAlarmSettings() async {
    await _android?.requestExactAlarmsPermission();
  }

  static Future<void> scheduleTask({
    required int id,
    required String title,
    required DateTime date,
    required int startMinutes,
    required int leadMinutes,
    required String soundKey,
  }) async {
    await init();

    final taskTime = DateTime(date.year, date.month, date.day, startMinutes ~/ 60, startMinutes % 60);
    final alertTime = taskTime.subtract(Duration(minutes: leadMinutes));
    if (!alertTime.isAfter(DateTime.now())) return;

    final sound = notificationSoundFor(soundKey);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        sound.channelId,
        'Task Reminders (${sound.label})',
        channelDescription: 'Task start reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: sound.rawName == null ? null : RawResourceAndroidNotificationSound(sound.rawName!),
        category: AndroidNotificationCategory.reminder,
      ),
    );

    // TZDateTime.from असली क्षण (instant) रखता है, इसलिए UTC डिफ़ॉल्ट होने से भी समय नहीं बिगड़ता।
    final when = tz.TZDateTime.from(alertTime, tz.local);
    final body = title;
    final heading = 'Upcoming in $leadMinutes mins';

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
      // exact alarm की अनुमति न हो तो लगभग-सही समय पर शेड्यूल करें, नोटिफिकेशन फिर भी आएगा
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

  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> showTest(String soundKey) async {
    await init();
    final sound = notificationSoundFor(soundKey);
    await _plugin.show(
      999001,
      'Taskify',
      'Test notification – sound: ${sound.label}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          sound.channelId,
          'Task Reminders (${sound.label})',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: sound.rawName == null ? null : RawResourceAndroidNotificationSound(sound.rawName!),
        ),
      ),
    );
  }
}
