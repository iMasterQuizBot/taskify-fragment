import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ai_service.dart';
import 'app_theme.dart';

enum _VoiceState { listening, thinking, speaking, idle }

/// बिना टेक्स्ट वाला voice mode।
/// आप बोलते हैं, जब चुप होते हैं (pause) तो बात AI को जाती है, और जवाब बोलकर सुनाया जाता है।
/// स्क्रीन पर सिर्फ़ रोशनी वाला orb दिखता है, बातचीत लिखी नहीं दिखती।
class VoiceOrbScreen extends StatefulWidget {
  final AiService ai;
  final String assistantName;
  final VoidCallback onChanged;

  const VoiceOrbScreen({
    super.key,
    required this.ai,
    required this.assistantName,
    required this.onChanged,
  });

  @override
  State<VoiceOrbScreen> createState() => _VoiceOrbScreenState();
}

class _VoiceOrbScreenState extends State<VoiceOrbScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  _VoiceState _state = _VoiceState.idle;
  double _level = 0; // mic की आवाज़ (0 से 1 के आस-पास)
  bool _active = false;
  String _userMessage = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _active = false;
    _stt.stop();
    _tts.stop();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _stt.initialize(
      onError: (_) {
        if (_active && _state == _VoiceState.listening) _listenAgain();
      },
    );
    if (!ok) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
    _active = true;
    _listenAgain();
  }

  void _setState(_VoiceState s) {
    if (mounted) setState(() => _state = s);
  }

  Future<void> _listenAgain() async {
    if (!_active || !mounted) return;
    _setState(_VoiceState.listening);
    await _stt.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 3), // 3 सेकंड चुप रहने पर बात खत्म
      onSoundLevelChange: (level) {
        if (mounted) setState(() => _level = (level.clamp(0, 12) / 12).toDouble());
      },
      onResult: (r) {
        if (!r.finalResult) return;
        final words = r.recognizedWords.trim();
        if (words.isEmpty) {
          _listenAgain();
          return;
        }
        _handleUtterance(words);
      },
    );
  }

  Future<void> _handleUtterance(String words) async {
    await _stt.stop();
    if (!_active) return;
    _userMessage = words; // सिर्फ़ यादरखने के लिए, UI में नहीं दिखता
    _setState(_VoiceState.thinking);
    try {
      final reply = await widget.ai.send(text: words);
      widget.onChanged();
      if (!_active) return;
      _setState(_VoiceState.speaking);
      await _tts.speak(reply);
    } catch (e) {
      if (!_active) return;
      _setState(_VoiceState.speaking);
      await _tts.speak(e.toString().replaceFirst('Exception: ', ''));
    }
    if (_active) _listenAgain();
  }

  Color get _color {
    switch (_state) {
      case _VoiceState.listening:
        return AppColors.cyan;
      case _VoiceState.thinking:
        return AppColors.violet;
      case _VoiceState.speaking:
        return AppColors.emerald;
      case _VoiceState.idle:
        return AppColors.textMuted;
    }
  }

  void _stop() {
    _active = false;
    _stt.stop();
    _tts.stop();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final base = 130 + 20 * _pulse.value;
                  final size = base + (_state == _VoiceState.listening ? _level * 80 : 0);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [_color.withOpacity(0.95), _color.withOpacity(0.2), Colors.transparent],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(color: _color.withOpacity(0.5), blurRadius: 60, spreadRadius: 10),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _stop,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
