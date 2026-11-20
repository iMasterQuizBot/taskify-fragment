import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app_database.dart';
import 'taskify_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;

  try {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (_) {}

  final db = AppDatabase();
  await db.init();
  await db.autoAllocateRollingHabits();
  // main.dart में
runApp(
  AnimatedOpacity(
    opacity: 1.0,
    duration: const Duration(milliseconds: 800), // 800ms की स्मूथनेस
    child: MyDailyRoutineApp(db: db),
  )
);
