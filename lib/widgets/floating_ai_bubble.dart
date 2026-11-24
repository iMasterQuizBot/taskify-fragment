import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_database.dart';
import '../app_theme.dart';
import '../app_ui_bridge.dart';
import '../live_voice_screen.dart';
import '../live_voice_service.dart';
import '../offline_ai_engine.dart';
import '../tts_voice.dart';
import 'ai_orb_icon.dart';

/// ~1cm रेडियस वाला फ्लोटिंग एनिमेटेड AI बबल:
/// - ऊपर 3 छोटे बटन: [Offline] [API] [✕]
/// - नीचे एनिमेटेड ग्लोइंग सर्कल (Hold to Speak + Drag anywhere + Tap to expand)
class FloatingAiBubble extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback onDatabaseChanged;

  const FloatingAiBubble({
    super.key,
    required this.db,
    required this.onDatabaseChanged,
  });

  @override
  State<FloatingAiBubble> createState() => _FloatingAiBubbleState();
}

class _FloatingAiBubbleState extends State<FloatingAiBubble> {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  late final OfflineAiEngine _offlineEngine = OfflineAiEngine(widget.db);
  LiveVoiceService? _apiSvc;

  Offset _pos = const Offset(20, 140);
  bool _initializedPos = false;
  bool _sttReady = false;
  bool _isHolding = false;
  String _state = 'idle'; // idle, connecting, listening, thinking, speaking
  double _micLevel = 0.0;
  String _recognized = '';

