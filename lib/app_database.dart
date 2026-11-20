import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:timezone/timezone.dart' as tz;

class AppDatabase {
  Database? _db;

  Future<void> init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'my_daily_routine.db');

    _db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            startMinutes INTEGER NOT NULL,
            endMinutes INTEGER,
            category TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'pending',
            repeatType TEXT NOT NULL DEFAULT 'once',
            repeatDays TEXT,
            notes TEXT,
            reminder INTEGER NOT NULL DEFAULT 0,
            subtasks TEXT,
            attachmentPath TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            colorHex TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            tasksJson TEXT NOT NULL
          )
        ''');

        final defaultCats = [
          {'name': 'Study', 'color': '#2563EB'},
          {'name': 'Work', 'color': '#22D3EE'},
          {'name': 'Health', 'color': '#34D399'},
          {'name': 'Exercise', 'color': '#10B981'},
          {'name': 'Personal', 'color': '#F472B6'},
          {'name': 'Family', 'color': '#FB7185'},
          {'name': 'Learning', 'color': '#2563EB'},
          {'name': 'Other', 'color': '#FBBF24'}
        ];

        for (final cat in defaultCats) {
          await db.insert('categories', {'name': cat['name'], 'colorHex': cat['color']});
        }

        await db.insert('settings', {'key': 'startMinutes', 'value': '360'});
        await db.insert('settings', {'key': 'endMinutes', 'value': '720'});
        await db.insert('settings', {'key': 'streakTarget', 'value': '80'});
        await db.insert('settings', {'key': 'carryForward', 'value': '0'});
        await db.insert('settings', {'key': 'theme', 'value': 'dark'});
        await db.insert('settings', {'key': 'appTitle', 'value': 'Taskify'});
        await db.insert('settings', {'key': 'notificationLeadTime', 'value': '5'});
        await db.insert('settings', {'key': 'refreshRateMode', 'value': '120'});
        await db.insert('settings', {'key': 'streakFreezeTokens', 'value': '2'});
        await db.insert('settings', {'key': 'pinSecurityEnabled', 'value': '0'});
        await db.insert('settings', {'key': 'appSecurityPin', 'value': ''});
        await db.insert('settings', {'key': 'featureSubtasksEnabled', 'value': '1'});
        await db.insert('settings', {'key': 'featurePomodoroEnabled', 'value': '1'});
        await db.insert('settings', {'key': 'featureAutoBackupEnabled', 'value': '1'});
        await db.insert('settings', {'key': 'autoBackupFolderPath', 'value': ''});
        await db.insert('settings', {'key': 'autoBackupDay', 'value': 'Sunday'});
        await db.insert('settings', {'key': 'cloudSyncEnabled', 'value': '0'});
        await db.insert('settings', {'key': 'cloudSyncUrl', 'value': ''});

        final techJe = [
          {'title': 'Civil Theory & Concept Revision', 'start': 360, 'end': 480, 'cat': 'Study', 'pri': 3},
          {'title': 'Concrete Tech & Survey PYQs', 'start': 510, 'end': 630, 'cat': 'Study', 'pri': 3},
          {'title': 'Formula Notes & Flashcards', 'start': 690, 'end': 780, 'cat': 'Study', 'pri': 2},
          {'title': 'Full Mock Test & Analysis', 'start': 840, 'end': 960, 'cat': 'Study', 'pri': 4},
          {'title': 'Evening Fitness & Walk', 'start': 1020, 'end': 1080, 'cat': 'Health', 'pri': 1},
        ];
        final fiveAm = [
          {'title': '5 AM Hydration & Reflection', 'start': 300, 'end': 330, 'cat': 'Health', 'pri': 2},
          {'title': 'Morning Running & Workout', 'start': 330, 'end': 420, 'cat': 'Exercise', 'pri': 3},
          {'title': 'Deep Work Session 1', 'start': 480, 'end': 600, 'cat': 'Work', 'pri': 4},
        ];
        await db.insert('templates', {'name': 'Tech JE Aspirant', 'tasksJson': jsonEncode(techJe)});
        await db.insert('templates', {'name': '5 AM Club', 'tasksJson': jsonEncode(fiveAm)});
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 6) {
          try {
            await db.execute('ALTER TABLE categories ADD COLUMN colorHex TEXT');
            await db.update('categories', {'colorHex': '#2563EB'}, where: "name = 'Study' OR name = 'Learning'");
          } catch (_) {}
        }
      },
    );
  }

  Database get db {
    if (_db == null) throw Exception('Database not initialized.');
    return _db!;
  }

  String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> autoAllocateRollingHabits() async {
    final repeatingTasks = await db.query('tasks', where: "repeatType != 'once' GROUP BY title");
    final now = DateTime.now();

    for (final task in repeatingTasks) {
      final repeatType = task['repeatType'] as String;
      final repeatDays = task['repeatDays'] as String? ?? '';
      final title = task['title'] as String;

      final weekdayMap = {'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6, 'Sun': 7};
      final targetWeekdays = repeatDays.split(',').map((d) => weekdayMap[d]).whereType<int>().toSet();

      for (int i = 0; i < 90; i++) {
        final targetDate = now.add(Duration(days: i));
        bool shouldAdd = false;

        if (repeatType == 'daily') {
          shouldAdd = true;
        } else if (repeatType == 'weekdays' && targetDate.weekday >= 1 && targetDate.weekday <= 5) {
          shouldAdd = true;
        } else if (repeatType == 'weekends' && (targetDate.weekday == 6 || targetDate.weekday == 7)) {
          shouldAdd = true;
        } else if (repeatType == 'custom_days' && targetWeekdays.contains(targetDate.weekday)) {
          shouldAdd = true;
        }

        if (shouldAdd) {
          final existing = await db.query(
            'tasks',
            where: 'date = ? AND title = ?',
            whereArgs: [dateKey(targetDate), title],
            limit: 1,
          );
          if (existing.isEmpty) {
            await addTask(
              date: targetDate,
              title: title,
              description: task['description']?.toString() ?? '',
              startMinutes: task['startMinutes'] as int,
              endMinutes: task['endMinutes'] as int?,
              category: task['category'].toString(),
              priority: task['priority'] as int,
              repeatType: repeatType,
              repeatDays: repeatDays,
              notes: task['notes']?.toString() ?? '',
              reminder: (task['reminder'] as int) == 1,
              subtasks: task['subtasks']?.toString() ?? '',
            );
          }
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> getTasks(DateTime date) async {
    return db.query(
      'tasks',
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'startMinutes ASC, id ASC',
    );
  }

  Future<int> calculateCurrentStreak() async {
    final allRows = await db.query('tasks', where: "status = 'completed'", orderBy: 'date DESC');
    if (allRows.isEmpty) return 0;

    final completedDates = allRows.map((e) => e['date'].toString()).toSet();
    int streak = 0;
    DateTime check = DateTime.now();

    if (!completedDates.contains(dateKey(check))) {
      check = check.subtract(const Duration(days: 1));
    }

    while (completedDates.contains(dateKey(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }

    return streak;
  }

  Future<int> addTask({
    required DateTime date,
    required String title,
    String description = '',
    required int startMinutes,
    int? endMinutes,
    required String category,
    required int priority,
    String repeatType = 'once',
    String repeatDays = '',
    String notes = '',
    bool reminder = false,
    String subtasks = '',
    String attachmentPath = '',
  }) async {
    final now = DateTime.now().toIso8601String();

    final id = await db.insert('tasks', {
      'date': dateKey(date),
      'title': title,
      'description': description,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'category': category,
      'priority': priority,
      'status': 'pending',
      'repeatType': repeatType,
      'repeatDays': repeatDays,
      'notes': notes,
      'reminder': reminder ? 1 : 0,
      'subtasks': subtasks,
      'attachmentPath': attachmentPath,
      'createdAt': now,
      'updatedAt': now,
    });

    if (reminder) {
      _scheduleTaskNotification(id, title, date, startMinutes);
    }
    return id;
  }

  Future<void> updateTask(
    int id, {
    required String title,
    required String description,
    required int startMinutes,
    int? endMinutes,
    required String category,
    required int priority,
    required String notes,
    required bool reminder,
    String subtasks = '',
    String attachmentPath = '',
  }) async {
    final taskRow = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    final dateStr = taskRow.isNotEmpty ? taskRow.first['date'].toString() : dateKey(DateTime.now());

    await db.update(
      'tasks',
      {
        'title': title,
        'description': description,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'category': category,
        'priority': priority,
        'notes': notes,
        'reminder': reminder ? 1 : 0,
        'subtasks': subtasks,
        'attachmentPath': attachmentPath,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (_) {}
    if (reminder) {
      _scheduleTaskNotification(id, title, DateTime.parse(dateStr), startMinutes);
    }
  }

  Future<void> updateFutureTasks(
    String originalTitle,
    DateTime fromDate, {
    required String newTitle,
    required String description,
    required int startMinutes,
    int? endMinutes,
    required String category,
    required int priority,
    required String repeatType,
    required String repeatDays,
    required String notes,
    String subtasks = '',
    bool reminder = false,
  }) async {
    final fromDateStr = dateKey(fromDate);
    final rows = await db.query(
      'tasks',
      where: 'title = ? AND date >= ?',
      whereArgs: [originalTitle, fromDateStr],
    );

    for (final row in rows) {
      final rowId = row['id'] as int;
      final rowDateStr = row['date'].toString();

      try {
        await flutterLocalNotificationsPlugin.cancel(rowId);
      } catch (_) {}

      await db.update(
        'tasks',
        {
          'title': newTitle,
          'description': description,
          'startMinutes': startMinutes,
          'endMinutes': endMinutes,
          'category': category,
          'priority': priority,
          'repeatType': repeatType,
          'repeatDays': repeatDays,
          'notes': notes,
          'subtasks': subtasks,
          'reminder': reminder ? 1 : 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [rowId],
      );

      if (reminder) {
        _scheduleTaskNotification(rowId, newTitle, DateTime.parse(rowDateStr), startMinutes);
      }
    }
  }

  Future<void> updateStatus(int id, String status) async {
    await db.update(
      'tasks',
      {
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSubtasks(int id, String subtasksJson) async {
    await db.update(
      'tasks',
      {
        'subtasks': subtasksJson,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTask(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (_) {}
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFutureTasksByTitle(String title, DateTime fromDate) async {
    final fromDateStr = dateKey(fromDate);
    await db.delete('tasks', where: 'title = ? AND date >= ?', whereArgs: [title, fromDateStr]);
  }

  Future<void> deleteAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (_) {}
    await db.delete('tasks');
  }

  Future<List<Map<String, dynamic>>> allTasks() async => db.query('tasks', orderBy: 'date DESC, startMinutes ASC');

  Future<List<Map<String, dynamic>>> tasksBetween(DateTime start, DateTime end) async {
    return db.query(
      'tasks',
      where: 'date >= ? AND date <= ?',
      whereArgs: [dateKey(start), dateKey(end)],
      orderBy: 'date ASC, startMinutes ASC',
    );
  }

  Future<List<Map<String, dynamic>>> categories() async => db.query('categories', orderBy: 'name ASC');

  Future<void> addCategory(String name, {String colorHex = '#2563EB'}) async {
    if (name.trim().isEmpty) return;
    await db.insert(
      'categories',
      {'name': name.trim(), 'colorHex': colorHex},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCategory(String name) async => db.delete('categories', where: 'name = ?', whereArgs: [name]);

  Future<List<Map<String, dynamic>>> getTemplates() async => db.query('templates', orderBy: 'id ASC');
  Future<void> saveTemplate(String name, String tasksJson) async {
    await db.insert('templates', {'name': name, 'tasksJson': tasksJson}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> deleteTemplate(int id) async => db.delete('templates', where: 'id = ?', whereArgs: [id]);

  Future<String?> getSetting(String key) async {
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (result.isEmpty) return null;
    return result.first['value']?.toString();
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> exportJson() async {
    final tasks = await allTasks();
    final cats = await categories();
    final settings = await db.query('settings');
    final tmps = await getTemplates();

    final backup = {
      'app': 'Taskify',
      'version': 6,
      'createdAt': DateTime.now().toIso8601String(),
      'tasks': tasks,
      'categories': cats,
      'templates': tmps,
      'settings': settings,
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> importJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map) throw Exception('Invalid backup.');

    final tasks = decoded['tasks'];
    if (tasks is! List) throw Exception('Invalid tasks array.');

    await db.transaction((txn) async {
      await txn.delete('tasks');
      for (final raw in tasks) {
        final task = Map<String, dynamic>.from(raw);
        task.remove('id');
        await txn.insert('tasks', task);
      }
    });
  }

  Future<void> _scheduleTaskNotification(int id, String title, DateTime date, int startMinutes) async {
    try {
      final leadStr = await getSetting('notificationLeadTime');
      final leadMinutes = int.tryParse(leadStr ?? '5') ?? 5;

      final hour = startMinutes ~/ 60;
      final minute = startMinutes % 60;

      final taskTime = DateTime(date.year, date.month, date.day, hour, minute);
      final alertTime = taskTime.subtract(Duration(minutes: leadMinutes));

      if (alertTime.isBefore(DateTime.now())) return;

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'taskify_alerts',
        'Task Reminders',
        channelDescription: 'On-time routine notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        'Upcoming in $leadMinutes mins',
        title,
        tz.TZDateTime.from(alertTime, tz.local),
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }
}
