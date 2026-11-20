import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'helpers.dart';

class TaskDialog extends StatefulWidget {
  final AppDatabase db;
  final DateTime date;
  final Map<String, dynamic>? task;

  const TaskDialog({super.key, required this.db, required this.date, this.task});

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final notesController = TextEditingController();
  final subtaskInputController = TextEditingController();
  final attachmentController = TextEditingController();

  TimeOfDay startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay? endTime;

  String category = 'Study';
  int priority = 1;
  bool reminder = true;
  String repeatType = 'once';
  List<Map<String, dynamic>> categories = [];

  final List<String> daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final Set<String> selectedCustomDays = {};

  DateTime pickerMonth = DateTime.now();
  final Set<String> selectedCustomDateKeys = {};
  List<Map<String, dynamic>> subtasks = [];

  bool applyToAllFuture = false;

  @override
  void initState() {
    super.initState();
    pickerMonth = DateTime(widget.date.year, widget.date.month, 1);
    load();

    final task = widget.task;
    if (task != null) {
      titleController.text = task['title'] ?? '';
      descriptionController.text = task['description'] ?? '';
      notesController.text = task['notes'] ?? '';
      attachmentController.text = task['attachmentPath'] ?? '';
      startTime = minutesToTime(task['startMinutes']);

      if (task['endMinutes'] != null) {
        endTime = minutesToTime(task['endMinutes']);
      }

      category = task['category'] ?? 'Study';
      priority = task['priority'] ?? 1;
      reminder = task['reminder'] == 1;
      repeatType = task['repeatType'] ?? 'once';

      final repeatDaysStr = task['repeatDays'] ?? '';
      if (repeatDaysStr.isNotEmpty) {
        selectedCustomDays.addAll(repeatDaysStr.split(','));
      }

      if (task['subtasks'] != null && task['subtasks'].toString().isNotEmpty) {
        try {
          final decoded = jsonDecode(task['subtasks'].toString());
          if (decoded is List) {
            subtasks = List<Map<String, dynamic>>.from(decoded);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> load() async {
    final result = await widget.db.categories();
    if (widget.task == null) {
      final savedStart = await widget.db.getSetting('startMinutes');
      final parsedStart = int.tryParse(savedStart ?? '');
      if (parsedStart != null && mounted) {
        setState(() => startTime = minutesToTime(parsedStart.clamp(0, 1439)));
      }
    }

    if (mounted) {
      setState(() {
        categories = result;
        if (!categories.any((c) => c['name'] == category)) {
          category = categories.isNotEmpty ? categories.first['name'].toString() : 'Study';
        }
      });
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    notesController.dispose();
    subtaskInputController.dispose();
    attachmentController.dispose();
    super.dispose();
  }

  int get startMinutes => startTime.hour * 60 + startTime.minute;

  int? get endMinutes {
    if (endTime == null) return null;
    return endTime!.hour * 60 + endTime!.minute;
  }

  Future<void> chooseStart() async {
    final value = await showTimePicker(
      context: context,
      initialTime: startTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (value != null) setState(() => startTime = value);
  }

  Future<void> chooseEnd() async {
    final value = await showTimePicker(
      context: context,
      initialTime: endTime ?? startTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (value != null) setState(() => endTime = value);
  }

  void addSubtask() {
    final text = subtaskInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      subtasks.add({'title': text, 'done': false});
      subtaskInputController.clear();
    });
  }

  Future<void> createCustomCategory() async {
    final cNameCtrl = TextEditingController();
    String pickedColor = '#2563EB';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('New Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: cNameCtrl, decoration: const InputDecoration(labelText: 'Category Name')),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['#2563EB', '#22D3EE', '#34D399', '#FBBF24', '#FB7185', '#8B5CF6'].map((col) {
                  return GestureDetector(
                    onTap: () => setDlg(() => pickedColor = col),
                    child: CircleAvatar(
                      backgroundColor: Color(int.parse(col.replaceAll('#', '0xFF'))),
                      radius: pickedColor == col ? 16 : 12,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (created == true && cNameCtrl.text.trim().isNotEmpty) {
      await widget.db.addCategory(cNameCtrl.text.trim(), colorHex: pickedColor);
      await load();
      setState(() => category = cNameCtrl.text.trim());
    }
  }

  Future<void> save() async {
    final title = titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a task name.')));
      return;
    }

    if (endMinutes != null && endMinutes! <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
      return;
    }

    if (repeatType == 'custom_days' && selectedCustomDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one day for Custom Days.')));
      return;
    }

    if (repeatType == 'custom_dates' && selectedCustomDateKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one date from the calendar.')));
      return;
    }

    final desc = descriptionController.text.trim();
    final note = notesController.text.trim();
    final subtasksJson = jsonEncode(subtasks);
    final attach = attachmentController.text.trim();
    final repeatDaysString = selectedCustomDays.join(',');

    if (widget.task != null) {
      if (applyToAllFuture) {
        await widget.db.updateFutureTasks(
          widget.task!['title'].toString(),
          widget.date,
          newTitle: title,
          description: desc,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          category: category,
          priority: priority,
          repeatType: repeatType,
          repeatDays: repeatDaysString,
          notes: note,
          subtasks: subtasksJson,
          reminder: reminder,
        );
      } else {
        await widget.db.updateTask(
          widget.task!['id'],
          title: title,
          description: desc,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          category: category,
          priority: priority,
          notes: note,
          reminder: reminder,
          subtasks: subtasksJson,
          attachmentPath: attach,
        );
      }
    } else {
      if (repeatType == 'once') {
        await widget.db.addTask(
          date: widget.date,
          title: title,
          description: desc,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          category: category,
          priority: priority,
          repeatType: repeatType,
          notes: note,
          reminder: reminder,
          subtasks: subtasksJson,
          attachmentPath: attach,
        );
      } else if (repeatType == 'alternate') {
        for (int i = 0; i < 60; i += 2) {
          final target = widget.date.add(Duration(days: i));
          await widget.db.addTask(
            date: target,
            title: title,
            description: desc,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            category: category,
            priority: priority,
            repeatType: repeatType,
            notes: note,
            reminder: reminder,
            subtasks: subtasksJson,
            attachmentPath: attach,
          );
        }
      } else if (repeatType == 'daily') {
        for (int i = 0; i < 60; i++) {
          final target = widget.date.add(Duration(days: i));
          await widget.db.addTask(
            date: target,
            title: title,
            description: desc,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            category: category,
            priority: priority,
            repeatType: repeatType,
            notes: note,
            reminder: reminder,
            subtasks: subtasksJson,
            attachmentPath: attach,
          );
        }
      } else if (repeatType == 'weekdays') {
        for (int i = 0; i < 60; i++) {
          final target = widget.date.add(Duration(days: i));
          if (target.weekday >= 1 && target.weekday <= 5) {
            await widget.db.addTask(
              date: target,
              title: title,
              description: desc,
              startMinutes: startMinutes,
              endMinutes: endMinutes,
              category: category,
              priority: priority,
              repeatType: repeatType,
              notes: note,
              reminder: reminder,
              subtasks: subtasksJson,
              attachmentPath: attach,
            );
          }
        }
      } else if (repeatType == 'weekends') {
        for (int i = 0; i < 60; i++) {
          final target = widget.date.add(Duration(days: i));
          if (target.weekday == 6 || target.weekday == 7) {
            await widget.db.addTask(
              date: target,
              title: title,
              description: desc,
              startMinutes: startMinutes,
              endMinutes: endMinutes,
              category: category,
              priority: priority,
              repeatType: repeatType,
              notes: note,
              reminder: reminder,
              subtasks: subtasksJson,
              attachmentPath: attach,
            );
          }
        }
      } else if (repeatType == 'custom_days') {
        final weekdayMap = {'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6, 'Sun': 7};
        final targetWeekdays = selectedCustomDays.map((d) => weekdayMap[d]).whereType<int>().toSet();

        for (int i = 0; i < 60; i++) {
          final target = widget.date.add(Duration(days: i));
          if (targetWeekdays.contains(target.weekday)) {
            await widget.db.addTask(
              date: target,
              title: title,
              description: desc,
              startMinutes: startMinutes,
              endMinutes: endMinutes,
              category: category,
              priority: priority,
              repeatType: repeatType,
              repeatDays: repeatDaysString,
              notes: note,
              reminder: reminder,
              subtasks: subtasksJson,
              attachmentPath: attach,
            );
          }
        }
      } else if (repeatType == 'custom_dates') {
        final sortedKeys = selectedCustomDateKeys.toList()..sort();
        for (final key in sortedKeys) {
          final parts = key.split('-').map(int.parse).toList();
          final target = DateTime(parts[0], parts[1], parts[2]);
          await widget.db.addTask(
            date: target,
            title: title,
            description: desc,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            category: category,
            priority: priority,
            repeatType: repeatType,
            notes: note,
            reminder: reminder,
            subtasks: subtasksJson,
            attachmentPath: attach,
          );
        }
      }
      await widget.db.autoAllocateRollingHabits();
    }

    if (mounted) Navigator.pop(context, true);
  }

  Widget _timeBox({required String title, required String value, required IconData icon, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.violet.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 17, color: AppColors.violet),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineMultiDatePicker() {
    final firstDay = DateTime(pickerMonth.year, pickerMonth.month, 1);
    final daysInMonth = DateTime(pickerMonth.year, pickerMonth.month + 1, 0).day;
    final leadingSpaces = firstDay.weekday % 7;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  setState(() {
                    pickerMonth = DateTime(pickerMonth.year, pickerMonth.month - 1, 1);
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(pickerMonth),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  setState(() {
                    pickerMonth = DateTime(pickerMonth.year, pickerMonth.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: const [
              _DayHeader('S'),
              _DayHeader('M'),
              _DayHeader('T'),
              _DayHeader('W'),
              _DayHeader('T'),
              _DayHeader('F'),
              _DayHeader('S'),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingSpaces + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (_, index) {
              if (index < leadingSpaces) return const SizedBox();

              final day = index - leadingSpaces + 1;
              final dateKey = '${pickerMonth.year}-${pickerMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isSelected = selectedCustomDateKeys.contains(dateKey);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      selectedCustomDateKeys.remove(dateKey);
                    } else {
                      selectedCustomDateKeys.add(dateKey);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.cyan : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.cyan : Colors.white.withOpacity(0.06),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '${selectedCustomDateKeys.length} dates selected (tap to toggle)',
            style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.all(Radius.circular(12))),
            child: Icon(editing ? Icons.edit_rounded : Icons.add_task_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Text(editing ? 'Edit Task' : 'Create Task', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.4)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Task name *', prefixIcon: Icon(Icons.task_alt_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes_rounded)),
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  _timeBox(title: 'START', value: formatMinutes(startTime.hour * 60 + startTime.minute), icon: Icons.schedule_rounded, onTap: chooseStart),
                  const SizedBox(width: 8),
                  _timeBox(title: 'END', value: endTime == null ? 'Optional' : formatMinutes(endTime!.hour * 60 + endTime!.minute), icon: Icons.schedule_outlined, onTap: chooseEnd),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: categories.any((c) => c['name'] == category) ? category : null,
                      dropdownColor: AppColors.surfaceElevated,
                      decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_rounded)),
                      items: categories.map((e) => DropdownMenuItem(value: e['name'].toString(), child: Text(e['name'].toString()))).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => category = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: createCustomCategory,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'New Category',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: priority,
                dropdownColor: AppColors.surfaceElevated,
                decoration: const InputDecoration(labelText: 'Priority', prefixIcon: Icon(Icons.flag_rounded)),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Low')),
                  DropdownMenuItem(value: 2, child: Text('Normal')),
                  DropdownMenuItem(value: 3, child: Text('High')),
                  DropdownMenuItem(value: 4, child: Text('Critical')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => priority = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: repeatType,
                dropdownColor: AppColors.surfaceElevated,
                decoration: const InputDecoration(labelText: 'Repeat Mode', prefixIcon: Icon(Icons.repeat_rounded)),
                items: const [
                  DropdownMenuItem(value: 'once', child: Text('One time')),
                  DropdownMenuItem(value: 'daily', child: Text('Every day (Rolling Infinite)')),
                  DropdownMenuItem(value: 'alternate', child: Text('Alternate Day (एक दिन छोड़ कर)')),
                  DropdownMenuItem(value: 'weekdays', child: Text('Monday-Friday (Weekdays)')),
                  DropdownMenuItem(value: 'weekends', child: Text('Weekends (Sat-Sun)')),
                  DropdownMenuItem(value: 'custom_days', child: Text('Custom Day (हफ़्ते के दिन)')),
                  DropdownMenuItem(value: 'custom_dates', child: Text('Custom Date (कैलेंडर तारीखें)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => repeatType = val);
                },
              ),
              if (repeatType == 'custom_days') ...[
                const SizedBox(height: 10),
                const Text('Select Days of Week:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: daysOfWeek.map((day) {
                    final selected = selectedCustomDays.contains(day);
                    return FilterChip(
                      label: Text(day),
                      selected: selected,
                      selectedColor: AppColors.violet.withOpacity(0.35),
                      checkmarkColor: AppColors.violet,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            selectedCustomDays.add(day);
                          } else {
                            selectedCustomDays.remove(day);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              if (repeatType == 'custom_dates') ...[
                _buildInlineMultiDatePicker(),
              ],
              const SizedBox(height: 10),
              const Text('Checklist / Subtasks (Optional):', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: subtaskInputController,
                      decoration: const InputDecoration(hintText: 'e.g. PYQ Solve / Notes'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: addSubtask,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              if (subtasks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: subtasks.map((st) {
                    return Chip(
                      label: Text(st['title'].toString(), style: const TextStyle(fontSize: 11)),
                      onDeleted: () {
                        setState(() => subtasks.remove(st));
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Formula Notes / Link', prefixIcon: Icon(Icons.edit_note_rounded)),
              ),
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.035),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: const Text('Advance Notification', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: const Text('Alert before start time', style: TextStyle(fontSize: 10.5)),
                  value: reminder,
                  onChanged: (val) => setState(() => reminder = val),
                ),
              ),
              if (editing) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: applyToAllFuture,
                  title: const Text('Apply edits to all future recurring tasks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: const Text('Updates name, time, category, notes, and subtasks across upcoming calendar.', style: TextStyle(fontSize: 10.5)),
                  onChanged: (v) => setState(() => applyToAllFuture = v == true),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        Container(
          decoration: const BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.all(Radius.circular(12))),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            onPressed: save,
            icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
            label: const Text('Save Task', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String text;
  const _DayHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