  @override
  void initState() {
    super.initState();
    AppUiBridge.instance.bubbleIsApiMode.addListener(_onModeChanged);
    AppUiBridge.instance.bubbleVisible.addListener(_onVisibilityChanged);
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await TtsVoice.apply(_tts, widget.db);
      await _tts.awaitSpeakCompletion(true);
      _sttReady = await _stt.initialize();
    } catch (_) {}
  }

  void _onVisibilityChanged() {
    if (!AppUiBridge.instance.bubbleVisible.value) {
      _stopAll();
    } else if (AppUiBridge.instance.bubbleIsApiMode.value) {
      _ensureApiService();
    }
  }

  void _onModeChanged() {
    _stopAll();
    if (AppUiBridge.instance.bubbleVisible.value && AppUiBridge.instance.bubbleIsApiMode.value) {
      _ensureApiService();
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureApiService() async {
    if (_apiSvc != null) return;
    final svc = LiveVoiceService(
      db: widget.db,
      onState: (s) {
        if (!mounted) return;
        if (s == 'stopped') return;
        if (s.startsWith('error:')) {
          setState(() => _state = 'idle');
          return;
        }
        setState(() => _state = s);
      },
      onDatabaseChanged: widget.onDatabaseChanged,
    );
    _apiSvc = svc;
    setState(() => _state = 'connecting');
    try {
      await svc.start();
      if (mounted) setState(() => _state = 'idle');
    } catch (e) {
      if (mounted) {
        setState(() => _state = 'idle');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _stopAll() async {
    _isHolding = false;
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    if (_apiSvc != null) {
      try {
        await _apiSvc!.dispose();
      } catch (_) {}
      _apiSvc = null;
    }
    if (mounted) {
      setState(() {
        _state = 'idle';
        _micLevel = 0.0;
      });
    }
  }

  Future<void> _onHoldStart() async {
    if (_isHolding) return;
    _isHolding = true;
    _recognized = '';
    final isApi = AppUiBridge.instance.bubbleIsApiMode.value;

    if (isApi) {
      await _ensureApiService();
      await _apiSvc?.interrupt();
      _apiSvc?.setMuted(false);
      if (mounted) setState(() => _state = 'listening');
      return;
    }

    try {
      await _tts.stop();
    } catch (_) {}
    if (!_sttReady) _sttReady = await _stt.initialize();
    if (!_sttReady) {
      _isHolding = false;
      return;
    }
    if (mounted) setState(() => _state = 'listening');
    await _stt.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(minutes: 2),
      onSoundLevelChange: (lvl) {
        if (mounted && _isHolding) {
          setState(() => _micLevel = (lvl.clamp(0, 12) / 12).toDouble());
        }
      },
      onResult: (r) {
        if (r.recognizedWords.trim().isNotEmpty) {
          _recognized = r.recognizedWords.trim();
        }
      },
    );
  }

  Future<void> _onHoldEnd() async {
    if (!_isHolding) return;
    _isHolding = false;
    final isApi = AppUiBridge.instance.bubbleIsApiMode.value;

    if (isApi) {
      _apiSvc?.endUserTurn();
      if (mounted) {
        setState(() {
          _state = 'thinking';
          _micLevel = 0.0;
        });
      }
      return;
    }

    try {
      await _stt.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    final words = _recognized.trim();
    if (words.isEmpty) {
      setState(() {
        _state = 'idle';
        _micLevel = 0.0;
      });
      return;
    }

    setState(() {
      _state = 'thinking';
      _micLevel = 0.0;
    });

    await widget.db.addAiMessage(channel: 'offline', role: 'user', text: words);
    final reply = await _offlineEngine.process(words);
    if (reply.dbChanged) widget.onDatabaseChanged();
    await widget.db.addAiMessage(channel: 'offline', role: 'assistant', text: reply.text);

    if (!mounted) return;
    setState(() => _state = 'speaking');
    try {
      await TtsVoice.apply(_tts, widget.db);
      await _tts.speak(TtsVoice.cleanForSpeech(reply.text));
    } catch (_) {}
    if (mounted && !_isHolding) setState(() => _state = 'idle');
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
    AppUiBridge.instance.bubbleIsApiMode.removeListener(_onModeChanged);
    AppUiBridge.instance.bubbleVisible.removeListener(_onVisibilityChanged);
    _stopAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppUiBridge.instance.bubbleVisible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();

        final size = MediaQuery.of(context).size;
        if (!_initializedPos) {
          _pos = Offset(size.width - 148, size.height - 230);
          _initializedPos = true;
        }

        final isApi = AppUiBridge.instance.bubbleIsApiMode.value;

        return Positioned(
          left: _pos.dx.clamp(6.0, size.width - 138),
          top: _pos.dy.clamp(40.0, size.height - 150),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ऊपर 3 छोटे बटन: [Offline] [API] [✕]
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xE6141926),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniBtn(
                        label: 'Offline',
                        active: !isApi,
                        color: AppColors.cyan,
                        onTap: () => AppUiBridge.instance.bubbleIsApiMode.value = false,
                      ),
                      const SizedBox(width: 4),
                      _MiniBtn(
                        label: 'API',
                        active: isApi,
                        color: AppColors.violet,
                        onTap: () => AppUiBridge.instance.bubbleIsApiMode.value = true,
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          AppUiBridge.instance.hideBubble();
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.rose.withOpacity(0.22),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.rose.withOpacity(0.6)),
                          ),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // ~1 cm रेडियस वाला एनिमेटेड सर्कल (Drag + Hold to Speak + Tap to Expand)
                GestureDetector(
                  onPanUpdate: (d) {
                    setState(() {
                      _pos += d.delta;
                    });
                  },
                  onLongPressStart: (_) => _onHoldStart(),
                  onLongPressEnd: (_) => _onHoldEnd(),
                  onTap: () async {
                    await _stopAll();
                    AppUiBridge.instance.hideBubble();
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveVoiceScreen(
                          db: widget.db,
                          onChanged: widget.onDatabaseChanged,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isApi ? AppColors.violet : AppColors.cyan).withOpacity(0.45),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: AnimatedScale(
                      scale: _isHolding ? (1.0 + (_micLevel * 0.15)) : 1.0,
                      duration: const Duration(milliseconds: 90),
                      child: AiOrbIcon(
                        size: 68,
                        state: _orbState,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.28) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.white.withOpacity(0.15)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
