import 'dart:io';

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_database.dart';
import 'app_theme.dart';
import 'package:share_plus/share_plus.dart';
import 'helpers.dart';
import 'notification_service.dart';
import 'permission_setup_screen.dart';
import 'native_storage_explorer_dialog.dart';
import 'ai_settings_page.dart';
import 'sound_settings_page.dart';

class SettingsPage extends StatefulWidget {
  final AppDatabase db;
  final String appTitle;
  final ValueChanged<ThemeMode> onThemeChanged;
  final Future<void> Function({String? title, int? leadTime, String? refreshMode}) onAppSettingsChanged;
  final VoidCallback onChanged;

  const SettingsPage({
    super.key,
    required this.db,
    required this.appTitle,
    required this.onThemeChanged,
    required this.onAppSettingsChanged,
    required this.onChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  int streakTarget = 80;
  bool carryForward = false;
  late String appTitle;
  int routineStartMinutes = 360;
  int routineEndMinutes = 720;
  int notificationLeadTime = 5;
  bool notifOn = true;
  String refreshRateMode = '120';

  int freezeTokens = 2;
  bool subtasksEnabled = true;
  bool autoBackupEnabled = true;
  String autoBackupFolder = '';
  String autoBackupDay = 'Sunday';
  bool cloudSyncEnabled = false;
  bool pinEnabled = false;
  bool bioEnabled = false;

  @override
  void initState() {
    super.initState();
    appTitle = widget.appTitle;
    load();
  }

  Future<void> load() async {
    final target = await widget.db.getSetting('streakTarget');
    final carry = await widget.db.getSetting('carryForward');
    final savedTitle = await widget.db.getSetting('appTitle');
    final savedStart = await widget.db.getSetting('startMinutes');
    final savedEnd = await widget.db.getSetting('endMinutes');
    final savedLead = await widget.db.getSetting('notificationLeadTime');
    final savedNotifOn = await widget.db.getSetting('notificationsEnabled');
    final savedRefresh = await widget.db.getSetting('refreshRateMode');
    final tokens = await widget.db.getSetting('streakFreezeTokens');
    final sub = await widget.db.getSetting('featureSubtasksEnabled');
    final autoB = await widget.db.getSetting('featureAutoBackupEnabled');
    final autoBF = await widget.db.getSetting('autoBackupFolderPath');
    final autoBD = await widget.db.getSetting('autoBackupDay');
    final cloudS = await widget.db.getSetting('cloudSyncEnabled');
    final pinEn = await widget.db.getSetting('pinSecurityEnabled');
    final bioEn = await widget.db.getSetting('biometricEnabled');

    if (!mounted) return;

    setState(() {
      streakTarget = int.tryParse(target ?? '') ?? 80;
      carryForward = carry == '1';
      appTitle = (savedTitle == null || savedTitle.trim().isEmpty) ? widget.appTitle : savedTitle.trim();
      routineStartMinutes = int.tryParse(savedStart ?? '') ?? 360;
      routineEndMinutes = int.tryParse(savedEnd ?? '') ?? 720;
      notificationLeadTime = int.tryParse(savedLead ?? '5') ?? 5;
      notifOn = savedNotifOn != '0';
      refreshRateMode = savedRefresh ?? '120';
      freezeTokens = int.tryParse(tokens ?? '2') ?? 2;
      subtasksEnabled = sub != '0';
      autoBackupEnabled = autoB != '0';
      autoBackupFolder = autoBF ?? '';
      autoBackupDay = autoBD ?? 'Sunday';
      cloudSyncEnabled = cloudS == '1';
      pinEnabled = pinEn == '1';
      bioEnabled = bioEn == '1';
    });
  }

  Future<void> chooseAutoBackupDay() async {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', 'Every Day'];
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Select Auto-Backup Schedule'),
        children: days.map((d) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, d),
            child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      await widget.db.setSetting('autoBackupDay', selected);
      setState(() => autoBackupDay = selected);
    }
  }

  Future<void> handleGoogleDriveOptions() async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Google Drive Options'),
        content: const Text('बैकअप फ़ाइल बनाकर Google Drive या किसी भी ऐप में भेजें, clipboard में कॉपी करें, या लिंक सेट करें:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'configure_link'),
            child: const Text('Set Drive Link'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'clipboard_backup'),
            child: const Text('Copy Backup'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'backup_now'),
            child: const Text('Share to Drive'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (action == 'backup_now') {
      await _performGoogleDriveBackup();
    } else if (action == 'clipboard_backup') {
      await backupToClipboard();
    } else if (action == 'configure_link') {
      await configureDriveLink();
    }
  }

  Future<void> backupToClipboard() async {
    try {
      final json = await widget.db.exportJson();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Taskify_Drive_Backup_$dateStr.json';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(json);

      await Clipboard.setData(ClipboardData(text: json));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup ready ($fileName).\nCopied to clipboard. Select Drive to save.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Drive action error: $e')));
    }
  }

  Future<void> configureDriveLink() async {
    final ctrl = TextEditingController();
    final currentUrl = await widget.db.getSetting('cloudSyncUrl');
    ctrl.text = currentUrl ?? '';

    if (!mounted) return;
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Google Drive Link / Webhook'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://drive.google.com/... or Webhook URL'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (res != null && res.isNotEmpty) {
      await widget.db.setSetting('cloudSyncUrl', res);
      await widget.db.setSetting('cloudSyncEnabled', '1');
      if (!mounted) return;
      setState(() => cloudSyncEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drive configuration saved!')));
    }
  }

  /// बैकअप फ़ाइल बनाकर शेयर शीट खोलता है। वहाँ Google Drive चुनकर सेव करें (कोई Google लॉगिन नहीं)।
  Future<void> _performGoogleDriveBackup() async {
    try {
      final json = await widget.db.exportJson();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Taskify_Backup_$dateStr.json';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(json);

      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/json')],
        subject: fileName,
        text: 'Taskify बैकअप',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('बैकअप नहीं बन सका: $e')));
    }
  }

  Future<void> manualBackupToDestinationFolder() async {
    try {
      Directory targetDir;
      if (autoBackupFolder.isNotEmpty && await Directory(autoBackupFolder).exists()) {
        targetDir = Directory(autoBackupFolder);
      } else {
        targetDir = Directory('/storage/emulated/0/Download');
        if (!await targetDir.exists()) {
          final ext = await getExternalStorageDirectory();
          targetDir = ext ?? await getApplicationDocumentsDirectory();
        }
      }

      final json = await widget.db.exportJson();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Taskify_AutoBackup_$dateStr.json';

      final file = File('${targetDir.path}/$fileName');
      await file.writeAsString(json);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created in:\n${file.path}'), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> pickAutoBackupFolder() async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auto-Backup Destination'),
        content: const Text('Choose an action:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'backup_now'),
            child: const Text('Backup Now Manually'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'select_folder'),
            child: const Text('Change Folder'),
          ),
        ],
      ),
    );

    if (action == 'backup_now') {
      await manualBackupToDestinationFolder();
    } else if (action == 'select_folder') {
      final chosenFolder = await showDialog<Directory>(
        context: context,
        builder: (_) => const NativeStorageExplorerDialog(isFolderPicker: true),
      );
      if (chosenFolder != null) {
        await widget.db.setSetting('autoBackupFolderPath', chosenFolder.path);
        setState(() => autoBackupFolder = chosenFolder.path);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Target folder updated:\n${chosenFolder.path}')),
        );
      }
    }
  }

  Future<void> exportBackupFile() async {
    try {
      final chosenFolder = await showDialog<Directory>(
        context: context,
        builder: (_) => const NativeStorageExplorerDialog(isFolderPicker: true),
      );

      Directory dest = chosenFolder ?? Directory('/storage/emulated/0/Download');
      if (!await dest.exists()) {
        final ext = await getExternalStorageDirectory();
        dest = ext ?? await getApplicationDocumentsDirectory();
      }

      final json = await widget.db.exportJson();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Taskify_Backup_$dateStr.json';

      final file = File('${dest.path}/$fileName');
      await file.writeAsString(json);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup exported successfully:\n${file.path}'), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
    }
  }

  Future<void> importBackupFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.single;
      if (!picked.name.toLowerCase().endsWith('.json')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('कृपया केवल .json बैकअप फ़ाइल चुनें।')),
        );
        return;
      }

      String content;
      if (picked.bytes != null) {
        content = utf8.decode(picked.bytes!);
      } else if (picked.path != null) {
        content = await File(picked.path!).readAsString();
      } else {
        throw Exception('फ़ाइल पढ़ी नहीं जा सकी।');
      }

      await widget.db.importJson(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully!')),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> exportMonthlyReportText() async {
    try {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final last = DateTime(now.year, now.month + 1, 0);
      final list = await widget.db.tasksBetween(first, last);

      final total = list.length;
      final done = list.where((e) => e['status'] == 'completed').length;
      final pct = total == 0 ? 0 : ((done / total) * 100).round();

      final doc = pw.Document();
      final monthTitle = DateFormat('MMMM yyyy').format(now);
      final Map<String, int> catCounts = {};
      final Map<String, int> catDone = {};
      for (final t in list) {
        final c = t['category'].toString();
        catCounts[c] = (catCounts[c] ?? 0) + 1;
        if (t['status'] == 'completed') catDone[c] = (catDone[c] ?? 0) + 1;
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) => [
            pw.Header(
              level: 0,
              child: pw.Text('TASKIFY MONTHLY PERFORMANCE REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('Month: $monthTitle   |   Total Tasks: $total   |   Completed: $done   |   Score: $pct%'),
            pw.SizedBox(height: 14),
            pw.Text('Category Breakdown', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Category', 'Completed', 'Total', 'Rate'],
              data: catCounts.keys.map((c) {
                final tot = catCounts[c] ?? 0;
                final dn = catDone[c] ?? 0;
                final rate = tot == 0 ? '0%' : '${((dn / tot) * 100).round()}%';
                return [c, '$dn', '$tot', rate];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Task Log', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Title', 'Category', 'Status'],
              data: list.take(120).map((t) => [
                t['date'].toString(),
                t['title'].toString(),
                t['category'].toString(),
                t['status'].toString(),
              ]).toList(),
            ),
          ],
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final pdfFile = File('${tempDir.path}/Taskify_Monthly_Report_${now.month}_${now.year}.pdf');
      await pdfFile.writeAsBytes(await doc.save());

      await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')],
        subject: 'Taskify Monthly Report - $monthTitle',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report creation failed: $e')));
    }
  }

  Future<void> useStreakFreeze() async {
    if (freezeTokens <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Streak Freeze tokens remaining.')));
      return;
    }
    final yes = await confirm(context, 'Use Streak Freeze Token?', 'Preserve streak for missed tasks.');
    if (!yes) return;
    setState(() => freezeTokens--);
    await widget.db.setSetting('streakFreezeTokens', '$freezeTokens');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Streak Freeze applied! Tokens left: $freezeTokens')));
  }

  Future<void> setupSecurityPin() async {
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set 4-Digit Security PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(hintText: 'PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save PIN')),
        ],
      ),
    );
    if (pin != null && pin.length == 4) {
      await widget.db.setSetting('appSecurityPin', pin);
      await widget.db.setSetting('pinSecurityEnabled', '1');
      setState(() => pinEnabled = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Security PIN enabled!')));
    }
  }

  Future<void> editAppTitle() async {
    final controller = TextEditingController(text: appTitle);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Display name', hintText: 'Taskifyy'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await widget.db.setSetting('appTitle', value);
    await widget.onAppSettingsChanged(title: value);
    if (mounted) setState(() => appTitle = value);
  }

  Future<void> editRoutineWindow() async {
    TimeOfDay start = minutesToTime(routineStartMinutes);
    TimeOfDay end = minutesToTime(routineEndMinutes);

    final result = await showDialog<List<TimeOfDay>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Routine window'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.wb_sunny_rounded, color: AppColors.amber),
                title: const Text('Start time'),
                subtitle: Text(start.format(context)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                      child: child!,
                    ),
                  );
                  if (picked != null) setDialogState(() => start = picked);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.nights_stay_rounded, color: AppColors.violet),
                title: const Text('End time'),
                subtitle: Text(end.format(context)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                      child: child!,
                    ),
                  );
                  if (picked != null) setDialogState(() => end = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final sm = start.hour * 60 + start.minute;
              final em = end.hour * 60 + end.minute;
              if (em <= sm) return;
              Navigator.pop(context, [start, end]);
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    final sm = result[0].hour * 60 + result[0].minute;
    final em = result[1].hour * 60 + result[1].minute;
    await widget.db.setSetting('startMinutes', '$sm');
    await widget.db.setSetting('endMinutes', '$em');
    if (mounted) setState(() { routineStartMinutes = sm; routineEndMinutes = em; });
    widget.onChanged();
  }

  Future<void> editNotificationLeadTime() async {
    final controller = TextEditingController(text: '$notificationLeadTime');
    final val = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notification Alert'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Minutes before start', hintText: 'e.g. 5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    final parsed = int.tryParse(val ?? '');
    if (parsed == null || parsed < 1 || parsed > 120) return;
    await widget.db.setSetting('notificationLeadTime', '$parsed');
    await widget.onAppSettingsChanged(leadTime: parsed);
    if (mounted) setState(() => notificationLeadTime = parsed);
  }

  Future<void> chooseRefreshRate() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Display Refresh Rate'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '120'),
            child: const ListTile(leading: Icon(Icons.speed_rounded, color: AppColors.violet), title: Text('120Hz (Ultra Smooth)')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '90'),
            child: const ListTile(leading: Icon(Icons.bolt_rounded, color: AppColors.cyan), title: Text('90Hz (Balanced)')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '60'),
            child: const ListTile(leading: Icon(Icons.battery_charging_full_rounded, color: AppColors.emerald), title: Text('60Hz (Battery Saver)')),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await widget.db.setSetting('refreshRateMode', selected);
    await widget.onAppSettingsChanged(refreshMode: selected);
    if (mounted) setState(() => refreshRateMode = selected);
  }

  Future<void> chooseTheme() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ThemeMode.dark),
            child: const ListTile(leading: Icon(Icons.dark_mode_rounded, color: AppColors.violet), title: Text('Dark Theme')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ThemeMode.light),
            child: const ListTile(leading: Icon(Icons.light_mode_rounded), title: Text('Light Theme')),
          ),
        ],
      ),
    );
    if (selected != null) {
      await widget.db.setSetting('theme', selected.name);
      widget.onThemeChanged(selected);
    }
  }

  Future<void> deleteAll() async {
    final first = await confirm(context, 'Delete ALL routine data?', 'All tasks, routines, and streaks will be wiped out.');
    if (!first) return;

    if (!mounted) return;
    final second = await confirm(context, 'Are you ABSOLUTELY sure?', 'This action is irreversible.');
    if (!second) return;

    await widget.db.deleteAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All routine data wiped permanently.')));
    }
    widget.onChanged();
  }

  Future<void> testNotification() async {
    await NotificationService.requestNotificationPermission();
    final ok = await NotificationService.showTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Test notification भेजा गया'
              : 'Notification भेजने में दिक्कत आई। Notification permission चेक करें।',
        ),
      ),
    );
  }

  Future<void> checkNotificationPermissions() async {
    final granted = await NotificationService.requestNotificationPermission();
    final exact = await NotificationService.canScheduleExact();
    if (!exact) {
      // Android 12+ पर यह सेटिंग खोलता है, वहाँ "Alarms & reminders" चालू करें
      await NotificationService.openExactAlarmSettings();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted && exact
              ? 'नोटिफिकेशन और Alarm अनुमति चालू हैं'
              : 'नोटिफिकेशन और "Alarms & reminders" की अनुमति दें',
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.11),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.17)),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, height: 1.3)),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: ListView(
        physics: const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast),
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // ===================== App Basics =====================
          const SectionLabel('App Basics'),
          _settingsTile(
            icon: Icons.title_rounded,
            color: AppColors.violet,
            title: 'App display name',
            subtitle: appTitle,
            onTap: editAppTitle,
          ),
          _settingsTile(
            icon: Icons.palette_rounded,
            color: AppColors.cyan,
            title: 'Appearance',
            subtitle: 'Dark or Light theme.',
            onTap: chooseTheme,
          ),
          _settingsTile(
            icon: Icons.schedule_rounded,
            color: AppColors.amber,
            title: 'Routine window',
            subtitle: '${formatMinutes(routineStartMinutes)} – ${formatMinutes(routineEndMinutes)}',
            onTap: editRoutineWindow,
          ),
          _settingsTile(
            icon: Icons.speed_rounded,
            color: AppColors.cyan,
            title: 'Display refresh rate',
            subtitle: '$refreshRateMode Hz (Locked)',
            onTap: chooseRefreshRate,
          ),

          // ===================== Notifications & Alarms =====================
          const SectionLabel('Notifications & Alarms'),
          _settingsTile(
            icon: Icons.notifications_active_rounded,
            color: AppColors.amber,
            title: 'Advance Notification Alert',
            subtitle: '$notificationLeadTime minutes before task start (Tap to set)',
            onTap: editNotificationLeadTime,
          ),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: const Icon(Icons.notifications_rounded, color: AppColors.amber),
              title: const Text('Notification चालू / बंद'),
              subtitle: const Text('बंद करने पर टास्क के नोटिफिकेशन और अलार्म नहीं आएँगे।'),
              value: notifOn,
              onChanged: (v) async {
                await widget.db.setSetting('notificationsEnabled', v ? '1' : '0');
                if (!v) await NotificationService.cancelAll();
                await widget.db.rescheduleAllReminders();
                if (mounted) setState(() => notifOn = v);
              },
            ),
          ),
          _settingsTile(
            icon: Icons.notification_add_rounded,
            color: AppColors.amber,
            title: 'Test Notification',
            subtitle: 'Abhi ek test notification bhejein',
            onTap: testNotification,
          ),
          _settingsTile(
            icon: Icons.security_rounded,
            color: AppColors.emerald,
            title: 'All App Permissions Hub',
            subtitle: 'सभी अनुमतियाँ (Mic, Camera, Files, Alarms, Battery) एक जगह से दें',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PermissionSetupScreen(
                  db: widget.db,
                  onDone: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          _settingsTile(
            icon: Icons.verified_user_rounded,
            color: AppColors.amber,
            title: 'Notification Permissions',
            subtitle: 'Notification और Alarm की अनुमति जाँचें / दें',
            onTap: checkNotificationPermissions,
          ),
          _settingsTile(
            icon: Icons.music_note_rounded,
            color: AppColors.amber,
            title: 'Sound & Notifications',
            subtitle: 'टास्क बनाने/पूरा होने, नोटिफिकेशन और अलार्म के लिए अपनी फ़ाइल चुनें।',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SoundSettingsPage(db: widget.db))),
          ),

          // ===================== AI Assistant =====================
          const SectionLabel('AI Assistant'),
          _settingsTile(
            icon: Icons.auto_awesome_rounded,
            color: AppColors.cyan,
            title: 'AI Assistant',
            subtitle: 'Gemini / DeepSeek API key, असिस्टेंट का नाम और मॉडल।',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AiSettingsPage(db: widget.db))),
          ),

          // ===================== Productivity Tools =====================
          const SectionLabel('Productivity Tools'),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.17)),
                ),
                child: const Icon(Icons.move_down_rounded, color: AppColors.cyan, size: 19),
              ),
              title: const Text('Carry forward unfinished', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Allow unfinished tasks to be moved to tomorrow.', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
              ),
              value: carryForward,
              onChanged: (value) async {
                setState(() => carryForward = value);
                await widget.db.setSetting('carryForward', value ? '1' : '0');
              },
            ),
          ),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.emerald.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.checklist_rounded, color: AppColors.emerald, size: 20),
              ),
              title: const Text('Task Checklists & Sub-tasks', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: const Text('Enable mini checklist inside task cards.', style: TextStyle(fontSize: 10.5)),
              value: subtasksEnabled,
              onChanged: (val) async {
                setState(() => subtasksEnabled = val);
                await widget.db.setSetting('featureSubtasksEnabled', val ? '1' : '0');
                widget.onChanged();
              },
            ),
          ),
          _settingsTile(
            icon: Icons.shield_rounded,
            color: AppColors.amber,
            title: 'Streak Freeze Tokens ($freezeTokens Left)',
            subtitle: '1-Click protect your streak if routine is missed.',
            onTap: useStreakFreeze,
          ),
          _settingsTile(
            icon: Icons.description_rounded,
            color: AppColors.rose,
            title: 'Generate Monthly Report File',
            subtitle: 'Compiles full month score into a clean Report text file.',
            onTap: exportMonthlyReportText,
          ),

          // ===================== Backup & Sync =====================
          const SectionLabel('Backup & Sync'),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.backup_rounded, color: AppColors.blue, size: 20),
              ),
              title: const Text('Auto-Rolling Backup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: Text('Schedule: $autoBackupDay (Tap to change)', style: const TextStyle(fontSize: 10.5)),
              value: autoBackupEnabled,
              onChanged: (val) async {
                setState(() => autoBackupEnabled = val);
                await widget.db.setSetting('featureAutoBackupEnabled', val ? '1' : '0');
              },
            ),
          ),
          _settingsTile(
            icon: Icons.calendar_today_rounded,
            color: AppColors.cyan,
            title: 'Auto-Backup Day ($autoBackupDay)',
            subtitle: 'Choose which day backup triggers automatically.',
            onTap: chooseAutoBackupDay,
          ),
          _settingsTile(
            icon: Icons.drive_file_move_rounded,
            color: AppColors.indigo,
            title: 'Auto-Backup Destination Folder',
            subtitle: autoBackupFolder.isEmpty ? 'Downloads (Tap to Backup Now / Pick Folder)' : '$autoBackupFolder (Tap for options)',
            onTap: pickAutoBackupFolder,
          ),
          _settingsTile(
            icon: Icons.cloud_sync_rounded,
            color: AppColors.emerald,
            title: 'Backup to Google Drive',
            subtitle: 'बैकअप फ़ाइल बनाकर Drive या किसी भी ऐप में शेयर करें (बिना लॉगिन)।',
            onTap: handleGoogleDriveOptions,
          ),
          _settingsTile(
            icon: Icons.file_download_outlined,
            color: AppColors.emerald,
            title: 'Export Backup File (.json)',
            subtitle: 'Pick folder & export without permission errors.',
            onTap: exportBackupFile,
          ),
          _settingsTile(
            icon: Icons.file_upload_outlined,
            color: AppColors.blue,
            title: 'Import Backup File (.json)',
            subtitle: 'Browse storage & select .json to restore.',
            onTap: importBackupFile,
          ),

          // ===================== Security =====================
          const SectionLabel('Security'),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.pink.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.lock_person_rounded, color: AppColors.pink, size: 20),
              ),
              title: const Text('App Security PIN Lock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: Text(pinEnabled ? 'Lock active (Requires PIN)' : 'Tap to setup 4-digit PIN lock', style: const TextStyle(fontSize: 10.5)),
              value: pinEnabled,
              onChanged: (val) async {
                if (val) {
                  setupSecurityPin();
                } else {
                  await widget.db.setSetting('pinSecurityEnabled', '0');
                  setState(() => pinEnabled = false);
                }
              },
            ),
          ),

          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.cyan.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.fingerprint_rounded, color: AppColors.cyan, size: 20),
              ),
              title: const Text('Fingerprint / Biometric Unlock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: const Text('PIN स्क्रीन पर फिंगरप्रिंट से अनलॉक करें', style: TextStyle(fontSize: 10.5)),
              value: bioEnabled,
              onChanged: (val) async {
                await widget.db.setSetting('biometricEnabled', val ? '1' : '0');
                setState(() => bioEnabled = val);
              },
            ),
          ),

          // ===================== Danger Zone =====================
          const SectionLabel('Danger Zone'),
          _settingsTile(
            icon: Icons.delete_forever_rounded,
            color: AppColors.rose,
            title: 'Delete All Data',
            subtitle: 'Double confirmation required.',
            onTap: deleteAll,
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}
