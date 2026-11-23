import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'app_database.dart';
import 'offline_ai_engine.dart';

/// Gemini API. Key यूज़र अपने फ़ोन में डालता है (flutter_secure_storage में, सुरक्षित)।
/// कोई बैकएंड नहीं: ऐप सीधे Google के API से बात करता है।
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

  /// 'gemini' या 'deepseek'। डिफ़ॉल्ट Gemini।
  final AppDatabase db;
  final List<Map<String, dynamic>> _history = []; // Gemini फ़ॉर्मेट
  final List<Map<String, dynamic>> _dsHistory = []; // DeepSeek / OpenAI फ़ॉर्मेट

  AiService(this.db);

  static DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  static String? cachedProvider;
  static String? cachedGeminiKey;
  static String? cachedDeepseekKey;
  static bool warmedUp = false;

  /// ऐप खुलते ही Offline AI (DB) और API AI (keys/settings) को सुरक्षित रूप से तैयार करता है।
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

  static const List<Map<String, dynamic>> _tools = [
    {
      'functionDeclarations': [
        {
          'name': 'add_task',
          'description': 'User की routine में नया टास्क जोड़ता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
              'start_time': {'type': 'STRING', 'description': 'शुरू का समय HH:MM (24 घंटे)'},
              'end_time': {'type': 'STRING', 'description': 'खत्म का समय HH:MM (वैकल्पिक)'},
              'category': {'type': 'STRING', 'description': 'Study, Work, Health, Exercise, Personal, Family, Learning, Other'},
              'priority': {'type': 'INTEGER', 'description': '1 से 4'},
            },
            'required': ['title', 'start_time'],
          },
        },
        {
          'name': 'delete_task',
          'description': 'नाम के आधार पर टास्क डिलीट करता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING', 'description': 'टास्क का नाम (आंशिक भी चलेगा)'},
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD; न दिया हो तो आज से आगे के सभी'},
            },
            'required': ['title'],
          },
        },
        {
          'name': 'list_tasks',
          'description': 'किसी दिन के टास्क दिखाता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
            },
          },
        },
        {
          'name': 'edit_task',
          'description': 'मौजूदा टास्क का नाम, समय या कैटेगरी बदलता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING', 'description': 'पुराने टास्क का नाम'},
              'new_title': {'type': 'STRING', 'description': 'नया नाम (वैकल्पिक)'},
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
              'start_time': {'type': 'STRING', 'description': 'नया समय HH:MM (24 घंटे, वैकल्पिक)'},
              'end_time': {'type': 'STRING', 'description': 'नया खत्म समय HH:MM (वैकल्पिक)'},
              'category': {'type': 'STRING', 'description': 'नई कैटेगरी (वैकल्पिक)'},
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
      ],
    },
  ];

  /// DeepSeek/OpenAI फ़ॉर्मेट में वही 3 tools
  static const List<Map<String, dynamic>> _dsTools = [
    {
      'type': 'function',
      'function': {
        'name': 'add_task',
        'description': 'User की routine में नया टास्क जोड़ता है।',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'टास्क का नाम'},
            'date': {'type': 'string', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
            'start_time': {'type': 'string', 'description': 'शुरू का समय HH:MM (24 घंटे)'},
            'end_time': {'type': 'string', 'description': 'खत्म का समय HH:MM (वैकल्पिक)'},
            'category': {'type': 'string', 'description': 'Study, Work, Health, Exercise, Personal, Family, Learning, Other'},
            'priority': {'type': 'integer', 'description': '1 से 4'},
          },
          'required': ['title', 'start_time'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_task',
        'description': 'नाम के आधार पर टास्क डिलीट करता है।',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'टास्क का नाम (आंशिक भी चलेगा)'},
            'date': {'type': 'string', 'description': 'YYYY-MM-DD; न दिया हो तो आज से आगे के सभी'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_tasks',
        'description': 'किसी दिन के टास्क दिखाता है।',
        'parameters': {
          'type': 'object',
          'properties': {
            'date': {'type': 'string', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'edit_task',
        'description': 'मौजूदा टास्क का नाम, समय या कैटेगरी बदलता है।',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'पुराने टास्क का नाम'},
            'new_title': {'type': 'string', 'description': 'नया नाम (वैकल्पिक)'},
            'date': {'type': 'string', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
            'start_time': {'type': 'string', 'description': 'नया समय HH:MM (24 घंटे, वैकल्पिक)'},
            'end_time': {'type': 'string', 'description': 'नया खत्म समय HH:MM (वैकल्पिक)'},
            'category': {'type': 'string', 'description': 'नई कैटेगरी (वैकल्पिक)'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'complete_task',
        'description': 'किसी टास्क को पूरा (completed) मार्क करता है।',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'टास्क का नाम'},
            'date': {'type': 'string', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
          },
          'required': ['title'],
        },
      },
    },
  ];

  Future<String> _systemPrompt() async {
    final name = (await db.getSetting('aiAssistantName'))?.trim();
    final assistant = (name == null || name.isEmpty) ? 'Taskify AI' : name;
    final now = _nowIst();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final time = DateFormat('HH:mm').format(now);
    final time12 = DateFormat('h:mm a').format(now);
    return '''तुम "$assistant" हो, Taskifyy ऐप के अंदर का सहायक।
टाइमज़ोन: भारत (IST, Asia/Kolkata, UTC+05:30)।
आज की भारतीय तारीख: $today, अभी का भारतीय समय: $time ($time12)।
नियम: हमेशा भारतीय समय (IST, UTC+05:30) का ही उपयोग करें—कभी भी UTC या ग्लोबल टाइम न लगाएँ। जब यूज़र "अभी" या "अभी के टाइम" कहे, तो $time को ही start_time मानें।
फ़ॉर्मेटिंग के सख़्त नियम:
- LaTeX, \$ चिन्ह, \\ कमांड, कोड-ब्लॉक या तालिका (table) बिल्कुल न लिखें।
- गणित सादे Unicode में लिखें, जैसे γ, ρ, ², ³, ×, ÷, √, ≈, %।
- जवाब को साफ़ पंक्तियों में लिखें: "हल:" या "चरण 1:" जैसे शीर्षक, फिर छोटी पंक्तियाँ।
- ज़रूरत हो तो ही **शब्द** से बोल्ड करें। सूची के लिए • लगाएँ।
- पहले सीधा उत्तर दें, फिर संक्षेप में कारण या चरण।
- यूज़र की भाषा (हिंदी, अंग्रेज़ी या मिक्स) में जवाब दें।
- टास्क जोड़ना, एडिट करना, पूरा करना, हटाना या दिखाना हो तो **हमेशा पहले दिए गए tool call ज़रूर चलाएँ**; बिना tool चलाए कभी मत कहें कि काम हो गया।
- सवाल की फ़ोटो हो तो सवाल हल करें और चरण-दर-चरण आसान भाषा में समझाएँ।
- जो पक्का न हो, वह साफ़ बताएँ।''';
  }

  /// यूज़र का संदेश (और चाहें तो फ़ोटो) भेजो, अंतिम जवाब लौटाता है।
  /// Settings में जो भी provider (Gemini / DeepSeek) चुना है, वही इस्तेमाल होता है।
  late final OfflineAiEngine _offlineFallback = OfflineAiEngine(db);
  bool _toolExecutedInTurn = false;

  Future<String> send({required String text, Uint8List? image, String? imageMime}) async {
    _toolExecutedInTurn = false;
    final provider = await getProvider();
    final reply = provider == 'deepseek'
        ? await _sendDeepSeek(text: text, image: image)
        : await _sendGemini(text: text, image: image, imageMime: imageMime);

    // अगर API AI ने tool call किए बिना ही "टास्क जोड़/एडिट कर दिया" जैसा जवाब दे दिया,
    // तो OfflineAiEngine के ज़रिए असली टास्क अपडेट पक्का करें:
    if (!_toolExecutedInTurn && image == null && text.trim().isNotEmpty) {
      final lower = text.toLowerCase();
      final looksLikeTaskCmd = RegExp(
        r'(add|create|edit|update|delete|remove|complete|done|जोड़|बना|एडिट|बदल|डिलीट|हटा|पूरा)',
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

    for (var round = 0; round < 4; round++) {
      final body = {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': _history,
        'tools': _tools,
        'generationConfig': {'temperature': 0.4},
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

  /// DeepSeek (OpenAI-compatible) API। नोट: DeepSeek photo/इमेज नहीं पढ़ सकता,
  /// सिर्फ़ text सवाल ही भेजे जाते हैं। फ़ोटो वाले सवाल के लिए Gemini पर स्विच करें।
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

    for (var round = 0; round < 4; round++) {
      final body = {
        'model': modelName,
        'messages': [
          {'role': 'system', 'content': system},
          ..._dsHistory,
        ],
        'tools': _dsTools,
        'temperature': 0.4,
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

  Future<Map<String, dynamic>> _execute(String name, Map<String, dynamic> args) async {
    _toolExecutedInTurn = true;
    try {
      switch (name) {
        case 'add_task':
          final start = _parseTime(args['start_time']);
          if (start == null) return {'error': 'start_time HH:MM में चाहिए'};
          final date = _parseDate(args['date']);
          final end = _parseTime(args['end_time']);
          final id = await db.addTask(
            date: date,
            title: (args['title'] ?? 'नया टास्क').toString(),
            startMinutes: start,
            endMinutes: end,
            category: (args['category'] ?? 'Other').toString(),
            priority: int.tryParse('${args['priority'] ?? 2}') ?? 2,
            reminder: true,
          );
          return {'ok': true, 'id': id, 'date': DateFormat('yyyy-MM-dd').format(date)};

        case 'delete_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          for (final r in rows) {
            await db.deleteTask(r['id'] as int);
          }
          return {'deleted': rows.length, 'titles': rows.map((r) => r['title']).toList()};

        case 'list_tasks':
          final rows = await db.getTasks(_parseDate(args['date']));
          return {
            'tasks': rows
                .map((r) => {
                      'title': r['title'],
                      'status': r['status'],
                      'startMinutes': r['startMinutes'],
                    })
                .toList(),
          };

        case 'edit_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          final t = rows.first;
          final newStart = _parseTime(args['start_time']) ?? (t['startMinutes'] as int);
          final newEnd = _parseTime(args['end_time']) ?? (t['endMinutes'] as int?);
          await db.updateTask(
            t['id'] as int,
            title: (args['new_title'] ?? t['title']).toString(),
            description: t['description']?.toString() ?? '',
            startMinutes: newStart,
            endMinutes: newEnd,
            category: (args['category'] ?? t['category']).toString(),
            priority: t['priority'] as int,
            notes: t['notes']?.toString() ?? '',
            reminder: (t['reminder'] as int) == 1,
            subtasks: t['subtasks']?.toString() ?? '',
            attachmentPath: t['attachmentPath']?.toString() ?? '',
          );
          return {'ok': true, 'updated': (args['new_title'] ?? t['title']).toString()};

        case 'complete_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          await db.updateStatus(rows.first['id'] as int, 'completed');
          return {'ok': true, 'completed': rows.first['title']};

        default:
          return {'error': 'अज्ञात कार्य: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
