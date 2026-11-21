import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'live_voice_service.dart';

/// Live बातचीत: बस गोला दिखता है। बोलें, AI आवाज़ में जवाब देगा। बीच में बोलकर उसे रोक सकते हैं।
class LiveVoiceScreen extends StatefulWidget {
  final AppDatabase db;
  const LiveVoiceScreen({super.key, required this.db});

  @override
  State<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends State<LiveVoiceScreen> with SingleTickerProviderStateMixin {
  late final LiveVoiceService _svc = LiveVoiceService(db: widget.db, onState: _onState);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  String _state = 'connecting';
  bool _muted = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _svc.start();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      Navigator.pop(context);
    }
  }

  void _onState(String s) {
    if (!mounted || _closed) return;
    if (s == 'stopped') return;
    if (s.startsWith('error:')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.substring(6))));
      _close();
      return;
    }
    setState(() => _state = s);
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await _svc.dispose();
    if (mounted) Navigator.pop(context);
  }

  Color get _color {
    switch (_state) {
      case 'speaking':
        return AppColors.emerald;
      case 'listening':
        return AppColors.cyan;
      case 'connecting':
        return AppColors.violet;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    if (!_closed) {
      _closed = true;
      _svc.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        if (!_closed) {
          _closed = true;
          _svc.dispose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final size = 140 + 26 * _pulse.value;
                    return GestureDetector(
                      onTap: () {
                        // गोले पर टैप = AI को अभी रोकना (interrupt)
                        if (_state == 'speaking') _svc.interrupt();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [_color.withOpacity(0.95), _color.withOpacity(0.2), Colors.transparent],
                            stops: const [0.0, 0.6, 1.0],
                          ),
                          boxShadow: [BoxShadow(color: _color.withOpacity(0.5), blurRadius: 60, spreadRadius: 10)],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _circleButton(
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      onTap: () {
                        setState(() => _muted = !_muted);
                        _svc.setMuted(_muted);
                      },
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
