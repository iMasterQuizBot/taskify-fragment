import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ai_service.dart';
import 'app_ui_bridge.dart';
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
  static DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
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
              'repeat_type': {'type': 'STRING', 'description': 'once, daily, alternate, weekdays, weekends, custom_days, custom_dates, spaced'},
              'repeat_days': {'type': 'STRING', 'description': 'जैसे Sun या Mon,Wed,Fri'},
              'notes': {'type': 'STRING', 'description': 'नोट्स, फॉर्मूला, लिंक या PYQ'},
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
          'name': 'skip_task',
          'description': 'किसी टास्क को skipped मार्क करता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'title': {'type': 'STRING', 'description': 'टास्क का नाम'},
            },
            'required': ['title'],
          },
        },
        {
          'name': 'list_tasks',
          'description': 'किसी एक दिन या अगले N दिनों (जैसे 10, 15, 30, 365 दिन) के टास्क दिखाता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'date': {'type': 'STRING', 'description': 'YYYY-MM-DD; न दिया हो तो आज'},
              'days_ahead': {'type': 'INTEGER', 'description': 'अगले कितने दिनों के टास्क चाहिए (1 से 365)'},
            },
          },
        },
        {
          'name': 'search_tasks',
          'description': 'पूरे इतिहास में टास्क खोजता है।',
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
          'description': 'आज या पिछले N दिनों के स्टैट्स व स्ट्रीक बताता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'days': {'type': 'INTEGER', 'description': 'दिनों की संख्या (1 से 365)'},
            },
          },
        },
        {
          'name': 'reschedule_overdue',
          'description': 'छूटे हुए Overdue टास्क को अगले खाली स्लॉट में शिफ्ट करता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {},
          },
        },
        {
          'name': 'navigate_and_control',
          'description': 'ऐप की कोई भी स्क्रीन खोलता है या टाइमर/डायलॉग चलाता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'action': {'type': 'STRING', 'description': 'open_today, open_calendar, open_stats, open_routines, open_settings, open_offline_ai, open_api_ai, open_deepseek, add_task_dialog, start_focus_25, start_focus_50'},
            },
            'required': ['action'],
          },
        },
        {
          'name': 'manage_category',
          'description': 'ऐप की कैटेगरी देखता, जोड़ता या डिलीट करता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'action': {'type': 'STRING', 'description': 'list, add, delete'},
              'name': {'type': 'STRING', 'description': 'कैटेगरी का नाम'},
            },
            'required': ['action'],
          },
        },
        {
          'name': 'manage_routine',
          'description': 'रूटीन टेम्पलेट देखता/लगाता है या आज के टास्क कल कॉपी करता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'action': {'type': 'STRING', 'description': 'list_templates, apply_template, copy_day'},
              'template_name': {'type': 'STRING', 'description': 'टेम्पलेट का नाम'},
            },
            'required': ['action'],
          },
        },
        {
          'name': 'get_app_overview',
          'description': 'ऐप का पूरा लाइव ओवरव्यू (आज के टास्क, स्ट्रीक, नोटिफिकेशन, मूड) देता है।',
          'parameters': {'type': 'OBJECT', 'properties': {}},
        },
        {
          'name': 'set_app_setting',
          'description': 'नोटिफिकेशन ऑन/ऑफ या ऐप सेटिंग बदलता है।',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'key': {'type': 'STRING', 'description': 'notificationsEnabled, notificationLeadTime, theme'},
              'value': {'type': 'STRING', 'description': '1/0, 5/10/15, dark/light'},
            },
            'required': ['key', 'value'],
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
    final istNow = _nowIst();
    final todayStr = DateFormat('yyyy-MM-dd').format(istNow);
    final timeStr24 = DateFormat('HH:mm').format(istNow);
    final timeStr12 = DateFormat('h:mm a').format(istNow);

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
              'text': 'तुम "$assistant" हो, Taskifyy ऐप के अंदर का स्मार्ट सहायक और छात्र-मोटिवेटर। तुम्हें और Taskifyy को Dilkhush Chauhan (दिलखुश चौहान) ने डेवलप किया है—पूछने पर यही नाम बताओ। हमेशा यूज़र को मोटिवेट करते रहो। टाइमज़ोन: भारत (IST, UTC+05:30)। आज की भारतीय तारीख़ $todayStr और अभी का समय $timeStr24 ($timeStr12) है। हमेशा भारतीय समय (IST) में ही काम करो। '
                  'यूज़र की भाषा में छोटा, सहज जवाब दो। चिन्ह या markdown मत बोलो। '
                  'जब भी यूज़र टास्क जोड़ने, एडिट करने, पूरा करने या डिलीट करने को कहे, तो '
                  'हमेशा दिए गए tool (add_task, edit_task, complete_task, delete_task, list_tasks) '
                  'तथा skip_task, search_tasks, get_stats, reschedule_overdue, set_app_setting को ज़रूर चलाओ। सभी 8 रिपीट मोड (once, daily, alternate, weekdays, weekends, custom_days जैसे सिर्फ Sunday के लिए repeat_days="Sun", custom_dates, spaced) और 365 दिन तक का शेड्यूल (days_ahead) संभाल सकते हो।',
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
          final rep = (args['repeat_type'] ?? 'once').toString();
          final repDays = (args['repeat_days'] ?? '').toString();
          final title = (args['title'] ?? 'नया टास्क').toString();
          final cat = (args['category'] ?? 'Other').toString();
          final pri = int.tryParse('${args['priority'] ?? 2}') ?? 2;
          final notes = (args['notes'] ?? '').toString();
          final targetDates = db.generateRepeatDates(date, rep, repDays, horizonDays: 60);
          final items = targetDates
              .map((d) => {
                    'date': d,
                    'title': title,
                    'startMinutes': start,
                    'endMinutes': end,
                    'category': cat,
                    'priority': pri,
                    'repeatType': rep == 'spaced' ? 'once' : rep,
                    'repeatDays': repDays,
                    'notes': notes,
                    'reminder': true,
                  })
              .toList();
          await db.addTasksBatch(items);
          onDatabaseChanged?.call();
          return {'ok': true, 'count': items.length, 'date': DateFormat('yyyy-MM-dd').format(date)};

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

        case 'skip_task':
          final sRows = await db.searchAllTasks((args['title'] ?? '').toString());
          if (sRows.isEmpty) return {'error': 'टास्क नहीं मिला'};
          await db.updateStatus(sRows.first['id'] as int, 'skipped');
          onDatabaseChanged?.call();
          return {'ok': true, 'skipped': sRows.first['title']};

        case 'list_tasks':
          if (args['days_ahead'] != null) {
            final days = (int.tryParse('${args['days_ahead']}') ?? 10).clamp(1, 366);
            final start = _parseDate(args['date']);
            final end = start.add(Duration(days: days - 1));
            final rRows = await db.tasksBetween(start, end);
            return {
              'days': days,
              'count': rRows.length,
              'tasks': rRows.take(120).map((r) => {
                'date': r['date'],
                'title': r['title'],
                'status': r['status'],
                'category': r['category'],
                'startMinutes': r['startMinutes'],
              }).toList(),
            };
          }
          final rows = await db.getTasks(_parseDate(args['date']));
          return {
            'tasks': rows
                .map((r) => {'title': r['title'], 'status': r['status'], 'startMinutes': r['startMinutes']})
                .toList(),
          };

        case 'search_tasks':
          final fRows = await db.searchAllTasks((args['query'] ?? '').toString());
          return {'count': fRows.length, 'tasks': fRows.take(20).map((r) => {'date': r['date'], 'title': r['title'], 'status': r['status']}).toList()};

        case 'get_stats':
          final days = (int.tryParse('${args['days'] ?? 30}') ?? 30).clamp(1, 365);
          final endD = _nowIst();
          final stRows = await db.tasksBetween(endD.subtract(Duration(days: days - 1)), endD);
          final doneCnt = stRows.where((r) => r['status'] == 'completed').length;
          final stk = await db.calculateCurrentStreak();
          return {'days': days, 'total': stRows.length, 'completed': doneCnt, 'streak': stk};

        case 'reschedule_overdue':
          final moved = await db.rescheduleOverdueTasks(_nowIst());
          onDatabaseChanged?.call();
          return {'ok': true, 'rescheduled': moved};

        case 'navigate_and_control':
          final act = (args['action'] ?? 'open_today').toString();
          final msg = await AppUiBridge.instance.trigger(act);
          return {'ok': true, 'message': msg};

        case 'manage_category':
          final cAct = (args['action'] ?? 'list').toString();
          if (cAct == 'add' && args['name'] != null) {
            await db.addCategory(args['name'].toString());
            onDatabaseChanged?.call();
            return {'ok': true, 'added': args['name']};
          } else if (cAct == 'delete' && args['name'] != null) {
            await db.deleteCategory(args['name'].toString());
            onDatabaseChanged?.call();
            return {'ok': true, 'deleted': args['name']};
          }
          final cats = await db.categories();
          return {'categories': cats.map((c) => c['name']).toList()};

        case 'manage_routine':
          final rAct = (args['action'] ?? 'list_templates').toString();
          if (rAct == 'list_templates') {
            final tpls = await db.getTemplates();
            return {'templates': tpls.map((t) => t['name']).toList()};
          } else if (rAct == 'copy_day') {
            final todayD = _nowIst();
            final tomD = todayD.add(const Duration(days: 1));
            final srcList = await db.getTasks(todayD);
            for (final t in srcList) {
              await db.addTask(
                date: tomD,
                title: t['title'].toString(),
                startMinutes: t['startMinutes'] as int,
                endMinutes: t['endMinutes'] as int?,
                category: t['category'].toString(),
                priority: t['priority'] as int,
                playSound: false,
              );
            }
            onDatabaseChanged?.call();
            return {'ok': true, 'copied': srcList.length};
          }
          return {'ok': true};

        case 'get_app_overview':
          final ist = _nowIst();
          final tList = await db.getTasks(ist);
          final dCnt = tList.where((r) => r['status'] == 'completed').length;
          final stkVal = await db.calculateCurrentStreak();
          return {'total': tList.length, 'completed': dCnt, 'streak': stkVal};

        case 'set_app_setting':
          final k = (args['key'] ?? '').toString();
          final v = (args['value'] ?? '').toString();
          if (k.isNotEmpty) {
            await db.setSetting(k, v);
            if (k == 'notificationsEnabled') await db.rescheduleAllReminders();
            onDatabaseChanged?.call();
          }
          return {'ok': true, 'key': k, 'value': v};

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
      await _rec.stop().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close().timeout(const Duration(milliseconds: 400));
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
