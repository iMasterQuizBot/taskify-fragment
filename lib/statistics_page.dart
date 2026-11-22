import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'helpers.dart';

class StatisticsPage extends StatefulWidget {
  final AppDatabase db;
  final DateTime targetDate;
  final ValueChanged<DateTime> onDatePicked;
  final VoidCallback onOpenSettings;

  const StatisticsPage({
    super.key,
    required this.db,
    required this.targetDate,
    required this.onDatePicked,
    required this.onOpenSettings,
  });

  @override
  State<StatisticsPage> createState() => StatisticsPageState();
}

class StatisticsPageState extends State<StatisticsPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> selectedDayTasks = [];
  List<Map<String, dynamic>> allCategories = [];
  bool loading = true;
  late DateTime activeDate;

  @override
  void initState() {
    super.initState();
    activeDate = widget.targetDate;
    load();
  }

  void setDate(DateTime date) {
    setState(() => activeDate = date);
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    tasks = await widget.db.allTasks();
    selectedDayTasks = await widget.db.getTasks(activeDate);
    allCategories = await widget.db.categories();
    if (mounted) setState(() => loading = false);
  }

  double calculate(List<Map<String, dynamic>> rows) {
    final active = rows.where((e) => e['status'] != 'skipped').toList();
    if (active.isEmpty) return 0;
    final completed = active.where((e) => e['status'] == 'completed').length;
    return completed / active.length;
  }

  double monthlyProgress() {
    final now = activeDate;
    final rows = tasks.where((task) {
      final date = DateTime.tryParse(task['date'].toString());
      return date != null && date.year == now.year && date.month == now.month;
    }).toList();
    return calculate(rows);
  }

  double weeklyProgress() {
    final now = activeDate;
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final rows = tasks.where((task) {
      final date = DateTime.tryParse(task['date'].toString());
      return date != null &&
          !date.isBefore(DateTime(monday.year, monday.month, monday.day)) &&
          !date.isAfter(DateTime(sunday.year, sunday.month, sunday.day));
    }).toList();

    return calculate(rows);
  }

  int countStatus(String status) {
    return selectedDayTasks.where((e) => e['status'] == status).length;
  }

  int get totalStudyMinutes {
    int total = 0;
    for (final t in selectedDayTasks) {
      final status = t['status'].toString();
      final cat = t['category'].toString().toLowerCase();
      if ((cat == 'study' || cat == 'learning') && status == 'completed') {
        final start = t['startMinutes'] as int;
        final end = (t['endMinutes'] as int?) ?? (start + 60);
        total += max(0, end - start);
      }
    }
    return total;
  }

  Future<void> showPeriodBreakdown({required String title, required DateTime start, required DateTime end}) async {
    final periodTasks = await widget.db.tasksBetween(start, end);
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final t in periodTasks) {
      final dateKey = t['date'].toString();
      grouped.putIfAbsent(dateKey, () => []).add(t);
    }

    final daysCount = end.difference(start).inDays + 1;
    final List<DateTime> allDays = List.generate(daysCount, (i) => start.add(Duration(days: i)));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131823),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    const GlowBadge(text: 'Tap day to select', color: AppColors.cyan),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: allDays.length,
                    itemBuilder: (_, index) {
                      final day = allDays[index];
                      final dKey = widget.db.dateKey(day);
                      final dayTasks = grouped[dKey] ?? [];
                      final score = calculate(dayTasks);
                      final accent = dayTasks.isEmpty
                          ? AppColors.textMuted
                          : (score >= .8 ? AppColors.emerald : (score >= .5 ? AppColors.amber : AppColors.rose));
                      final isSelectedDay = DateUtils.isSameDay(day, activeDate);

                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onDatePicked(day);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelectedDay ? AppColors.violet.withOpacity(0.2) : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelectedDay ? AppColors.cyan : Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.calendar_today_rounded, size: 15, color: accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('EEE, d MMMM yyyy').format(day),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    const SizedBox(height: 5),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: score,
                                        minHeight: 4,
                                        backgroundColor: Colors.white.withOpacity(0.06),
                                        valueColor: AlwaysStoppedAnimation(accent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                dayTasks.isEmpty ? '0%' : '${(score * 100).round()}%',
                                style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void showFilteredList(String status, String title, Color color) {
    final filtered = selectedDayTasks.where((t) => t['status'] == status).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131823),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "${DateFormat('d MMM').format(activeDate)}'s $title Tasks (${filtered.length})",
              style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No $title tasks found for this date.', style: const TextStyle(color: Colors.white54)),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final item = filtered[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.circle, size: 9, color: color),
                      title: Text(
                        item['title'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        formatMinutes(item['startMinutes']),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      trailing: GlowBadge(text: item['category'], color: color),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: AppColors.violet)),
      );
    }

    final isToday = DateUtils.isSameDay(activeDate, DateTime.now());
    final dateLabel = isToday ? "Today" : DateFormat('d MMM yyyy').format(activeDate);

    final monday = activeDate.subtract(Duration(days: activeDate.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final firstDayOfMonth = DateTime(activeDate.year, activeDate.month, 1);
    final lastDayOfMonth = DateTime(activeDate.year, activeDate.month + 1, 0);

    final studyHours = totalStudyMinutes ~/ 60;
    final studyMins = totalStudyMinutes % 60;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Text(
          'Insights',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6),
        ),
        actions: [
          GlobalSettingsButton(onTap: widget.onOpenSettings),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        color: AppColors.violet,
        backgroundColor: AppColors.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast)),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            GlassCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.18), shape: BoxShape.circle),
                    child: const Icon(Icons.school_rounded, color: AppColors.cyan, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DAILY COMPLETED STUDY TIME', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.textMuted, letterSpacing: 0.8)),
                        const SizedBox(height: 3),
                        Text('${studyHours}h ${studyMins}m Studied', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                        Text(DateFormat('EEEE, d MMMM').format(activeDate), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _scoreCard(
                      'This week',
                      weeklyProgress(),
                      AppColors.violet,
                      Icons.calendar_view_week_rounded,
                      onTap: () => showPeriodBreakdown(
                        title: 'Week: ${DateFormat('d MMM').format(monday)} – ${DateFormat('d MMM').format(sunday)}',
                        start: monday,
                        end: sunday,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _scoreCard(
                      'This month',
                      monthlyProgress(),
                      AppColors.cyan,
                      Icons.calendar_month_rounded,
                      onTap: () => showPeriodBreakdown(
                        title: 'Month: ${DateFormat('MMMM yyyy').format(activeDate)}',
                        start: firstDayOfMonth,
                        end: lastDayOfMonth,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SectionLabel(
              '$dateLabel overview',
              subtitle: 'Tap tile to view',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.75,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _statTile(
                    Icons.check_circle_rounded,
                    'Completed',
                    countStatus('completed'),
                    AppColors.emerald,
                    () => showFilteredList('completed', 'Completed', AppColors.emerald),
                  ),
                  _statTile(
                    Icons.schedule_rounded,
                    'Pending',
                    countStatus('pending'),
                    AppColors.cyan,
                    () => showFilteredList('pending', 'Pending', AppColors.cyan),
                  ),
                  _statTile(
                    Icons.fast_forward_rounded,
                    'Skipped',
                    countStatus('skipped'),
                    AppColors.amber,
                    () => showFilteredList('skipped', 'Skipped', AppColors.amber),
                  ),
                  _statTile(
                    Icons.close_rounded,
                    'Missed',
                    countStatus('missed'),
                    AppColors.rose,
                    () => showFilteredList('missed', 'Missed', AppColors.rose),
                  ),
                ],
              ),
            ),
            SectionLabel(
              'Category-wise stats',
              subtitle: dateLabel,
            ),
            ..._buildCategoryStats(),
          ],
        ),
      ),
    );
  }

  Widget _scoreCard(String title, double score, Color accent, IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.08), blurRadius: 20),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 16),
                ),
                const Spacer(),
                Text(
                  '${(score * 100).round()}%',
                  style: TextStyle(color: accent, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                const Icon(Icons.touch_app_rounded, size: 13, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: score,
                minHeight: 4.5,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(IconData icon, String title, int value, Color accent, VoidCallback onTap) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Icon(Icons.touch_app_rounded, size: 13, color: Colors.white24),
        ],
      ),
    );
  }

  IconData _categoryIcon(String name) {
    switch (name.toLowerCase()) {
      case 'exercise':
      case 'workout':
        return Icons.fitness_center_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'health':
        return Icons.favorite_rounded;
      case 'learning':
        return Icons.menu_book_rounded;
      case 'personal':
        return Icons.person_rounded;
      case 'study':
        return Icons.school_rounded;
      case 'work':
      case 'deep work':
        return Icons.work_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  void _showCategoryTasks(String categoryName, Color color) {
    final filtered = selectedDayTasks
        .where((t) => t['category'].toString().toLowerCase() == categoryName.toLowerCase())
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131823),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${DateFormat('d MMM').format(activeDate)} • $categoryName (${filtered.length})',
              style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No $categoryName tasks found for this date.', style: const TextStyle(color: Colors.white54)),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final item = filtered[i];
                    final done = item['status'] == 'completed';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        done ? Icons.check_circle_rounded : Icons.schedule_rounded,
                        size: 16,
                        color: done ? AppColors.emerald : color,
                      ),
                      title: Text(
                        item['title'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        taskTime(item),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      trailing: GlowBadge(text: item['status'].toString(), color: done ? AppColors.emerald : color),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategoryStats() {
    const coreNames = ['Exercise', 'Family', 'Health', 'Learning', 'Other', 'Personal', 'Study', 'Work'];
    final seen = <String>{};
    final List<({String name, String? hex})> ordered = [];

    for (final name in coreNames) {
      final match = allCategories.where((c) => c['name'].toString().toLowerCase() == name.toLowerCase()).toList();
      final hex = match.isNotEmpty ? match.first['colorHex']?.toString() : null;
      ordered.add((name: name, hex: hex));
      seen.add(name.toLowerCase());
    }
    for (final c in allCategories) {
      final n = c['name'].toString();
      if (!seen.contains(n.toLowerCase())) {
        ordered.add((name: n, hex: c['colorHex']?.toString()));
        seen.add(n.toLowerCase());
      }
    }
    for (final t in selectedDayTasks) {
      final n = t['category'].toString();
      if (!seen.contains(n.toLowerCase())) {
        ordered.add((name: n, hex: null));
        seen.add(n.toLowerCase());
      }
    }

    return ordered.map((cat) {
      final catTasks = selectedDayTasks
          .where((t) => t['category'].toString().toLowerCase() == cat.name.toLowerCase())
          .toList();
      final activeTasks = catTasks.where((t) => t['status'] != 'skipped').toList();
      final doneTasks = activeTasks.where((t) => t['status'] == 'completed').toList();
      final pct = activeTasks.isEmpty ? 0.0 : doneTasks.length / activeTasks.length;

      int completedMins = 0;
      for (final t in doneTasks) {
        final start = t['startMinutes'] as int;
        final end = (t['endMinutes'] as int?) ?? (start + 60);
        completedMins += max(0, end - start);
      }
      final hrs = completedMins ~/ 60;
      final mins = completedMins % 60;
      final timeText = completedMins == 0 ? '0m' : (hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m');
      final accent = categoryColor(cat.name, customHex: cat.hex);

      return GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => _showCategoryTasks(cat.name, accent),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: accent.withOpacity(0.24)),
              ),
              child: Icon(_categoryIcon(cat.name), color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cat.name,
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                      Text(
                        '${doneTasks.length}/${activeTasks.length} • $timeText',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4.5,
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ],
        ),
      );
    }).toList();
  }
}
