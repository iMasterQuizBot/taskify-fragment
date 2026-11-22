import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'focus_timer_dialog.dart';
import 'helpers.dart';
import 'task_dialog.dart';
import 'live_voice_screen.dart';
import 'widgets/ai_orb_icon.dart';

class TodayPage extends StatefulWidget {
  final AppDatabase db;
  final String appTitle;
  final DateTime date;
  final VoidCallback onChanged;
  final void Function(Offset position) onCelebrate;
  final VoidCallback onResetToToday;
  final VoidCallback onOpenSettings;

  const TodayPage({
    super.key,
    required this.db,
    required this.appTitle,
    required this.date,
    required this.onChanged,
    required this.onCelebrate,
    required this.onResetToToday,
    required this.onOpenSettings,
  });

  @override
  State<TodayPage> createState() => TodayPageState();
}

class TodayPageState extends State<TodayPage> {
  List<Map<String, dynamic>> tasks = [];
  bool loading = true;
  bool subtasksEnabled = true;
  int currentStreak = 0;
  String todayMood = '';
  static const MethodChannel _widgetChannel = MethodChannel('taskify/widget');

  bool isSelectionMode = false;
  final Set<int> selectedTaskIds = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      isSelectionMode = false;
      selectedTaskIds.clear();
      load();
    }
  }

  Future<void> load() async {
    final list = await widget.db.getTasks(widget.date);
    final subOpt = await widget.db.getSetting('featureSubtasksEnabled');
    final streak = await widget.db.calculateCurrentStreak();
    final moodRow = await widget.db.getMoodLog(DateTime.now());
    if (mounted) {
      setState(() {
        tasks = list.map((e) => Map<String, dynamic>.from(e)).toList();
        subtasksEnabled = subOpt != '0';
        currentStreak = streak;
        todayMood = moodRow?['mood']?.toString() ?? '';
        loading = false;
      });
    }
    if (DateUtils.isSameDay(widget.date, DateTime.now())) {
      _syncHomeWidget(list, streak);
    }
  }

  int get completed => tasks.where((e) => e['status'] == 'completed').length;
  int get active => tasks.where((e) => e['status'] != 'skipped').length;
  int get pending => tasks.where((e) => e['status'] == 'pending').length;
  double get progress => active == 0 ? 0 : completed / active;

  String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> addTask() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(db: widget.db, date: widget.date),
    );
    if (result == true) widget.onChanged();
  }

  Future<void> editTask(Map<String, dynamic> task) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(db: widget.db, date: widget.date, task: task),
    );
    if (result == true) widget.onChanged();
  }

  Future<void> changeTaskStatus(int taskId, String nextStatus, {Offset? tapPosition}) async {
    if (nextStatus == 'completed') {
      HapticFeedback.mediumImpact();
      if (tapPosition != null) {
        widget.onCelebrate(tapPosition);
      }
    }

    setState(() {
      final index = tasks.indexWhere((t) => t['id'] == taskId);
      if (index != -1) {
        tasks[index]['status'] = nextStatus;
      }
    });

    await widget.db.updateStatus(taskId, nextStatus);
    widget.onChanged();
  }

  void openFocusTimer(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (_) => FocusTimerDialog(
        taskTitle: task['title'].toString(),
        initialStartMinutes: task['startMinutes'] as int,
        initialEndMinutes: task['endMinutes'] as int?,
      ),
    );
  }

  Future<void> showBulkDeleteOptions() async {
    if (selectedTaskIds.isEmpty) return;

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${selectedTaskIds.length} Selected Tasks?'),
        content: const Text('Choose deletion scope for these selected routine items:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'only_today'),
            child: const Text('Only Today'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all_future'),
            child: const Text('Include Future Too'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (action == 'only_today') {
      for (final id in selectedTaskIds) {
        await widget.db.deleteTask(id);
      }
    } else if (action == 'all_future') {
      final selectedTasks = tasks.where((t) => selectedTaskIds.contains(t['id'])).toList();
      for (final t in selectedTasks) {
        await widget.db.deleteFutureTasksByTitle(t['title'].toString(), widget.date);
      }
    }

    setState(() {
      isSelectionMode = false;
      selectedTaskIds.clear();
    });
    widget.onChanged();
  }

  Future<void> showTaskDeleteOptions(Map<String, dynamic> task) async {
    final title = task['title'].toString();
    final id = task['id'] as int;

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text('Choose how you want to remove this task:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'only_today'),
            child: const Text('Only This Day'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'all_future'),
            child: const Text('All Future Tasks'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (action == 'only_today') {
      await widget.db.deleteTask(id);
      widget.onChanged();
    } else if (action == 'all_future') {
      final confirmAll = await confirm(
        context,
        'Delete All Future Tasks?',
        'This will permanently delete "$title" from today and all future dates.',
      );
      if (confirmAll) {
        await widget.db.deleteFutureTasksByTitle(title, widget.date);
        widget.onChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(widget.date, DateTime.now());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: isSelectionMode
            ? Text('${selectedTaskIds.length} Selected', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    widget.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                  ),
                ],
              ),
        actions: isSelectionMode
            ? [
                IconButton(
                  tooltip: 'Select All',
                  icon: const Icon(Icons.select_all_rounded, color: AppColors.cyan),
                  onPressed: () {
                    setState(() {
                      if (selectedTaskIds.length == tasks.length) {
                        selectedTaskIds.clear();
                      } else {
                        selectedTaskIds.addAll(tasks.map((t) => t['id'] as int));
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Delete Selected',
                  icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.rose),
                  onPressed: showBulkDeleteOptions,
                ),
                IconButton(
                  tooltip: 'Cancel Selection',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    setState(() {
                      isSelectionMode = false;
                      selectedTaskIds.clear();
                    });
                  },
                ),
              ]
            : [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.violet.withOpacity(0.32), blurRadius: 16)],
                  ),
                  child: IconButton(
                    tooltip: 'Add Task',
                    onPressed: addTask,
                    icon: const Icon(Icons.add_rounded, size: 21, color: Colors.white),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: IconButton(
                    tooltip: 'Search Tasks',
                    onPressed: _openGlobalSearch,
                    icon: const Icon(Icons.search_rounded, size: 20, color: AppColors.cyan),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: IconButton(
                    tooltip: 'Refresh All',
                    onPressed: widget.onChanged,
                    icon: const Icon(Icons.refresh_rounded, size: 20, color: Colors.white70),
                  ),
                ),
                GlobalSettingsButton(onTap: widget.onOpenSettings),
              ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.violet))
          : RefreshIndicator(
              color: AppColors.violet,
              backgroundColor: AppColors.surface,
              onRefresh: () async => widget.onChanged(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  _dateHeader(isToday),
                  _progressCard(isToday),
                  _moodAndBriefingBar(isToday),
                  _autoRescheduleBanner(isToday),
                  _currentTask(),
                  SectionLabel(
                    'Today’s timeline',
                    subtitle: isSelectionMode ? 'Tap items to select / unselect' : (tasks.isEmpty ? null : '${tasks.length} tasks • Hold to multi-select'),
                  ),
                  if (tasks.isEmpty) _emptyState() else ...tasks.map(_taskCard),
                ],
              ),
            ),
    );
  }

  Widget _dateHeader(bool isToday) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat('EEEE, d MMMM').format(widget.date),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          if (!isToday)
            const GlowBadge(text: 'History', color: AppColors.amber, icon: Icons.history_rounded),
        ],
      ),
    );
  }

  Widget _progressCard(bool isToday) {
    final percentage = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x337C3AED), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                              child: const Text('TODAY’S PROGRESS', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withOpacity(0.24),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🔥 ', style: TextStyle(fontSize: 11)),
                                  Text(
                                    '$currentStreak Day${currentStreak == 1 ? '' : 's'} Streak',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text('$completed of $active completed', style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          pending == 0 && active > 0
                              ? '🏆 Unstoppable! Daily mission completed.'
                              : '$pending task${pending == 1 ? '' : 's'} in motion. Keep pushing!',
                          style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 95,
                    height: 95,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 7.5,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.white.withOpacity(0.18),
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$percentage%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 23, height: 1, letterSpacing: -1.0)),
                            const SizedBox(height: 3),
                            Text('complete', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 9.0, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: addTask,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.24)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 18, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Add Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: InkWell(
                      onTap: widget.onResetToToday,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.5)),
                        ),
                        child: const Center(
                          child: Icon(Icons.today_rounded, size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveVoiceScreen(db: widget.db, onChanged: widget.onChanged),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.45)),
                        ),
                        child: const Center(
                          child: AiOrbIcon(size: 18, state: AiOrbState.idle),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _currentTask() {
    if (tasks.isEmpty || isSelectionMode) return const SizedBox();

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    Map<String, dynamic>? current;
    Map<String, dynamic>? next;

    for (final task in tasks) {
      if (task['status'] == 'completed' || task['status'] == 'skipped') continue;

      final start = task['startMinutes'] as int;
      final end = task['endMinutes'] as int?;

      if (start <= currentMinutes && (end == null || currentMinutes <= end)) {
        current = task;
        break;
      }
      if (start > currentMinutes) {
        next = task;
        break;
      }
    }

    if (current == null && next == null) return const SizedBox();

    final task = current ?? next!;
    final isCurrent = current != null;
    final accent = categoryColor(task['category'].toString());

    return GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: accent.withOpacity(0.14), borderRadius: BorderRadius.circular(11)),
            child: Icon(isCurrent ? Icons.play_arrow_rounded : Icons.skip_next_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCurrent ? 'NOW' : 'NEXT', style: TextStyle(color: accent, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(task['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatMinutes(task['startMinutes']), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.violet.withOpacity(0.24), AppColors.cyan.withOpacity(0.12)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 28, color: AppColors.violet),
          ),
          const SizedBox(height: 14),
          const Text('Your day is wide open', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 5),
          const Text('Add your first task and start shaping a focused routine.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _reminderToggle(Map<String, dynamic> task) {
    final on = task['reminder'] == 1 || task['reminder'] == true;
    return Tooltip(
      message: on ? 'Notification बंद करें' : 'Notification चालू करें',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () async {
          final newOn = !on;
          await widget.db.setTaskReminder(task['id'] as int, newOn);
          if (!mounted) return;
          setState(() => task['reminder'] = newOn ? 1 : 0);
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
            size: 15,
            color: on ? AppColors.amber : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final id = task['id'] as int;
    final status = task['status'] as String;
    final isDone = status == 'completed';
    final overdue = !isDone && isOverdue(task, widget.date);
    final category = task['category'].toString();
    final accent = categoryColor(category);
    final isSelected = selectedTaskIds.contains(id);

    List<dynamic> subtaskList = [];
    if (task['subtasks'] != null && task['subtasks'].toString().isNotEmpty) {
      try {
        subtaskList = jsonDecode(task['subtasks'].toString());
      } catch (_) {}
    }

    final cardWidget = GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
      color: isSelected ? AppColors.violet.withOpacity(0.26) : null,
      onTap: () {
        if (isSelectionMode) {
          setState(() {
            if (isSelected) {
              selectedTaskIds.remove(id);
              if (selectedTaskIds.isEmpty) isSelectionMode = false;
            } else {
              selectedTaskIds.add(id);
            }
          });
        } else {
          editTask(task);
        }
      },
      onLongPress: () {
        HapticFeedback.selectionClick();
        setState(() {
          isSelectionMode = true;
          selectedTaskIds.add(id);
        });
      },
      child: AnimatedOpacity(
        opacity: isDone ? 0.65 : 1,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isSelectionMode)
                  Checkbox(
                    value: isSelected,
                    activeColor: AppColors.cyan,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          selectedTaskIds.add(id);
                        } else {
                          selectedTaskIds.remove(id);
                          if (selectedTaskIds.isEmpty) isSelectionMode = false;
                        }
                      });
                    },
                  )
                else
                  _statusButton(task, accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task['title'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: isDone ? AppColors.textMuted : AppColors.textPrimary,
                                decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
                              ),
                            ),
                          ),
                          if ((task['priority'] as int) >= 3)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(color: priorityColor(task['priority']), shape: BoxShape.circle),
                            ),
                          if (!isSelectionMode) ...[
                            const SizedBox(width: 4),
                            _reminderToggle(task),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: overdue ? AppColors.rose : AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            taskTime(task),
                            style: TextStyle(
                              color: overdue ? AppColors.rose : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlowBadge(text: category, color: accent),
                          if (status == 'completed') ...[
                            const SizedBox(width: 6),
                            const GlowBadge(text: 'Completed', color: AppColors.emerald, icon: Icons.check_rounded),
                          ],
                          if (status == 'skipped') ...[
                            const SizedBox(width: 6),
                            const GlowBadge(text: 'Skipped', color: AppColors.amber, icon: Icons.fast_forward_rounded),
                          ],
                          if (status == 'missed') ...[
                            const SizedBox(width: 6),
                            const GlowBadge(text: 'Missed', color: AppColors.rose, icon: Icons.close_rounded),
                          ],
                          if (overdue) ...[
                            const SizedBox(width: 6),
                            const GlowBadge(text: 'Overdue', color: AppColors.rose, icon: Icons.notification_important_rounded),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isSelectionMode) ...[
                  if (!isDone)
                    IconButton(
                      icon: const Icon(Icons.timer_outlined, size: 18, color: AppColors.cyan),
                      tooltip: 'Focus Timer',
                      onPressed: () => openFocusTimer(task),
                    ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textMuted),
                    onSelected: (value) async {
                      switch (value) {
                        case 'complete':
                          changeTaskStatus(id, 'completed');
                          break;
                        case 'pending':
                          changeTaskStatus(id, 'pending');
                          break;
                        case 'skip':
                          changeTaskStatus(id, 'skipped');
                          break;
                        case 'missed':
                          changeTaskStatus(id, 'missed');
                          break;
                        case 'edit':
                          await editTask(task);
                          break;
                        case 'delete':
                          await showTaskDeleteOptions(task);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'complete', child: Text('Mark Complete')),
                      PopupMenuItem(value: 'pending', child: Text('Mark Pending')),
                      PopupMenuItem(value: 'skip', child: Text('Skip')),
                      PopupMenuItem(value: 'missed', child: Text('Mark Missed')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ],
            ),
            if (subtasksEnabled && subtaskList.isNotEmpty) ...[
              const SizedBox(height: 6),
              Column(
                children: List.generate(subtaskList.length, (sIdx) {
                  final s = subtaskList[sIdx];
                  final sDone = s['done'] == true;
                  return GestureDetector(
                    onTap: () async {
                      subtaskList[sIdx]['done'] = !sDone;
                      await widget.db.updateSubtasks(task['id'], jsonEncode(subtaskList));
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                      child: Row(
                        children: [
                          Icon(sDone ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 14, color: sDone ? AppColors.emerald : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s['title'].toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: sDone ? AppColors.textMuted : AppColors.textSecondary,
                                decoration: sDone ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );

    if (isSelectionMode) return cardWidget;

    return Dismissible(
      key: ValueKey('task_$id'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await changeTaskStatus(id, isDone ? 'pending' : 'completed');
        } else {
          await changeTaskStatus(id, 'skipped');
        }
        return false; // लिस्ट से हटाएँ नहीं, स्टेटस अपडेट करके वहीं दिखाएँ
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.emerald.withOpacity(0.32), AppColors.emerald.withOpacity(0.10)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.emerald.withOpacity(0.45)),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 22),
            const SizedBox(width: 8),
            Text(
              isDone ? 'Pending' : 'Complete',
              style: const TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.amber.withOpacity(0.10), AppColors.amber.withOpacity(0.32)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.amber.withOpacity(0.45)),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Skip', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 13)),
            SizedBox(width: 8),
            Icon(Icons.fast_forward_rounded, color: AppColors.amber, size: 22),
          ],
        ),
      ),
      child: cardWidget,
    );
  }

  Widget _statusButton(Map<String, dynamic> task, Color accent) {
    final status = task['status'];
    final isDone = status == 'completed';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (!isDone) {
          changeTaskStatus(task['id'] as int, 'completed', tapPosition: details.globalPosition);
        } else {
          changeTaskStatus(task['id'] as int, 'pending');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          color: isDone ? AppColors.emerald : accent.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(color: isDone ? AppColors.emerald : accent.withOpacity(0.6), width: 1.6),
        ),
        child: Icon(
          Icons.check_rounded,
          size: 15,
          color: isDone ? AppColors.background : accent.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _autoRescheduleBanner(bool isToday) {
    if (!isToday || isSelectionMode) return const SizedBox();
    final overdueCount = tasks.where((t) => isOverdue(t, widget.date)).length;
    if (overdueCount == 0) return const SizedBox();

    return GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      glowColor: AppColors.rose,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.rose.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.rose.withOpacity(0.45)),
            ),
            child: const Icon(Icons.auto_fix_high_rounded, color: AppColors.rose, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Auto-Reschedule $overdueCount Overdue Task${overdueCount == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openRescheduleOptions(overdueCount),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: GlowBadge(text: '1-Tap Fix', color: AppColors.cyan),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRescheduleOptions(int overdueCount) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131824),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Reschedule $overdueCount Overdue Task${overdueCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.next_plan_rounded, color: AppColors.cyan),
                title: const Text('Reschedule to Next Task', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('अगले खाली टाइम स्लॉट में अपने-आप शिफ़्ट करें'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final moved = await widget.db.rescheduleOverdueTasks(widget.date);
                  if (!mounted) return;
                  if (moved > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✨ $moved Overdue टास्क अगले खाली स्लॉट में शिफ़्ट किए गए।')),
                    );
                    widget.onChanged();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded, color: AppColors.violet),
                title: const Text('Reschedule to Time', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('अपनी पसंद का समय चुनकर उस समय पर शिफ़्ट करें'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
                      child: child!,
                    ),
                  );
                  if (picked == null || !mounted) return;
                  final customMins = picked.hour * 60 + picked.minute;
                  final moved = await widget.db.rescheduleOverdueTasks(
                    widget.date,
                    customStartMinutes: customMins,
                  );
                  if (!mounted) return;
                  if (moved > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('🕒 $moved Overdue टास्क ${formatMinutes(customMins)} से शिफ़्ट किए गए।')),
                    );
                    widget.onChanged();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGlobalSearch() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = await widget.db.searchAllTasks('');
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121722),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          maxChildSize: 0.94,
          minChildSize: 0.45,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'टास्क, कैटेगरी या नोट्स सर्च करें…',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.cyan),
                  ),
                  onChanged: (q) async {
                    final rows = await widget.db.searchAllTasks(q);
                    if (ctx.mounted) setSheet(() => results = rows);
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: results.isEmpty
                      ? const Center(child: Text('कोई टास्क नहीं मिला।', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final t = results[i];
                            final accent = categoryColor(t['category'].toString());
                            return GlassCard(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              onTap: () {
                                Navigator.pop(ctx);
                                editTask(t);
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${t['date']} • ${taskTime(t)}',
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GlowBadge(text: t['category'].toString(), color: accent),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    searchCtrl.dispose();
  }

  Future<void> _syncHomeWidget(List<Map<String, dynamic>> dayTasks, int streak) async {
    try {
      final activeList = dayTasks.where((t) => t['status'] != 'skipped').toList();
      final doneCount = activeList.where((t) => t['status'] == 'completed').length;
      final pendingTitles = activeList
          .where((t) => t['status'] == 'pending')
          .take(3)
          .map((t) => '${formatMinutes(t['startMinutes'])} • ${t['title']}')
          .toList();
      await _widgetChannel.invokeMethod('updateWidget', {
        'title': widget.appTitle,
        'done': doneCount,
        'total': activeList.length,
        'streak': streak,
        'tasks': pendingTitles,
      });
    } catch (_) {}
  }

  Widget _moodAndBriefingBar(bool isToday) {
    if (!isToday || isSelectionMode) return const SizedBox();
    const moods = [
      ('🔥', 'Focused', 5),
      ('⚡', 'High', 4),
      ('🙂', 'Good', 3),
      ('😴', 'Tired', 2),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: moods.map((m) {
                  final selected = todayMood == m.$2;
                  return GestureDetector(
                    onTap: () async {
                      await widget.db.setMoodLog(DateTime.now(), m.$2, m.$3);
                      if (mounted) setState(() => todayMood = m.$2);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.cyan.withOpacity(0.22) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: selected ? Border.all(color: AppColors.cyan.withOpacity(0.6)) : null,
                      ),
                      child: Text('${m.$1} ${m.$2}', style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GlassCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            glowColor: AppColors.cyan,
            onTap: _openBriefingSheet,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wb_twilight_rounded, size: 15, color: AppColors.amber),
                SizedBox(width: 5),
                Text('Briefing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBriefingSheet() async {
    final highPri = tasks.where((t) => (t['priority'] as int) >= 3 && t['status'] == 'pending').toList();
    final pendingList = tasks.where((t) => t['status'] == 'pending').toList();
    final isEvening = DateTime.now().hour >= 18;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131824),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isEvening ? '🌙 Night Review Briefing' : '🌅 Morning Briefing',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              '• कुल सक्रिय टास्क: $active\n'
              '• पूरे हुए: $completed (${(progress * 100).round()}%)\n'
              '• बाकी पेंडिंग: ${pendingList.length}\n'
              '• हाई-प्रायोरिटी बाकी: ${highPri.length}\n'
              '• 🔥 करंट स्ट्रीक: $currentStreak दिन',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.55),
            ),
            if (pendingList.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final tomorrow = DateTime.now().add(const Duration(days: 1));
                    for (final t in pendingList) {
                      await widget.db.addTask(
                        date: tomorrow,
                        title: t['title'].toString(),
                        description: t['description']?.toString() ?? '',
                        startMinutes: t['startMinutes'] as int,
                        endMinutes: t['endMinutes'] as int?,
                        category: t['category'].toString(),
                        priority: t['priority'] as int,
                        notes: t['notes']?.toString() ?? '',
                        reminder: (t['reminder'] as int) == 1,
                        subtasks: t['subtasks']?.toString() ?? '',
                        playSound: false,
                      );
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${pendingList.length} पेंडिंग टास्क कल पर शिफ़्ट किए गए।')),
                    );
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.move_down_rounded, size: 18),
                  label: const Text('बाकी टास्क कल पर शिफ़्ट करें'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
