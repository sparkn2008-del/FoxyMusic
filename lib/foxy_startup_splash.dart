import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

const _kSplashAsset = 'assets/images/foxy_splash.png';
const _kSplashDuration = Duration(seconds: 4);
const _kGold = Color(0xFFFFF0D4);
const _kWarmGlow = Color(0xFFFFE9B8);

/// Cinematic cold start using the real Foxy emblem art — no hand-drawn vector fox.
class FoxyStartupSplash extends StatefulWidget {
  const FoxyStartupSplash({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<FoxyStartupSplash> createState() => _FoxyStartupSplashState();
}

class _FoxyStartupSplashState extends State<FoxyStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kSplashDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onFinished();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return (t - a) / (b - a);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final emblemSize = math.min(screen.width * 0.62, 300.0);
    final center = Offset(screen.width / 2, screen.height / 2);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;

        final wake = Curves.easeOutCubic.transform(_seg(t, 0.12, 0.40));
        final turn = Curves.easeInOutCubic.transform(_seg(t, 0.38, 0.52));
        final run = Curves.easeInCubic.transform(_seg(t, 0.50, 0.94));
        final star = Curves.easeInOut.transform(_seg(t, 0.30, 0.84));
        final fadeOut = Curves.easeIn.transform(_seg(t, 0.90, 1.0));
        final overlay = 1.0 - fadeOut;

        final breathe = 1.0 + math.sin(t * math.pi * 2.8) * 0.016 * (1 - wake * 0.85);
        final runBob = math.sin(run * math.pi * 11) * 11 * (1 - run * 0.25);
        final runDx = run * (screen.width + emblemSize * 1.2);
        return IgnorePointer(
          ignoring: fadeOut > 0.82,
          child: Material(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: overlay,
                  child: CustomPaint(
                    painter: _AmbientStarsPainter(phase: t),
                  ),
                ),
                if (run > 0.08)
                  Opacity(
                    opacity: overlay * run * 0.55,
                    child: CustomPaint(
                      painter: _SpeedLinesPainter(
                        origin: center + Offset(runDx * 0.35, runBob),
                        strength: run,
                      ),
                    ),
                  ),
                if (star > 0.02)
                  _RisingMusicStar(
                    progress: star,
                    screen: screen,
                    emblemCenter: center,
                    opacity: overlay,
                  ),
                Center(
                  child: Transform.translate(
                    offset: Offset(runDx, runBob),
                    child: _FoxyEmblemStage(
                      size: emblemSize,
                      wake: wake,
                      turn: turn,
                      run: run,
                      breathe: breathe,
                      opacity: overlay,
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

/// The real logo with bloom, wake brighten, 3D turn, and motion trails.
class _FoxyEmblemStage extends StatelessWidget {
  const _FoxyEmblemStage({
    required this.size,
    required this.wake,
    required this.turn,
    required this.run,
    required this.breathe,
    required this.opacity,
  });

  final double size;
  final double wake;
  final double turn;
  final double run;
  final double breathe;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final brightness = lerpDouble(0.62, 1.18, wake)!;
    final bloom = lerpDouble(0.25, 1.0, wake)!;
    final scale = breathe * lerpDouble(0.90, 1.10, wake)!;
    final rotateY = turn * -1.45;
    final rotateZ =
        lerpDouble(-0.06, 0.0, wake)! + math.sin(run * math.pi * 10) * 0.07 * run;
    final squashY = 1.0 + math.sin(run * math.pi * 10) * 0.04 * run;

    Widget emblem = _EmblemImage(
      size: size,
      brightness: brightness,
      bloom: bloom,
    );

    if (wake > 0.12) {
      emblem = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          emblem,
          _WakeGlintOverlay(size: size, progress: wake),
        ],
      );
    }

    emblem = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateY(rotateY)
        ..rotateZ(rotateZ)
        ..scale(scale, scale * squashY),
      child: emblem,
    );

    if (run > 0.05) {
      emblem = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 5; i >= 1; i--)
            Opacity(
              opacity: opacity * (1 - run) * 0.14 * (i / 5),
              child: Transform.translate(
                offset: Offset(-i * 22.0 * run, i * 1.5),
                child: Transform.scale(
                  scale: 1 - i * 0.018,
                  child: _EmblemImage(
                    size: size,
                    brightness: brightness * 0.85,
                    bloom: bloom * 0.6,
                  ),
                ),
              ),
            ),
          Opacity(opacity: opacity, child: emblem),
        ],
      );
    } else {
      emblem = Opacity(opacity: opacity, child: emblem);
    }

