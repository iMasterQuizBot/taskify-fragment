import 'package:intl/intl.dart';
import 'app_database.dart';

class OfflineAiReply {
  final String text;
  final bool dbChanged;
  final bool suggestDeepSeek;
  final String? deepSeekQuery;

  const OfflineAiReply({
    required this.text,
    this.dbChanged = false,
    this.suggestDeepSeek = false,
    this.deepSeekQuery,
  });
}

class OfflineAiEngine {
  final AppDatabase db;

  OfflineAiEngine(this.db);

  Future<OfflineAiReply> process(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return const OfflineAiReply(
        text: 'कुछ बोलें या लिखें — जैसे: "कल सुबह 7 बजे जिम का टास्क जोड़ो" या "आज के टास्क दिखाओ"।',
      );
    }

    final lower = input.toLowerCase();

    // 1. Help / Greeting
    if (_matchesAny(lower, ['help', 'मदद', 'क्या कर सकते', 'hi', 'hello', 'नमस्ते', 'हेलो']) &&
        input.split(RegExp(r'\s+')).length <= 4) {
      return const OfflineAiReply(
        text: 'नमस्ते! मैं आपका ऑफलाइन Taskify AI हूँ ⚡\n\n'
            'आप मुझसे कह सकते हैं:\n'
            '• "कल सुबह 7 बजे जिम का टास्क जोड़ो"\n'
            '• "रोज सुबह 6 बजे पानी पीने का रूटीन बनाओ"\n'
            '• "आज के टास्क दिखाओ"\n'
            '• "जिम वाला टास्क पूरा हो गया"\n'
            '• "जिम वाला टास्क डिलीट करो"\n'
            '• "मेरी प्रोग्रेस बताओ"\n\n'
            'बड़े सवालों के लिए मैं सीधे DeepSeek से कनेक्ट कर दूँगा!',
      );
    }

    // 2. Stats / Streak / Progress
    if (_matchesAny(lower, ['streak', 'स्ट्रीक', 'progress', 'प्रोग्रेस', 'stats', 'स्टैट्स', 'रिपोर्ट', 'स्कोर'])) {
      final todayTasks = await db.getTasks(DateTime.now());
      final total = todayTasks.length;
      final done = todayTasks.where((t) => t['status'] == 'completed').length;
      final pending = total - done;
      final pct = total == 0 ? 0 : ((done / total) * 100).round();
      final streak = await db.calculateCurrentStreak();

      return OfflineAiReply(
        text: '📊 आज की रिपोर्ट:\n'
            '• कुल टास्क: $total\n'
            '• पूरे हुए: $done ($pct%)\n'
            '• बाकी हैं: $pending\n'
            '• 🔥 करंट स्ट्रीक: $streak दिन',
      );
    }

