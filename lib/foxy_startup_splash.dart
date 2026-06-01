import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _kSplashDuration = Duration(milliseconds: 1100);

/// Cold-start splash: simple Foxy-style black screen with restrained branding.
class FoxyStartupSplash extends StatefulWidget {
  const FoxyStartupSplash({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<FoxyStartupSplash> createState() => _FoxyStartupSplashState();
}

class _FoxyStartupSplashState extends State<FoxyStartupSplash> {
  Timer? _finishFallback;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _finishFallback = Timer(_kSplashDuration, _finish);
  }

  @override
  void dispose() {
    _finishFallback?.cancel();
    super.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _finishFallback?.cancel();
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/foxy_logo.png',
              width: 78,
              height: 78,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 18),
            const Text(
              'FoxyMusic',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deep black field with subtle white vignette pulse.
class _SplashBackdropPainter extends CustomPainter {
  _SplashBackdropPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pulse = 0.04 + 0.03 * math.sin(phase * math.pi * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0.0, 0.15),
          radius: 1.1,
          colors: [
            const Color(0xFF0A0A0A),
            const Color(0xFF000000),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.85, 0.35),
          radius: 0.55,
          colors: [
            Colors.white.withValues(alpha: pulse),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashBackdropPainter old) => old.phase != phase;
}

/// Glowing white melody trails racing right (ahead of the fox).
class _MelodyChasePainter extends CustomPainter {
  _MelodyChasePainter({required this.phase, required this.screen});

  final double phase;
  final Size screen;

  @override
  void paint(Canvas canvas, Size size) {
    final chase = Curves.easeOutCubic.transform(_seg(phase, 0.28, 0.92));
    if (chase <= 0) return;

    final baseY = size.height * 0.46;
    final leadX = size.width * (0.48 + chase * 0.78);

    for (var i = 0; i < 10; i++) {
      final lag = i * 0.038;
      final noteT = (chase - lag).clamp(0.0, 1.0);
      if (noteT <= 0) continue;

      final x =
          leadX - noteT * size.width * 0.32 + math.sin(phase * 10 + i) * 10;
      final y =
          baseY + math.sin(phase * math.pi * 3.8 + i * 0.72) * 34 - i * 2.6;
      final glow = noteT * (0.55 + 0.45 * math.sin(phase * math.pi * 5 + i));

      _drawGlowNote(canvas, Offset(x, y), 10 + i * 0.35, glow);
    }

  }

  void _drawGlowNote(Canvas canvas, Offset c, double size, double intensity) {
    final core = Colors.white.withValues(alpha: (0.85 * intensity).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      size * 0.9,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(c + Offset(size * 0.2, size * 0.25), size * 0.32, Paint()..color = core);
    final stem = Path()
      ..moveTo(c.dx, c.dy + size * 0.12)
      ..lineTo(c.dx + size * 0.05, c.dy - size * 0.7);
    canvas.drawPath(
      stem,
      Paint()
        ..color = core
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.14
        ..strokeCap = StrokeCap.round,
    );
  }

  double _seg(double t, double a, double b) {
    if (t <= a) return 0.0;
    if (t >= b) return 1.0;
    return (t - a) / (b - a);
  }

  @override
  bool shouldRepaint(covariant _MelodyChasePainter old) =>
      old.phase != phase || old.screen != screen;
}

/// Procedural side-view fox with perspective shading (3D-style, no external model).
class _FoxChasePainter extends CustomPainter {
  _FoxChasePainter({required this.phase, required this.screen});

  final double phase;
  final Size screen;

  @override
  void paint(Canvas canvas, Size size) {
    _SplashBackdropPainter(phase: phase).paint(canvas, size);
    _MelodyChasePainter(phase: phase, screen: screen).paint(canvas, size);

    final groundY = size.height * 0.56;
    final foxScale = math.min(size.width, size.height) * 0.24;
    final centerX = _foxCenterX(size.width);
    final center = Offset(centerX, size.height * 0.56);

    final pose = _foxPose(phase);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(pose.tilt);
    canvas.scale(
      foxScale * pose.scale * pose.squashX,
      foxScale * pose.scale * 0.92 * pose.squashY,
    );

    if (pose.running) {
      _drawRunSmears(canvas, pose.runCycle);
    }
    _drawGroundShadow(canvas, pose.runCycle, groundY - center.dy);

    if (pose.sleeping) {
      _drawSleepingFox(canvas, pose.breath);
    } else if (pose.waking) {
      _drawWakingFox(canvas, pose.wakeT);
    } else {
      _drawRunningFox(canvas, pose.runCycle, pose.mouthGlow);
    }

    canvas.restore();
  }

  _FoxPose _foxPose(double t) {
    if (t < 0.26) {
      final breath = 0.5 + 0.5 * math.sin(t * math.pi * 6);
      return _FoxPose(
        sleeping: true,
        breath: breath,
        scale: 0.95 + breath * 0.03,
        tilt: -0.08,
      );
    }
    if (t < 0.44) {
      final wakeT = Curves.easeOutBack.transform(_seg(t, 0.26, 0.44));
      return _FoxPose(
        waking: true,
        wakeT: wakeT,
        scale: 0.92 + wakeT * 0.14,
        tilt: -0.05 + wakeT * 0.05,
      );
    }
    final runPhase = Curves.easeInCubic.transform(_seg(t, 0.44, 0.94));
    final runCycle = (runPhase * 16) % 1.0;
    final mouthGlow = _seg(t, 0.42, 0.54);
    final bob = math.sin(runCycle * math.pi * 2);
    return _FoxPose(
      running: true,
      runCycle: runCycle,
      scale: 1.05 + runPhase * 0.08,
      tilt: 0.02 + 0.09 * bob,
      squashX: 1.0 + 0.08 * bob,
      squashY: 1.0 - 0.05 * bob.abs(),
      mouthGlow: mouthGlow,
    );
  }

  double _foxCenterX(double width) {
    if (phase < 0.26) return width * 0.32;
    if (phase < 0.44) {
      final w = Curves.easeOut.transform(_seg(phase, 0.26, 0.44));
      return ui.lerpDouble(width * 0.32, width * 0.36, w)!;
    }
    final run = Curves.easeInCubic.transform(_seg(phase, 0.44, 0.94));
    return width * (0.36 + run * 0.92);
  }

  void _drawGroundShadow(Canvas canvas, double runCycle, double dy) {
    final stretch = 1.0 + 0.15 * math.sin(runCycle * math.pi * 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, dy),
        width: 1.42 * stretch,
        height: 0.18,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  void _drawSleepingFox(Canvas canvas, double breath) {
    final y = 0.03 + breath * 0.018;
    _drawTail(
      canvas,
      Offset(0.62, y + 0.06),
      curled: true,
      thickness: 0.18,
      alpha: 0.34,
    );
    _drawBody(
      canvas,
      center: Offset(0.02, y + 0.1),
      stretch: 0.96,
      crouch: 0.24,
      alpha: 0.44,
      dim: true,
    );
    _drawHead(
      canvas,
      Offset(-0.63, y + 0.02),
      0.41,
      eyesOpen: false,
      dim: true,
    );
    _drawFoldedLeg(canvas, const Offset(-0.18, 0.43), alpha: 0.22);
    _drawFoldedLeg(canvas, const Offset(0.32, 0.44), alpha: 0.18);
  }

  void _drawWakingFox(Canvas canvas, double wakeT) {
    final rise = Curves.easeOutCubic.transform(wakeT);
    final recoil = math.sin(wakeT * math.pi).clamp(0.0, 1.0);
    _drawTail(
      canvas,
      Offset(0.66, 0.04 - rise * 0.12),
      curled: wakeT < 0.72,
      sway: wakeT,
      thickness: 0.18 + recoil * 0.02,
      alpha: 0.5 + wakeT * 0.25,
    );
    _drawBody(
      canvas,
      center: Offset(0.05, 0.08 - rise * 0.16),
      stretch: 0.98 + rise * 0.12,
      crouch: 0.2 - rise * 0.08,
      alpha: 0.58 + rise * 0.28,
    );
    _drawHead(
      canvas,
      Offset(-0.62 + rise * 0.1, -0.06 - rise * 0.25),
      0.44 + rise * 0.06,
      eyesOpen: wakeT > 0.35,
      eyeGlow: wakeT,
    );
    _drawLeg(canvas, const Offset(-0.34, 0.3), -0.45 + rise * 0.9, alpha: 0.45);
    _drawLeg(canvas, const Offset(0.25, 0.32), 0.55 - rise * 0.75, alpha: 0.38);
  }

  void _drawRunningFox(Canvas canvas, double cycle, double mouthGlow) {
    final bounce = math.sin(cycle * math.pi * 2) * 0.06;
    final stretch = 1.06 + 0.08 * math.sin(cycle * math.pi * 2).abs();
    _drawTail(
      canvas,
      Offset(0.74, -0.08 + bounce * 0.5),
      curled: false,
      sway: cycle,
      thickness: 0.17,
      alpha: 0.78,
    );
    _drawBody(
      canvas,
      center: Offset(0.08, bounce),
      stretch: stretch,
      crouch: 0.03,
      alpha: 0.88,
    );

    final legPhase = cycle * math.pi * 2;
    _drawLeg(canvas, const Offset(-0.36, 0.27), legPhase, alpha: 0.8);
    _drawLeg(canvas, const Offset(-0.04, 0.31), legPhase + math.pi, alpha: 0.64);
    _drawLeg(canvas, const Offset(0.28, 0.27), legPhase + math.pi * 0.5, alpha: 0.76);
    _drawLeg(canvas, const Offset(0.52, 0.3), legPhase + math.pi * 1.5, alpha: 0.58);

    _drawHead(
      canvas,
      Offset(-0.68, -0.18 + bounce),
      0.48,
      eyesOpen: true,
      eyeGlow: 1,
      mouthGlow: mouthGlow,
    );
  }

  void _drawRunSmears(Canvas canvas, double cycle) {
    final smearPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.035
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.025);
    for (var i = 0; i < 5; i++) {
      final y = -0.18 + i * 0.13 + math.sin(cycle * math.pi * 2 + i) * 0.018;
      canvas.drawLine(
        Offset(-0.98 - i * 0.1, y),
        Offset(-0.42 - i * 0.08, y - 0.02),
        smearPaint,
      );
    }
  }

  void _drawBody(
    Canvas canvas, {
    required Offset center,
    required double stretch,
    required double crouch,
    required double alpha,
    bool dim = false,
  }) {
    final body = Path()
      ..moveTo(center.dx - 0.68 * stretch, center.dy + 0.02)
      ..cubicTo(
        center.dx - 0.5 * stretch,
        center.dy - 0.34 - crouch,
        center.dx + 0.2 * stretch,
        center.dy - 0.36 - crouch * 0.7,
        center.dx + 0.66 * stretch,
        center.dy - 0.08,
      )
      ..cubicTo(
        center.dx + 0.74 * stretch,
        center.dy + 0.16,
        center.dx + 0.38 * stretch,
        center.dy + 0.32,
        center.dx - 0.12 * stretch,
        center.dy + 0.3,
      )
      ..cubicTo(
        center.dx - 0.52 * stretch,
        center.dy + 0.28,
        center.dx - 0.76 * stretch,
        center.dy + 0.17,
        center.dx - 0.68 * stretch,
        center.dy + 0.02,
      )
      ..close();

    _drawSilhouette(canvas, body, alpha: alpha, dim: dim);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.026
        ..color = Colors.white.withValues(alpha: dim ? 0.16 : 0.32),
    );
  }

  void _drawHead(
    Canvas canvas,
    Offset c,
    double r, {
    required bool eyesOpen,
    double eyeGlow = 0,
    double mouthGlow = 0,
    bool dim = false,
  }) {
    final head = Path()
      ..moveTo(c.dx - r * 0.72, c.dy - r * 0.02)
      ..cubicTo(
        c.dx - r * 0.62,
        c.dy - r * 0.52,
        c.dx - r * 0.18,
        c.dy - r * 0.78,
        c.dx + r * 0.26,
        c.dy - r * 0.55,
      )
      ..cubicTo(
        c.dx + r * 0.72,
        c.dy - r * 0.28,
        c.dx + r * 0.86,
        c.dy + r * 0.25,
        c.dx + r * 0.42,
        c.dy + r * 0.5,
      )
      ..cubicTo(
        c.dx - r * 0.04,
        c.dy + r * 0.76,
        c.dx - r * 0.72,
        c.dy + r * 0.5,
        c.dx - r * 0.72,
        c.dy - r * 0.02,
      )
      ..close();
    _drawSilhouette(canvas, head, alpha: dim ? 0.42 : 0.86, dim: dim);
    final earL = Path()
      ..moveTo(c.dx - r * 0.55, c.dy - r * 0.55)
      ..lineTo(c.dx - r * 0.85, c.dy - r * 1.05)
      ..lineTo(c.dx - r * 0.15, c.dy - r * 0.75)
      ..close();
    final earR = Path()
      ..moveTo(c.dx + r * 0.15, c.dy - r * 0.7)
      ..lineTo(c.dx + r * 0.35, c.dy - r * 1.1)
      ..lineTo(c.dx + r * 0.55, c.dy - r * 0.5)
      ..close();
    _drawSilhouette(canvas, earL, alpha: dim ? 0.34 : 0.72, dim: dim);
    _drawSilhouette(canvas, earR, alpha: dim ? 0.34 : 0.72, dim: dim);
    final earStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.025
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawPath(earL, earStroke);
    canvas.drawPath(earR, earStroke);

    if (eyesOpen) {
      for (final ex in [-0.28, 0.12]) {
        final eye = Offset(c.dx + r * ex, c.dy - r * 0.08);
        canvas.drawCircle(
          eye,
          r * 0.11,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.26 + 0.74 * eyeGlow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(eye, r * 0.07, Paint()..color = Colors.white);
      }
    } else {
      for (final ex in [-0.22, 0.18]) {
        final eye = Offset(c.dx + r * ex, c.dy - r * 0.02);
        canvas.drawLine(
          eye + Offset(-r * 0.1, 0),
          eye + Offset(r * 0.1, 0),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.25)
            ..strokeWidth = 0.04
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    if (mouthGlow > 0) {
      canvas.drawCircle(
        Offset(c.dx + r * 0.45, c.dy + r * 0.12),
        r * 0.08,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * mouthGlow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    final snout = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.42, c.dy + r * 0.15),
        width: r * 0.55,
        height: r * 0.38,
      ),
      Radius.circular(r * 0.2),
    );
    canvas.drawRRect(snout, Paint()..color = const Color(0xFF060606));
    canvas.drawRRect(
      snout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  void _drawLeg(Canvas canvas, Offset hip, double phase, {double alpha = 0.7}) {
    final swing = math.sin(phase) * 0.36;
    final lift = math.cos(phase).clamp(-1.0, 1.0) * 0.1;
    final knee = hip + Offset(swing * 0.22, 0.2 - lift.abs() * 0.22);
    final foot = knee + Offset(swing * 0.22, 0.23 + lift * 0.18);
    final paint = Paint()
      ..color = const Color(0xFF050505)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round;
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.2 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.04);
    canvas.drawLine(hip, knee, glow);
    canvas.drawLine(knee, foot, glow);
    canvas.drawLine(hip, knee, paint);
    canvas.drawLine(knee, foot, paint);
    canvas.drawCircle(foot, 0.05, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  void _drawFoldedLeg(Canvas canvas, Offset hip, {double alpha = 0.24}) {
    final p = Path()
      ..moveTo(hip.dx, hip.dy)
      ..quadraticBezierTo(hip.dx + 0.18, hip.dy + 0.08, hip.dx + 0.34, hip.dy)
      ..quadraticBezierTo(hip.dx + 0.18, hip.dy + 0.14, hip.dx - 0.02, hip.dy + 0.08);
    canvas.drawPath(
      p,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawTail(
    Canvas canvas,
    Offset base, {
    required bool curled,
    double sway = 0,
    double thickness = 0.15,
    double alpha = 0.7,
  }) {
    final path = Path()..moveTo(base.dx, base.dy);
    if (curled) {
      path.cubicTo(
        base.dx + 0.52,
        base.dy - 0.34,
        base.dx + 0.18,
        base.dy - 0.72,
        base.dx - 0.14,
        base.dy - 0.42,
      );
    } else {
      final w = math.sin(sway * math.pi * 2) * 0.16;
      path.cubicTo(
        base.dx + 0.28,
        base.dy - 0.18 + w,
        base.dx + 0.55,
        base.dy - 0.42 - w,
        base.dx + 0.82,
        base.dy - 0.16,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness + 0.06
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.06),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF050505)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.028,
    );
  }

  void _drawSilhouette(
    Canvas canvas,
    Path path, {
    required double alpha,
    bool dim = false,
  }) {
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: dim ? 0.08 : 0.16 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.06),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF151515),
            Color(0xFF000000),
          ],
        ).createShader(path.getBounds()),
    );
  }

  double _seg(double t, double a, double b) {
    if (t <= a) return 0.0;
    if (t >= b) return 1.0;
    return (t - a) / (b - a);
  }

  @override
  bool shouldRepaint(covariant _FoxChasePainter old) =>
      old.phase != phase || old.screen != screen;
}

class _FoxPose {
  const _FoxPose({
    this.sleeping = false,
    this.waking = false,
    this.running = false,
    this.breath = 0,
    this.wakeT = 0,
    this.runCycle = 0,
    this.scale = 1,
    this.tilt = 0,
    this.mouthGlow = 0,
    this.squashX = 1.0,
    this.squashY = 1.0,
  });

  final bool sleeping;
  final bool waking;
  final bool running;
  final double breath;
  final double wakeT;
  final double runCycle;
  final double scale;
  final double tilt;
  final double mouthGlow;
  final double squashX;
  final double squashY;
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
  Timer? _splashFallback;

  @override
  void initState() {
    super.initState();
    _splashFallback = Timer(
      _kSplashDuration + const Duration(milliseconds: 700),
      _hideSplash,
    );
  }

  @override
  void dispose() {
    _splashFallback?.cancel();
    super.dispose();
  }

  void _hideSplash() {
    if (!_showSplash) return;
    _splashFallback?.cancel();
    if (mounted) setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          FoxyStartupSplash(
            onFinished: _hideSplash,
          ),
      ],
    );
  }
}
