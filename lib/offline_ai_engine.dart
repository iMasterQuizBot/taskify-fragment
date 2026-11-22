import 'dart:math' as math;
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

  // मल्टी-टर्न मेमोरी (ताकि अधूरा टास्क पूछकर पूरा कर सके)
  bool _awaitingTask = false;
  String? _pendingTitle;
  DateTime? _pendingDate;
  int? _pendingMinutes;
  bool _pendingDaily = false;
  String? _pendingCategory;

  // पिछली बातचीत याद रखने के लिए हल्की मेमोरी
  final List<String> _recentTopics = [];

  OfflineAiEngine(this.db);

  void _resetDraft() {
    _awaitingTask = false;
    _pendingTitle = null;
    _pendingDate = null;
    _pendingMinutes = null;
    _pendingDaily = false;
    _pendingCategory = null;
  }

  Future<OfflineAiReply> process(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      return const OfflineAiReply(
        text: 'कुछ बोलें या लिखें — जैसे: "कल सुबह 7 बजे जिम जोड़ो", "आज के टास्क दिखाओ", या मुझसे कोई सामान्य बात पूछें।',
      );
    }

    _recentTopics.add(input);
    if (_recentTopics.length > 10) _recentTopics.removeAt(0);

    final lower = input.toLowerCase();

    // 0. अगर पहले से कोई टास्क ड्राफ्ट अधूरा है, तो उसे पूरा करें (या कैंसिल करें)
    if (_awaitingTask) {
      if (_matchesAny(lower, ['cancel', 'रद्द', 'छोड़ो', 'रहने दो', 'मत जोड़ो', 'stop'])) {
        _resetDraft();
        return const OfflineAiReply(text: 'ठीक है, टास्क जोड़ना रद्द कर दिया है।');
      }

      final extractedTime = _extractMinutesOrNull(lower);
      final extractedDate = _extractDateOrNull(lower);
      if (extractedTime != null) _pendingMinutes = extractedTime;
      if (extractedDate != null) _pendingDate = extractedDate;
      if (_matchesAny(lower, ['daily', 'everyday', 'every day', 'रोज', 'रोज़', 'हर दिन'])) {
        _pendingDaily = true;
      }

      final possibleTitle = _extractTitle(input);
      if ((_pendingTitle == null || _pendingTitle!.isEmpty) && possibleTitle.isNotEmpty) {
        _pendingTitle = possibleTitle[0].toUpperCase() + possibleTitle.substring(1);
        _pendingCategory ??= _detectCategory(lower);
      }

      return _finalizeOrAskDraft();
    }

    // 1. सामान्य बातचीत / अभिवादन / हाल-चाल / धन्यवाद
    if (_matchesAny(lower, ['कैसे हो', 'कैसी हो', 'how are you', 'kya haal', 'क्या हाल', 'sab badhiya'])) {
      return const OfflineAiReply(
        text: 'मैं बिल्कुल बढ़िया हूँ और आपके टास्क व रूटीन संभालने के लिए तैयार हूँ! 😊 बताइए आज क्या काम करना है?',
      );
    }

    if (_matchesAny(lower, ['thank', 'thanks', 'धन्यवाद', 'शुक्रिया', 'thnx', 'shukriya'])) {
      return const OfflineAiReply(
        text: 'आपका स्वागत है! हमेशा आपकी मदद के लिए हाज़िर हूँ। 👍',
      );
    }

    if (_matchesAny(lower, ['कौन हो', 'who are you', 'तुम्हारा नाम', 'your name'])) {
      return const OfflineAiReply(
        text: 'मैं Taskify का स्मार्ट Offline AI सहायक हूँ! मैं बिना इंटरनेट के भी आपके टास्क जोड़, एडिट, पूरा और ट्रैक कर सकता हूँ, और आपसे सामान्य बातचीत भी कर सकता हूँ।',
      );
    }

    if (_matchesAny(lower, ['अभी टाइम', 'क्या समय', 'what time', 'kitne baje', 'कितने बजे', 'आज की तारीख', 'today date', 'कौन सा दिन'])) {
      final now = DateTime.now();
      return OfflineAiReply(
        text: '🕒 अभी समय है: ${DateFormat('h:mm a').format(now)}\n📅 आज की तारीख़: ${DateFormat('EEEE, d MMMM yyyy').format(now)}',
      );
    }

    if (_matchesAny(lower, ['motivat', 'मोटिवेशन', 'बोर', 'थक', 'focus', 'फ़ोकस', 'पढ़ाई कैसे', 'study tip'])) {
      return const OfflineAiReply(
        text: '💡 फ़ोकस टिप: एक समय में सिर्फ़ 1 ज़रूरी टास्क चुनें, 25 मिनट का Focus Timer लगाएँ और फोन की डिस्ट्रैक्शन दूर रखें। छोटे-छोटे कदम ही बड़ा रिजल्ट देते हैं!',
      );
    }

    // सरल गणित (जैसे "25 * 4", "150 + 75", "sqrt 144")
    final mathReply = _trySimpleMath(lower);
    if (mathReply != null) {
      return OfflineAiReply(text: mathReply);
    }

    if (_matchesAny(lower, ['help', 'मदद', 'क्या कर सकते', 'hi', 'hello', 'नमस्ते', 'हेलो', 'hey']) &&
        input.split(RegExp(r'\s+')).length <= 4) {
      return const OfflineAiReply(
        text: 'नमस्ते! मैं आपका स्मार्ट Offline Taskify AI हूँ ⚡\n\n'
            'आप मुझसे कह सकते हैं:\n'
            '• "कल सुबह 7 बजे जिम जोड़ो"\n'
            '• "टास्क जोड़ो" (मैं नाम और समय पूछ लूँगा)\n'
            '• "जिम वाला टास्क एडिट करके 8 बजे कर दो"\n'
            '• "आज के टास्क दिखाओ" / "मेरी प्रोग्रेस बताओ"\n'
            '• "जिम वाला टास्क पूरा हो गया" / "डिलीट करो"\n\n'
            'सामान्य बातचीत और सरल गणित भी मैं ऑफलाइन कर सकता हूँ!',
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

    // 3. Edit / Reschedule Task
    if (_matchesAny(lower, ['edit', 'change', 'update', 'reschedule', 'बदलो', 'एडिट', 'शिफ्ट', 'टाइम बदल'])) {
      final newTime = _extractMinutesOrNull(lower);
      final keyword = _cleanKeywords(input, [
        'edit', 'change', 'update', 'reschedule', 'time', 'to', 'task', 'my', 'the',
        'एडिट', 'बदलो', 'बदल', 'कर', 'दो', 'करो', 'शिफ्ट', 'टाइम', 'समय', 'वाला', 'टास्क', 'को', 'से', 'पर', 'बजे',
      ]);
      final cleanTitle = _extractTitle(keyword);
      if (cleanTitle.isEmpty) {
        return const OfflineAiReply(text: 'कौन सा टास्क एडिट करना है? उसका नाम और नया समय बताएं — जैसे: "जिम वाला टास्क 8 बजे कर दो"।');
      }
      final matches = await db.searchTasks(cleanTitle);
      if (matches.isEmpty) {
        return OfflineAiReply(text: '"$cleanTitle" नाम का कोई आने वाला टास्क नहीं मिला।');
      }
      final t = matches.first;
      if (newTime == null) {
        return OfflineAiReply(text: '"${t['title']}" का नया समय क्या रखना है? कृपया समय बताएं (जैसे 7:30 PM)।');
      }
      final oldStart = t['startMinutes'] as int;
      final oldEnd = t['endMinutes'] as int?;
      final duration = (oldEnd != null && oldEnd > oldStart) ? (oldEnd - oldStart) : 60;
      await db.updateTask(
        t['id'] as int,
        title: t['title'].toString(),
        description: t['description']?.toString() ?? '',
        startMinutes: newTime,
        endMinutes: (newTime + duration) % 1440,
        category: t['category'].toString(),
        priority: t['priority'] as int,
        notes: t['notes']?.toString() ?? '',
        reminder: (t['reminder'] as int) == 1,
        subtasks: t['subtasks']?.toString() ?? '',
        attachmentPath: t['attachmentPath']?.toString() ?? '',
      );
      return OfflineAiReply(
        text: '✏️ "${t['title']}" का समय बदलकर ${_formatMinutes(newTime)} कर दिया गया है।',
        dbChanged: true,
      );
    }

    // 4. Complete Task
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

    // 5. Delete Task
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

    // 6. List / Show Tasks
    if (_matchesAny(lower, ['show', 'list', 'tasks', 'टास्क दिखाओ', 'बाकी', 'pending', 'क्या है', 'कौन से', 'आज के टास्क', 'कल के टास्क'])) {
      final targetDate = _extractDateOrNull(lower) ?? DateTime.now();
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

    // 7. Add Task / Routine / Reminder — समझदारी से नाम और समय जांचकर जोड़ें या पूछें!
    if (_matchesAny(lower, [
          'add', 'create', 'remind', 'reminder', 'schedule', 'routine', 'daily',
          'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म',
        ])) {
      _pendingDate = _extractDateOrNull(lower) ?? DateTime.now();
      _pendingMinutes = _extractMinutesOrNull(lower);
      _pendingDaily = _matchesAny(lower, ['daily', 'everyday', 'every day', 'routine', 'रोज', 'रोज़', 'हर दिन', 'रूटीन']);
      _pendingCategory = _detectCategory(lower);

      final title = _extractTitle(input);
      _pendingTitle = title.isEmpty ? null : (title[0].toUpperCase() + title.substring(1));
      _awaitingTask = true;

      return _finalizeOrAskDraft();
    }

    // 8. सामान्य छोटा जवाब या DeepSeek Web का सुझाव
    if (input.split(RegExp(r'\s+')).length <= 3 && !_matchesAny(lower, ['क्या', 'क्यों', 'कैसे', 'what', 'why', 'how', 'explain', 'solve'])) {
      return const OfflineAiReply(
        text: 'मैं आपकी बात सुन रहा हूँ! अगर कोई टास्क जोड़ना हो तो नाम और समय बताएं, या कोई सवाल पूछें।',
      );
    }

    return OfflineAiReply(
      text: 'यह एक विस्तृत या ऑनलाइन जानकारी वाला सवाल है। नीचे बटन से सीधे **DeepSeek Web** या **API AI** पर पूछ सकते हैं 👇',
      suggestDeepSeek: true,
      deepSeekQuery: input,
    );
  }

  Future<OfflineAiReply> _finalizeOrAskDraft() async {
    if (_pendingTitle == null || _pendingTitle!.trim().isEmpty) {
      return const OfflineAiReply(
        text: 'ज़रूर! इस टास्क का **नाम** क्या रखना है? (और अगर समय भी बताना चाहें तो साथ में बोल दें, जैसे "जिम 7 बजे")',
      );
    }
    if (_pendingMinutes == null) {
      return OfflineAiReply(
        text: 'ठीक है, **"$_pendingTitle"** किस समय के लिए जोड़ना है? (जैसे "सुबह 7 बजे" या "6:30 PM")',
      );
    }

    final title = _pendingTitle!;
    final date = _pendingDate ?? DateTime.now();
    final startMinutes = _pendingMinutes!;
    final isDaily = _pendingDaily;
    final category = _pendingCategory ?? 'Personal';

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
    _resetDraft();

    return OfflineAiReply(
      text: '✅ टास्क सेव हो गया!\n'
          '• नाम: $title\n'
          '• समय: $dateLabel, $timeLabel\n'
          '• कैटेगरी: $category\n'
          '• 🔔 रिमाइंडर: चालू',
      dbChanged: true,
    );
  }

  String? _trySimpleMath(String lower) {
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*([+\-*/x×÷])\s*(-?\d+(?:\.\d+)?)\s*$').firstMatch(lower);
    if (m != null) {
      final a = double.tryParse(m.group(1)!);
      final op = m.group(2)!;
      final b = double.tryParse(m.group(3)!);
      if (a != null && b != null) {
        double res;
        switch (op) {
          case '+':
            res = a + b;
            break;
          case '-':
            res = a - b;
            break;
          case '*':
          case 'x':
          case '×':
            res = a * b;
            break;
          case '/':
          case '÷':
            if (b == 0) return '0 से भाग (divide) नहीं किया जा सकता।';
            res = a / b;
            break;
          default:
            return null;
        }
        final formatted = res == res.roundToDouble() ? res.toInt().toString() : res.toStringAsFixed(2);
        return '🧮 उत्तर: $formatted';
      }
    }
    final sq = RegExp(r'(?:sqrt|वर्गमूल)\s*\(?\s*(\d+(?:\.\d+)?)\s*\)?').firstMatch(lower);
    if (sq != null) {
      final n = double.tryParse(sq.group(1)!);
      if (n != null) {
        final r = math.sqrt(n);
        final formatted = r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(3);
        return '🧮 √$n = $formatted';
      }
    }
    return null;
  }

  bool _matchesAny(String text, List<String> words) {
    for (final w in words) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  DateTime? _extractDateOrNull(String lower) {
    final now = DateTime.now();
    if (lower.contains('परसों') || lower.contains('day after tomorrow')) {
      return now.add(const Duration(days: 2));
    }
    if (lower.contains('कल') || lower.contains('tomorrow')) {
      return now.add(const Duration(days: 1));
    }
    if (lower.contains('आज') || lower.contains('today')) {
      return now;
    }
    return null;
  }

  int? _extractMinutesOrNull(String lower) {
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

    return null;
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
      'new', 'one', 'please', 'pls', 'set', 'make', 'my',
      'जोड़ो', 'जोड़', 'बनाओ', 'बना', 'लगाओ', 'लगा', 'करो', 'करना', 'दो', 'देना', 'चाहिए',
      'टास्क', 'रूटीन', 'रिमाइंडर', 'अलार्म', 'नया', 'एक', 'वाला', 'मेरा',
      'आज', 'कल', 'परसों', 'रोज', 'रोज़', 'हर', 'दिन', 'सुबह', 'शाम', 'रात', 'दोपहर',
      'का', 'की', 'के', 'को', 'में', 'पर', 'से', 'है', 'हूं', 'हूँ',
    ]);
  }

  String _cleanKeywords(String input, List<String> stopWords) {
    final stopSet = stopWords.map((e) => e.toLowerCase()).toSet();
    final parts = input.split(RegExp(r'\s+')).where((w) {
      final clean = w.replaceAll(RegExp(r'[,.!?।]'), '').toLowerCase();
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
