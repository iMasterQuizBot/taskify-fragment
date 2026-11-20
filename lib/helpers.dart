// ============================================================
// HELPERS (STRICT 12-HOUR AM/PM ENGINE)
// ============================================================

String formatMinutes(int minutes) {
  final hour24 = (minutes ~/ 60) % 24;
  final minute = minutes % 60;

  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;

  return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
}

String taskTime(Map<String, dynamic> task) {
  final start = formatMinutes(task['startMinutes']);
  if (task['endMinutes'] == null) return start;
  return '$start – ${formatMinutes(task['endMinutes'])}';
}

TimeOfDay minutesToTime(int minutes) {
  return TimeOfDay(
    hour: (minutes ~/ 60) % 24,
    minute: minutes % 60,
  );
}

bool isOverdue(Map<String, dynamic> task, DateTime date) {
  if (task['status'] != 'pending') return false;

  final today = DateUtils.isSameDay(date, DateTime.now());
  if (!today) return false;

  final now = DateTime.now();
  final current = now.hour * 60 + now.minute;
  final end = task['endMinutes'] ?? task['startMinutes'];

  return current > end;
}

Future<bool> confirm(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ),
      ],
    ),
  );

  return result ?? false;
}
