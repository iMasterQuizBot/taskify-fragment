import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'google_drive_service.dart';
import 'helpers.dart';
import 'native_storage_explorer_dialog.dart';

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
  final GoogleDriveService _driveService = GoogleDriveService();

  int streakTarget = 80;
  bool carryForward = false;
  late String appTitle;
  int routineStartMinutes = 360;
  int routineEndMinutes = 720;
  int notificationLeadTime = 5;
  String refreshRateMode = '120';

  int freezeTokens = 2;
  bool subtasksEnabled = true;
  bool autoBackupEnabled = true;
  String autoBackupFolder = '';
  String autoBackupDay = 'Sunday';
  bool cloudSyncEnabled = false;
  bool pinEnabled = false;

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
    final savedRefresh = await widget.db.getSetting('refreshRateMode');
    final tokens = await widget.db.getSetting('streakFreezeTokens');
    final sub = await widget.db.getSetting('featureSubtasksEnabled');
    final autoB = await widget.db.getSetting('featureAutoBackupEnabled');
    final autoBF = await widget.db.getSetting('autoBackupFolderPath');
    final autoBD = await widget.db.getSetting('autoBackupDay');
    final cloudS = await widget.db.getSetting('cloudSyncEnabled');
    final pinEn = await widget.db.getSetting('pinSecurityEnabled');

    if (!mounted) return;

    setState(() {
      streakTarget = int.tryParse(target ?? '') ?? 80;
      carryForward = carry == '1';
      appTitle = (savedTitle == null || savedTitle.trim().isEmpty) ? widget.appTitle : savedTitle.trim();
      routineStartMinutes = int.tryParse(savedStart ?? '') ?? 360;
      routineEndMinutes = int.tryParse(savedEnd ?? '') ?? 720;
      notificationLeadTime = int.tryParse(savedLead ?? '5') ?? 5;
      refreshRateMode = savedRefresh ?? '120';
      freezeTokens = int.tryParse(tokens ?? '2') ?? 2;
      subtasksEnabled = sub != '0';
      autoBackupEnabled = autoB != '0';
      autoBackupFolder = autoBF ?? '';
      autoBackupDay = autoBD ?? 'Sunday';
      cloudSyncEnabled = cloudS == '1';
      pinEnabled = pinEn == '1';
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
        title: const Text('Google Drive Backup'),
        content: const Text('Do you want to backup your data to Google Drive now? (Saved securely in a hidden app folder)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'backup_now'),
            child: const Text('Backup Now (Drive)'),
          ),
        ],
      ),
    );

    if (action == 'backup_now') {
      await _performGoogleDriveBackup();
    }
  }

  Future<void> _performGoogleDriveBackup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.violet)),
    );

    try {
      final json = await widget.db.exportJson();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'Taskify_Backup_$dateStr.json';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(json);

      final success = await _driveService.uploadBackup(tempFile, fileName);

      if (mounted) Navigator.pop(context);

      if (success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Backup successfully saved to Google Drive!')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Backup failed or cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
      final selectedFile = await showDialog<File>(
        context: context,
        builder: (_) => const NativeStorageExplorerDialog(
          isFolderPicker: false,
          fileExtensions: ['.json'],
        ),
      );

      if (selectedFile != null) {
        final content = await selectedFile.readAsString();
        await widget.db.importJson(content);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully!')),
        );
        widget.onChanged();
      }
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

      final buffer = StringBuffer();
      buffer.writeln('========================================');
      buffer.writeln('     TASKIFY MONTHLY PERFORMANCE       ');
      buffer.writeln('========================================');
      buffer.writeln('Month: ${DateFormat('MMMM yyyy').format(now)}');
      buffer.writeln('Total Tasks: $total');
      buffer.writeln('Completed Tasks: $done');
      buffer.writeln('Monthly Score: $pct%');
      buffer.writeln('----------------------------------------\n');

      for (final t in list) {
        buffer.writeln('${t['date']} | ${t['title']} | ${t['category']} | Status: ${t['status']}');
      }

      final chosenFolder = await showDialog<Directory>(
        context: context,
        builder: (_) => const NativeStorageExplorerDialog(isFolderPicker: true),
      );

      if (chosenFolder == null) return;

      final file = File('${chosenFolder.path}/Taskify_Monthly_Report_${now.month}_${now.year}.txt');
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved to:\n${file.path}'), duration: const Duration(seconds: 4)),
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
          decoration: const InputDecoration(labelText: 'Display name', hintText: 'Taskify'),
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const SectionLabel('Productivity & Notifications'),
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
          const SectionLabel('Power Tools & Offline Suite'),
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
            title: 'Google Drive Backup',
            subtitle: 'Securely save backup in hidden Google Drive folder.',
            onTap: handleGoogleDriveOptions,
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
          const SectionLabel('App controls'),
          _settingsTile(
            icon: Icons.title_rounded,
            color: AppColors.violet,
            title: 'App display name',
            subtitle: appTitle,
            onTap: editAppTitle,
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
          const SectionLabel('Customization'),
          _settingsTile(
            icon: Icons.palette_rounded,
            color: AppColors.cyan,
            title: 'Appearance',
            subtitle: 'Dark or Light theme.',
            onTap: chooseTheme,
          ),
          const SectionLabel('Backup & data'),
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
          _settingsTile(
            icon: Icons.delete_forever_rounded,
            color: AppColors.rose,
            title: 'Delete All Data',
            subtitle: 'Double confirmation required.',
            onTap: deleteAll,
          ),
        ],
      ),
    );
  }
}
