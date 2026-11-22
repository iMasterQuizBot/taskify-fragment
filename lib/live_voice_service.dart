import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ai_service.dart';
import 'app_database.dart';

/// Gemini Live: Push-to-Talk (दबाकर बोलें, छोड़ने पर AI जवाब देता है) +
/// असली Taskify DB टूल्स (add_task, edit_task, complete_task, delete_task, list_tasks)।
class LiveVoiceService {
  static const MethodChannel _pcm = MethodChannel('taskify/pcm');

  static const List<String> voices = [
    'Kore', 'Puck', 'Charon', 'Fenrir', 'Aoede', 'Leda', 'Orus', 'Zephyr',
  ];

  static const String defaultModel = 'gemini-2.5-flash-native-audio-preview-09-2025';

  final AppDatabase db;
  final void Function(String state) onState; // listening, speaking, connecting, idle, error, stopped
  final void Function()? onDatabaseChanged;

  final AudioRecorder _rec = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _micSub;
  bool _ready = false;
  bool _muted = true; // Push-to-Talk: डिफ़ॉल्ट म्यूट, दबाने पर अनम्यूट
  bool _running = false;

  LiveVoiceService({
    required this.db,
    required this.onState,
    this.onDatabaseChanged,
  });

  bool get muted => _muted;
  void setMuted(bool v) => _muted = v;

  /// यूज़र के गोला छोड़ते ही माइक बंद करके Gemini को तुरंत जवाब देने का संकेत भेजें
  void endUserTurn() {
    _muted = true;
    if (_ws != null && _ready && _running) {
      try {
        _ws!.sink.add(jsonEncode({
          'realtimeInput': {'audioStreamEnd': true},
        }));
      } catch (_) {}
    }
  }

  /// AI की आवाज़ तुरंत रोकें
  Future<void> interrupt() async {
    try {
      await _pcm.invokeMethod('flush');
    } catch (_) {}
    onState('idle');
  }

