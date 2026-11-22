import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'live_voice_service.dart';
import 'offline_ai_engine.dart';
import 'tts_voice.dart';
import 'widgets/ai_orb_icon.dart';

enum _VoiceMode { offline, api }

/// Perplexity-स्टाइल Live Voice AI स्क्रीन:
/// - ऊपर Offline AI और API AI में क्लिक करके स्विच करें
/// - बीच में Perplexity जैसा एनिमेटेड गोला (Orb)
/// - मोबाइल का Home बटन दबाने पर भी Foreground Service के साथ बैकग्राउंड में चलता रहता है
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

  late final LiveVoiceService _apiSvc = LiveVoiceService(db: widget.db, onState: _onApiState);
  late final OfflineAiEngine _offlineEngine = OfflineAiEngine(widget.db);
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  _VoiceMode _mode = _VoiceMode.offline;
  String _state = 'idle'; // connecting, listening, thinking, speaking, idle
  bool _muted = false;
  bool _closed = false;
  bool _offlineActive = false;
  double _micLevel = 0.0;
  String _statusLabel = 'बोलने के लिए तैयार…';

  @override
  void initState() {
    super.initState();
    _startForegroundService();
    _startOfflineMode();
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

  Future<void> _switchMode(_VoiceMode next) async {
    if (_mode == next || _closed) return;
    await _stopCurrentMode();
    if (!mounted || _closed) return;
    setState(() {
      _mode = next;
      _muted = false;
      _micLevel = 0.0;
    });
    if (next == _VoiceMode.offline) {
      await _startOfflineMode();
    } else {
      await _startApiMode();
    }
  }

  Future<void> _stopCurrentMode() async {
    _offlineActive = false;
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _apiSvc.stop();
    } catch (_) {}
  }

  Future<void> _startOfflineMode() async {
    setState(() {
      _state = 'connecting';
      _statusLabel = 'Offline Voice AI शुरू हो रहा है…';
    });

    final ok = await _stt.initialize(
      onError: (_) {
        if (_offlineActive && _mode == _VoiceMode.offline && !_muted && _state == 'listening') {
          Future.delayed(const Duration(milliseconds: 400), _listenOfflineAgain);
        }
      },
    );
    if (!mounted || _closed || _mode != _VoiceMode.offline) return;
    if (!ok) {
      setState(() {
        _state = 'idle';
        _statusLabel = 'माइक या स्पीच रिकग्निशन उपलब्ध नहीं है।';
      });
      return;
    }

    await TtsVoice.apply(_tts, widget.db);
    await _tts.awaitSpeakCompletion(true);
    _offlineActive = true;
    await _listenOfflineAgain();
  }

  Future<void> _listenOfflineAgain() async {
    if (!_offlineActive || _closed || _mode != _VoiceMode.offline || _muted || !mounted) return;
    setState(() {
      _state = 'listening';
      _statusLabel = 'Offline AI सुन रहा है…';
    });
    await _stt.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 2),
      onSoundLevelChange: (level) {
        if (mounted && _mode == _VoiceMode.offline) {
          setState(() => _micLevel = (level.clamp(0, 12) / 12).toDouble());
        }
      },
      onResult: (r) {
        if (!r.finalResult || _mode != _VoiceMode.offline || !_offlineActive) return;
        final words = r.recognizedWords.trim();
        if (words.isEmpty) {
          _listenOfflineAgain();
          return;
        }
        _handleOfflineUtterance(words);
      },
    );
  }

  Future<void> _handleOfflineUtterance(String words) async {
    await _stt.stop();
    if (!_offlineActive || _closed || _mode != _VoiceMode.offline) return;

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

    if (!_offlineActive || _closed || _mode != _VoiceMode.offline || !mounted) return;
    setState(() {
      _state = 'speaking';
      _statusLabel = 'बोल रहा हूँ… (रोकने के लिए गोले पर टैप करें)';
    });
    await _tts.speak(TtsVoice.cleanForSpeech(reply.text));
    if (_offlineActive && _mode == _VoiceMode.offline && !_muted && mounted) {
      await _listenOfflineAgain();
    }
  }

  Future<void> _startApiMode() async {
    setState(() {
      _state = 'connecting';
      _statusLabel = 'API Live AI से जुड़ रहा है…';
    });
    try {
      await _apiSvc.start();
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
        'listening' => 'API Live AI सुन रहा है…',
        'speaking' => 'API Live AI बोल रहा है… (टैप करके रोकें)',
        'connecting' => 'API Live AI से जुड़ रहा है…',
        _ => 'तैयार…',
      };
    });
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    if (_mode == _VoiceMode.api) {
      _apiSvc.setMuted(nextMuted);
    } else {
      if (nextMuted) {
        await _stt.stop();
        if (mounted) {
          setState(() {
            _state = 'idle';
            _statusLabel = 'माइक म्यूट है';
          });
        }
      } else {
        await _listenOfflineAgain();
      }
    }
  }

  Future<void> _interruptOrTapOrb() async {
    if (_mode == _VoiceMode.api) {
      if (_state == 'speaking') {
        await _apiSvc.interrupt();
      } else if (_state == 'idle') {
        await _startApiMode();
      }
    } else {
      if (_state == 'speaking') {
        await _tts.stop();
        if (_offlineActive && !_muted) await _listenOfflineAgain();
      } else if (_state == 'idle' && !_muted) {
        await _startOfflineMode();
      }
    }
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
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
      _offlineActive = false;
      _stt.stop();
      _tts.stop();
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
        if (!didPop) _close();
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
              // बीच में Perplexity-स्टाइल एनिमेटेड Orb
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _interruptOrTapOrb,
                      child: AnimatedScale(
                        scale: 1.0 + (_state == 'listening' ? _micLevel * 0.16 : 0.0),
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
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // नीचे Mute और Close बटन
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _circleButton(
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      onTap: _toggleMute,
                    ),
                    const SizedBox(width: 26),
                    _circleButton(icon: Icons.close_rounded, onTap: _close),
                  ],
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

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}
