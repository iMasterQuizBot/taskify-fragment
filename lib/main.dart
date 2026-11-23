import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_database.dart';
import 'notification_service.dart';
import 'sound_service.dart';
import 'taskify_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;

  final db = AppDatabase();
  await db.init();

  // ऐप को बिना किसी देरी के तुरंत खोलें (बाकी भारी काम बैकग्राउंड में होंगे)
  runApp(FadeInApp(child: MyDailyRoutineApp(db: db)));

  unawaited(_initBackgroundServices(db));
}

Future<void> _initBackgroundServices(AppDatabase db) async {
  try {
    await NotificationService.init();
  } catch (_) {}
  try {
    await SoundService.init(db);
  } catch (_) {}
  try {
    await db.autoAllocateRollingHabits();
  } catch (_) {}
  try {
    await db.rescheduleAllReminders();
  } catch (_) {}
}

/// ऐप ओपन होते ही तुरंत और स्मूथ (260ms) एंट्रेंस एनिमेशन
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );
  }
}