  static const List<Map<String, dynamic>> _liveTools = [
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
          'name': 'edit_task',
          'description': 'मौजूदा टास्क का नाम, समय या कैटेगरी बदलता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING', 'description': 'पुराने टास्क का नाम'},
              'new_title': {'type': 'STRING', 'description': 'नया नाम (वैकल्पिक)'},
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD (वैकल्पिक)'},
              'start_time': {'type': 'STRING', 'description': 'नया समय HH:MM (वैकल्पिक)'},
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
        {
          'name': 'delete_task',
          'description': 'नाम के आधार पर टास्क डिलीट करता है।',
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

  Future<void> start() async {
    final key = await AiService.getApiKey();
    if (key == null || key.isEmpty) {
      throw Exception('पहले Settings → AI Assistant में Gemini API key डालें।');
    }
    final model = (await db.getSetting('liveModel'))?.trim();
    final voice = (await db.getSetting('liveVoice'))?.trim();
    final name = (await db.getSetting('aiAssistantName'))?.trim();
    final assistant = (name == null || name.isEmpty) ? 'Taskify AI' : name;
    final modelName = (model == null || model.isEmpty) ? defaultModel : model;
    final voiceName = (voice == null || voice.isEmpty) ? voices.first : voice;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    onState('connecting');
    _running = true;
    _muted = true;

    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$key',
    );
    _ws = WebSocketChannel.connect(uri);

    _ws!.sink.add(jsonEncode({
      'setup': {
        'model': 'models/$modelName',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceName},
            },
          },
        },
        'tools': _liveTools,
        'systemInstruction': {
          'parts': [
            {
              'text': 'तुम "$assistant" हो, Taskify ऐप का सहायक। आज की तारीख़ $todayStr है। '
                  'यूज़र की भाषा में छोटा, सहज जवाब दो। चिन्ह या markdown मत बोलो। '
                  'जब भी यूज़र टास्क जोड़ने, एडिट करने, पूरा करने या डिलीट करने को कहे, तो '
                  'हमेशा दिए गए tool (add_task, edit_task, complete_task, delete_task, list_tasks) '
                  'को ज़रूर चलाओ—बिना tool चलाए कभी मत कहो कि टास्क जोड़ या बदल दिया।',
            },
          ],
        },
      },
    }));

    await _pcm.invokeMethod('start', {'rate': 24000});

    _wsSub = _ws!.stream.listen(
      _onMessage,
      onError: (_) => _fail('कनेक्शन में समस्या आई।'),
      onDone: () {
        if (_running) _fail('कनेक्शन बंद हो गया।');
      },
    );

    if (!await _rec.hasPermission()) {
      throw Exception('माइक्रोफ़ोन की अनुमति दें।');
    }
    final mic = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _micSub = mic.listen((chunk) {
      if (!_running || !_ready || _muted || _ws == null) return;
      _ws!.sink.add(jsonEncode({
        'realtimeInput': {
          'audio': {'mimeType': 'audio/pcm;rate=16000', 'data': base64Encode(chunk)},
        },
      }));
    });
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

  Future<Map<String, dynamic>> _executeTool(String name, Map<String, dynamic> args) async {
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
          onDatabaseChanged?.call();
          return {'ok': true, 'id': id, 'date': DateFormat('yyyy-MM-dd').format(date)};

        case 'edit_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          final t = rows.first;
          final newStart = _parseTime(args['start_time']) ?? (t['startMinutes'] as int);
          await db.updateTask(
            t['id'] as int,
            title: (args['new_title'] ?? t['title']).toString(),
            description: t['description']?.toString() ?? '',
            startMinutes: newStart,
            endMinutes: t['endMinutes'] as int?,
            category: (args['category'] ?? t['category']).toString(),
            priority: t['priority'] as int,
            notes: t['notes']?.toString() ?? '',
            reminder: (t['reminder'] as int) == 1,
            subtasks: t['subtasks']?.toString() ?? '',
            attachmentPath: t['attachmentPath']?.toString() ?? '',
          );
          onDatabaseChanged?.call();
          return {'ok': true, 'updated': (args['new_title'] ?? t['title']).toString()};

        case 'complete_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          if (rows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          await db.updateStatus(rows.first['id'] as int, 'completed');
          onDatabaseChanged?.call();
          return {'ok': true, 'completed': rows.first['title']};

        case 'delete_task':
          final rows = await db.searchTasks(
            (args['title'] ?? '').toString(),
            date: args['date'] == null ? null : _parseDate(args['date']),
          );
          for (final r in rows) {
            await db.deleteTask(r['id'] as int);
          }
          onDatabaseChanged?.call();
          return {'deleted': rows.length};

        case 'list_tasks':
          final rows = await db.getTasks(_parseDate(args['date']));
          return {
            'tasks': rows
                .map((r) => {'title': r['title'], 'status': r['status'], 'startMinutes': r['startMinutes']})
                .toList(),
          };

        default:
          return {'error': 'Unknown tool: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> _handleToolCalls(Map<String, dynamic> toolCall) async {
    final calls = (toolCall['functionCalls'] as List?) ?? const [];
    if (calls.isEmpty) return;

    final responses = <Map<String, dynamic>>[];
    for (final c in calls) {
      final callMap = c as Map<String, dynamic>;
      final id = callMap['id']?.toString() ?? '';
      final name = callMap['name']?.toString() ?? '';
      final args = (callMap['args'] as Map?)?.cast<String, dynamic>() ?? {};
      final res = await _executeTool(name, args);
      responses.add({
        'id': id,
        'name': name,
        'response': res,
      });
    }

    if (_ws != null && _running) {
      _ws!.sink.add(jsonEncode({
        'toolResponse': {'functionResponses': responses},
      }));
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final msg = jsonDecode(text) as Map<String, dynamic>;

      if (msg.containsKey('setupComplete')) {
        _ready = true;
        onState('idle');
        return;
      }

      if (msg.containsKey('toolCall')) {
        _handleToolCalls(msg['toolCall'] as Map<String, dynamic>);
        return;
      }

      final content = msg['serverContent'] as Map<String, dynamic>?;
      if (content == null) return;

      if (content['interrupted'] == true) {
        _pcm.invokeMethod('flush');
        onState('idle');
      }

      final turn = content['modelTurn'] as Map<String, dynamic>?;
      final parts = (turn?['parts'] as List?) ?? const [];
      for (final p in parts) {
        final inline = (p as Map)['inlineData'] as Map<String, dynamic>?;
        if (inline == null) continue;
        final bytes = base64Decode(inline['data'].toString());
        _pcm.invokeMethod('write', {'bytes': bytes});
        onState('speaking');
      }

      if (content['turnComplete'] == true) {
        onState(_muted ? 'idle' : 'listening');
      }
    } catch (_) {}
  }

  void _fail(String why) {
    if (!_running) return;
    onState('error:$why');
    stop();
  }

  Future<void> stop() async {
    if (!_running && _ws == null) return;
    _running = false;
    _ready = false;
    _muted = true;
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _rec.stop();
    } catch (_) {}
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    try {
      await _pcm.invokeMethod('stop');
    } catch (_) {}
    onState('stopped');
  }

  Future<void> dispose() async {
    await stop();
    await _rec.dispose();
  }
}
