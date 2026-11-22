import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'notification_service.dart';

class PermissionSetupScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback onDone;

  const PermissionSetupScreen({
    super.key,
    required this.db,
    required this.onDone,
  });

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _notif = false;
  bool _mic = false;
  bool _camera = false;
  bool _media = false;
  bool _exactAlarm = false;
  bool _battery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    try {
      final n = await Permission.notification.isGranted;
      final m = await Permission.microphone.isGranted;
      final c = await Permission.camera.isGranted;
      final p = await Permission.photos.isGranted ||
          await Permission.storage.isGranted ||
          await Permission.audio.isGranted;
      final a = await NotificationService.canScheduleExact();
      final b = await Permission.ignoreBatteryOptimizations.isGranted;

      if (!mounted) return;
      setState(() {
        _notif = n;
        _mic = m;
        _camera = c;
        _media = p;
        _exactAlarm = a;
        _battery = b;
      });
    } catch (_) {}
  }

  Future<void> _grantAllRuntime() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (Platform.isAndroid) {
        // एक ही क्रम में सुरक्षित रूप से सभी runtime permissions माँगें (ताकि कोई conflict/crash न हो)
        await [
          Permission.notification,
          Permission.microphone,
          Permission.camera,
          Permission.photos,
          Permission.audio,
          Permission.storage,
        ].request();
      }
    } catch (_) {}
    await _refreshStatuses();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestSingle(Permission p) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await p.request();
      if (status.isPermanentlyDenied && mounted) {
        await openAppSettings();
      }
    } catch (_) {}
    await _refreshStatuses();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestExactAlarm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NotificationService.openExactAlarmSettings();
    } catch (_) {}
    await _refreshStatuses();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestBattery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {}
    await _refreshStatuses();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    await widget.db.setSetting('permissionsSetupDone', '1');
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
              children: [
                Center(
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppColors.cyan.withOpacity(0.35), blurRadius: 22),
                      ],
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Taskify Permissions Setup',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ताकि ऐप कभी क्रैश न हो और सारे फीचर्स (Voice AI, अलार्म, फ़ोटो, साउंड) एक बार में सही चलें, नीचे की अनुमतियाँ यहीं से दें:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: AppColors.violet.withOpacity(0.35), blurRadius: 16),
                    ],
                  ),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _grantAllRuntime,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.done_all_rounded, color: Colors.white),
                    label: const Text(
                      'सभी मुख्य अनुमतियाँ एक साथ दें',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _permTile(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications',
                  subtitle: 'टास्क रिमाइंडर और Live Focus Timer के लिए',
                  granted: _notif,
                  onTap: () => _requestSingle(Permission.notification),
                ),
                _permTile(
                  icon: Icons.mic_rounded,
                  title: 'Microphone',
                  subtitle: 'Voice AI और बोलकर कमांड देने के लिए',
                  granted: _mic,
                  onTap: () => _requestSingle(Permission.microphone),
                ),
                _permTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Camera',
                  subtitle: 'टाइमटेबल फ़ोटो और DeepSeek Web अपलोड के लिए',
                  granted: _camera,
                  onTap: () => _requestSingle(Permission.camera),
                ),
                _permTile(
                  icon: Icons.folder_open_rounded,
                  title: 'Files, Photos & Audio',
                  subtitle: 'फ़ोकस साउंड और JSON बैकअप फ़ाइलों के लिए',
                  granted: _media,
                  onTap: () async {
                    await _requestSingle(Permission.photos);
                    await _requestSingle(Permission.audio);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(
                    'External System Permissions (यहीं से खोलें)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.cyan),
                  ),
                ),
                _permTile(
                  icon: Icons.alarm_on_rounded,
                  title: 'Alarms & Reminders',
                  subtitle: 'ठीक समय पर अलार्म बजने के लिए (System Setting)',
                  granted: _exactAlarm,
                  onTap: _requestExactAlarm,
                ),
                _permTile(
                  icon: Icons.battery_saver_rounded,
                  title: 'Background Run (Battery)',
                  subtitle: 'ताकि बैकग्राउंड में Voice AI व अलार्म बंद न हों',
                  granted: _battery,
                  onTap: _requestBattery,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppColors.cyan.withOpacity(0.5)),
                    ),
                  ),
                  onPressed: _finish,
                  child: const Text(
                    'आगे बढ़ें (Continue to Taskify)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      glowColor: granted ? AppColors.emerald : AppColors.amber,
      onTap: granted ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (granted ? AppColors.emerald : AppColors.amber).withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: granted ? AppColors.emerald : AppColors.amber, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlowBadge(
            text: granted ? 'Allowed' : 'Allow',
            color: granted ? AppColors.emerald : AppColors.cyan,
            icon: granted ? Icons.check_circle_rounded : Icons.touch_app_rounded,
          ),
        ],
      ),
    );
  }
}