    // 3. Complete Task
    if (_matchesAny(lower, ['complete', 'done', 'finish', 'पूरा', 'खत्म', 'हो गया', 'कर लिया'])) {
      final keyword = _cleanKeywords(input, [
        'complete', 'completed', 'done', 'finish', 'finished', 'mark', 'as', 'task', 'my', 'the',
        'पूरा', 'हो', 'गया', 'कर', 'लिया', 'खत्म', 'वाला', 'टास्क', 'मेरा', 'को', 'दो', 'दिया',
      ]);
      if (keyword.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क पूरा हुआ? नाम बताएं — जैसे: "जिम वाला टास्क पूरा हो गया"।');
      }

      final matches = await db.searchTasks(keyword);
      final pendingMatch = matches.where((t) => t['status'] != 'completed').toList();
      if (pendingMatch.isEmpty) {
        return OfflineAiReply(text: '"$keyword" नाम का कोई पेंडिंग टास्क नहीं मिला।');
      }

      final task = pendingMatch.first;
      await db.updateStatus(task['id'] as int, 'completed');
      return OfflineAiReply(
        text: '✅ शाबाश! "${task['title']}" को पूरा (Completed) मार्क कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 4. Delete Task
    if (_matchesAny(lower, ['delete', 'remove', 'हटाओ', 'डिलीट', 'हटा दो', 'मिटाओ'])) {
      final keyword = _cleanKeywords(input, [
        'delete', 'remove', 'cancel', 'task', 'my', 'the',
        'डिलीट', 'हटाओ', 'हटा', 'दो', 'मिटाओ', 'वाला', 'टास्क', 'मेरा', 'को', 'करो',
      ]);
      if (keyword.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क डिलीट करना है? नाम बताएं — जैसे: "जिम वाला टास्क डिलीट करो"।');
      }

      final matches = await db.searchTasks(keyword);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$keyword" नाम का कोई टास्क नहीं मिला।');
      }

      final task = matches.first;
      await db.deleteTask(task['id'] as int);
      return OfflineAiReply(
        text: '🗑️ "${task['title']}" (${task['date']}) डिलीट कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 5. List / Show Tasks
    if (_matchesAny(lower, ['show', 'list', 'tasks', 'टास्क दिखाओ', 'बाकी', 'pending', 'क्या है', 'कौन से', 'आज के टास्क', 'कल के टास्क'])) {
      final targetDate = _extractDate(lower);
      final tasks = await db.getTasks(targetDate);
      final dateLabel = _dateLabel(targetDate);

      if (tasks.isEmpty) {
        return OfflineAiReply(text: '📅 $dateLabel कोई टास्क नहीं है। आप नया टास्क जोड़ सकते हैं!');
      }

      final onlyPending = _matchesAny(lower, ['pending', 'बाकी', 'बचे']);
      final filtered = onlyPending ? tasks.where((t) => t['status'] != 'completed').toList() : tasks;

      if (filtered.isEmpty) {
        return OfflineAiReply(text: '🎉 $dateLabel के सभी टास्क पूरे हो चुके हैं!');
      }

      final lines = filtered.map((t) {
        final done = t['status'] == 'completed';
        final timeStr = _formatMinutes(t['startMinutes'] as int);
        return '${done ? "✅" : "⏳"} $timeStr — ${t['title']}';
      }).join('\n');

      return OfflineAiReply(text: '📅 $dateLabel के टास्क (${filtered.length}):\n\n$lines');
    }

    // 6. Add Task / Routine / Reminder
    if (_matchesAny(lower, [
          'add', 'create', 'remind', 'reminder', 'schedule', 'routine', 'daily',
          'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म', 'बजे', 'am', 'pm',
        ])) {
      final date = _extractDate(lower);
      final startMinutes = _extractMinutes(lower);
      final isDaily = _matchesAny(lower, ['daily', 'everyday', 'every day', 'routine', 'रोज', 'रोज़', 'हर दिन', 'रूटीन']);
      final category = _detectCategory(lower);

      String title = _extractTitle(input);
      if (title.isEmpty) {
        title = 'New Task';
      } else {
        title = title[0].toUpperCase() + title.substring(1);
      }

      await db.addTask(
        date: date,
        title: title,
        startMinutes: startMinutes,
        endMinutes: (startMinutes + 60) % 1440,
        category: category,
        priority: 2,
        repeatType: isDaily ? 'daily' : 'once',
        reminder: true,
      );

      if (isDaily) {
        await db.autoAllocateRollingHabits();
      }

      final dateLabel = isDaily ? 'रोज़ (Daily)' : _dateLabel(date);
      final timeLabel = _formatMinutes(startMinutes);

      return OfflineAiReply(
        text: '✅ टास्क सेव हो गया!\n'
            '• नाम: $title\n'
            '• समय: $dateLabel, $timeLabel\n'
            '• कैटेगरी: $category\n'
            '• 🔔 रिमाइंडर: चालू',
        dbChanged: true,
      );
    }

    // 7. Fallback -> Connect directly to DeepSeek Web
    return OfflineAiReply(
      text: 'यह एक जनरल/बड़ा सवाल लग रहा है। इसे नीचे दिए बटन से सीधे **DeepSeek Web** पर पूछें 👇',
      suggestDeepSeek: true,
      deepSeekQuery: input,
    );
  }

  bool _matchesAny(String text, List<String> words) {
    for (final w in words) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  DateTime _extractDate(String lower) {
    final now = DateTime.now();
    if (lower.contains('परसों') || lower.contains('day after tomorrow')) {
      return now.add(const Duration(days: 2));
    }
    if (lower.contains('कल') || lower.contains('tomorrow')) {
      return now.add(const Duration(days: 1));
    }
    return now;
  }

  int _extractMinutes(String lower) {
    final amPmRegex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)');
    final m1 = amPmRegex.firstMatch(lower);
    if (m1 != null) {
      int h = int.parse(m1.group(1)!);
      final min = int.tryParse(m1.group(2) ?? '0') ?? 0;
      final mer = m1.group(3)!;
      if (mer == 'pm' && h < 12) h += 12;
      if (mer == 'am' && h == 12) h = 0;
      return (h.clamp(0, 23) * 60) + min.clamp(0, 59);
    }

    final hindiRegex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:बजे|baje)');
    final m2 = hindiRegex.firstMatch(lower);
    if (m2 != null) {
      int h = int.parse(m2.group(1)!);
      final min = int.tryParse(m2.group(2) ?? '0') ?? 0;
      if (_matchesAny(lower, ['शाम', 'रात', 'दोपहर', 'evening', 'night', 'afternoon']) && h < 12) {
        h += 12;
      }
      return (h.clamp(0, 23) * 60) + min.clamp(0, 59);
    }

    final twentyFour = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(lower);
    if (twentyFour != null) {
      final h = int.parse(twentyFour.group(1)!);
      final min = int.parse(twentyFour.group(2)!);
      return h * 60 + min;
    }

    final now = DateTime.now();
    final nextHour = (now.hour + 1) % 24;
    return nextHour * 60;
  }

  String _detectCategory(String lower) {
    if (_matchesAny(lower, ['study', 'exam', 'test', 'mock', 'revision', 'notes', 'pyq', 'पढ़ाई', 'पढ़ना', 'नोट्स'])) {
      return 'Study';
    }
    if (_matchesAny(lower, ['gym', 'workout', 'run', 'walk', 'yoga', 'exercise', 'जिम', 'व्यायाम', 'दौड़'])) {
      return 'Exercise';
    }
    if (_matchesAny(lower, ['water', 'medicine', 'health', 'sleep', 'पानी', 'दवा', 'सोना', 'सेहत'])) {
      return 'Health';
    }
    if (_matchesAny(lower, ['work', 'office', 'meeting', 'project', 'ऑफिस', 'मीटिंग', 'काम'])) {
      return 'Work';
    }
    return 'Personal';
  }

  String _extractTitle(String input) {
    var cleaned = input
        .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{1,2}(?::\d{2})?\s*(?:बजे|baje)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'), '');

    return _cleanKeywords(cleaned, [
      'add', 'create', 'remind', 'me', 'to', 'reminder', 'schedule', 'task', 'routine',
      'daily', 'everyday', 'every', 'day', 'today', 'tomorrow', 'at', 'for', 'a', 'an', 'the',
      'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'करो', 'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म',
      'आज', 'कल', 'परसों', 'रोज', 'रोज़', 'हर', 'दिन', 'सुबह', 'शाम', 'रात', 'दोपहर', 'का', 'की', 'के', 'को', 'में', 'पर',
    ]);
  }

  String _cleanKeywords(String input, List<String> stopWords) {
    final stopSet = stopWords.map((e) => e.toLowerCase()).toSet();
    final parts = input.split(RegExp(r'\s+')).where((w) {
      final clean = w.replaceAll(RegExp(r'[,.!?]'), '').toLowerCase();
      return clean.isNotEmpty && !stopSet.contains(clean);
    });
    return parts.join(' ').trim();
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final dt = DateTime(2026, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'आज';
    if (diff == 1) return 'कल';
    if (diff == 2) return 'परसों';
    return DateFormat('dd MMM').format(date);
  }
}
