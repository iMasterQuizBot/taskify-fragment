import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'helpers.dart';
import 'task_dialog.dart';

class RoutinesPage extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback onChanged;
  final VoidCallback onOpenSettings;

  const RoutinesPage({
    super.key,
    required this.db,
    required this.onChanged,
    required this.onOpenSettings,
  });

  @override
  State<RoutinesPage> createState() => RoutinesPageState();
}

class RoutinesPageState extends State<RoutinesPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> tasks = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final today = DateTime.now();
    final rows = await widget.db.getTasks(today);
    if (mounted) setState(() => tasks = rows);
  }

  Future<void> editRoutineSlot(Map<String, dynamic> task) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(db: widget.db, date: DateTime.now(), task: task),
    );
    if (result == true) widget.onChanged();
  }

  Future<void> copyTodayToTomorrow() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final existing = await widget.db.getTasks(tomorrow);

    if (existing.isNotEmpty) {
      final yes = await confirm(
        context,
        'Tomorrow already has tasks',
        'Copying may create duplicates. Continue?',
      );
      if (!yes) return;
    }

    for (final task in tasks) {
      await widget.db.addTask(
        date: tomorrow,
        title: task['title'],
        description: task['description'] ?? '',
        startMinutes: task['startMinutes'],
        endMinutes: task['endMinutes'],
        category: task['category'],
        priority: task['priority'],
        notes: task['notes'] ?? '',
        reminder: task['reminder'] == 1,
        subtasks: task['subtasks'] ?? '',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Routine copied to tomorrow.')),
      );
    }
    widget.onChanged();
  }

  Future<void> addQuickTask() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(db: widget.db, date: DateTime.now()),
    );
    if (result == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Text(
          'Routines',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.045),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: IconButton(
              tooltip: 'Copy to tomorrow',
              onPressed: copyTodayToTomorrow,
              icon: const Icon(Icons.content_copy_rounded, size: 19),
            ),
          ),
          GlobalSettingsButton(onTap: widget.onOpenSettings),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withOpacity(0.30),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton(
            elevation: 0,
            backgroundColor: Colors.transparent,
            onPressed: addQuickTask,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
      body: tasks.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(bottom: 140),
              children: const [
                SectionLabel('Today’s routine'),
                GlassCard(
                  padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Column(
                    children: [
                      Icon(Icons.all_inclusive_rounded, size: 40, color: AppColors.violet),
                      SizedBox(height: 12),
                      Text('No routine yet', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
                      SizedBox(height: 5),
                      Text('Create tasks and build a routine that works for you.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              physics: const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast),
              padding: const EdgeInsets.only(bottom: 150),
              children: [
                SectionLabel('Today’s routine (Tap to edit)', subtitle: '${tasks.length} tasks'),
                ...List.generate(tasks.length, (index) {
                  final task = tasks[index];
                  final accent = categoryColor(task['category'].toString());

                  return GlassCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    onTap: () => editRoutineSlot(task),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accent.withOpacity(0.20), accent.withOpacity(0.06)],
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: accent.withOpacity(0.20)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task['title'],
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.schedule_rounded, size: 11, color: AppColors.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatMinutes(task['startMinutes']),
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 6),
                                  GlowBadge(text: task['category'].toString(), color: accent),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.cyan),
                          onPressed: () => editRoutineSlot(task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.rose),
                          onPressed: () async {
                            final yes = await confirm(context, 'Delete Routine Task?', 'This routine slot will be removed permanently.');
                            if (!yes) return;
                            await widget.db.deleteTask(task['id']);
                            widget.onChanged();
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
