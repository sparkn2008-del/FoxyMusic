import 'dart:async';

import 'package:flutter/material.dart';

const _kSplashDuration = Duration(milliseconds: 1100);

/// Cold-start splash: simple Foxy-style black screen with restrained branding.
class FoxyStartupSplash extends StatefulWidget {
  const FoxyStartupSplash({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<FoxyStartupSplash> createState() => _FoxyStartupSplashState();
}

class _FoxyStartupSplashState extends State<FoxyStartupSplash>
    with SingleTickerProviderStateMixin {
  Timer? _finishFallback;
  bool _finished = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _finishFallback = Timer(_kSplashDuration, _finish);
  }

  @override
  void dispose() {
    _finishFallback?.cancel();
    _pulseCtrl.dispose();
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
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_pulseCtrl.value);
                return SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: 0.2 + (0.62 * t),
                      minHeight: 2,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
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
        if (!_showSplash)
          widget.child
        else
          const ColoredBox(color: Color(0xFF000000)),
        if (_showSplash) FoxyStartupSplash(onFinished: _hideSplash),
      ],
    );
  }
}
