import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'focus_timer_dialog.dart';
import 'helpers.dart';
import 'task_dialog.dart';

class TodayPage extends StatefulWidget {
  final AppDatabase db;
  final String appTitle;
  final DateTime date;
  final VoidCallback onChanged;
  final void Function(Offset position) onCelebrate;
  final VoidCallback onResetToToday;

  const TodayPage({
    super.key,
    required this.db,
    required this.appTitle,
    required this.date,
    required this.onChanged,
    required this.onCelebrate,
    required this.onResetToToday,
  });

  @override
  State<TodayPage> createState() => TodayPageState();
}

class TodayPageState extends State<TodayPage> {
  List> tasks = [];
  bool loading = true;
  bool subtasksEnabled = true;
  int currentStreak = 0;

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
    if (mounted) {
      setState(() {
        tasks = list.map((e) => Map<String, dynamic>.from(e)).toList();
        subtasksEnabled = subOpt != '0';
        currentStreak = streak;
        loading = false;
      });
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
                  margin: const EdgeInsets.only(right: 16),
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

    return GlassCard(
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
}
