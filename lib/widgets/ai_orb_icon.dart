import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Perplexity-जैसा गोल, स्फेरिकल "ब्रीदिंग" और वॉइस-रिएक्टिव orb।
///
/// states:
///  - idle      : धीमी, शांत साँस जैसी pulse (डिफ़ॉल्ट)
///  - listening : तेज़ नीली-सियान aurora wave
///  - speaking  : violet→cyan दोनों रंग ऊर्जावान रूप से धड़कते हैं
enum AiOrbState { idle, listening, speaking }

class AiOrbIcon extends StatefulWidget {
  final double size;
  final AiOrbState state;
  const AiOrbIcon({super.key, this.size = 22, this.state = AiOrbState.idle});

  @override
  State<AiOrbIcon> createState() => _AiOrbIconState();
}

class _AiOrbIconState extends State<AiOrbIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Duration _durationFor(AiOrbState s) {
    switch (s) {
      case AiOrbState.speaking:
        return const Duration(milliseconds: 520);
      case AiOrbState.listening:
        return const Duration(milliseconds: 900);
      case AiOrbState.idle:
        return const Duration(milliseconds: 1600);
    }
  }

  @override
  void didUpdateWidget(covariant AiOrbIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _c.duration = _durationFor(widget.state);
      _c.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final glowStrength = switch (widget.state) {
      AiOrbState.idle => 0.42,
      AiOrbState.listening => 0.65,
      AiOrbState.speaking => 0.92,
    };

    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final phase = _c.value * 2 * math.pi;
        final t = 0.5 + 0.5 * math.sin(phase); // 0..1 smooth wave
        final scale = 1.0 + (t * (widget.state == AiOrbState.speaking ? 0.24 : 0.16));
        final glow = glowStrength * (0.55 + t * 0.45);
        final angle = _c.value * 2 * math.pi;

        return SizedBox(
          width: widget.size * 1.9,
          height: widget.size * 1.9,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // बाहर की फैलती हुई Perplexity-स्टाइल glow रिंग
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size * 1.9,
                    height: widget.size * 1.9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.cyan.withOpacity(glow * 0.55),
                          AppColors.violet.withOpacity(glow * 0.18),
                          Colors.transparent,
                        ],
                        stops: const [0.15, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                // घूमता हुआ स्फेरिकल Perplexity-जैसा कोर
                Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          AppColors.cyan.withOpacity(0.98),
                          AppColors.violet.withOpacity(0.95),
                          AppColors.indigo.withOpacity(0.95),
                          AppColors.cyan.withOpacity(0.98),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan.withOpacity(glow),
                          blurRadius: 10 + (t * 8),
                          spreadRadius: 0.6,
                        ),
                      ],
                    ),
                    child: Container(
                      margin: EdgeInsets.all(widget.size * 0.16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.55 + t * 0.25),
                            AppColors.cyan.withOpacity(0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}
