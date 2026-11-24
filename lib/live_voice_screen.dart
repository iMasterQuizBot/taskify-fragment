import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'app_ui_bridge.dart';
import 'live_voice_service.dart';
import 'offline_ai_engine.dart';
import 'tts_voice.dart';
import 'widgets/ai_orb_icon.dart';

enum _VoiceMode { offline, api }

/// Perplexity-स्टाइल Push-to-Talk Live Voice AI स्क्रीन:
/// - गोले को दबाकर रखें (Hold) -> तभी सुनेगा (बीच में रुकेगा नहीं और AI की आवाज़ नहीं पकड़ेगा)
/// - गोला छोड़ें (Release) -> तब AI सोचकर पूरा जवाब बोलेगा
/// - Offline AI और API AI दोनों में असली टास्क क्रिएट/एडिट/डिलीट होते हैं
class LiveVoiceScreen extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback? onChanged;

  const LiveVoiceScreen({
    super.key,
    required this.db,
    this.onChanged,
  });

  @override
  State<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends State<LiveVoiceScreen> {
  static const MethodChannel _bgChannel = MethodChannel('taskify/background');
  static const MethodChannel _sttAudio = MethodChannel('taskify/stt_audio');

  late final LiveVoiceService _apiSvc = LiveVoiceService(
    db: widget.db,
    onState: _onApiState,
    onDatabaseChanged: widget.onChanged,
  );
  late final OfflineAiEngine _offlineEngine = OfflineAiEngine(widget.db);
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  _VoiceMode _mode = _VoiceMode.offline;
  String _state = 'idle'; // idle, connecting, listening, thinking, speaking
  bool _isHolding = false;
  bool _closed = false;
  bool _sttReady = false;
  double _micLevel = 0.0;
  String _lastRecognized = '';
  String _statusLabel = 'बोलने के लिए गोले को दबाकर रखें';

  @override
  void initState() {
    super.initState();
    _startForegroundService();
    _initOffline();
  }

  Future<void> _startForegroundService() async {
    try {
      await _bgChannel.invokeMethod('startVoiceService');
    } catch (_) {}
  }

  Future<void> _stopForegroundService() async {
    try {
      await _bgChannel.invokeMethod('stopVoiceService');
    } catch (_) {}
  }

  Future<void> _initOffline() async {
    try {
      await TtsVoice.apply(_tts, widget.db);
      await _tts.awaitSpeakCompletion(true);
      _sttReady = await _stt.initialize();
    } catch (_) {}
    if (!mounted || _closed || _mode != _VoiceMode.offline) return;
    setState(() {
      _state = 'idle';
      _statusLabel = _sttReady
          ? 'बोलने के लिए गोले को दबाकर रखें'
          : 'माइक की अनुमति दें, फिर गोले को दबाकर बोलें';
    });
  }

  Future<void> _switchMode(_VoiceMode next) async {
    if (_mode == next || _closed) return;
    _isHolding = false;
    await _stopCurrentMode();
    if (!mounted || _closed) return;
    setState(() {
      _mode = next;
      _micLevel = 0.0;
      _state = 'idle';
    });
    if (next == _VoiceMode.offline) {
      await _initOffline();
    } else {
      await _startApiMode();
    }
  }

  Future<void> _stopCurrentMode() async {
    try {
      await _sttAudio.invokeMethod('muteBeep');
      await _stt.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _apiSvc.stop();
    } catch (_) {}
  }

  Future<void> _startApiMode() async {
    setState(() {
      _state = 'connecting';
      _statusLabel = 'API Live AI से जुड़ रहा है…';
    });
    try {
      await _apiSvc.start();
      if (!mounted || _closed || _mode != _VoiceMode.api) return;
      setState(() {
        _state = 'idle';
        _statusLabel = 'बोलने के लिए गोले को दबाकर रखें';
      });
    } catch (e) {
      if (!mounted || _closed || _mode != _VoiceMode.api) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() {
        _state = 'idle';
        _statusLabel = msg;
      });
    }
  }

  void _onApiState(String s) {
    if (!mounted || _closed || _mode != _VoiceMode.api) return;
    if (s == 'stopped') return;
    if (s.startsWith('error:')) {
      final err = s.substring(6);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      setState(() {
        _state = 'idle';
        _statusLabel = err;
      });
      return;
    }
    setState(() {
      _state = s;
      _statusLabel = switch (s) {
        'listening' => 'सुन रहा हूँ… (छोड़ने पर जवाब मिलेगा)',
        'speaking' => 'API Live AI बोल रहा है…',
        'connecting' => 'API Live AI से जुड़ रहा है…',
        _ => 'बोलने के लिए गोले को दबाकर रखें',
      };
    });
  }

  /// गोला दबाने पर (Hold Start): AI को चुप कराकर सिर्फ़ यूज़र की आवाज़ सुनें
  Future<void> _onHoldStart() async {
    if (_closed || _isHolding) return;
    _isHolding = true;
    _lastRecognized = '';

    if (_mode == _VoiceMode.api) {
      await _apiSvc.interrupt();
      _apiSvc.setMuted(false);
      if (mounted) {
        setState(() {
          _state = 'listening';
          _statusLabel = 'सुन रहा हूँ… (बोलकर छोड़ें)';
        });
      }
      return;
    }

    // Offline mode Push-to-Talk
    try {
      await _tts.stop();
    } catch (_) {}
    if (!_sttReady) {
      _sttReady = await _stt.initialize();
    }
    if (!_sttReady) {
      _isHolding = false;
      if (mounted) {
        setState(() {
          _state = 'idle';
          _statusLabel = 'माइक या स्पीच उपलब्ध नहीं है।';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _state = 'listening';
        _statusLabel = 'सुन रहा हूँ… (बोलकर छोड़ें)';
      });
    }

    try { await _sttAudio.invokeMethod('muteBeep'); } catch (_) {}
    await _stt.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(minutes: 2),
      onSoundLevelChange: (level) {
        if (mounted && _isHolding && _mode == _VoiceMode.offline) {
          setState(() => _micLevel = (level.clamp(0, 12) / 12).toDouble());
        }
      },
      onResult: (r) {
        if (r.recognizedWords.trim().isNotEmpty) {
          _lastRecognized = r.recognizedWords.trim();
        }
      },
    );
  }

  /// गोला छोड़ने पर (Hold End): माइक बंद करें और अब जवाब बोलें
  Future<void> _onHoldEnd() async {
    if (!_isHolding || _closed) return;
    _isHolding = false;

    if (_mode == _VoiceMode.api) {
      _apiSvc.endUserTurn();
      if (mounted) {
        setState(() {
          _state = 'thinking';
          _micLevel = 0.0;
          _statusLabel = 'सोच रहा हूँ…';
        });
      }
      return;
    }

    try {
      await _sttAudio.invokeMethod('muteBeep');
      await _stt.stop();
    } catch (_) {}
    // थोड़ा सा इंतज़ार ताकि अंतिम शब्द result में आ जाएँ
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted || _closed || _mode != _VoiceMode.offline) return;

    final words = _lastRecognized.trim();
    if (words.isEmpty) {
      setState(() {
        _state = 'idle';
        _micLevel = 0.0;
        _statusLabel = 'कोई आवाज़ नहीं सुनी — फिर से दबाकर बोलें';
      });
      return;
    }

    await _handleOfflineUtterance(words);
  }

  Future<void> _handleOfflineUtterance(String words) async {
    setState(() {
      _state = 'thinking';
      _micLevel = 0.0;
      _statusLabel = 'सोच रहा हूँ…';
    });

    await widget.db.addAiMessage(channel: 'offline', role: 'user', text: words);
    final reply = await _offlineEngine.process(words);
    if (reply.dbChanged) {
      widget.onChanged?.call();
    }
    await widget.db.addAiMessage(
      channel: 'offline',
      role: 'assistant',
      text: reply.text,
      deepSeekQuery: reply.suggestDeepSeek ? reply.deepSeekQuery : null,
    );

    if (!mounted || _closed || _mode != _VoiceMode.offline) return;
    setState(() {
      _state = 'speaking';
      _statusLabel = 'बोल रहा हूँ… (नया सवाल पूछने के लिए गोला दबाएँ)';
    });
    try {
      await TtsVoice.apply(_tts, widget.db);
      await _tts.speak(TtsVoice.cleanForSpeech(reply.text));
    } catch (_) {}

    if (mounted && !_closed && !_isHolding && _mode == _VoiceMode.offline) {
      setState(() {
        _state = 'idle';
        _statusLabel = 'बोलने के लिए गोले को दबाकर रखें';
      });
    }
  }

  Future<void> _minimizeToBubble() async {
    if (_closed) return;
    final isApi = _mode == _VoiceMode.api;
    _closed = true;
    _isHolding = false;
    await _stopCurrentMode();
    await _apiSvc.dispose();
    await _stopForegroundService();
    AppUiBridge.instance.showBubble(isApi: isApi);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _isHolding = false;
    await _stopCurrentMode();
    await _apiSvc.dispose();
    await _stopForegroundService();
    if (mounted) Navigator.pop(context);
  }

  AiOrbState get _orbState {
    switch (_state) {
      case 'speaking':
        return AiOrbState.speaking;
      case 'listening':
      case 'thinking':
      case 'connecting':
        return AiOrbState.listening;
      default:
        return AiOrbState.idle;
    }
  }

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      _isHolding = false;
      try {
        _stt.stop();
      } catch (_) {}
      try {
        _tts.stop();
      } catch (_) {}
      _apiSvc.dispose();
      _stopForegroundService();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimizeToBubble();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(child: AmbientBackground()),
              // ऊपर Offline AI और API AI चुनने वाला टॉगल
              Positioned(
                top: 18,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A24),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _modeChip(
                          label: 'Offline AI',
                          icon: Icons.bolt_rounded,
                          selected: _mode == _VoiceMode.offline,
                          onTap: () => _switchMode(_VoiceMode.offline),
                        ),
                        const SizedBox(width: 4),
                        _modeChip(
                          label: 'API AI',
                          icon: Icons.auto_awesome_rounded,
                          selected: _mode == _VoiceMode.api,
                          onTap: () => _switchMode(_VoiceMode.api),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // बीच में Push-to-Talk Perplexity-स्टाइल एनिमेटेड Orb
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Listener(
                      onPointerDown: (_) => _onHoldStart(),
                      onPointerUp: (_) => _onHoldEnd(),
                      onPointerCancel: (_) => _onHoldEnd(),
                      child: AnimatedScale(
                        scale: _isHolding
                            ? (1.12 + _micLevel * 0.14)
                            : 1.0,
                        duration: const Duration(milliseconds: 140),
                        child: AiOrbIcon(
                          size: 132,
                          state: _orbState,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        _statusLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isHolding ? AppColors.cyan : AppColors.textSecondary,
                          fontSize: 13.5,
                          fontWeight: _isHolding ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // नीचे Close बटन
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _close,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.heroGradient : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
