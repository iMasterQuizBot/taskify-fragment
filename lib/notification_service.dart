import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// पहला वही आइकन जो flutter_launcher_icons बनाता है (pubspec में "launcher_icon")।
  /// वह न मिले तो बाकी विकल्प एक-एक करके आज़माए जाते हैं, ताकि
  /// "invalid_icon" एरर से नोटिफिकेशन कभी बंद न हो।
  static const List<String> _iconCandidates = [
    '@mipmap/launcher_icon',
    '@mipmap/ic_launcher',
    'launcher_icon',
    'ic_launcher',
  ];

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try { tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); } catch (_) {}

    Object? lastError;
    for (final icon in _iconCandidates) {
      try {
        await _plugin.initialize(
          InitializationSettings(android: AndroidInitializationSettings(icon)),
        );
        _ready = true;
        return;
      } catch (e) {
        lastError = e;
        debugPrint('Notification icon "$icon" नहीं चला: $e');
      }
    }
    throw lastError ?? Exception('Notification init failed');
  }

  static Future<bool> requestNotificationPermission() async {
    try {
      await init();
      final granted = await _android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canScheduleExact() async {
    try {
      return (await _android?.canScheduleExactNotifications()) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openExactAlarmSettings() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static int _fingerprint(String s) => s.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);

  /// स्लॉट के साउंड के हिसाब से Android details बनाता है और चैनल तैयार करता है।
  /// [useCustomSound] false हो तो सिस्टम का डिफ़ॉल्ट साउंड लगता है (सुरक्षित fallback)।
  static Future<AndroidNotificationDetails> _detailsFor(
    String slotId, {
    bool useCustomSound = true,
  }) async {
    final source = useCustomSound ? await SoundService.getSource(slotId) : 'builtin:default';
    final label = SoundService.slotById(slotId).label;

    AndroidNotificationSound? sound;
    if (source.startsWith('builtin:')) {
      final key = source.substring(8);
      if (key != 'default') {
        final res = SoundService.rawResourceFor(key);
        if (res != null) sound = RawResourceAndroidNotificationSound(res);
      }
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

  /// पहले आपका चुना हुआ साउंड आज़माता है। अगर साउंड की फ़ाइल रिसोर्स में न मिले
  /// (PlatformException invalid_sound), तो बिना कस्टम साउंड के दोबारा कोशिश करता है,
  /// ताकि नोटिफिकेशन कम से कम आए ज़रूर।
  static Future<void> _withSoundFallback(
    String slotId,
    Future<void> Function(AndroidNotificationDetails details) action,
  ) async {
    try {
      await action(await _detailsFor(slotId));
    } on PlatformException catch (e) {
      debugPrint('Notification (custom sound) failed: ${e.code} ${e.message}');
      await action(await _detailsFor(slotId, useCustomSound: false));
    }
  }

  static Future<void> _zoned({
    required int id,
    required String heading,
    required String body,
    required DateTime at,
    required String slotId,
  }) async {
    final when = tz.TZDateTime.from(at, tz.local);
    await _withSoundFallback(slotId, (android) async {
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
      } on PlatformException catch (e) {
        if (e.code == 'invalid_sound' || e.code == 'invalid_icon') rethrow;
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
    });
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
          slotId: 'reminder',
        );
      }
    }

    if (alarmEnabled && taskTime.isAfter(now)) {
      await _zoned(
        id: id + alarmOffset,
        heading: 'अभी शुरू करें',
        body: title,
        at: taskTime,
        slotId: 'alarm',
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

  /// टेस्ट नोटिफिकेशन। भेज दिया तो true, कोई दिक्कत आई तो false।
  static Future<bool> showTest() async {
    try {
      await init();
      await _withSoundFallback('reminder', (android) async {
        await _plugin.show(
          999001,
          'Taskify',
          'Test notification – आपका चुना हुआ साउंड',
          NotificationDetails(android: android),
        );
      });
      return true;
    } catch (e) {
      debugPrint('Test notification failed: $e');
      return false;
    }
  }

  static const int focusTimerNotifId = 888001;

  static Future<void> showOngoingFocusTimer({
    required String title,
    required String phase,
    required int secondsLeft,
  }) async {
    try {
      await init();
      final mins = (secondsLeft ~/ 60).toString().padLeft(2, '0');
      final secs = (secondsLeft % 60).toString().padLeft(2, '0');
      const android = AndroidNotificationDetails(
        'taskify_focus_live',
        'Focus Timer',
        channelDescription: 'Live Focus Timer countdown',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        silent: true,
        showWhen: false,
      );
      await _plugin.show(
        focusTimerNotifId,
        '$phase: $title',
        'समय शेष: $mins:$secs',
        const NotificationDetails(android: android),
      );
    } catch (_) {}
  }

  static Future<void> cancelFocusTimer() async {
    try {
      await _plugin.cancel(focusTimerNotifId);
    } catch (_) {}
  }
}
