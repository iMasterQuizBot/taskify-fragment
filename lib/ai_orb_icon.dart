import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Perplexity-जैसा गोल, स्फेरिकल "ब्रीदिंग" bubble — पूरे ऐप में AI के हर
/// entry-point (टॉप आइकन + नीचे AI tab) पर यही एक जैसा दिखेगा, ताकि यूज़र को
/// एक ही consistent "live AI" पहचान मिले।
///
/// states:
///  - idle      : धीमी, शांत साँस जैसी pulse (डिफ़ॉल्ट)
///  - listening : हल्की तेज़ नीली glow
///  - speaking  : violet→cyan दोनों रंग एक साथ धड़कते हैं (ज़्यादा जीवंत)
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
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Duration _durationFor(AiOrbState s) {
    switch (s) {
      case AiOrbState.speaking:
        return const Duration(milliseconds: 420);
      case AiOrbState.listening:
        return const Duration(milliseconds: 750);
      case AiOrbState.idle:
        return const Duration(milliseconds: 1400);
    }
  }

  @override
  void didUpdateWidget(covariant AiOrbIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _c.duration = _durationFor(widget.state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glowStrength = switch (widget.state) {
      AiOrbState.idle => 0.35,
      AiOrbState.listening => 0.55,
      AiOrbState.speaking => 0.85,
    };

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value; // 0..1
        final scale = 1.0 + (t * 0.18);
        final glow = glowStrength * (0.5 + t * 0.5);
        return SizedBox(
          width: widget.size * 1.9,
          height: widget.size * 1.9,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // बाहर की फैलती हुई glow रिंग
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size * 1.9,
                    height: widget.size * 1.9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.cyan.withOpacity(glow * 0.5),
                          AppColors.violet.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // ठोस केंद्र का गोला (स्फेरिकल)
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.violet.withOpacity(0.95),
                        AppColors.cyan.withOpacity(0.95),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withOpacity(glow),
                        blurRadius: 10 + (t * 6),
                        spreadRadius: 0.5,
                      ),
                    ],
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