    return SizedBox(width: size * 1.2, height: size * 1.2, child: emblem);
  }
}

class _EmblemImage extends StatelessWidget {
  const _EmblemImage({
    required this.size,
    required this.brightness,
    required this.bloom,
  });

  final double size;
  final double brightness;
  final double bloom;

  @override
  Widget build(BuildContext context) {
    final art = Image.asset(
      _kSplashAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (bloom > 0.15)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 28 * bloom,
              sigmaY: 28 * bloom,
            ),
            child: Opacity(
              opacity: 0.42 * bloom,
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  _kWarmGlow,
                  BlendMode.srcIn,
                ),
                child: art,
              ),
            ),
          ),
        if (bloom > 0.35)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12 * bloom, sigmaY: 12 * bloom),
            child: Opacity(
              opacity: 0.55 * bloom,
              child: art,
            ),
          ),
        ColorFiltered(
          colorFilter: ColorFilter.matrix(_brightnessMatrix(brightness)),
          child: art,
        ),
        if (bloom > 0.5)
          IgnorePointer(
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kWarmGlow.withValues(alpha: 0.14 * bloom),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Soft eye glints + chest glow when the emblem wakes (over the artwork).
class _WakeGlintOverlay extends StatelessWidget {
  const _WakeGlintOverlay({required this.size, required this.progress});

  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    final eyeL = Offset(size * 0.395, size * 0.355);
    final eyeR = Offset(size * 0.515, size * 0.348);

    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _WakeGlintPainter(
            eyeL: eyeL,
            eyeR: eyeR,
            progress: p,
          ),
        ),
      ),
    );
  }
}

class _WakeGlintPainter extends CustomPainter {
  const _WakeGlintPainter({
    required this.eyeL,
    required this.eyeR,
    required this.progress,
  });

  final Offset eyeL;
  final Offset eyeR;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    for (final eye in [eyeL, eyeR]) {
      final r = lerpDouble(0.0, 5.5, progress)!;
      canvas.drawCircle(
        eye,
        r * 2.8,
        Paint()
          ..color = _kWarmGlow.withValues(alpha: 0.22 * progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        eye,
        r,
        Paint()..color = _kGold.withValues(alpha: 0.95 * progress),
      );
    }

    final chest = Offset(size.width * 0.44, size.height * 0.48);
    canvas.drawCircle(
      chest,
      18 * progress,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _kWarmGlow.withValues(alpha: 0.2 * progress),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: chest, radius: 22)),
    );
  }

  @override
  bool shouldRepaint(covariant _WakeGlintPainter old) => old.progress != progress;
}

class _RisingMusicStar extends StatelessWidget {
  const _RisingMusicStar({
    required this.progress,
    required this.screen,
    required this.emblemCenter,
    required this.opacity,
  });

