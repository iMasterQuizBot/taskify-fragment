import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'focus_timer_dialog.dart';
import 'helpers.dart';
import 'task_dialog.dart';

class FocusTimerDialog extends StatefulWidget {
  final String taskTitle;
  final int initialStartMinutes;
  final int? initialEndMinutes;

  const FocusTimerDialog({
    super.key,
    required this.taskTitle,
    required this.initialStartMinutes,
    this.initialEndMinutes,
  });

  @override
  State<FocusTimerDialog> createState() => _FocusTimerDialogState();
}

class _FocusTimerDialogState extends State<FocusTimerDialog> {
  bool isClockMode = false;
  int secondsRemaining = 25 * 60;
  bool isRunning = false;
  File? customAudioFile;
  final AudioPlayer audioPlayer = AudioPlayer();

  late TimeOfDay clockStart;
  late TimeOfDay clockEnd;

  @override
  void initState() {
    super.initState();
    clockStart = minutesToTime(widget.initialStartMinutes);
    if (widget.initialEndMinutes != null) {
      clockEnd = minutesToTime(widget.initialEndMinutes!);
      final diff = (widget.initialEndMinutes! - widget.initialStartMinutes) * 60;
      if (diff > 0) secondsRemaining = diff;
    } else {
      clockEnd = minutesToTime(widget.initialStartMinutes + 25);
    }
  }

  @override
  void dispose() {
    audioPlayer.stop();
    audioPlayer.dispose();
    super.dispose();
  }

  void recalculateFromClock() {
    final s = clockStart.hour * 60 + clockStart.minute;
    final e = clockEnd.hour * 60 + clockEnd.minute;
    if (e > s) {
      setState(() {
        secondsRemaining = (e - s) * 60;
      });
    }
  }

  void toggleTimer() async {
    setState(() => isRunning = !isRunning);
    if (isRunning) {
      if (customAudioFile != null && await customAudioFile!.exists()) {
        await audioPlayer.setReleaseMode(ReleaseMode.loop);
        await audioPlayer.play(DeviceFileSource(customAudioFile!.path));
      }
      _run();
    } else {
      await audioPlayer.pause();
    }
  }

  void _run() async {
    while (isRunning && secondsRemaining > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !isRunning) break;
      setState(() => secondsRemaining--);
    }
    if (secondsRemaining == 0 && mounted) {
      await audioPlayer.stop();
      HapticFeedback.vibrate();
      setState(() => isRunning = false);
    }
  }

  Future<void> chooseCustomAudio() async {
    final pickedFile = await showDialog<File>(
      context: context,
      builder: (_) => const NativeStorageExplorerDialog(
        isFolderPicker: false,
        fileExtensions: ['.mp3', '.wav', '.m4a', '.aac', '.ogg'],
      ),
    );
    if (pickedFile != null) {
      setState(() {
        customAudioFile = pickedFile;
      });
    }
  }

  Future<void> editDurationDirectly() async {
    final mCtrl = TextEditingController(text: '${secondsRemaining ~/ 60}');
    final sCtrl = TextEditingController(text: '${secondsRemaining % 60}');

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Duration (Min : Sec)'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: mCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: sCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seconds'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );

    if (res == true) {
      final m = int.tryParse(mCtrl.text.trim()) ?? 0;
      final s = int.tryParse(sCtrl.text.trim()) ?? 0;
      setState(() {
        secondsRemaining = (m * 60) + s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mins = (secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (secondsRemaining % 60).toString().padLeft(2, '0');

    if (isRunning) {
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(
          widget.taskTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
              ),
              child: Text(
                '$mins:$secs',
                style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: AppColors.cyan, letterSpacing: -2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: toggleTimer,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => isRunning = false);
                    Navigator.pop(context);
                  },
                  child: const Text('Stop & Exit'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Expanded(child: Text('Focus: ${widget.taskTitle}', maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: Icon(isClockMode ? Icons.timer_outlined : Icons.schedule_rounded, color: AppColors.cyan, size: 20),
            tooltip: isClockMode ? 'Switch to Timer Mode' : 'Switch to Clock Mode',
            onPressed: () => setState(() => isClockMode = !isClockMode),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: dynamicSize(context),
          children: [
            GestureDetector(
              onTap: editDurationDirectly,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '$mins:$secs',
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.cyan),
                    ),
                    const Text('Tap to set exact minutes', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (isClockMode) ...[
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.play_circle_outline_rounded, color: AppColors.emerald),
                      title: const Text('From Clock', style: TextStyle(fontSize: 11)),
                      subtitle: Text(clockStart.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onTap: () async {
                        final p = await showTimePicker(
                          context: context,
                          initialTime: clockStart,
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                            child: child!,
                          ),
                        );
                        if (p != null) {
                          setState(() => clockStart = p);
                          recalculateFromClock();
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.stop_circle_outlined, color: AppColors.rose),
                      title: const Text('To Clock', style: TextStyle(fontSize: 11)),
                      subtitle: Text(clockEnd.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onTap: () async {
                        final p = await showTimePicker(
                          context: context,
                          initialTime: clockEnd,
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                            child: child!,
                          ),
                        );
                        if (p != null) {
                          setState(() => clockEnd = p);
                          recalculateFromClock();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const Divider(),
            ],
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.audiotrack_rounded, color: AppColors.blue, size: 20),
              title: Text(customAudioFile != null ? p.basename(customAudioFile!.path) : 'Choose Sound from Device', style: const TextStyle(fontSize: 12)),
              subtitle: const Text('Select .mp3 / .wav file for focus session', style: TextStyle(fontSize: 10)),
              onTap: chooseCustomAudio,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: toggleTimer,
          child: const Text('Start Focus'),
        ),
      ],
    );
  }

  MainAxisSize dynamicSize(BuildContext context) => MainAxisSize.min;
}
