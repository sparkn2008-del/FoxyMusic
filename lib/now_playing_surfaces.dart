part of 'main.dart';

class _LyricsBackdropStage extends StatelessWidget {
  const _LyricsBackdropStage({
    required this.lines,
    required this.loading,
    required this.positionMs,
    required this.accent,
    required this.preferLrclib,
    required this.romanized,
    required this.onSeekToLine,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final bool preferLrclib;
  final bool romanized;
  final ValueChanged<int> onSeekToLine;

  @override
  Widget build(BuildContext context) {
    return _FoxyPerfProbe.measure(
      'lyrics.stage.build',
      () => Stack(
        fit: StackFit.expand,
        children: [
          if (loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: accent.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Loading lyrics...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: _EmptyTabBody(
                  icon: Icons.subtitles_off_rounded,
                  title: 'No lyrics found...',
                  subtitle: preferLrclib
                      ? 'LRCLIB had no match - try turning off "Prefer LRCLIB" in Settings or the menu.'
                      : 'YouTube captions had no match - try "Prefer LRCLIB" in Settings.',
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: RepaintBoundary(
                child: _AnimatedLyricsList(
                  lines: lines,
                  positionMs: positionMs,
                  accent: Colors.white,
                  onSeekToLine: onSeekToLine,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 18,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: lines.isEmpty || loading ? 0.0 : 0.88,
                  child: Text(
                    romanized
                        ? 'Synced | Romanized'
                        : (preferLrclib
                              ? 'Synced | LRCLIB'
                              : 'Synced | YouTube'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedLyricsList extends StatefulWidget {
  const _AnimatedLyricsList({
    required this.lines,
    required this.positionMs,
    required this.accent,
    required this.onSeekToLine,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final Color accent;
  final ValueChanged<int> onSeekToLine;

  @override
  State<_AnimatedLyricsList> createState() => _AnimatedLyricsListState();
}

class _AnimatedLyricsListState extends State<_AnimatedLyricsList>
    with SingleTickerProviderStateMixin {
  static const _lineStride = 70.0;
  static const _topInset = 84.0;
  static const _bottomInset = 300.0;
  late final ScrollController _controller;
  late final AnimationController _pulseCtrl;
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = _activeIndex;
    if (active != _lastActive) {
      _FoxyPerfProbe.event('lyrics.activeLine.shift');
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final viewport = _controller.position.viewportDimension;
        final focusY = math.max(112.0, viewport * 0.26);
        final target = (active * _lineStride - focusY).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  int get _activeIndex {
    var active = widget.lines.lastIndexWhere(
      (line) => line.timeMs <= widget.positionMs,
    );
    if (active < 0) active = 0;
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return _FoxyPerfProbe.measure(
      'lyrics.list.build',
      () => ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.64, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.fromLTRB(16, _topInset, 16, _bottomInset),
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final line = widget.lines[index];
            final delta = index - active;
            final distance = delta.abs();
            final isActive = distance == 0;
            final passed = delta < 0;
            final opacity = switch (distance) {
              0 => 1.0,
              1 => 0.84,
              2 => 0.63,
              3 => 0.42,
              _ => 0.24,
            };
            final fontSize = switch (distance) {
              0 => 27.5,
              1 => 23.8,
              2 => 21.6,
              3 => 20.0,
              _ => 18.8,
            };
            final verticalPad = switch (distance) {
              0 => 9.0,
              1 => 7.5,
              2 => 6.5,
              _ => 5.5,
            };
            final slideY = switch (delta) {
              0 => 0.0,
              -1 => -0.055,
              1 => 0.055,
              < 0 => -0.025,
              _ => 0.025,
            };
            final baseScale = switch (distance) {
              0 => 1.0,
              1 => 0.985,
              2 => 0.968,
              _ => 0.952,
            };
            final glow = isActive
                ? [
                    Shadow(
                      color: widget.accent.withValues(alpha: 0.50),
                      blurRadius: 12,
                    ),
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.42),
                      blurRadius: 6,
                    ),
                  ]
                : null;
            Widget lineText(double scale, {double pulse = 0.0}) {
              return Text(
                line.text,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : passed
                      ? Colors.white.withValues(alpha: 0.46)
                      : Colors.white.withValues(alpha: 0.74),
                  fontSize: fontSize + pulse,
                  height: 1.18,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: widget.accent.withValues(
                              alpha: 0.50 + (0.08 * pulse),
                            ),
                            blurRadius: 12 + (6 * pulse),
                          ),
                          Shadow(
                            color: Colors.white.withValues(
                              alpha: 0.40 + (0.06 * pulse),
                            ),
                            blurRadius: 6 + (2 * pulse),
                          ),
                        ]
                      : glow,
                ),
              );
            }

            Widget frame(Widget child, {double scale = 1.0}) {
              return AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                offset: Offset(0, slideY),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  scale: scale,
                  alignment: Alignment.centerLeft,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    opacity: opacity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: EdgeInsets.symmetric(vertical: verticalPad),
                      child: child,
                    ),
                  ),
                ),
              );
            }

            if (!isActive) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSeekToLine(line.timeMs),
                child: frame(lineText(baseScale), scale: baseScale),
              );
            }
            return AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final pulse = Curves.easeInOutSine.transform(_pulseCtrl.value);
                final pulseScale = baseScale + (0.014 * pulse);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSeekToLine(line.timeMs),
                  child: frame(
                    lineText(pulseScale, pulse: 0.35 * pulse),
                    scale: pulseScale,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.blurEnabled,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.fullBleed = false,
    this.backgroundStyle = 0,
  });

  final String url;
  final String videoId;
  final String title;
  final String artist;
  final bool blurEnabled;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;
  final bool fullBleed;
  final int backgroundStyle;

  @override
  Widget build(BuildContext context) {
    return _FoxyPerfProbe.measure('backdrop.blur.build', () {
      final accent = Theme.of(context).colorScheme.primary;
      File? offlineFile() {
        if (!useOfflineArtwork || kIsWeb) return null;
        final p = offlineArtworkPath?.trim();
        if (p == null || p.isEmpty) return null;
        final f = File(p);
        if (f.existsSync()) return f;
        return null;
      }

      final of = offlineFile();
      final deviceWidth =
          MediaQuery.sizeOf(context).width *
          MediaQuery.devicePixelRatioOf(context);
      final backdropDecodeWidth = deviceWidth.isFinite
          ? deviceWidth.round().clamp(960, fullBleed ? 2400 : 1800)
          : (fullBleed ? 1800 : 1320);
      final backdropQuality = backgroundStyle == 3
          ? FilterQuality.high
          : FilterQuality.high;
      final brandUnderlay = fullBleed
          ? const ColoredBox(color: Color(0xFF050505))
          : _FoxyBrandGradientBackdrop(
              variant: _FoxyGradientVariant.player,
              child: const SizedBox.expand(),
            );
      if (backgroundStyle == 2) {
        return const ColoredBox(color: Colors.black);
      }
      final imageChild = of != null
          ? Image.file(
              of,
              key: ValueKey<String>('bd|${of.path}'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              gaplessPlayback: true,
              cacheWidth: backdropDecodeWidth,
              filterQuality: backdropQuality,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: Color(0xFF080808)),
            )
          : _BackdropArtworkImage(
              key: ValueKey<String>('bd|$videoId|$url'),
              url: url,
              videoId: videoId,
              cacheWidth: backdropDecodeWidth,
              filterQuality: backdropQuality,
            );

      final hasBackdropImage = !url.isBlank || of != null;
      if (!hasBackdropImage) {
        return Stack(
          fit: StackFit.expand,
          children: [
            brandUnderlay,
            if (!fullBleed)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.1, -0.35),
                    radius: 1.45,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      _FoxyBrandPalette.foxDeep.withValues(alpha: 0.14),
                      const Color(0xFF080808).withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
            if (fullBleed)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.05, -0.25),
                    radius: 1.18,
                    colors: [
                      accent.withValues(alpha: 0.16),
                      const Color(0xFF060606).withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
          ],
        );
      }

      if (backgroundStyle == 3) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _BackdropMotionLoop(
              fullBleed: fullBleed,
              child: RepaintBoundary(child: SizedBox.expand(child: imageChild)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.22),
                    Colors.black.withValues(alpha: 0.44),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      if (backgroundStyle == 1 || !blurEnabled) {
        return Stack(
          fit: StackFit.expand,
          children: [
            brandUnderlay,
            if (!fullBleed)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.1, -0.35),
                    radius: 1.45,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      _FoxyBrandPalette.foxDeep.withValues(alpha: 0.14),
                      const Color(0xFF080808).withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
            if (fullBleed)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.05, -0.25),
                    radius: 1.18,
                    colors: [
                      accent.withValues(alpha: 0.16),
                      const Color(0xFF060606).withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
          ],
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          if (!fullBleed) brandUnderlay,
          RepaintBoundary(
            child: Transform.scale(
              scale: fullBleed ? 1.24 : 1.12,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: fullBleed ? 30 : 24,
                  sigmaY: fullBleed ? 30 : 24,
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: fullBleed ? 0.20 : 0.14),
                    BlendMode.darken,
                  ),
                  child: SizedBox.expand(child: imageChild),
                ),
              ),
            ),
          ),
          Opacity(
            opacity: fullBleed ? 0.10 : 0.08,
            child: Transform.scale(
              scale: fullBleed ? 1.08 : 1.03,
              child: SizedBox.expand(child: imageChild),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: fullBleed ? 0.06 : 0.12),
                  Colors.black.withValues(alpha: fullBleed ? 0.18 : 0.28),
                  Colors.black.withValues(alpha: fullBleed ? 0.42 : 0.58),
                  Colors.black.withValues(alpha: fullBleed ? 0.68 : 0.82),
                ],
                stops: const [0.0, 0.28, 0.66, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.08),
                radius: fullBleed ? 1.02 : 1.14,
                colors: [
                  accent.withValues(alpha: fullBleed ? 0.10 : 0.08),
                  Colors.white.withValues(alpha: fullBleed ? 0.02 : 0.015),
                  Colors.transparent,
                  Colors.black.withValues(alpha: fullBleed ? 0.18 : 0.10),
                ],
                stops: const [0.0, 0.22, 0.64, 1.0],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _BackdropMotionLoop extends StatefulWidget {
  const _BackdropMotionLoop({required this.child, required this.fullBleed});

  final Widget child;
  final bool fullBleed;

  @override
  State<_BackdropMotionLoop> createState() => _BackdropMotionLoopState();
}

class _BackdropMotionLoopState extends State<_BackdropMotionLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 38),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleMin = widget.fullBleed ? 1.035 : 1.02;
    final scaleMax = widget.fullBleed ? 1.075 : 1.05;
    final panX = widget.fullBleed ? 6.0 : 4.0;
    final panY = widget.fullBleed ? 4.0 : 2.5;
    return _FoxyPerfProbe.measure(
      'backdrop.motion.build',
      () => ClipRect(
        child: AnimatedBuilder(
          animation: _ctrl,
          child: RepaintBoundary(child: widget.child),
          builder: (context, child) {
            final raw = _ctrl.value;
            final t = Curves.easeInOutSine.transform(
              (math.sin(raw * math.pi * 2) + 1) * 0.5,
            );
            final scale = lerpDouble(scaleMin, scaleMax, t)!;
            final x = math.sin(raw * math.pi * 2) * panX;
            final y = math.cos(raw * math.pi * 2) * panY;
            return Transform.translate(
              offset: Offset(x, y),
              child: Transform.scale(
                scale: scale,
                child: SizedBox.expand(child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BackdropArtworkImage extends StatefulWidget {
  const _BackdropArtworkImage({
    super.key,
    required this.url,
    required this.videoId,
    required this.cacheWidth,
    required this.filterQuality,
  });

  final String url;
  final String videoId;
  final int cacheWidth;
  final FilterQuality filterQuality;

  @override
  State<_BackdropArtworkImage> createState() => _BackdropArtworkImageState();
}

class _BackdropArtworkImageState extends State<_BackdropArtworkImage> {
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _resetCandidates();
  }

  @override
  void didUpdateWidget(covariant _BackdropArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.videoId != widget.videoId) {
      _resetCandidates();
    }
  }

  void _resetCandidates() {
    _candidates = _backdropArtworkCandidates(widget.url, widget.videoId);
    _index = 0;
  }

  void _advanceCandidate() {
    if (_index >= _candidates.length - 1) return;
    setState(() => _index += 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) {
      return const ColoredBox(color: Color(0xFF080808));
    }
    return Image.network(
      _candidates[_index],
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      gaplessPlayback: true,
      cacheWidth: widget.cacheWidth,
      filterQuality: widget.filterQuality,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _advanceCandidate();
        });
        return const ColoredBox(color: Color(0xFF080808));
      },
    );
  }
}
