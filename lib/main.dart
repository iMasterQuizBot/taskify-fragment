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

  // FadeInApp के साथ ऐप शुरू करें
  runApp(FadeInApp(child: MyDailyRoutineApp(db: db)));
}

// ऐप ओपन होते ही स्मूथनेस (Fade-in Effect) देने के लिए यह विजेट बनाया गया है
class FadeInApp extends StatefulWidget {
  final Widget child;
  const FadeInApp({super.key, required this.child});

  @override
  State<FadeInApp> createState() => _FadeInAppState();
}

class _FadeInAppState extends State<FadeInApp> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    // 100ms बाद फेड-इन शुरू होगा
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 800), // 800ms की स्मूथनेस
      curve: Curves.easeInOut,
      child: widget.child,
    );
  }
}
