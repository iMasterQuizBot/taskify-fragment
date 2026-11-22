import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'app_database.dart';

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
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
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
  ];

  Future<String> _systemPrompt() async {
    final name = (await db.getSetting('aiAssistantName'))?.trim();
    final assistant = (name == null || name.isEmpty) ? 'Taskify AI' : name;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final time = DateFormat('HH:mm').format(now);
    return '''तुम "$assistant" हो, Taskify ऐप के अंदर का सहायक।
आज की तारीख: $today, अभी का समय: $time।
फ़ॉर्मेटिंग के सख़्त नियम:
- LaTeX, \$ चिन्ह, \\ कमांड, कोड-ब्लॉक या तालिका (table) बिल्कुल न लिखें।
- गणित सादे Unicode में लिखें, जैसे γ, ρ, ², ³, ×, ÷, √, ≈, %।
- जवाब को साफ़ पंक्तियों में लिखें: "हल:" या "चरण 1:" जैसे शीर्षक, फिर छोटी पंक्तियाँ।
- ज़रूरत हो तो ही **शब्द** से बोल्ड करें। सूची के लिए • लगाएँ।
- पहले सीधा उत्तर दें, फिर संक्षेप में कारण या चरण।
- यूज़र की भाषा (हिंदी, अंग्रेज़ी या मिक्स) में जवाब दें।
- टास्क जोड़ना, हटाना या दिखाना हो तो दिए गए tools इस्तेमाल करें, फिर नतीजा एक लाइन में बताएँ।
- सवाल की फ़ोटो हो तो सवाल हल करें और चरण-दर-चरण आसान भाषा में समझाएँ।
- जो पक्का न हो, वह साफ़ बताएँ।''';
  }

  /// यूज़र का संदेश (और चाहें तो फ़ोटो) भेजो, अंतिम जवाब लौटाता है।
  /// Settings में जो भी provider (Gemini / DeepSeek) चुना है, वही इस्तेमाल होता है।
  Future<String> send({required String text, Uint8List? image, String? imageMime}) async {
    final provider = await getProvider();
    if (provider == 'deepseek') {
      return _sendDeepSeek(text: text, image: image);
    }
    return _sendGemini(text: text, image: image, imageMime: imageMime);
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
    if (v == null) return DateTime.now();
    try {
      final d = DateTime.parse(v.toString());
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return DateTime.now();
    }
  }

  int? _parseTime(dynamic v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v.toString().trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  Future<Map<String, dynamic>> _execute(String name, Map<String, dynamic> args) async {
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

        default:
          return {'error': 'अज्ञात कार्य: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