  final double progress;
  final Size screen;
  final Offset emblemCenter;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final start = emblemCenter + Offset(screen.width * 0.06, screen.height * 0.04);
    final end = Offset(screen.width * 0.5, screen.height * 0.05);
    final pos = Offset.lerp(start, end, progress)!;
    final twinkle = 0.55 + 0.45 * math.sin(progress * math.pi * 7);
    final scale = lerpDouble(1.15, 0.45, progress)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 1; i <= 6; i++)
          Positioned(
            left: pos.dx - 4,
            top: pos.dy + i * 11,
            child: Opacity(
              opacity: opacity * (1 - progress) * 0.2 * (1 - i / 7),
              child: Icon(
                Icons.star_rounded,
                size: 6 + i * 1.8,
                color: _kWarmGlow.withValues(alpha: 0.65),
              ),
            ),
          ),
        Positioned(
          left: pos.dx - 28,
          top: pos.dy - 28,
          child: Opacity(
            opacity: opacity * (1 - progress * 0.45) * twinkle,
            child: Transform.rotate(
              angle: progress * math.pi * 0.35,
              child: Transform.scale(
                scale: scale,
                child: const _MusicStarNote(size: 56),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Polished glowing note (layered blurs + gradient fill).
class _MusicStarNote extends StatelessWidget {
  const _MusicStarNote({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _StarBurstPainter(),
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Icon(
              Icons.music_note_rounded,
              size: size * 0.52,
              color: _kWarmGlow.withValues(alpha: 0.5),
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), _kGold, _kWarmGlow],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Icon(
              Icons.music_note_rounded,
              size: size * 0.48,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarBurstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final p = Paint()
        ..shader = LinearGradient(
          begin: Alignment.center,
          end: Alignment(math.cos(a), math.sin(a)),
          colors: [
            _kWarmGlow.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.5));
      canvas.drawLine(
        c,
        c + Offset(math.cos(a) * size.width * 0.42, math.sin(a) * size.width * 0.42),
        p..strokeWidth = 2.2..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AmbientStarsPainter extends CustomPainter {
  const _AmbientStarsPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(11);
    final p = Paint();
    for (var i = 0; i < 48; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final pulse = 0.25 +
          0.75 * (0.5 + 0.5 * math.sin(phase * math.pi * 4 + i * 1.3));
      p.color = Colors.white.withValues(alpha: 0.045 * pulse);
      final r = 0.8 + rnd.nextDouble() * 1.6;
      canvas.drawCircle(Offset(x, y), r, p);
      if (i % 9 == 0) {
        _drawSparkle(canvas, Offset(x, y), 3 + pulse * 2, pulse * 0.35);
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, double a) {
    final p = Paint()
      ..color = _kWarmGlow.withValues(alpha: a)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), p);
    canvas.drawLine(c + Offset(0, -r), c + Offset(0, r), p);
  }

  @override
  bool shouldRepaint(covariant _AmbientStarsPainter old) => old.phase != phase;
}

class _SpeedLinesPainter extends CustomPainter {
  const _SpeedLinesPainter({required this.origin, required this.strength});

  final Offset origin;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final rnd = math.Random(3);
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (var i = 0; i < 14; i++) {
      final y = origin.dy + (rnd.nextDouble() - 0.5) * 120;
      final len = 40 + rnd.nextDouble() * 90;
      final x0 = origin.dx - len * strength;
      p.color = _kWarmGlow.withValues(alpha: 0.12 * strength * (0.4 + rnd.nextDouble()));
      canvas.drawLine(Offset(x0, y), Offset(origin.dx - 12, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) =>
      old.origin != origin || old.strength != strength;
}

List<double> _brightnessMatrix(double b) {
  return <double>[
    b, 0, 0, 0, 0,
    0, b, 0, 0, 0,
    0, 0, b, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Wraps home and plays splash once per cold start.
class FoxyAppLaunchGate extends StatefulWidget {
  const FoxyAppLaunchGate({super.key, required this.child});

  final Widget child;

  @override
  State<FoxyAppLaunchGate> createState() => _FoxyAppLaunchGateState();
}

class _FoxyAppLaunchGateState extends State<FoxyAppLaunchGate> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          FoxyStartupSplash(
            onFinished: () {
              if (mounted) setState(() => _showSplash = false);
            },
          ),
      ],
    );
  }
}
