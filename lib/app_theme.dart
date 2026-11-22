// ============================================================
// DESIGN SYSTEM & TELEGRAM-STYLE CONFETTI
// ============================================================
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0B0E14);
  static const surface = Color(0xFF161B26);
  static const surfaceSoft = Color(0xFF121721);
  static const surfaceElevated = Color(0xFF1B2130);

  static const violet = Color(0xFF8B5CF6);
  static const indigo = Color(0xFF5B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const blue = Color(0xFF2563EB); // Royal Blue for Study
  static const emerald = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const rose = Color(0xFFFB7185);
  static const pink = Color(0xFFF472B6);

  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFFA7B0C0);
  static const textMuted = Color(0xFF6F7A8C);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),
      Color(0xFF4F46E5),
      Color(0xFF0891B2),
      Color(0xFF22D3EE),
    ],
    stops: [0.0, 0.36, 0.72, 1.0],
  );
}

Color categoryColor(String category, {String? customHex}) {
  if (customHex != null && customHex.isNotEmpty) {
    try {
      return Color(int.parse(customHex.replaceAll('#', '0xFF')));
    } catch (_) {}
  }
  switch (category.toLowerCase()) {
    case 'study':
    case 'learning':
      return AppColors.blue;
    case 'work':
    case 'deep work':
      return AppColors.cyan;
    case 'health':
      return AppColors.emerald;
    case 'exercise':
    case 'workout':
      return const Color(0xFF10B981);
    case 'personal':
      return AppColors.pink;
    case 'family':
      return AppColors.rose;
    case 'other':
      return AppColors.amber;
    default:
      return AppColors.violet;
  }
}

Color priorityColor(int priority) {
  switch (priority) {
    case 4:
      return AppColors.rose;
    case 3:
      return AppColors.amber;
    case 2:
      return AppColors.blue;
    default:
      return AppColors.textMuted;
  }
}

class ConfettiParticle {
  late double x, y, vx, vy, size, rotation, rotationSpeed, opacity;
  late Color color;

  ConfettiParticle({required Offset origin}) {
    final rand = Random();
    final angle = rand.nextDouble() * 2 * pi;
    final speed = rand.nextDouble() * 200 + 100;
    x = origin.dx;
    y = origin.dy;
    vx = cos(angle) * speed;
    vy = sin(angle) * speed - 50;
    size = rand.nextDouble() * 6 + 4;
    rotation = rand.nextDouble() * 2 * pi;
    rotationSpeed = (rand.nextDouble() - 0.5) * 10;
    opacity = 1.0;
    final palette = [
      AppColors.emerald,
      AppColors.cyan,
      AppColors.blue,
      AppColors.amber,
      AppColors.pink,
      Colors.white,
    ];
    color = palette[rand.nextInt(palette.length)];
  }

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 260 * dt;
    rotation += rotationSpeed * dt;
    opacity = max(0.0, opacity - dt * 1.3);
  }
}

class ConfettiOverlayWidget extends StatefulWidget {
  final Offset origin;
  final VoidCallback onFinished;

  const ConfettiOverlayWidget({super.key, required this.origin, required this.onFinished});

  @override
  State<ConfettiOverlayWidget> createState() => _ConfettiOverlayWidgetState();
}

class _ConfettiOverlayWidgetState extends State<ConfettiOverlayWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<ConfettiParticle> particles;

  @override
  void initState() {
    super.initState();
    particles = List.generate(45, (_) => ConfettiParticle(origin: widget.origin));
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    DateTime lastTime = DateTime.now();

    _controller.addListener(() {
      final now = DateTime.now();
      final dt = (now.difference(lastTime).inMicroseconds) / 1000000.0;
      lastTime = now;
      for (final p in particles) {
        p.update(dt);
      }
      setState(() {});
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(particles),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  _ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.7), const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? glowColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.borderRadius,
    this.color,
    this.glowColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    final glow = glowColor ?? AppColors.violet;

    Widget content = ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: color != null
                ? [color!.withOpacity(0.88), color!.withOpacity(0.68)]
                : [
                    const Color(0xD91E2538),
                    const Color(0xCC121724),
                  ],
          ),
          borderRadius: radius,
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
            width: 1.05,
          ),
          boxShadow: const [],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap != null || onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          splashColor: AppColors.cyan.withOpacity(0.16),
          highlightColor: Colors.white.withOpacity(0.06),
          onTap: onTap,
          onLongPress: onLongPress,
          child: content,
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(padding: margin, child: content),
    );
  }
}

class GlowBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const GlowBadge({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SectionLabel(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
          ),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -180,
              right: -160,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.violet.withOpacity(0.14), Colors.transparent]),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: -220,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.cyan.withOpacity(0.08), Colors.transparent]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlobalSettingsButton extends StatelessWidget {
  final VoidCallback onTap;
  const GlobalSettingsButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xEB151A24),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.settings_rounded, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
