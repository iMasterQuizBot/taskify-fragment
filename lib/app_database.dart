import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'notification_service.dart';
import 'sound_service.dart';

class AppDatabase {
  Database? _db;

  Future<void> init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'my_daily_routine.db');

    _db = await openDatabase(
      path,
      version: 10,
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

        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            channel TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            imageBase64 TEXT,
            deepSeekQuery TEXT,
            chatDate TEXT,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS mood_logs (
            date TEXT PRIMARY KEY,
            mood TEXT NOT NULL,
            energy INTEGER NOT NULL,
            updatedAt TEXT NOT NULL
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
        await db.insert('settings', {'key': 'appTitle', 'value': 'Taskifyy'});
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
        if (oldV < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ai_messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              channel TEXT NOT NULL,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              imageBase64 TEXT,
              deepSeekQuery TEXT,
              chatDate TEXT,
              createdAt TEXT NOT NULL
            )
          ''');
        }
        if (oldV < 8) {
          try {
            await db.execute('ALTER TABLE ai_messages ADD COLUMN chatDate TEXT');
          } catch (_) {}
          try {
            await db.execute("UPDATE ai_messages SET chatDate = substr(createdAt, 1, 10) WHERE chatDate IS NULL OR chatDate = ''");
          } catch (_) {}
        }
        if (oldV < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS mood_logs (
              date TEXT PRIMARY KEY,
              mood TEXT NOT NULL,
              energy INTEGER NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
        }
        if (oldV < 10) {
          try {
            await db.update('settings', {'value': 'Taskifyy'}, where: "key = 'appTitle' AND value = 'Taskify'");
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
              playSound: false,
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
    bool playSound = true,
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
    if (playSound) {
      SoundService.play('taskCreated');
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
      await NotificationService.cancel(id);
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

    // 1. सबसे महत्वपूर्ण फिक्स: पास्ट के टास्क का रिपीट बंद करें
    // ताकि पुराना टाइटल आगे के दिनों में अपने आप जनरेट न हो
    await db.update(
      'tasks',
      {'repeatType': 'once'},
      where: 'title = ? AND date < ?',
      whereArgs: [originalTitle, fromDateStr],
    );

    // 2. अगर टाइटल बदला है, तो फ्यूचर में नए टाइटल के डुप्लीकेट टास्क डिलीट करें
    if (originalTitle != newTitle) {
      await db.delete(
        'tasks',
        where: 'title = ? AND date > ?',
        whereArgs: [newTitle, fromDateStr],
      );
    }

    // 3. अब fromDate (आज) से आगे के सभी टास्क को अपडेट करें
    final rows = await db.query(
      'tasks',
      where: 'title = ? AND date >= ?',
      whereArgs: [originalTitle, fromDateStr],
    );

    for (final row in rows) {
      final rowId = row['id'] as int;
      final rowDateStr = row['date'].toString();

      try {
        await NotificationService.cancel(rowId);
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

    if (status == 'completed') {
      SoundService.play('taskCompleted');
      final row = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
      if (row.isNotEmpty && await allDoneOn(row.first['date'].toString())) {
        SoundService.play('allCompleted');
      }
    }
  }

  /// उस दिन के सारे टास्क पूरे हैं या नहीं
  Future<bool> allDoneOn(String dateStr) async {
    final rows = await db.query('tasks', where: 'date = ?', whereArgs: [dateStr]);
    return rows.isNotEmpty && rows.every((r) => r['status'] == 'completed');
  }

  /// नाम (आंशिक भी) से टास्क खोजना। date न दी हो तो आज से आगे के सभी।
  Future<List<Map<String, dynamic>>> searchTasks(String title, {DateTime? date}) async {
    final like = '%${title.trim()}%';
    if (date != null) {
      return db.query('tasks',
          where: 'title LIKE ? AND date = ?', whereArgs: [like, dateKey(date)]);
    }
    return db.query('tasks',
        where: 'title LIKE ? AND date >= ?', whereArgs: [like, dateKey(DateTime.now())]);
  }

  /// किसी एक टास्क का नोटिफिकेशन चालू/बंद
  Future<void> setTaskReminder(int id, bool on) async {
    await db.update('tasks', {'reminder': on ? 1 : 0, 'updatedAt': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    if (!on) {
      await NotificationService.cancel(id);
      return;
    }
    final row = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isNotEmpty) {
      final r = row.first;
      await _scheduleTaskNotification(id, r['title'].toString(),
          DateTime.parse(r['date'].toString()), r['startMinutes'] as int);
    }
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
      await NotificationService.cancel(id);
    } catch (_) {}
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFutureTasksByTitle(String title, DateTime fromDate) async {
    final fromDateStr = dateKey(fromDate);
    await db.delete('tasks', where: 'title = ? AND date >= ?', whereArgs: [title, fromDateStr]);
  }

  Future<void> deleteAll() async {
    try {
      await NotificationService.cancelAll();
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
    final aiMsgs = await db.query('ai_messages', orderBy: 'id ASC');
    final moods = await db.query('mood_logs', orderBy: 'date DESC');

    final backup = {
      'app': 'Taskify',
      'version': 9,
      'createdAt': DateTime.now().toIso8601String(),
      'tasks': tasks,
      'categories': cats,
      'templates': tmps,
      'settings': settings,
      'ai_messages': aiMsgs,
      'mood_logs': moods,
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> importJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map) throw Exception('Invalid backup.');

    final tasks = decoded['tasks'];
    if (tasks is! List) throw Exception('Invalid tasks array.');

    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('tasks');
      for (final raw in tasks) {
        if (raw is! Map) continue;
        final src = Map<String, dynamic>.from(raw);
        await txn.insert('tasks', {
          'date': (src['date'] ?? dateKey(DateTime.now())).toString(),
          'title': (src['title'] ?? 'Task').toString(),
          'description': src['description']?.toString() ?? '',
          'startMinutes': int.tryParse('${src['startMinutes'] ?? 360}') ?? 360,
          'endMinutes': src['endMinutes'] == null ? null : int.tryParse('${src['endMinutes']}'),
          'category': (src['category'] ?? 'Other').toString(),
          'priority': int.tryParse('${src['priority'] ?? 1}') ?? 1,
          'status': (src['status'] ?? 'pending').toString(),
          'repeatType': (src['repeatType'] ?? 'once').toString(),
          'repeatDays': src['repeatDays']?.toString() ?? '',
          'notes': src['notes']?.toString() ?? '',
          'reminder': (src['reminder'] == 1 || src['reminder'] == true) ? 1 : 0,
          'subtasks': src['subtasks']?.toString() ?? '',
          'attachmentPath': src['attachmentPath']?.toString() ?? '',
          'createdAt': (src['createdAt'] ?? nowIso).toString(),
          'updatedAt': (src['updatedAt'] ?? nowIso).toString(),
        });
      }

      final cats = decoded['categories'];
      if (cats is List) {
        for (final c in cats) {
          if (c is! Map || c['name'] == null) continue;
          await txn.insert(
            'categories',
            {'name': c['name'].toString(), 'colorHex': c['colorHex']?.toString() ?? '#2563EB'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final tmps = decoded['templates'];
      if (tmps is List) {
        for (final tp in tmps) {
          if (tp is! Map || tp['name'] == null || tp['tasksJson'] == null) continue;
          await txn.insert(
            'templates',
            {'name': tp['name'].toString(), 'tasksJson': tp['tasksJson'].toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final sets = decoded['settings'];
      if (sets is List) {
        for (final s in sets) {
          if (s is! Map || s['key'] == null) continue;
          await txn.insert(
            'settings',
            {'key': s['key'].toString(), 'value': s['value']?.toString() ?? ''},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final aiMsgs = decoded['ai_messages'];
      if (aiMsgs is List) {
        await txn.delete('ai_messages');
        for (final m in aiMsgs) {
          if (m is! Map || m['text'] == null) continue;
          await txn.insert('ai_messages', {
            'channel': (m['channel'] ?? 'offline').toString(),
            'role': (m['role'] ?? 'user').toString(),
            'text': m['text'].toString(),
            'imageBase64': m['imageBase64']?.toString(),
            'deepSeekQuery': m['deepSeekQuery']?.toString(),
            'chatDate': m['chatDate']?.toString(),
            'createdAt': (m['createdAt'] ?? nowIso).toString(),
          });
        }
      }

      final moods = decoded['mood_logs'];
      if (moods is List) {
        for (final md in moods) {
          if (md is! Map || md['date'] == null || md['mood'] == null) continue;
          await txn.insert(
            'mood_logs',
            {
              'date': md['date'].toString(),
              'mood': md['mood'].toString(),
              'energy': int.tryParse('${md['energy'] ?? 3}') ?? 3,
              'updatedAt': (md['updatedAt'] ?? nowIso).toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> _scheduleTaskNotification(int id, String title, DateTime date, int startMinutes) async {
    try {
      final leadStr = await getSetting('notificationLeadTime');
      final leadMinutes = int.tryParse(leadStr ?? '5') ?? 5;
      final enabled = (await getSetting('notificationsEnabled')) != '0';
      final alarmEnabled = (await getSetting('alarmEnabled')) != '0';

      await NotificationService.scheduleTask(
        id: id,
        title: title,
        date: date,
        startMinutes: startMinutes,
        leadMinutes: leadMinutes,
        enabled: enabled,
        alarmEnabled: alarmEnabled && enabled,
      );
    } catch (e) {
      debugPrint('Notification schedule error (task $id): $e');
    }
  }

  /// ऐप खुलने पर आने वाले सभी रिमाइंडर फिर से शेड्यूल करता है (रीबूट/अपडेट के बाद भी)।
  Future<void> rescheduleAllReminders() async {
    final today = dateKey(DateTime.now());
    final rows = await db.query(
      'tasks',
      where: "reminder = 1 AND status != 'completed' AND date >= ?",
      whereArgs: [today],
    );
    for (final row in rows) {
      final startMinutes = row['startMinutes'] as int;
      await _scheduleTaskNotification(
        row['id'] as int,
        row['title'].toString(),
        DateTime.parse(row['date'].toString()),
        startMinutes,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAiMessages(String channel, {String? chatDate}) async {
    if (chatDate != null && chatDate.isNotEmpty) {
      return db.query(
        'ai_messages',
        where: "channel = ? AND (chatDate = ? OR (chatDate IS NULL AND substr(createdAt, 1, 10) = ?))",
        whereArgs: [channel, chatDate, chatDate],
        orderBy: 'id ASC',
      );
    }
    return db.query(
      'ai_messages',
      where: 'channel = ?',
      whereArgs: [channel],
      orderBy: 'id ASC',
    );
  }

  Future<List<String>> getAiChatDates(String channel) async {
    final rows = await db.rawQuery(
      "SELECT DISTINCT COALESCE(NULLIF(chatDate, ''), substr(createdAt, 1, 10)) AS d FROM ai_messages WHERE channel = ? ORDER BY d DESC",
      [channel],
    );
    return rows.map((r) => r['d']?.toString() ?? '').where((d) => d.isNotEmpty).toList();
  }

  Future<int> addAiMessage({
    required String channel,
    required String role,
    required String text,
    String? imageBase64,
    String? deepSeekQuery,
    String? chatDate,
  }) async {
    final now = DateTime.now();
    return db.insert('ai_messages', {
      'channel': channel,
      'role': role,
      'text': text,
      'imageBase64': imageBase64,
      'deepSeekQuery': deepSeekQuery,
      'chatDate': chatDate ?? dateKey(now),
      'createdAt': now.toIso8601String(),
    });
  }

  Future<void> deleteAiMessage(int id) async {
    await db.delete('ai_messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAiMessages(String channel, {String? chatDate}) async {
    if (chatDate != null && chatDate.isNotEmpty) {
      await db.delete(
        'ai_messages',
        where: "channel = ? AND (chatDate = ? OR (chatDate IS NULL AND substr(createdAt, 1, 10) = ?))",
        whereArgs: [channel, chatDate, chatDate],
      );
      return;
    }
    await db.delete('ai_messages', where: 'channel = ?', whereArgs: [channel]);
  }

  /// सभी तारीख़ों में नाम, कैटेगरी, विवरण या नोट्स से टास्क खोजना (Global Search)
  Future<List<Map<String, dynamic>>> searchAllTasks(String query) async {
    final q = '%${query.trim()}%';
    return db.query(
      'tasks',
      where: 'title LIKE ? OR category LIKE ? OR description LIKE ? OR notes LIKE ?',
      whereArgs: [q, q, q, q],
      orderBy: 'date DESC, startMinutes ASC',
      limit: 60,
    );
  }

  /// आज के छूटे हुए (Overdue) टास्क को अगले खाली स्लॉट या चुने गए समय पर शिफ़्ट करें
  Future<int> rescheduleOverdueTasks(DateTime date, {int? customStartMinutes}) async {
    final now = DateTime.now();
    final isToday = dateKey(date) == dateKey(now);
    if (!isToday) return 0;

    final currentMins = now.hour * 60 + now.minute;
    final dayTasks = await getTasks(date);
    final overdue = dayTasks.where((t) {
      if (t['status'] != 'pending') return false;
      final end = (t['endMinutes'] as int?) ?? (t['startMinutes'] as int);
      return currentMins > end;
    }).toList();

    if (overdue.isEmpty) return 0;

    int cursor = customStartMinutes ?? (((currentMins + 29) ~/ 30) * 30);
    int moved = 0;

    for (final t in overdue) {
      final oldStart = t['startMinutes'] as int;
      final oldEnd = t['endMinutes'] as int?;
      final duration = (oldEnd != null && oldEnd > oldStart) ? (oldEnd - oldStart) : 60;

      DateTime targetDate = date;
      int newStart = cursor;
      if (newStart + duration > 23 * 60 + 30) {
        // आज जगह नहीं बची तो कल सुबह 7:00 AM से शिफ़्ट करें
        targetDate = date.add(const Duration(days: 1));
        newStart = 420 + (moved * 60);
        if (newStart > 21 * 60) newStart = 420;
      } else {
        cursor = newStart + duration + 15;
      }

      final id = t['id'] as int;
      try {
        await NotificationService.cancel(id);
      } catch (_) {}

      await db.update(
        'tasks',
        {
          'date': dateKey(targetDate),
          'startMinutes': newStart,
          'endMinutes': (newStart + duration) % 1440,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if ((t['reminder'] as int) == 1) {
        await _scheduleTaskNotification(id, t['title'].toString(), targetDate, newStart);
      }
      moved++;
    }
    return moved;
  }

  Future<Map<String, dynamic>?> getMoodLog(DateTime date) async {
    final rows = await db.query('mood_logs', where: 'date = ?', whereArgs: [dateKey(date)], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setMoodLog(DateTime date, String mood, int energy) async {
    await db.insert(
      'mood_logs',
      {
        'date': dateKey(date),
        'mood': mood,
        'energy': energy,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
