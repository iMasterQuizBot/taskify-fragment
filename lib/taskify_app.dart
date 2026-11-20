import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'main_screen.dart';

class MyDailyRoutineApp extends StatefulWidget {
  final AppDatabase db;
  const MyDailyRoutineApp({super.key, required this.db});

  @override
  State<MyDailyRoutineApp> createState() => _MyDailyRoutineAppState();
}

class _MyDailyRoutineAppState extends State<MyDailyRoutineApp> {
  ThemeMode themeMode = ThemeMode.dark;
  String appTitle = 'Taskify';
  int notificationLeadTime = 5;
  String refreshRateMode = '120';
  bool isLocked = false;
  String savedPin = '';

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
    _loadAppSettings();
  }

  Future<void> _loadAppSettings() async {
    final savedTitle = await widget.db.getSetting('appTitle');
    final savedLead = await widget.db.getSetting('notificationLeadTime');
    final savedRefresh = await widget.db.getSetting('refreshRateMode');
    final pinEnabled = await widget.db.getSetting('pinSecurityEnabled');
    final pin = await widget.db.getSetting('appSecurityPin');

    if (mounted) {
      setState(() {
        appTitle = (savedTitle == null || savedTitle.trim().isEmpty) ? 'Taskify' : savedTitle.trim();
        notificationLeadTime = int.tryParse(savedLead ?? '5') ?? 5;
        refreshRateMode = savedRefresh ?? '120';
        savedPin = pin ?? '';
        isLocked = pinEnabled == '1' && savedPin.isNotEmpty;
      });
    }
  }

  Future<void> updateAppSettings({String? title, int? leadTime, String? refreshMode}) async {
    if (title != null) {
      final cleaned = title.trim();
      if (cleaned.isNotEmpty) {
        await widget.db.setSetting('appTitle', cleaned);
        if (mounted) setState(() => appTitle = cleaned);
      }
    }
    if (leadTime != null) {
      await widget.db.setSetting('notificationLeadTime', '$leadTime');
      if (mounted) setState(() => notificationLeadTime = leadTime);
    }
    if (refreshMode != null) {
      await widget.db.setSetting('refreshRateMode', refreshMode);
      if (mounted) setState(() => refreshRateMode = refreshMode);
    }
  }

  Future<void> _loadSavedTheme() async {
    final saved = await widget.db.getSetting('theme');
    if (!mounted) return;

    setState(() {
      switch (saved) {
        case 'light':
          themeMode = ThemeMode.light;
          break;
        case 'system':
          themeMode = ThemeMode.system;
          break;
        case 'dark':
        default:
          themeMode = ThemeMode.dark;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.violet,
        secondary: AppColors.cyan,
        surface: AppColors.surface,
        error: AppColors.rose,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      ),
      dividerColor: Colors.white.withOpacity(0.06),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF111620),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1A2030),
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.045),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.violet, width: 1.4)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF171C27),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
    );

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: AppColors.violet,
      scaffoldBackgroundColor: const Color(0xFFF5F7FC),
    );

    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: isLocked
          ? PinLockScreen(
              expectedPin: savedPin,
              onUnlocked: () => setState(() => isLocked = false),
            )
          : MainScreen(
              db: widget.db,
              appTitle: appTitle,
              onThemeChanged: (mode) => setState(() => themeMode = mode),
              onAppSettingsChanged: updateAppSettings,
            ),
    );
  }
}

class PinLockScreen extends StatefulWidget {
  final String expectedPin;
  final VoidCallback onUnlocked;

  const PinLockScreen({super.key, required this.expectedPin, required this.onUnlocked});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController pinCtrl = TextEditingController();
  String errorText = '';

  void verify() {
    if (pinCtrl.text.trim() == widget.expectedPin.trim()) {
      widget.onUnlocked();
    } else {
      setState(() {
        errorText = 'Incorrect PIN. Try again.';
        pinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              const Text('Taskify Locked', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Enter your 4-digit security PIN', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(counterText: ''),
                  onSubmitted: (_) => verify(),
                ),
              ),
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(errorText, style: const TextStyle(color: AppColors.rose, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: verify,
                style: FilledButton.styleFrom(backgroundColor: AppColors.violet),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
