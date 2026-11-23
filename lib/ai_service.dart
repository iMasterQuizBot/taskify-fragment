import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'offline_ai_engine.dart';

/// Gemini / DeepSeek API Service — Taskifyy ऐप का पूरा कंट्रोल, 1–2+ महीने का इतिहास,
/// भारतीय समय (IST), और हमेशा छात्र-मोटिवेटर व्यक्तित्व।
class AiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyName = 'gemini_api_key';
  static const String _deepseekKeyName = 'deepseek_api_key';

  static Future<String?> getApiKey() => _storage.read(key: _keyName);
  static Future<void> saveApiKey(String key) => _storage.write(key: _keyName, value: key.trim());
  static Future<void> clearApiKey() => _storage.delete(key: _keyName);

  static Future<String?> getDeepseekKey() => _storage.read(key: _deepseekKeyName);
  static Future<void> saveDeepseekKey(String key) => _storage.write(key: _deepseekKeyName, value: key.trim());
  static Future<void> clearDeepseekKey() => _storage.delete(key: _deepseekKeyName);

  final AppDatabase db;
  final List<Map<String, dynamic>> _history = [];
  final List<Map<String, dynamic>> _dsHistory = [];

  AiService(this.db);

  static DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  static String? cachedProvider;
  static String? cachedGeminiKey;
  static String? cachedDeepseekKey;
  static bool warmedUp = false;

  static Future<void> warmUp(AppDatabase db) async {
    if (warmedUp) return;
    warmedUp = true;
    try {
      cachedProvider = (await db.getSetting('aiProvider'))?.trim();
      cachedGeminiKey = await getApiKey();
      cachedDeepseekKey = await getDeepseekKey();
      final today = DateFormat('yyyy-MM-dd').format(_nowIst());
      await db.getAiMessages('offline', chatDate: today);
      await db.getAiMessages('api', chatDate: today);
    } catch (_) {}
  }

  void resetChat() {
    _history.clear();
    _dsHistory.clear();
  }

  Future<String> getProvider() async {
    final p = (await db.getSetting('aiProvider'))?.trim();
    return (p == null || p.isEmpty) ? 'gemini' : p;
  }

  static const List<Map<String, dynamic>> _toolSpecs = [
    {
      'name': 'add_task',
      'description': 'नया टास्क या रूटीन जोड़ता है (कैटेगरी, प्रायोरिटी, रिपीट मोड, सबटास्क, नोट्स व रिमाइंडर सहित)।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
          'description': {'type': 'STRING', 'description': 'विवरण (वैकल्पिक)'},
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
          'start_time': {'type': 'STRING', 'description': 'शुरू का समय HH:MM (24 घंटे)'},
          'end_time': {'type': 'STRING', 'description': 'खत्म का समय HH:MM (वैकल्पिक)'},
          'category': {'type': 'STRING', 'description': 'Study, Work, Health, Exercise, Personal, Family, Learning, Other या कोई कस्टम नाम'},
          'priority': {'type': 'INTEGER', 'description': '1=Low, 2=Normal, 3=High, 4=Critical'},
          'repeat_type': {'type': 'STRING', 'description': 'once, daily, alternate, weekdays, weekends, custom_days, custom_dates, spaced'},
          'repeat_days': {'type': 'STRING', 'description': 'custom_days के लिए जैसे Mon,Wed,Fri'},
          'custom_dates': {'type': 'STRING', 'description': 'custom_dates के लिए कॉमा से अलग YYYY-MM-DD तारीखें'},
          'subtasks': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
            'description': 'चेकलिस्ट / सबटास्क की सूची',
          },
          'notes': {'type': 'STRING', 'description': 'नोट्स या लिंक'},
          'reminder': {'type': 'BOOLEAN', 'description': 'नोटिफिकेशन चालू/बंद (डिफ़ॉल्ट true)'},
        },
        'required': ['title', 'start_time'],
      },
    },
    {
      'name': 'edit_task',
      'description': 'मौजूदा टास्क का नाम, समय, कैटेगरी, प्रायोरिटी, नोट्स, सबटास्क या रिमाइंडर बदलता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'पुराने टास्क का नाम'},
          'new_title': {'type': 'STRING', 'description': 'नया नाम'},
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
          'start_time': {'type': 'STRING', 'description': 'नया समय HH:MM'},
          'end_time': {'type': 'STRING', 'description': 'नया खत्म समय HH:MM'},
          'category': {'type': 'STRING', 'description': 'नई कैटेगरी'},
          'priority': {'type': 'INTEGER', 'description': '1 से 4'},
          'notes': {'type': 'STRING', 'description': 'नए नोट्स'},
          'subtasks': {'type': 'ARRAY', 'items': {'type': 'STRING'}, 'description': 'नई चेकलिस्ट'},
          'reminder': {'type': 'BOOLEAN', 'description': 'नोटिफिकेशन ऑन/ऑफ'},
          'apply_to_future': {'type': 'BOOLEAN', 'description': 'आने वाले सभी रिपीटिंग टास्क पर लागू करें'},
        },
        'required': ['title'],
      },
    },
    {
      'name': 'complete_task',
      'description': 'किसी टास्क को पूरा (completed) मार्क करता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
        },
        'required': ['title'],
      },
    },
    {
      'name': 'skip_task',
      'description': 'किसी टास्क को skipped मार्क करता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
        },
        'required': ['title'],
      },
    },
    {
      'name': 'delete_task',
      'description': 'टास्क डिलीट करता है (केवल एक दिन या भविष्य के सभी रिपीटिंग टास्क)।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD'},
          'delete_future': {'type': 'BOOLEAN', 'description': 'भविष्य के सभी समान टास्क हटाएँ'},
        },
        'required': ['title'],
      },
    },
    {
      'name': 'list_tasks',
      'description': 'किसी एक दिन या 1–2+ महीने की तारीख़ रेंज (start_date से end_date) के सभी टास्क दिखाता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (एक दिन के लिए)'},
          'start_date': {'type': 'STRING', 'description': 'रेंज की शुरुआती तारीख YYYY-MM-DD'},
          'end_date': {'type': 'STRING', 'description': 'रेंज की अंतिम तारीख YYYY-MM-DD'},
        },
      },
    },
    {
      'name': 'search_tasks',
      'description': 'पूरे इतिहास (पिछले कई महीनों से आगे तक) में नाम, कैटेगरी या नोट्स से टास्क खोजता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'query': {'type': 'STRING', 'description': 'खोजने का शब्द'},
        },
        'required': ['query'],
      },
    },
    {
      'name': 'get_stats',
      'description': 'आज, पिछले N दिनों (जैसे 30 या 60 दिन), स्ट्रीक, स्टडी समय और कैटेगरी-वाइज आँकड़े बताता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'days': {'type': 'INTEGER', 'description': 'कितने दिनों का रिकॉर्ड चाहिए (जैसे 1, 7, 30, 60)'},
        },
      },
    },
    {
      'name': 'manage_category',
      'description': 'ऐप की कैटेगरी देखता, जोड़ता या डिलीट करता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'action': {'type': 'STRING', 'description': 'list, add, या delete'},
          'name': {'type': 'STRING', 'description': 'कैटेगरी का नाम'},
          'color_hex': {'type': 'STRING', 'description': 'रंग का हेक्स कोड जैसे #22D3EE'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'reschedule_overdue',
      'description': 'आज के छूटे हुए (Overdue) टास्क को अगले खाली स्लॉट या कस्टम समय पर रीशेड्यूल करता है।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'start_time': {'type': 'STRING', 'description': 'वैकल्पिक कस्टम समय HH:MM'},
        },
      },
    },
    {
      'name': 'set_app_setting',
      'description': 'ऐप सेटिंग बदलता है (जैसे notificationsEnabled, notificationLeadTime, theme, appTitle)।',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'key': {'type': 'STRING', 'description': 'notificationsEnabled, notificationLeadTime, theme, appTitle'},
          'value': {'type': 'STRING', 'description': 'नया मान (जैसे 1/0, 5, dark/light, Taskifyy)'},
        },
        'required': ['key', 'value'],
      },
    },
  ];

  static final List<Map<String, dynamic>> _tools = [
    {'functionDeclarations': _toolSpecs},
  ];

  static Map<String, dynamic> _toLowerTypes(Map<String, dynamic> schema) {
    final out = <String, dynamic>{};
    schema.forEach((k, v) {
      if (k == 'type' && v is String) {
        out[k] = v.toLowerCase();
      } else if (v is Map<String, dynamic>) {
        out[k] = _toLowerTypes(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static final List<Map<String, dynamic>> _dsTools = _toolSpecs
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t['name'],
              'description': t['description'],
              'parameters': _toLowerTypes(t['parameters'] as Map<String, dynamic>),
            },
          })
      .toList();

  Future<String> _systemPrompt() async {
    final name = (await db.getSetting('aiAssistantName'))?.trim();
    final assistant = (name == null || name.isEmpty) ? 'Taskifyy AI' : name;
    final now = _nowIst();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final time = DateFormat('HH:mm').format(now);
    final time12 = DateFormat('h:mm a').format(now);
    final cats = (await db.categories()).map((c) => c['name'].toString()).join(', ');
    final streak = await db.calculateCurrentStreak();

    return '''तुम "$assistant" हो, Taskifyy ऐप के अंदर का स्मार्ट सहायक और छात्र-मोटिवेटर।
निर्माता / डेवलपर पहचान: अगर कोई पूछे कि तुम्हें या इस ऐप को किसने बनाया/डेवलप किया है, तो गर्व से बताओ: "Dilkhush Chauhan (दिलखुश चौहान)"।
व्यक्तित्व: हमेशा सामान्य, दोस्ताना ढंग से बात करो और हर छात्र/यूज़र को हमेशा प्रेरित (motivate) करते रहो—उन्हें लक्ष्य पूरा करने का हौसला दो।
टाइमज़ोन: भारत (IST, Asia/Kolkata, UTC+05:30)।
आज की भारतीय तारीख: $today, अभी का भारतीय समय: $time ($time12)।
मौजूदा कैटेगरी: $cats | करंट स्ट्रीक: $streak दिन।
नियम:
- हमेशा भारतीय समय (IST, UTC+05:30) का ही उपयोग करें। "अभी" कहने पर $time लें।
- तुम्हारे पास पूरे ऐप का कंट्रोल है: add_task (कैटेगरी, प्रायोरिटी 1-4, रिपीट मोड once/daily/alternate/weekdays/weekends/custom_days/custom_dates/spaced, सबटास्क, नोट्स, रिमाइंडर), edit_task, complete_task, skip_task, delete_task, list_tasks (1-2 महीने की रेंज भी), search_tasks, get_stats, manage_category, reschedule_overdue, set_app_setting।
- कोई भी ऐप काम (टास्क जोड़ना, एडिट, डिलीट, हिस्ट्री देखना, सेटिंग बदलना) करने से पहले **हमेशा tool call चलाएँ**, फिर नतीजा बताएँ।
- LaTeX, \$ चिन्ह, \\ कमांड, कोड-ब्लॉक या तालिका (table) न लिखें; गणित सादे Unicode में लिखें।
- यूज़र की भाषा (हिंदी, अंग्रेज़ी या मिक्स) में जवाब दें।''';
  }

  late final OfflineAiEngine _offlineFallback = OfflineAiEngine(db);
  bool _toolExecutedInTurn = false;

  Future<String> send({required String text, Uint8List? image, String? imageMime}) async {
    _toolExecutedInTurn = false;
    final provider = await getProvider();
    final reply = provider == 'deepseek'
        ? await _sendDeepSeek(text: text, image: image)
        : await _sendGemini(text: text, image: image, imageMime: imageMime);

    if (!_toolExecutedInTurn && image == null && text.trim().isNotEmpty) {
      final lower = text.toLowerCase();
      final looksLikeTaskCmd = RegExp(
        r'(add|create|edit|update|delete|remove|complete|done|skip|reschedule|जोड़|बना|एडिट|बदल|डिलीट|हटा|पूरा|स्किप)',
      ).hasMatch(lower);
      if (looksLikeTaskCmd) {
        final off = await _offlineFallback.process(text);
        if (off.dbChanged) {
          return '$reply\n\n${off.text}';
        }
      }
    }
    return reply;
  }

  Future<String> _sendGemini({required String text, Uint8List? image, String? imageMime}) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('पहले Settings → AI Assistant में अपनी Gemini API key डालें।');
    }
    final model = (await db.getSetting('geminiModel'))?.trim();
    final modelName = (model == null || model.isEmpty) ? 'gemini-2.5-flash' : model;

    final parts = <Map<String, dynamic>>[];
    if (image != null) {
      parts.add({
        'inlineData': {'mimeType': imageMime ?? 'image/jpeg', 'data': base64Encode(image)},
      });
    }
    parts.add({'text': text.isEmpty ? 'इस सवाल को हल करो और समझाओ।' : text});
    _history.add({'role': 'user', 'parts': parts});

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );
    final system = await _systemPrompt();

    for (var round = 0; round < 5; round++) {
      final body = {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': _history,
        'tools': _tools,
        'generationConfig': {'temperature': 0.45},
      };

      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        _history.removeLast();
        throw Exception(_errorMessage(resp.statusCode, resp.body));
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('AI ने जवाब नहीं दिया (शायद सुरक्षा फ़िल्टर)।');
      }
      final modelContent = (candidates.first as Map)['content'] as Map<String, dynamic>;
      final modelParts = (modelContent['parts'] as List? ?? []).cast<Map<String, dynamic>>();
      _history.add({'role': 'model', 'parts': modelParts});

      final calls = modelParts.where((p) => p.containsKey('functionCall')).toList();
      if (calls.isEmpty) {
        final reply = modelParts.map((p) => p['text']?.toString() ?? '').join().trim();
        return reply.isEmpty ? 'जवाब खाली आया।' : reply;
      }

      final responses = <Map<String, dynamic>>[];
      for (final c in calls) {
        final fc = c['functionCall'] as Map<String, dynamic>;
        final name = fc['name'].toString();
        final args = (fc['args'] as Map?)?.cast<String, dynamic>() ?? {};
        final result = await _execute(name, args);
        responses.add({
          'functionResponse': {'name': name, 'response': result},
        });
      }
      _history.add({'role': 'user', 'parts': responses});
    }
    return 'कार्रवाई पूरी हुई।';
  }

  Future<String> _sendDeepSeek({required String text, Uint8List? image}) async {
    final apiKey = await getDeepseekKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('पहले Settings → AI Assistant में अपनी DeepSeek API key डालें।');
    }
    if (image != null) {
      throw Exception('DeepSeek फ़िलहाल फ़ोटो वाले सवाल नहीं पढ़ सकता। फ़ोटो के लिए Gemini चुनें।');
    }
    final model = (await db.getSetting('deepseekModel'))?.trim();
    final modelName = (model == null || model.isEmpty) ? 'deepseek-chat' : model;

    _dsHistory.add({'role': 'user', 'content': text.isEmpty ? 'इस सवाल को हल करो और समझाओ।' : text});

    final uri = Uri.parse('https://api.deepseek.com/chat/completions');
    final system = await _systemPrompt();

    for (var round = 0; round < 5; round++) {
      final body = {
        'model': modelName,
        'messages': [
          {'role': 'system', 'content': system},
          ..._dsHistory,
        ],
        'tools': _dsTools,
        'temperature': 0.45,
      };

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        _dsHistory.removeLast();
        throw Exception(_dsErrorMessage(resp.statusCode, resp.body));
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('AI ने जवाब नहीं दिया।');
      }
      final message = (choices.first as Map)['message'] as Map<String, dynamic>;
      final toolCalls = (message['tool_calls'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      _dsHistory.add({
        'role': 'assistant',
        'content': message['content'],
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      });

      if (toolCalls.isEmpty) {
        final reply = (message['content'] ?? '').toString().trim();
        return reply.isEmpty ? 'जवाब खाली आया।' : reply;
      }

      for (final call in toolCalls) {
        final fn = call['function'] as Map<String, dynamic>;
        final name = fn['name'].toString();
        Map<String, dynamic> args = {};
        try {
          args = (jsonDecode(fn['arguments'] as String? ?? '{}') as Map).cast<String, dynamic>();
        } catch (_) {}
        final result = await _execute(name, args);
        _dsHistory.add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'content': jsonEncode(result),
        });
      }
    }
    return 'कार्रवाई पूरी हुई।';
  }

  String _dsErrorMessage(int code, String body) {
    try {
      final msg = (jsonDecode(body)['error']?['message'] ?? '').toString();
      if (code == 401) return 'DeepSeek API key गलत है। Settings में जाँचें।';
      if (code == 429) return 'DeepSeek की सीमा/क्रेडिट पूरी हुई। थोड़ी देर बाद कोशिश करें।';
      if (code == 402) return 'DeepSeek अकाउंट में क्रेडिट/बैलेंस नहीं है।';
      if (msg.isNotEmpty) return 'AI त्रुटि ($code): $msg';
    } catch (_) {}
    return 'AI त्रुटि ($code)';
  }

  String _errorMessage(int code, String body) {
    try {
      final msg = (jsonDecode(body)['error']?['message'] ?? '').toString();
      if (code == 400 && msg.contains('API key')) return 'API key गलत है। Settings में जाँचें।';
      if (code == 429) return 'Gemini की सीमा पूरी हुई। थोड़ी देर बाद कोशिश करें।';
      if (msg.isNotEmpty) return 'AI त्रुटि ($code): $msg';
    } catch (_) {}
    return 'AI त्रुटि ($code)';
  }

  DateTime _parseDate(dynamic v) {
    if (v == null) return _nowIst();
    try {
      final d = DateTime.parse(v.toString());
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return _nowIst();
    }
  }

  int? _parseTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().toLowerCase();
    if (s == 'now' || s == 'current' || s == 'अभी') {
      final ist = _nowIst();
      return ist.hour * 60 + ist.minute;
    }
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  String _encodeSubtasks(dynamic raw) {
    if (raw is List) {
      final list = raw.map((e) => {'title': e.toString(), 'done': false}).toList();
      return jsonEncode(list);
    }
    return '';
  }

  Future<Map<String, dynamic>> _execute(String name, Map<String, dynamic> args) async {
    _toolExecutedInTurn = true;
    try {
      switch (name) {
        case 'add_task':
          final start = _parseTime(args['start_time']);
          if (start == null) return {'error': 'start_time HH:MM में चाहिए'};
          final date = _parseDate(args['date']);
          final end = _parseTime(args['end_time']);
          final cat = (args['category'] ?? 'Other').toString().trim();
          final existingCats = await db.categories();
          if (!existingCats.any((c) => c['name'].toString().toLowerCase() == cat.toLowerCase())) {
            await db.addCategory(cat);
          }
          final pri = (int.tryParse('${args['priority'] ?? 2}') ?? 2).clamp(1, 4);
          final rep = (args['repeat_type'] ?? 'once').toString();
          final repDays = (args['repeat_days'] ?? '').toString();
          final subs = _encodeSubtasks(args['subtasks']);
          final notes = (args['notes'] ?? '').toString();
          final desc = (args['description'] ?? '').toString();
          final rem = args['reminder'] is bool ? (args['reminder'] as bool) : true;
          final title = (args['title'] ?? 'नया टास्क').toString();

          if (rep == 'spaced') {
            for (final offset in [0, 1, 3, 7, 21]) {
              await db.addTask(
                date: date.add(Duration(days: offset)),
                title: offset == 0 ? title : '$title (Rev +${offset}d)',
                description: desc,
                startMinutes: start,
                endMinutes: end,
                category: cat,
                priority: pri,
                repeatType: 'once',
                notes: notes,
                reminder: rem,
                subtasks: subs,
              );
            }
          } else if (rep == 'alternate') {
            for (int i = 0; i < 60; i += 2) {
              await db.addTask(
                date: date.add(Duration(days: i)),
                title: title,
                description: desc,
                startMinutes: start,
                endMinutes: end,
                category: cat,
                priority: pri,
                repeatType: 'alternate',
                notes: notes,
                reminder: rem,
                subtasks: subs,
                playSound: i == 0,
              );
            }
          } else if (rep == 'custom_dates' && args['custom_dates'] != null) {
            final dList = args['custom_dates'].toString().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
            for (final dStr in dList) {
              await db.addTask(
                date: _parseDate(dStr),
                title: title,
                description: desc,
                startMinutes: start,
                endMinutes: end,
                category: cat,
                priority: pri,
                repeatType: 'custom_dates',
                notes: notes,
                reminder: rem,
                subtasks: subs,
              );
            }
          } else {
            await db.addTask(
              date: date,
              title: title,
              description: desc,
              startMinutes: start,
              endMinutes: end,
              category: cat,
              priority: pri,
              repeatType: rep,
              repeatDays: repDays,
              notes: notes,
              reminder: rem,
              subtasks: subs,
            );
            if (rep != 'once') {
              await db.autoAllocateRollingHabits();
            }
          }
          return {'ok': true, 'title': title, 'repeat': rep, 'category': cat, 'priority': pri};

        case 'edit_task':
          final rows = await db.searchAllTasks((args['title'] ?? '').toString());
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          final t = rows.first;
          final newStart = _parseTime(args['start_time']) ?? (t['startMinutes'] as int);
          final newEnd = _parseTime(args['end_time']) ?? (t['endMinutes'] as int?);
          final newTitle = (args['new_title'] ?? t['title']).toString();
          final newCat = (args['category'] ?? t['category']).toString();
          final newPri = args['priority'] != null ? (int.tryParse('${args['priority']}') ?? t['priority'] as int) : (t['priority'] as int);
          final newNotes = args['notes']?.toString() ?? (t['notes']?.toString() ?? '');
          final newSubs = args['subtasks'] != null ? _encodeSubtasks(args['subtasks']) : (t['subtasks']?.toString() ?? '');
          final newRem = args['reminder'] is bool ? (args['reminder'] as bool) : (t['reminder'] == 1);

          if (args['apply_to_future'] == true) {
            await db.updateFutureTasks(
              t['title'].toString(),
              _parseDate(args['date']),
              newTitle: newTitle,
              description: t['description']?.toString() ?? '',
              startMinutes: newStart,
              endMinutes: newEnd,
              category: newCat,
              priority: newPri,
              repeatType: t['repeatType'].toString(),
              repeatDays: t['repeatDays']?.toString() ?? '',
              notes: newNotes,
              subtasks: newSubs,
              reminder: newRem,
            );
          } else {
            await db.updateTask(
              t['id'] as int,
              title: newTitle,
              description: t['description']?.toString() ?? '',
              startMinutes: newStart,
              endMinutes: newEnd,
              category: newCat,
              priority: newPri,
              notes: newNotes,
              reminder: newRem,
              subtasks: newSubs,
              attachmentPath: t['attachmentPath']?.toString() ?? '',
            );
          }
          return {'ok': true, 'updated': newTitle};

        case 'complete_task':
          final rows = await db.searchAllTasks((args['title'] ?? '').toString());
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          await db.updateStatus(rows.first['id'] as int, 'completed');
          return {'ok': true, 'completed': rows.first['title']};

        case 'skip_task':
          final rows = await db.searchAllTasks((args['title'] ?? '').toString());
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          await db.updateStatus(rows.first['id'] as int, 'skipped');
          return {'ok': true, 'skipped': rows.first['title']};

        case 'delete_task':
          final titleQ = (args['title'] ?? '').toString();
          if (args['delete_future'] == true) {
            await db.deleteFutureTasksByTitle(titleQ, _parseDate(args['date']));
            return {'ok': true, 'deletedFutureFor': titleQ};
          }
          final rows = await db.searchTasks(
            titleQ,
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          for (final r in rows) {
            await db.deleteTask(r['id'] as int);
          }
          return {'deleted': rows.length, 'titles': rows.map((r) => r['title']).toList()};

        case 'list_tasks':
          if (args['start_date'] != null && args['end_date'] != null) {
            final rows = await db.tasksBetween(_parseDate(args['start_date']), _parseDate(args['end_date']));
            return {
              'count': rows.length,
              'tasks': rows
                  .take(80)
                  .map((r) => {
                        'date': r['date'],
                        'title': r['title'],
                        'status': r['status'],
                        'category': r['category'],
                        'priority': r['priority'],
                        'startMinutes': r['startMinutes'],
                      })
                  .toList(),
            };
          }
          final rows = await db.getTasks(_parseDate(args['date']));
          return {
            'tasks': rows
                .map((r) => {
                      'title': r['title'],
                      'status': r['status'],
                      'category': r['category'],
                      'priority': r['priority'],
                      'startMinutes': r['startMinutes'],
                    })
                .toList(),
          };

        case 'search_tasks':
          final rows = await db.searchAllTasks((args['query'] ?? '').toString());
          return {
            'count': rows.length,
            'tasks': rows
                .take(30)
                .map((r) => {
                      'date': r['date'],
                      'title': r['title'],
                      'status': r['status'],
                      'category': r['category'],
                      'startMinutes': r['startMinutes'],
                    })
                .toList(),
          };

        case 'get_stats':
          final days = (int.tryParse('${args['days'] ?? 30}') ?? 30).clamp(1, 365);
          final end = _nowIst();
          final start = end.subtract(Duration(days: days - 1));
          final rows = await db.tasksBetween(start, end);
          final done = rows.where((r) => r['status'] == 'completed').length;
          final streak = await db.calculateCurrentStreak();
          final mood = await db.getMoodLog(end);
          return {
            'days': days,
            'totalTasks': rows.length,
            'completed': done,
            'streak': streak,
            'todayMood': mood?['mood'] ?? 'none',
          };

        case 'manage_category':
          final action = (args['action'] ?? 'list').toString();
          if (action == 'add' && args['name'] != null) {
            await db.addCategory(
              args['name'].toString(),
              colorHex: (args['color_hex'] ?? '#22D3EE').toString(),
            );
            return {'ok': true, 'added': args['name']};
          } else if (action == 'delete' && args['name'] != null) {
            await db.deleteCategory(args['name'].toString());
            return {'ok': true, 'deleted': args['name']};
          }
          final cats = await db.categories();
          return {'categories': cats.map((c) => c['name']).toList()};

        case 'reschedule_overdue':
          final customStart = _parseTime(args['start_time']);
          final moved = await db.rescheduleOverdueTasks(_nowIst(), customStartMinutes: customStart);
          return {'ok': true, 'rescheduledCount': moved};

        case 'set_app_setting':
          final key = (args['key'] ?? '').toString();
          final value = (args['value'] ?? '').toString();
          if (key.isEmpty) return {'error': 'key missing'};
          await db.setSetting(key, value);
          if (key == 'notificationsEnabled') {
            await db.rescheduleAllReminders();
          }
          return {'ok': true, 'key': key, 'value': value};

        default:
          return {'error': 'अज्ञात कार्य: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
