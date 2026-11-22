import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ai_service.dart';
import 'app_database.dart';

/// Gemini Live: आप बोलते हैं, AI उसी समय आवाज़ में जवाब देता है।
/// आप बीच में बोलें तो AI रुक जाता है (interrupt)।
/// माइक का डेटा 16kHz PCM, और AI की आवाज़ 24kHz PCM में आती है।
class LiveVoiceService {
  static const MethodChannel _pcm = MethodChannel('taskify/pcm');

  static const List<String> voices = [
    'Kore', 'Puck', 'Charon', 'Fenrir', 'Aoede', 'Leda', 'Orus', 'Zephyr',
  ];

  static const String defaultModel = 'gemini-2.5-flash-native-audio-preview-09-2025';

  final AppDatabase db;
  final void Function(String state) onState; // listening, speaking, connecting, error, stopped

  final AudioRecorder _rec = AudioRecorder();
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _micSub;
  bool _ready = false;
  bool _muted = false;
  bool _running = false;

  LiveVoiceService({required this.db, required this.onState});

  bool get muted => _muted;
  void setMuted(bool v) => _muted = v;

  /// AI की आवाज़ तुरंत रोकें (बाकी बातचीत चलती रहती है)
  Future<void> interrupt() async {
    try {
      await _pcm.invokeMethod('flush');
    } catch (_) {}
    onState('listening');
  }

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

    onState('connecting');
    _running = true;

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
        // FIX: पहले यह config बिल्कुल नहीं भेजा जाता था, इसलिए Gemini की डिफ़ॉल्ट
        // (धीमी/ढीली) VAD settings लगती थीं — जिसकी वजह से (1) बीच में बोलने पर
        // आधी-अधूरी आवाज़ से AI "कन्फ्यूज़" होकर गलत जवाब देता था, और (2) बोलना
        // बंद करने के बाद जवाब आने में काफ़ी देर लगती थी। अब: ज़्यादा sensitivity
        // से interrupt तुरंत और साफ़ पकड़ा जाता है, और कम silence-duration से
        // जवाब बहुत जल्दी शुरू होता है — बातचीत Perplexity जैसी फ़ास्ट लगेगी।
        'realtimeInputConfig': {
          'automaticActivityDetection': {
            'disabled': false,
            'startOfSpeechSensitivity': 'START_SENSITIVITY_HIGH',
            'endOfSpeechSensitivity': 'END_SENSITIVITY_HIGH',
            'prefixPaddingMs': 20,
            'silenceDurationMs': 150,
          },
        },
        'systemInstruction': {
          'parts': [
            {
              'text': 'तुम "$assistant" हो, Taskify ऐप का सहायक। यूज़र की भाषा में छोटा, सहज और '
                  'बातचीत वाला जवाब दो। चिन्ह, गणित के symbols या markdown कभी मत बोलो, '
                  'सिर्फ़ सादे शब्दों में बात करो।',
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

  void _onMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final msg = jsonDecode(text) as Map<String, dynamic>;

      if (msg.containsKey('setupComplete')) {
        _ready = true;
        onState('listening');
        return;
      }

      final content = msg['serverContent'] as Map<String, dynamic>?;
      if (content == null) return;

      if (content['interrupted'] == true) {
        _pcm.invokeMethod('flush');
        onState('listening');
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

      if (content['turnComplete'] == true) onState('listening');
    } catch (_) {
      // खराब फ़्रेम हो तो छोड़ दें
    }
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
