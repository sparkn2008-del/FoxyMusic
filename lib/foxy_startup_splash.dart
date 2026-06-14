import 'dart:async';

import 'package:flutter/material.dart';

const _kSplashDuration = Duration(milliseconds: 1350);

/// Cold-start splash: stable black screen with centered logo and looping loader.
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
  bool _logoReady = false;
  late final AnimationController _loaderCtrl;

  @override
  void initState() {
    super.initState();
    _loaderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
    _finishFallback = Timer(_kSplashDuration, _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoReady) return;
    _logoReady = true;
    precacheImage(const AssetImage('assets/images/foxy_logo.png'), context);
  }

  @override
  void dispose() {
    _finishFallback?.cancel();
    _loaderCtrl.dispose();
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
        child: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/foxy_logo.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _loaderCtrl,
                builder: (context, _) {
                  final t = Curves.easeInOutCubic.transform(_loaderCtrl.value);
                  return SizedBox(
                    width: 108,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Align(
                          alignment: Alignment(-1 + (2 * t), 0),
                          child: Container(
                            width: 42,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.86),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  blurRadius: 10,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
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
    _splashFallback = Timer(_kSplashDuration, _hideSplash);
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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: _showSplash
            ? FoxyStartupSplash(
                key: const ValueKey('foxy-splash'),
                onFinished: _hideSplash,
              )
            : KeyedSubtree(
                key: const ValueKey('foxy-app'),
                child: widget.child,
              ),
      ),
    );
  }
}
