import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'helpers.dart';

class CalendarPage extends StatefulWidget {
  final AppDatabase db;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onOpenSettings;

  const CalendarPage({
    super.key,
    required this.db,
    required this.selectedDate,
    required this.onDateSelected,
    required this.onOpenSettings,
  });

  @override
  State<CalendarPage> createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  DateTime month = DateTime.now();
  Map<String, double> scores = {};
  List<Map<String, dynamic>> selectedTasks = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);

    final rows = await widget.db.tasksBetween(first, last);
    final map = <String, double>{};
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final key = row['date'].toString();
      grouped.putIfAbsent(key, () => []).add(row);
    }

    for (final entry in grouped.entries) {
      final active = entry.value.where((e) => e['status'] != 'skipped').toList();
      final done = active.where((e) => e['status'] == 'completed').length;
      map[entry.key] = active.isEmpty ? 0 : done / active.length;
    }

    final dayTasks = await widget.db.getTasks(widget.selectedDate);

    if (mounted) {
      setState(() {
        scores = map;
        selectedTasks = dayTasks;
      });
    }
  }

  Future<void> chooseDay(DateTime date) async {
    final tasks = await widget.db.getTasks(date);
    setState(() => selectedTasks = tasks);
    widget.onDateSelected(date);
  }

  Color scoreColor(double score) {
    if (score >= .8) return AppColors.emerald;
    if (score >= .5) return AppColors.amber;
    return AppColors.rose;
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Text(
          'Calendar',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.6),
        ),
        actions: [
          GlobalSettingsButton(onTap: widget.onOpenSettings),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.violet,
        backgroundColor: AppColors.surface,
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _calendarArrow(Icons.chevron_left_rounded, () {
                        setState(() => month = DateTime(month.year, month.month - 1, 1));
                        load();
                      }),
                      Column(
                        children: [
                          Text(
                            DateFormat('MMMM').format(month),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                          ),
                          Text(
                            '${month.year}',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      _calendarArrow(Icons.chevron_right_rounded, () {
                        setState(() => month = DateTime(month.year, month.month + 1, 1));
                        load();
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      _DayName('SUN'),
                      _DayName('MON'),
                      _DayName('TUE'),
                      _DayName('WED'),
                      _DayName('THU'),
                      _DayName('FRI'),
                      _DayName('SAT'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: leading + days,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 1.15,
                    ),
                    itemBuilder: (_, index) {
                      if (index < leading) return const SizedBox();

                      final day = index - leading + 1;
                      final date = DateTime(month.year, month.month, day);
                      final key = widget.db.dateKey(date);
                      final score = scores[key];
                      final isToday = DateUtils.isSameDay(date, DateTime.now());
                      final isSelected = DateUtils.isSameDay(date, widget.selectedDate);

                      return GestureDetector(
                        onTap: () => chooseDay(date),
                        child: Container(
                          margin: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.violet.withOpacity(0.32)
                                : (score == null ? Colors.white.withOpacity(0.025) : scoreColor(score).withOpacity(0.12)),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.cyan
                                  : (isToday ? AppColors.violet : (score == null ? Colors.white.withOpacity(0.05) : scoreColor(score).withOpacity(0.28))),
                              width: isSelected || isToday ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  color: isSelected ? AppColors.cyan : (isToday ? AppColors.violet : AppColors.textPrimary),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (score != null)
                                Text(
                                  '${(score * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: scoreColor(score),
                                  ),
                                )
                              else
                                const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SectionLabel('Performance key'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: const [
                  GlowBadge(text: '80–100% (High)', color: AppColors.emerald),
                  GlowBadge(text: '50–79% (Moderate)', color: AppColors.amber),
                  GlowBadge(text: 'Below 50% (Needs Focus)', color: AppColors.rose),
                ],
              ),
            ),
            if (selectedTasks.isNotEmpty) ...[
              SectionLabel(
                DateFormat('d MMMM yyyy').format(widget.selectedDate),
                subtitle: '${selectedTasks.length} tasks',
              ),
              ...selectedTasks.map((task) {
                final done = task['status'] == 'completed';
                final accent = categoryColor(task['category'].toString());

                return GlassCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: done ? AppColors.emerald.withOpacity(0.15) : accent.withOpacity(0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: done ? AppColors.emerald.withOpacity(0.28) : accent.withOpacity(0.22),
                          ),
                        ),
                        child: Icon(
                          done ? Icons.check_rounded : Icons.schedule_rounded,
                          color: done ? AppColors.emerald : accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task['title'],
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatMinutes(task['startMinutes']),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      GlowBadge(text: task['category'].toString(), color: accent),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _calendarArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
      ),
    );
  }
}

class _DayName extends StatelessWidget {
  final String text;
  const _DayName(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: AppColors.textMuted,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}
