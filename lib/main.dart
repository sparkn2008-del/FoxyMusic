import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

typedef FoxyOnPlay =
    Future<void> Function(_Song song, List<_Song> queue, {bool radioTail});

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;
/// Light black veil on transparent chrome (nav, controls, chips).
const double _kSubtleBlackTint = 0.10;

String _kAppVersionLabel = 'v1.1';
String _kAppVersionName = '1.1';
const String _kGitHubProjectUrl = 'https://github.com/sparkn2008-del/FoxyMusic';
const String _kAboutCreditLine =
    'Made with ❤️ by Foxy Nish aka sparkn2008-del 🦊✨';
const String _kFoxyLogoAsset = 'assets/images/foxy_logo.png';

/// Metrolist-style now playing foreground (backdrop stays full-bleed [_BlurBackdrop]).
const Color _kMetrolistNpSurface = Color(0xFF2E2E30);
const Color _kMetrolistNpSurfaceHigh = Color(0xFF3D3D42);
const Color _kMetrolistNpTime = Color(0xFF9E9E9E);

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xCC000000),
    Color.lerp(const Color(0xFF4A4334), accent, 0.28)!,
  );
}

/// Parses catalog duration ("4:32", "1:23:04", or plain seconds / ms) when Exo [durationMs] is unknown.
int? _durationHintMsFromCatalog(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.tryParse(s);
    if (n == null) return null;
    if (n >= 10000) return n;
    return n * 1000;
  }
  final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? -1).toList();
  if (parts.isEmpty || parts.any((e) => e < 0)) return null;
  if (parts.length == 2) return (parts[0] * 60 + parts[1]) * 1000;
  if (parts.length >= 3) {
    return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
  }
  return null;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FoxyFlutterApp());
}

class FoxyFlutterApp extends StatefulWidget {
  const FoxyFlutterApp({super.key});

  @override
  State<FoxyFlutterApp> createState() => _FoxyFlutterAppState();
}

class _FoxyFlutterAppState extends State<FoxyFlutterApp> {
  final _rootNavKey = GlobalKey<NavigatorState>();
  _FlutterAppearance _appearance = const _FlutterAppearance();
  String? _homeBackgroundPath;
  bool _dynamicSongColors = true;
  int? _songAccentArgb;
  int _paletteEpoch = 0;
  String _lastPlayerVideoId = '';
  StreamSubscription<dynamic>? _rootEventSub;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    unawaited(_loadAppVersion());
    _rootEventSub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          final nextDynamic = state['dynamicSongColors'] != false;
          final a = state['songAccentArgb'];
          final nextAccent = a is num ? a.toInt() : null;
          final pe = state['paletteEpoch'];
          final nextEpoch = pe is num ? pe.toInt() : _paletteEpoch;
          final accentChanged = nextAccent != _songAccentArgb;
          final epochChanged = nextEpoch != _paletteEpoch;
          final cs = _asMap(state['currentSong']);
          final vid = cs?['videoId']?.toString() ?? '';
          final videoChanged = vid != _lastPlayerVideoId;
          setState(() {
            _dynamicSongColors = nextDynamic;
            _songAccentArgb = nextAccent;
            _paletteEpoch = nextEpoch;
            _lastPlayerVideoId = vid;
          });
          if (nextDynamic &&
              (accentChanged || epochChanged || videoChanged)) {
            unawaited(_loadAppearance());
          }
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
      } else if (type == 'updateAvailable') {
        final update = _asMap(map['update']);
        if (update != null) {
          _promptUpdateAvailable(update);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPlayerThemeFromNative();
    });
  }

  Future<void> _syncPlayerThemeFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map == null || !mounted) return;
      final pe = map['paletteEpoch'];
      setState(() {
        _dynamicSongColors = map['dynamicSongColors'] != false;
        final a = map['songAccentArgb'];
        _songAccentArgb = a is num ? a.toInt() : null;
        if (pe is num) {
          _paletteEpoch = pe.toInt();
        }
        final cs = _asMap(map['currentSong']);
        _lastPlayerVideoId = cs?['videoId']?.toString() ?? '';
      });
      if (_dynamicSongColors) {
        unawaited(_loadAppearance());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _rootEventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppearance'));
      if (map != null && mounted) {
        setState(() {
          _appearance = _FlutterAppearance.fromMap(map);
          final d = map['dynamicSongColors'];
          if (d is bool) {
            _dynamicSongColors = d;
          }
          final bg = map['homeBackgroundPath']?.toString().trim();
          _homeBackgroundPath =
              (bg != null && bg.isNotEmpty) ? bg : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAppVersion() async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppVersion'));
      if (map == null || !mounted) return;
      final name = map['versionName']?.toString().trim() ?? '';
      if (name.isEmpty) return;
      setState(() {
        _kAppVersionName = name;
        _kAppVersionLabel = 'v$name';
      });
    } catch (_) {}
  }

  void _promptUpdateAvailable(Map<String, dynamic> map) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rootNavKey.currentContext;
      if (ctx == null || !mounted) return;
      _showUpdateResultDialog(ctx, map, title: 'Update available');
    });
  }

  Color get _effectiveAccent {
    if (_dynamicSongColors && _songAccentArgb != null) {
      return Color(_songAccentArgb! & 0xFFFFFFFF);
    }
    return _appearance.accent;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _effectiveAccent;
    return MaterialApp(
      navigatorKey: _rootNavKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _appearance.background,
        colorScheme: ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: _appearance.surface,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white.withValues(alpha: 0.55);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent.withValues(alpha: 0.55);
            }
            return Colors.white.withValues(alpha: 0.12);
          }),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF141414),
          selectedColor: const Color(0xFF2C2C2C),
          disabledColor: const Color(0xFF141414),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          labelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          showCheckmark: true,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: FoxyHomeShell(homeBackgroundPath: _homeBackgroundPath),
    );
  }
}

class _FlutterAppearance {
  const _FlutterAppearance({
    this.accent = const Color(0xFFFF2D55),
    this.background = _kTrueBlack,
    this.surface = _kTrueBlack,
    this.surfaceHigh = const Color(0xFF121212),
    this.muted = const Color(0xFFB0B0B0),
  });

  factory _FlutterAppearance.fromMap(Map<String, dynamic> map) =>
      _FlutterAppearance(
        accent: _argbToColor(map['accentArgb']) ?? const Color(0xFFFF2D55),
        background: _argbToColor(map['backgroundArgb']) ?? _kTrueBlack,
        surface: _argbToColor(map['surfaceArgb']) ?? _kTrueBlack,
        surfaceHigh:
            _argbToColor(map['surfaceHighArgb']) ?? const Color(0xFF121212),
        muted: _argbToColor(map['mutedArgb']) ?? const Color(0xFFB0B0B0),
      );

  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color muted;
}

Color? _argbToColor(dynamic value) {
  if (value is num) return Color(value.toInt() & 0xFFFFFFFF);
  return null;
}

String _playerProgressStyleLabel(int raw) {
  switch (raw.clamp(0, 3)) {
    case 0:
      return 'Default';
    case 1:
      return 'Slim';
    case 2:
      return 'Wavy';
    default:
      return 'Squiggly';
  }
}

String _playerSeekMotionLabel(int raw) {
  switch (raw.clamp(0, 2)) {
    case 1:
      return 'Pulse thumb';
    case 2:
      return 'Shimmer';
    default:
      return 'Static';
  }
}

/// Warm fox-fur tones from the FoxyMusic logo (amber → deep orange → cream).
class _FoxyBrandPalette {
  static const foxAmber = Color(0xFFFF9A3C);
  static const foxDeep = Color(0xFFE85D04);
  static const foxCream = Color(0xFFFFD9B0);
  static const foxEmber = Color(0xFFFF1744);
}

enum _FoxyGradientVariant { home, player }

/// Large soft blooms — fox logo warmth + dynamic song accent.
class _FoxyBrandGradientBackdrop extends StatelessWidget {
  const _FoxyBrandGradientBackdrop({
    required this.child,
    this.variant = _FoxyGradientVariant.home,
  });

  final Widget child;
  final _FoxyGradientVariant variant;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final strong = variant == _FoxyGradientVariant.player;
    // SimpMusic-style: dark base with one soft accent bloom (player is subtler than home).
    final topH = strong ? 440.0 : 460.0;
    final bottomH = strong ? 320.0 : 340.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF000000),
                Color.lerp(const Color(0xFF1A0E08), const Color(0xFF0A0A0A), 0.5)!,
                Color.lerp(const Color(0xFF120808), surface, 0.55)!,
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -100,
          right: -100,
          height: topH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.15, -0.2),
                  radius: 1.35,
                  colors: [
                    Color.lerp(_FoxyBrandPalette.foxCream, accent, 0.35)!
                        .withValues(alpha: strong ? 0.22 : 0.34),
                    _FoxyBrandPalette.foxAmber.withValues(alpha: strong ? 0.14 : 0.22),
                    _FoxyBrandPalette.foxDeep.withValues(alpha: strong ? 0.06 : 0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 0.62, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: -90,
          left: 120,
          height: topH * 0.85,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.2,
                  colors: [
                    _FoxyBrandPalette.foxEmber.withValues(alpha: strong ? 0.1 : 0.18),
                    accent.withValues(alpha: strong ? 0.08 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -110,
          right: -110,
          height: bottomH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomCenter,
                  radius: 1.25,
                  colors: [
                    _FoxyBrandPalette.foxDeep.withValues(alpha: strong ? 0.14 : 0.16),
                    accent.withValues(alpha: strong ? 0.06 : 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Branded FoxyMusic logo (PNG with glow on black).
class _FoxyAppLogo extends StatelessWidget {
  const _FoxyAppLogo({
    this.size = 120,
    this.borderRadius = 20,
    this.showGlow = true,
  });

  final double size;
  final double borderRadius;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: showGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.22),
                  blurRadius: size * 0.28,
                  spreadRadius: size * 0.02,
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          _kFoxyLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.music_note_rounded,
            size: size * 0.5,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }
}

class _FoxyHomeBackdrop extends StatelessWidget {
  const _FoxyHomeBackdrop({
    required this.child,
    this.customPath,
  });

  final Widget child;
  final String? customPath;

  @override
  Widget build(BuildContext context) {
    Widget bg;
    if (customPath != null &&
        customPath!.isNotEmpty &&
        !kIsWeb &&
        File(customPath!).existsSync()) {
      bg = Image.file(
        File(customPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    } else {
      bg = Image.asset(
        'assets/images/foxy_home_bg.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFF000000)),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0.42),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Translucent surface — does **not** blur the wallpaper (cards, bars, sheets).
class _FoxyGlassTint extends StatelessWidget {
  const _FoxyGlassTint({
    required this.child,
    this.borderRadius = 0,
    this.tintOpacity = 0.28,
    this.borderOpacity = 0.1,
    this.showBottomBorder = false,
  });

  final Widget child;
  final double borderRadius;
  final double tintOpacity;
  final double borderOpacity;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius > 0 ? BorderRadius.circular(borderRadius) : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: tintOpacity),
        borderRadius: radius,
        border: showBottomBorder
            ? Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: borderOpacity),
                ),
              )
            : Border.all(
                color: Colors.white.withValues(alpha: borderOpacity),
              ),
      ),
      child: child,
    );
  }
}

/// Glass control surface. SimpMusic-style: scrolling lists use [blur] off (tint
/// only) so wallpaper is not re-sampled every frame; fixed chrome may use blur.
class _FoxyGlassButton extends StatelessWidget {
  const _FoxyGlassButton({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tintOpacity = 0.34,
    this.blurSigma = 10,
    this.selected = false,
    this.padding = EdgeInsets.zero,
    this.blur = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double tintOpacity;
  final double blurSigma;
  final bool selected;
  final EdgeInsetsGeometry padding;
  /// Live [BackdropFilter] — only for small fixed chrome (nav, header icons).
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final effectiveTint = blur
        ? tintOpacity
        : (tintOpacity + 0.08).clamp(0.0, 0.52);
    final fill = selected
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: effectiveTint),
          )
        : Colors.black.withValues(alpha: effectiveTint);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(
            alpha: selected ? 0.28 : (blur ? 0.16 : 0.14),
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    Widget core = ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: surface,
            )
          : surface,
    );
    if (blur) {
      core = RepaintBoundary(child: core);
    }
    if (onTap != null) {
      core = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: core,
        ),
      );
    }
    return core;
  }
}

/// Text action styled as frosted glass (Play all, Retry, …).
class _FoxyGlassTextButton extends StatelessWidget {
  const _FoxyGlassTextButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onPressed,
      selected: selected,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

_HomeSectionLayout _homeSectionLayout(_SongSection section) {
  switch (section.layout) {
    case 'video':
      return _HomeSectionLayout.video;
    case 'grid':
      return _HomeSectionLayout.grid;
    case 'chart':
      return _HomeSectionLayout.chart;
    case 'artist':
      return _HomeSectionLayout.artist;
    case 'cards':
      return _HomeSectionLayout.cards;
    default:
      final t = section.title.toLowerCase();
      if (t.contains('video')) return _HomeSectionLayout.video;
      if (t.contains('chart')) return _HomeSectionLayout.chart;
      if (t.contains('artist') || t.contains('similar')) {
        return _HomeSectionLayout.artist;
      }
      if (t.contains('release') ||
          t.contains('discover') ||
          t.contains('cover') ||
          t.contains('remix') ||
          t.contains('daily') ||
          t.contains('fresh')) {
        return _HomeSectionLayout.grid;
      }
      return _HomeSectionLayout.cards;
  }
}

void _openSearchResultsPage(
  BuildContext context, {
  required String query,
  required FoxyOnPlay onPlay,
  void Function(String q)? onDiscoverSearch,
}) {
  final q = query.trim();
  if (q.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _SearchResultsPage(
        query: q,
        onPlay: onPlay,
        onDiscoverSearch: onDiscoverSearch,
      ),
    ),
  );
}

const _homeMoodChips = <String>[
  'All',
  'Relax',
  'Sleep',
  'Energize',
  'Sad',
];

const _searchFilterChips = <String>[
  'All',
  'Songs',
  'Videos',
  'Albums',
  'Artists',
];

enum _HomeSectionLayout { shelf, cards, grid, video, chart, artist }

/// Metrolist-style 2×2 picker (also used from the player overflow menu).
Future<int?> pickMetrolistSeekBarStyle(
  BuildContext context, {
  required int current,
}) {
  const previewAccent = Color(0xFFFF5C8D);
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget tile(int style, String label) {
        final sel = current == style;
        return Material(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(ctx, style),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: sel ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _MetrolistSeekPainter(
                        progress: 0.38,
                        dimmed: false,
                        style: style,
                        accent: previewAccent,
                        motion: 0,
                        motionPhase: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text(
          'Seek bar style',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.94),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: tile(0, 'Default')),
                  const SizedBox(width: 10),
                  Expanded(child: tile(2, 'Wavy')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: tile(1, 'Slim')),
                  const SizedBox(width: 10),
                  Expanded(child: tile(3, 'Squiggly')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    },
  );
}

String _formatStorageBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class FoxyHomeShell extends StatefulWidget {
  const FoxyHomeShell({super.key, this.homeBackgroundPath});

  final String? homeBackgroundPath;

  @override
  State<FoxyHomeShell> createState() => _FoxyHomeShellState();
}

class _FoxyHomeShellState extends State<FoxyHomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;
  final GlobalKey<_SearchTabState> _searchTabKey = GlobalKey<_SearchTabState>();
  final GlobalKey<_LibraryTabState> _libraryTabKey = GlobalKey<_LibraryTabState>();
  Map<String, dynamic> _player = const {};
  Map<String, dynamic> _account = const {};
  StreamSubscription<dynamic>? _sub;
  Timer? _miniPlayerSyncTimer;
  /// Avoid mini player + expanded sheet stacking (and Hero flights from feed art).
  bool _nowPlayingSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccount();
    unawaited(_syncPlayerFromNative());
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          _applyPlayerState(state);
        }
      } else if (type == 'accountChanged') {
        unawaited(_loadAccount());
      }
    });
    _miniPlayerSyncTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) {
        if (!mounted || _nowPlayingSheetOpen) return;
        unawaited(_syncPlayerFromNativeIfChanged());
      },
    );
  }

  void _applyPlayerState(Map<String, dynamic> state) {
    final next = _detachPlayerState(state);
    if (!_playerSnapshotChanged(_player, next)) return;
    setState(() => _player = next);
  }

  bool _playerSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (prev['playerEpoch'] != next['playerEpoch']) return true;
    if (prev['positionMs'] != next['positionMs']) return true;
    if (prev['durationMs'] != next['durationMs']) return true;
    if (prev['isPlaying'] != next['isPlaying']) return true;
    if (prev['isBuffering'] != next['isBuffering']) return true;
    if (prev['songIsLiked'] != next['songIsLiked']) return true;
    if (prev['paletteEpoch'] != next['paletteEpoch']) return true;
    final pVid = _asMap(prev['currentSong'])?['videoId']?.toString() ?? '';
    final nVid = _asMap(next['currentSong'])?['videoId']?.toString() ?? '';
    if (pVid != nVid) return true;
    final pArt = _asMap(prev['currentSong'])?['artwork']?.toString() ?? '';
    final nArt = _asMap(next['currentSong'])?['artwork']?.toString() ?? '';
    if (pArt != nArt) return true;
    final pOff =
        _asMap(prev['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    final nOff =
        _asMap(next['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    return pOff != nOff;
  }

  Future<void> _syncPlayerFromNativeIfChanged() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map != null && mounted) {
        _applyPlayerState(map);
      }
    } catch (_) {}
  }

  Future<void> _loadAccount() async {
    try {
      final map = _asMap(await _method.invokeMethod('accountInfo'));
      if (mounted && map != null) setState(() => _account = map);
    } catch (_) {}
  }

  Future<void> _syncPlayerFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map != null && mounted) {
        _applyPlayerState(map);
      }
    } catch (_) {}
  }

  Future<void> _openHomeSettings() async {
    Map<String, dynamic> appearance = const {};
    try {
      appearance =
          _asMap(await _method.invokeMethod('getAppearance')) ?? const {};
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Stack(
        fit: StackFit.expand,
        children: [
          _FoxyHomeBackdrop(
            customPath: widget.homeBackgroundPath,
            child: const SizedBox.expand(),
          ),
          _SettingsSheet(
            appearance: appearance,
            onSetAppearance: (patch) async {
              await _method.invokeMethod('setAppearance', patch);
            },
            account: _account,
            onAccountRefresh: _loadAccount,
            onOpenAccountHub: () {
              Navigator.of(sheetCtx).pop();
              Future.microtask(() {
                if (mounted) unawaited(_openAccountHub());
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openAccountHub() async {
    final h = MediaQuery.sizeOf(context).height;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: h * 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: ColoredBox(
            color: const Color(0xFF0B0B0B),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Expanded(child: _AccountHubBody(onPlay: _playSong)),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) await _loadAccount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _miniPlayerSyncTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPlayerFromNative());
    }
  }

  Future<void> _playSong(_Song song, List<_Song> queue, {bool radioTail = false}) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    final start = math.max(index, 0);
    if (mounted) {
      setState(() {
        _player = _detachPlayerState(<String, dynamic>{
          ..._player,
          'currentSong': song.toMap(),
          'isBuffering': true,
          'isPlaying': false,
          'positionMs': 0,
          'durationMs': 0,
          'queue': songs.map((item) => item.toMap()).toList(),
          'queueIndex': start,
        });
      });
    }
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': start,
      'radioTail': radioTail,
    });
    if (mounted) await _syncPlayerFromNative();
  }

  void _openSearchWithQuery(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() => _tabIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchTabKey.currentState?.applyExternalQuery(q);
    });
  }

  void _openPlayer({int initialTab = 0}) {
    setState(() => _nowPlayingSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final top = MediaQuery.paddingOf(sheetContext).top;
        final height = MediaQuery.sizeOf(sheetContext).height - top;
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: height,
              child: _NowPlayingSheet(
                player: _player,
                initialTab: initialTab,
                homeBackgroundPath: widget.homeBackgroundPath,
                onNotifyHomePlayerSync: _syncPlayerFromNative,
                onPlay: _playSong,
                onDiscoverSearch: _openSearchWithQuery,
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _nowPlayingSheetOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSongMap = _asMap(_player['currentSong']) ?? const {};
final currentSong = _Song.fromMap(currentSongMap);

final hasSong = currentSong.videoId.isNotEmpty && currentSong.title.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniBottom = bottomInset + 10;
    final tabs = [
      _HomeTab(
        key: const PageStorageKey('home-tab'),
        currentVideoId: currentSong.videoId,
        onPlay: _playSong,
        account: _account,
        onOpenSettings: _openHomeSettings,
        onDiscoverSearch: _openSearchWithQuery,
        homeBackgroundPath: widget.homeBackgroundPath,
      ),
      KeyedSubtree(
        key: const PageStorageKey('search-tab'),
        child: _SearchTab(
          key: _searchTabKey,
          onPlay: _playSong,
          onDiscoverSearch: _openSearchWithQuery,
        ),
      ),
      _LibraryTab(
        key: _libraryTabKey,
        onPlay: _playSong,
        onOpenSearch: () => setState(() => _tabIndex = 1),
        onDiscoverSearch: _openSearchWithQuery,
      ),
    ];
    final safeTab = _tabIndex.clamp(0, tabs.length - 1);
    if (safeTab != _tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tabIndex = safeTab);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        if (_libraryTabKey.currentState?.consumeAndroidBack() == true) {
          return;
        }
        if (safeTab == 1 &&
            (_searchTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab != 0) {
          setState(() => _tabIndex = 0);
          return;
        }
        unawaited(_method.invokeMethod('moveTaskToBack'));
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _FoxyHomeBackdrop(
            customPath: widget.homeBackgroundPath,
            child: const SizedBox.expand(),
          ),
          IndexedStack(index: safeTab, children: tabs),
          if (hasSong && !_nowPlayingSheetOpen)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: miniBottom),
                child: _MiniPlayer(
                  key: ValueKey<Object>(
                    _player['playerEpoch'] ?? currentSong.videoId,
                  ),
                  player: _player,
                  onOpen: () => _openPlayer(),
                  onResync: _syncPlayerFromNative,
                  glass: true,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _FoxyBottomNav(
        selectedIndex: safeTab,
        onSelected: (index) => setState(() => _tabIndex = index),
        transparent: true,
      ),
    ),
    );
  }
}

class _FoxyBottomNav extends StatelessWidget {
  const _FoxyBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    this.transparent = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Home'),
      (Icons.search_rounded, 'Search'),
      (Icons.library_music_rounded, 'Library'),
    ];
    final navRow = SizedBox(
      height: 54,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: transparent
                    ? _FoxyGlassButton(
                        blur: true,
                        onTap: () => onSelected(i),
                        selected: selectedIndex == i,
                        borderRadius: BorderRadius.circular(999),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].$1,
                              color: selectedIndex == i
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.55),
                              size: 22,
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                items[i].$2,
                                style: TextStyle(
                                  color: selectedIndex == i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Material(
                        color: selectedIndex == i
                            ? _kNavPillFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSelected(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                items[i].$1,
                                color: selectedIndex == i
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  items[i].$2,
                                  style: TextStyle(
                                    color: selectedIndex == i
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: transparent
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(
                    alpha: 0.22 + _kSubtleBlackTint,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: navRow,
                ),
              )
            : _FoxySurface(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                cornerRadius: 20,
                child: navRow,
              ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    super.key,
    required this.currentVideoId,
    required this.onPlay,
    required this.account,
    required this.onOpenSettings,
    this.onDiscoverSearch,
    this.homeBackgroundPath,
  });

  final String currentVideoId;
  final FoxyOnPlay onPlay;
  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final void Function(String query)? onDiscoverSearch;
  final String? homeBackgroundPath;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  List<_SongSection> _sections = _HomeCache.sections;
  bool _loading = _HomeCache.sections.isEmpty;
  String? _error = _HomeCache.error;
  String _homeChip = 'All';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (_HomeCache.sections.isEmpty) {
      _loadHome();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account['isSignedIn'] != widget.account['isSignedIn']) {
      unawaited(_loadHome(force: true));
    }
  }

  Future<void> _loadHome({bool force = false}) async {
    if (!force && _HomeCache.sections.isNotEmpty) {
      setState(() {
        _sections = _HomeCache.sections;
        _error = _HomeCache.error;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(await _method.invokeMethod('homeFeed')) ?? const {};
      final sections = (response['sections'] as List? ?? const [])
          .map((item) => _SongSection.fromMap(_asMap(item) ?? const {}))
          .where((section) => section.songs.isNotEmpty)
          .toList();
      _HomeCache.sections = sections;
      _HomeCache.error = null;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (e) {
      _HomeCache.error = e.toString();
      if (!mounted) return;
      setState(() {
        _error = _HomeCache.error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMood(String mood) async {
    try {
      final cached = _HomeCache.moodSections[mood];
      final section =
          cached ??
          _SongSection.fromMap(
            _asMap(await _method.invokeMethod('moodMix', {'mood': mood})) ??
                const {},
          );
      if (cached == null) _HomeCache.moodSections[mood] = section;
      if (!mounted || section.songs.isEmpty) return;
      setState(() {
        _sections = [
          section,
          ..._sections.where((item) => item.title != section.title),
        ];
        _HomeCache.sections = _sections;
      });
    } catch (_) {}
  }

  void _onHomeChip(String label) {
    setState(() => _homeChip = label);
    if (label == 'All') {
      _loadHome(force: true);
    } else {
      _loadMood(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    super.build(context);
    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF151515),
      onRefresh: () async {
        setState(() => _homeChip = 'All');
        await _loadHome(force: true);
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 480,
        slivers: [
          SliverToBoxAdapter(
            child: _HomeTopBar(
              account: widget.account,
              onOpenSettings: widget.onOpenSettings,
              selectedChip: _homeChip,
              onChipSelected: _onHomeChip,
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(child: _HomeLoading())
          else if (_error != null)
            SliverToBoxAdapter(
              child: _HomeError(
                message: _error!,
                onRetry: () {
                  unawaited(_loadHome(force: true));
                },
              ),
            )
          else if (_homeChip == 'All' && _sections.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No feed rows yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pull to refresh or open Search to find music.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _FoxyGlassTextButton(
                      label: 'Retry',
                      onPressed: () => unawaited(_loadHome(force: true)),
                    ),
                  ],
                ),
              ),
            )
          else if (_homeChip == 'All') ...[
            if (_sections.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _HomeQuickPicks(
                  songs: _sections
                      .expand((s) => s.songs)
                      .take(24)
                      .toList(),
                  currentVideoId: widget.currentVideoId,
                  onPlay: widget.onPlay,
                ),
              ),
              SliverToBoxAdapter(
                child: _HomeFreshFindsRow(
                  sections: _sections,
                  onPlay: widget.onPlay,
                  onDiscoverSearch: widget.onDiscoverSearch,
                ),
              ),
            ],
            for (final sec in _sections)
              SliverToBoxAdapter(
                child: _HomeFeedSection(
                  section: sec,
                  layout: _homeSectionLayout(sec),
                  currentVideoId: widget.currentVideoId,
                  onPlay: widget.onPlay,
                ),
              ),
          ]
          else if (_sections.isNotEmpty)
            SliverToBoxAdapter(
              child: _HomeSongCardsSection(
                section: _sections.first,
                currentVideoId: widget.currentVideoId,
                onPlay: widget.onPlay,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 120),
              child: Center(
                child: Text(
                  '@2026 FoxyMusic $_kAppVersionLabel',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _HomeCache {
  static List<_SongSection> sections = const [];
  static String? error;
  static final Map<String, _SongSection> moodSections = {};
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.account,
    required this.onOpenSettings,
    required this.selectedChip,
    required this.onChipSelected,
  });

  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final String selectedChip;
  final ValueChanged<String> onChipSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _FoxyAppLogo(size: 36, borderRadius: 10, showGlow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FoxyMusic',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _kAppVersionLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _GlassIconButton(
                  tooltip: 'Notifications',
                  icon: Icons.notifications_none_rounded,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No new notifications'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'History',
                  icon: Icons.history_rounded,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Open the Library tab for History'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Settings',
                  icon: Icons.settings_rounded,
                  onPressed: onOpenSettings,
                ),
              ],
            ),
            Text(
              _homeGreeting(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final label in _homeMoodChips)
                    _TopFilterChip(
                      label: label,
                      selected: selectedChip == label,
                      onTap: () => onChipSelected(label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _FoxyGlassButton(
        blur: true,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white.withValues(alpha: 0.88)),
        ),
      ),
    );
  }
}

String _homeGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Up late';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  if (h < 22) return 'Good evening';
  return 'Wind down';
}

/// Plain header for Library / Downloads (not the YT-style home hero).
class _ScreenTopBar extends StatelessWidget {
  const _ScreenTopBar({
    this.leading,
    required this.title,
    this.onRefresh,
    this.subtitle,
    this.onSearch,
    this.onSparkle,
    this.onDownloads,
  });

  final Widget? leading;
  final String title;
  final VoidCallback? onRefresh;
  final String? subtitle;
  final VoidCallback? onSearch;
  final VoidCallback? onSparkle;
  final VoidCallback? onDownloads;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) leading!,
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onDownloads != null)
                  _GlassIconButton(
                    tooltip: 'Downloads',
                    icon: Icons.download_rounded,
                    onPressed: onDownloads!,
                  ),
                if (onSparkle != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Discovery',
                    icon: Icons.auto_awesome_rounded,
                    onPressed: onSparkle!,
                  ),
                ],
                if (onSearch != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Search',
                    icon: Icons.search_rounded,
                    onPressed: onSearch!,
                  ),
                ],
                if (onRefresh != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: onRefresh!,
                  ),
                ],
              ],
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopFilterChip extends StatelessWidget {
  const _TopFilterChip({
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: selected,
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoxySurface extends StatelessWidget {
  const _FoxySurface({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.selected = false,
    this.onTap,
    this.cornerRadius = _kCardRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  final VoidCallback? onTap;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (onTap == null) {
      return Padding(
        padding: margin,
        child: _FoxyGlassTint(
          borderRadius: cornerRadius,
          tintOpacity: selected ? 0.34 : 0.22,
          borderOpacity: selected ? 0.2 : 0.1,
          child: Padding(padding: padding, child: child),
        ),
      );
    }
    return Padding(
      padding: margin,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: selected,
        borderRadius: BorderRadius.circular(cornerRadius),
        padding: padding,
        child: child,
      ),
    );
  }
}

class _FoxySectionHeader extends StatelessWidget {
  const _FoxySectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoxySongTile extends StatelessWidget {
  const _FoxySongTile({
    required this.song,
    required this.onTap,
    this.onMore,
    this.trailingIcon = Icons.play_circle_fill_rounded,
    this.active = false,
    this.index,
    this.thumbRadius = 6,
    this.songDownloadProgress,
    this.showPlayAndMore = false,
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final IconData trailingIcon;
  final bool active;
  final int? index;
  final double thumbRadius;
  /// When set (e.g. active Media3 / progressive download), a thin bar is shown under the row.
  final double? songDownloadProgress;
  /// When true with [onMore], shows both play and overflow actions (e.g. Downloads tab).
  final bool showPlayAndMore;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget trailing;
    if (onMore != null && showPlayAndMore) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play',
            onPressed: onTap,
            icon: Icon(trailingIcon, color: active ? accent : Colors.white),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      );
    } else if (onMore != null) {
      trailing = IconButton(
        tooltip: 'More',
        onPressed: onMore,
        icon: const Icon(Icons.more_vert_rounded),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: onTap,
        icon: Icon(trailingIcon, color: active ? accent : Colors.white),
      );
    }

    return _FoxySurface(
      selected: active,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (index != null) ...[
                SizedBox(
                  width: 26,
                  child: Text(
                    '${index! + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active ? accent : Colors.white.withValues(alpha: 0.42),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _Artwork(
                url: song.highQualityArtwork,
                size: 52,
                radius: thumbRadius,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          if (songDownloadProgress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: songDownloadProgress!.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.black.withValues(alpha: 0.22),
                color: accent.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FoxyFeatureTile extends StatelessWidget {
  const _FoxyFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _FoxySurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// SimpMusic-style full-screen results with Songs / Videos / Albums / Artists tabs.
class _SearchResultsPage extends StatefulWidget {
  const _SearchResultsPage({
    required this.query,
    required this.onPlay,
    this.onDiscoverSearch,
  });

  final String query;
  final FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<_SearchResultsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<_Song> _songs = const [];
  List<_Song> _videos = const [];
  List<_Song> _albums = const [];
  List<_Song> _artists = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = _asMap(
            await _method.invokeMethod('searchAll', {
              'query': widget.query,
              'limit': 28,
            }),
          ) ??
          const {};
      if (!mounted) return;
      List<_Song> parseList(String key) => (response[key] as List? ?? const [])
          .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
          .where((s) => s.videoId.isNotEmpty)
          .toList();
      setState(() {
        _songs = parseList('songs');
        _videos = parseList('videos');
        _albums = parseList('albums');
        _artists = parseList('artists');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  Widget _tabBody(List<_Song> items, {bool videoStyle = false}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (items.isEmpty) {
      return const _EmptyTabBody(
        icon: Icons.search_off_rounded,
        title: 'Nothing here',
        subtitle: 'Try another spelling or category.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final song = items[index];
        return _FoxySongTile(
          song: song,
          index: index,
          thumbRadius: 12,
          showPlayAndMore: true,
          trailingIcon: videoStyle
              ? Icons.play_circle_outline_rounded
              : Icons.play_circle_fill_rounded,
          onTap: () => widget.onPlay(
            song,
            items,
            radioTail: !videoStyle,
          ),
          onMore: () => _openMenu(song, items),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _FoxyBrandGradientBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Results',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Material(
              color: Colors.black.withValues(alpha: 0.35),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                indicatorColor: accent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: [
                  Tab(text: 'Songs (${_loading ? '…' : _songs.length})'),
                  Tab(text: 'Videos (${_loading ? '…' : _videos.length})'),
                  Tab(text: 'Albums (${_loading ? '…' : _albums.length})'),
                  Tab(text: 'Artists (${_loading ? '…' : _artists.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _tabBody(_songs),
                  _tabBody(_videos, videoStyle: true),
                  _tabBody(_albums),
                  _tabBody(_artists),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  const _SearchTab({
    super.key,
    required this.onPlay,
    required this.onDiscoverSearch,
  });

  final FoxyOnPlay onPlay;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _filter = 'All';
  String? _error;
  bool _loading = false;
  Timer? _debounce;
  List<_Song> _songs = const [];
  List<_Song> _videos = const [];
  List<_Song> _albums = const [];
  List<_Song> _artists = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void applyExternalQuery(String raw) {
    final q = raw.trim();
    setState(() {
      _query = q;
      _controller.text = q;
      _error = null;
    });
    if (q.length >= 2) {
      unawaited(_runSearch(q));
    }
  }

  bool consumeAndroidBack() {
    if (_controller.text.trim().isEmpty &&
        _query.trim().isEmpty &&
        _error == null &&
        !_hasResults) {
      return false;
    }
    setState(() {
      _controller.clear();
      _query = '';
      _filter = 'All';
      _error = null;
      _songs = const [];
      _videos = const [];
      _albums = const [];
      _artists = const [];
      _loading = false;
    });
    return true;
  }

  bool get _hasResults =>
      _songs.isNotEmpty ||
      _videos.isNotEmpty ||
      _albums.isNotEmpty ||
      _artists.isNotEmpty;

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _error = null;
    });
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _loading = false;
        _songs = const [];
        _videos = const [];
        _albums = const [];
        _artists = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(_runSearch(q));
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = _asMap(
            await _method.invokeMethod('searchAll', {
              'query': query,
              'limit': 24,
            }),
          ) ??
          const {};
      if (!mounted || _query.trim() != query) return;
      List<_Song> parseList(String key) =>
          (response[key] as List? ?? const [])
              .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
              .where((s) => s.videoId.isNotEmpty)
              .toList();
      setState(() {
        _songs = parseList('songs');
        _videos = parseList('videos');
        _albums = parseList('albums');
        _artists = parseList('artists');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.length < 2) return;
    _debounce?.cancel();
    unawaited(_runSearch(query));
  }

  List<({_Song song, bool isArtist})> get _visibleRows {
    switch (_filter) {
      case 'Songs':
        return _songs.map((s) => (song: s, isArtist: false)).toList();
      case 'Videos':
        return _videos.map((s) => (song: s, isArtist: false)).toList();
      case 'Albums':
        return _albums.map((s) => (song: s, isArtist: false)).toList();
      case 'Artists':
        return _artists.map((s) => (song: s, isArtist: true)).toList();
      default:
        return [
          ..._artists.map((s) => (song: s, isArtist: true)),
          ..._songs.map((s) => (song: s, isArtist: false)),
          ..._videos.map((s) => (song: s, isArtist: false)),
          ..._albums.map((s) => (song: s, isArtist: false)),
        ];
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accent = Theme.of(context).colorScheme.primary;
    final suggestions = const [
      'Arijit Singh',
      'Punjabi hits',
      'Lo-fi Hindi',
      'Workout mix',
      'New music',
      'Romantic songs',
    ];
    final rows = _visibleRows;
    final showResults = _query.trim().length >= 2;

    return CustomScrollView(
        key: const PageStorageKey('search-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        cacheExtent: 400,
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FoxyGlassTint(
                      borderRadius: 28,
                      tintOpacity: 0.52,
                      borderOpacity: 0.16,
                      child: TextField(
                      controller: _controller,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _submitSearch,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists, albums',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: _FoxyGlassButton(
                                  onTap: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                  borderRadius: BorderRadius.circular(999),
                                  padding: EdgeInsets.zero,
                                  child: const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(
                            color: accent.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    ),
                    if (showResults) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final label in _searchFilterChips)
                              _TopFilterChip(
                                label: label,
                                selected: _filter == label,
                                onTap: () => setState(() => _filter = label),
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in suggestions)
                            _FoxyGlassButton(
                              onTap: () {
                                _controller.text = item;
                                _controller.selection =
                                    TextSelection.collapsed(
                                  offset: item.length,
                                );
                                _submitSearch(item);
                              },
                              borderRadius: BorderRadius.circular(28),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                item,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (showResults && _loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (showResults && rows.isEmpty && _error == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No results for “${_query.trim()}”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else if (showResults)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = rows[index];
                  final song = row.song;
                  final queue = row.isArtist ? _artists : _songs;
                  return _SimpMusicSearchRow(
                    song: song,
                    isArtist: row.isArtist,
                    onTap: () => widget.onPlay(
                      song,
                      queue.isEmpty ? [song] : queue,
                      radioTail: !row.isArtist,
                    ),
                    onMore: () => _openMenu(
                      song,
                      queue.isEmpty ? [song] : queue,
                    ),
                  );
                },
                childCount: rows.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
    );
  }
}

class _SimpMusicSearchRow extends StatelessWidget {
  const _SimpMusicSearchRow({
    required this.song,
    required this.isArtist,
    required this.onTap,
    required this.onMore,
  });

  final _Song song;
  final bool isArtist;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final thumbSize = isArtist ? 52.0 : 52.0;
    Widget leading;
    if (isArtist) {
      leading = ClipOval(
        child: _Artwork(
          url: song.highQualityArtwork,
          size: thumbSize,
          radius: 0,
          identityTag: song.videoId,
        ),
      );
    } else {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _Artwork(
          url: song.highQualityArtwork,
          size: thumbSize,
          radius: 0,
          identityTag: song.videoId,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        blurSigma: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isArtist ? song.artist.ifBlank(song.title) : song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArtist ? 'Artists' : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _FoxyGlassButton(
              onTap: onMore,
              borderRadius: BorderRadius.circular(999),
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryRichTile extends StatelessWidget {
  const _LibraryRichTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      blurSigma: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.black87, size: 24),
            ),
          ),
          const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Metrolist-style downloads summary (storage + offline count).
class _MetrolistDownloadsHeader extends StatefulWidget {
  const _MetrolistDownloadsHeader({
    required this.songCount,
    required this.activeCount,
    this.onPlayAll,
  });

  final int songCount;
  final int activeCount;
  final VoidCallback? onPlayAll;

  @override
  State<_MetrolistDownloadsHeader> createState() =>
      _MetrolistDownloadsHeaderState();
}

class _MetrolistDownloadsHeaderState extends State<_MetrolistDownloadsHeader> {
  Map<String, dynamic> _storage = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = _asMap(await _method.invokeMethod('storageStats')) ?? const {};
      if (!mounted) return;
      setState(() {
        _storage = raw;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bytes = ((_storage['downloadBytes'] ?? 0) as num).toInt();
  return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_done_rounded,
                    color: accent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Downloads',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _loading
                              ? 'Calculating storage…'
                              : '${widget.songCount} songs offline · ${_formatStorageBytes(bytes)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onPlayAll != null)
                    FilledButton.icon(
                      onPressed: widget.onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
                    ),
                ],
              ),
              if (widget.activeCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${widget.activeCount} active download${widget.activeCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    super.key,
    required this.onPlay,
    required this.onOpenSearch,
    required this.onDiscoverSearch,
  });

  final FoxyOnPlay onPlay;
  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin {
  static const int _scopeHub = 0;
  static const int _scopeLiked = 1;
  static const int _scopeHistory = 2;
  static const int _scopeDownloads = 3;
  static const int _scopeMostPlayed = 4;
  static const int _scopePlaylists = 5;

  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _downloads = const [];
  List<_Song> _mostPlayed = const [];
  List<_Song> _recentlyAdded = const [];
  List<_UserPlaylist> _userPlaylists = const [];
  int _scope = _scopeHub;
  final Map<String, double> _downloadProgress = {};
  StreamSubscription<dynamic>? _libraryEvents;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _libraryEvents = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null || !mounted) return;
      final type = map['type']?.toString();
      if (type == 'libraryDownloadProgress') {
        final raw = _asMap(map['downloadProgress']);
        if (raw == null) return;
        final next = <String, double>{};
        raw.forEach((k, v) {
          if (v is num) next[k.toString()] = v.toDouble();
        });
        setState(() {
          _downloadProgress
            ..clear()
            ..addAll(next);
        });
      } else if (type == 'libraryDownloadsChanged' ||
          type == 'libraryFeedChanged' ||
          type == 'accountChanged') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _libraryEvents?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final response =
        _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;
    setState(() {
      _liked = _songsFrom(response['liked']);
      _history = _songsFrom(response['history']);
      _downloads = _songsFrom(response['downloads']);
      _mostPlayed = _songsFrom(response['mostPlayed']);
      _recentlyAdded = _songsFrom(response['recentlyAdded']);
      _userPlaylists = _userPlaylistsFrom(response['userPlaylists']);
      _loading = false;
    });
  }

  bool get _hub => _scope == _scopeHub;

  List<_Song> get _activeSongs {
    switch (_scope) {
      case _scopeLiked:
        return _liked;
      case _scopeHistory:
        return _history;
      case _scopeDownloads:
        return _downloads;
      case _scopeMostPlayed:
        return _mostPlayed;
      case _scopePlaylists:
        return const [];
      default:
        return _recentlyAdded;
    }
  }

  String get _sectionTitle {
    switch (_scope) {
      case _scopeLiked:
        return 'Liked';
      case _scopeHistory:
        return 'History';
      case _scopeDownloads:
        return 'Downloaded';
      case _scopeMostPlayed:
        return 'Most played';
      case _scopePlaylists:
        return 'Your playlists';
      default:
        return 'Recently added';
    }
  }

  void _goHub() => setState(() => _scope = _scopeHub);

  /// Used from Home to jump into Library drill-ins.
  void openAtScope(int scope) {
    if (!mounted) return;
    setState(() {
      _scope = scope.clamp(_scopeHub, _scopePlaylists);
    });
  }

  /// System back: leave a library drill-in (Liked, History, …) before tabs handle back.
  bool consumeAndroidBack() {
    if (_hub) return false;
    _goHub();
    return true;
  }

  void _openSongOverflow(BuildContext context, _Song song, List<_Song> queue) {
    showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: _load,
    );
  }

  Future<void> _playUserPlaylist(
    BuildContext snackContext,
    _UserPlaylist p,
  ) async {
    await playFetchedUserPlaylist(snackContext, p, widget.onPlay);
  }

  void _shuffleCurrent() {
    final s = _activeSongs;
    if (s.isEmpty) return;
    final list = List<_Song>.from(s)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  Widget _librarySectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _hubGrid() {
    void pick(String q) => widget.onDiscoverSearch(q);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _librarySectionTitle('PICKS FOR YOU'),
          Row(
            children: [
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFFFB74D),
                  icon: Icons.auto_awesome_rounded,
                  title: 'Quick picks',
                  subtitle: 'Fresh mixes',
                  onTap: () => pick('quick pick music'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFF80DEEA),
                  icon: Icons.explore_rounded,
                  title: 'Your Daily Discover',
                  subtitle: 'Personal blend',
                  onTap: () => pick('discover mix today'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFF48FB1),
                  icon: Icons.new_releases_rounded,
                  title: 'New releases',
                  subtitle: 'Latest drops',
                  onTap: () => pick('new release music'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFCE93D8),
                  icon: Icons.stacked_line_chart_rounded,
                  title: 'Charts',
                  subtitle: "What's trending",
                  onTap: () => pick('top songs charts today'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFA1887F),
                  icon: Icons.shuffle_rounded,
                  title: 'Mixed for you',
                  subtitle: 'Genre blend',
                  onTap: () => pick('mixed pop hits playlist'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFF7986CB),
                  icon: Icons.local_fire_department_rounded,
                  title: 'Trending now',
                  subtitle: 'Hot tracks',
                  onTap: () => pick('trending songs now'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFFF8A65),
                  icon: Icons.bolt_rounded,
                  title: 'Energy boost',
                  subtitle: 'Workout & drive',
                  onTap: () => pick('high energy workout music'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFF81C784),
                  icon: Icons.spa_rounded,
                  title: 'Chill & focus',
                  subtitle: 'Wind down',
                  onTap: () => pick('chill relax focus music'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFF64B5F6),
                  icon: Icons.nightlight_round,
                  title: 'Sleep sounds',
                  subtitle: 'Soft & calm',
                  onTap: () => pick('sleep ambient music'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LibraryRichTile(
                  color: const Color(0xFFFFD54F),
                  icon: Icons.wb_sunny_rounded,
                  title: 'Feel-good',
                  subtitle: 'Sunshine vibes',
                  onTap: () => pick('feel good happy songs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LibraryRichTile(
            color: const Color(0xFF4FC3F7),
            icon: Icons.podcasts_rounded,
            title: 'Deep cuts',
            subtitle: 'Hidden gems & live',
            onTap: () => pick('deep cuts live sessions'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final songs = _activeSongs;
    final chips = <(IconData, String, int)>[
      (Icons.explore_rounded, 'Discover', _scopeHub),
      (Icons.favorite_rounded, 'Liked', _scopeLiked),
      (Icons.history_rounded, 'History', _scopeHistory),
      (Icons.download_rounded, 'Downloads', _scopeDownloads),
      (Icons.trending_up_rounded, 'Most played', _scopeMostPlayed),
      (Icons.playlist_play_rounded, 'Playlists', _scopePlaylists),
    ];

    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 400,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            leading: !_hub
                ? _GlassIconButton(
                    tooltip: 'Back to Discover',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _goHub,
                  )
                : null,
            title: 'Library',
            subtitle: _hub
                ? '${_liked.length} liked · ${_downloads.length} offline · ${_userPlaylists.length} playlists'
                : _sectionTitle,
            onRefresh: _load,
            onSearch: widget.onOpenSearch,
            onDownloads: _hub
                ? () => setState(() => _scope = _scopeDownloads)
                : null,
            onSparkle: () => widget.onDiscoverSearch('top songs charts today'),
          ),
        ),
        if (_scope == _scopeDownloads)
          SliverToBoxAdapter(
            child: _MetrolistDownloadsHeader(
              songCount: _downloads.length,
              activeCount: _downloadProgress.length,
              onPlayAll: _downloads.isEmpty
                  ? null
                  : () => widget.onPlay(_downloads.first, _downloads),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FoxyGlassButton(
                        onTap: () => setState(() => _scope = chip.$3),
                        selected: _scope == chip.$3,
                        borderRadius: BorderRadius.circular(20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(chip.$1, size: 18, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              chip.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_hub) ...[
          SliverToBoxAdapter(child: _hubGrid()),
          if (_userPlaylists.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Row(
                  children: [
                    Text(
                      'Playlists',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final c = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('New playlist'),
                            content: TextField(
                              controller: c,
                              decoration:
                                  const InputDecoration(hintText: 'Name'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  dCtx,
                                  c.text.trim(),
                                ),
                                child: const Text('Create'),
                              ),
                            ],
                          ),
                        );
                        if (name != null && name.isNotEmpty && mounted) {
                          await _method.invokeMethod('playlistCreate', {
                            'name': name,
                          });
                          await _load();
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
            ),
          if (_userPlaylists.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 88,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _userPlaylists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = _userPlaylists[i];
                    final art =
                        p.songs.isEmpty ? '' : p.songs.first.artwork;
                    return Material(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (p.songs.isEmpty) return;
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: const Color(0xFF111111),
                            builder: (ctx) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.65,
                              maxChildSize: 0.92,
                              builder: (_, scroll) => ListView(
                                controller: scroll,
                                padding: const EdgeInsets.all(12),
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  for (var j = 0; j < p.songs.length; j++)
                                    _FoxySongTile(
                                      song: p.songs[j],
                                      index: j,
                                      thumbRadius: 10,
                                      showPlayAndMore: true,
                                      onTap: () =>
                                          widget.onPlay(p.songs[j], p.songs),
                                      onMore: () => _openSongOverflow(
                                        context,
                                        p.songs[j],
                                        p.songs,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 200,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: art.isEmpty
                                      ? Container(
                                          width: 48,
                                          height: 48,
                                          color: Colors.grey.shade800,
                                          child: const Icon(
                                            Icons.queue_music_rounded,
                                          ),
                                        )
                                      : Image.network(
                                          art,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(
              children: [
                Text(
                  _hub ? 'Recently added' : _sectionTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (songs.isNotEmpty && _scope != _scopePlaylists) ...[
                  IconButton.filledTonal(
                    tooltip: 'Shuffle',
                    onPressed: _shuffleCurrent,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => widget.onPlay(songs.first, songs),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_scope == _scopeDownloads && _downloadProgress.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active downloads',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final e in _downloadProgress.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _songTitleForVideoId(
                                      e.key,
                                      _liked,
                                      _history,
                                      _downloads,
                                      _recentlyAdded,
                                      _mostPlayed,
                                    ) ??
                                    'Track ${e.key}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value.clamp(0.0, 1.0),
                                  minHeight: 5,
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.25),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_scope == _scopePlaylists)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  if (_userPlaylists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Create a playlist with “New” above, add songs from the ··· menu, or sign in on the Account tab to load your YouTube Music playlists.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    for (final p in _userPlaylists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: Icon(
                              p.isYoutube
                                  ? Icons.cloud_queue_rounded
                                  : Icons.queue_music_rounded,
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                              p.isYoutube
                                  ? '${p.displayTrackCount} songs · YouTube Music'
                                  : '${p.displayTrackCount} songs · On device',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: () => _playUserPlaylist(context, p),
                            ),
                            onTap: () => _playUserPlaylist(context, p),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (songs.isEmpty && _scope != _scopePlaylists)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_sectionTitle),
              title: 'Nothing here yet',
              subtitle:
                  'Play music, like tracks, and download for offline — your library grows automatically.',
            ),
          )
        else if (_scope != _scopePlaylists && songs.isNotEmpty)
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final dl = _scope == _scopeDownloads;
              if (dl) {
                return _FoxySongTile(
                  song: song,
                  index: index,
                  thumbRadius: 12,
                  trailingIcon: Icons.play_circle_fill_rounded,
                  showPlayAndMore: true,
                  onTap: () => widget.onPlay(song, songs),
                  onMore: () => _openSongOverflow(context, song, songs),
                );
              }
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 12,
                trailingIcon: Icons.play_circle_fill_rounded,
                showPlayAndMore: true,
                onTap: () => widget.onPlay(song, songs),
                onMore: () => _openSongOverflow(context, song, songs),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _AccountHubBody extends StatefulWidget {
  const _AccountHubBody({required this.onPlay});

  final FoxyOnPlay onPlay;

  @override
  State<_AccountHubBody> createState() => _AccountHubBodyState();
}

class _AccountHubBodyState extends State<_AccountHubBody>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _appearance = const {};
  Map<String, dynamic> _account = const {};
  Map<String, List<_Song>> _library = const {};
  int _section = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('getAppearance'),
      _method.invokeMethod('accountInfo'),
      _method.invokeMethod('libraryFeed'),
    ]);
    final appearance = _asMap(values[0]) ?? const {};
    final account = _asMap(values[1]) ?? const {};
    final libraryMap = _asMap(values[2]) ?? const {};
    final library = <String, List<_Song>>{
      'Liked': _songsFrom(libraryMap['liked']),
      'Playlists': _songsFrom(libraryMap['playlists'] ?? libraryMap['saved']),
      'History': _songsFrom(libraryMap['history']),
      'Downloads': _songsFrom(libraryMap['downloads']),
    };
    if (mounted) {
      setState(() {
        _appearance = appearance;
        _account = account;
        _library = library;
      });
    }
  }

  Future<void> _setAppearance(Map<String, dynamic> patch) async {
    await _method.invokeMethod('setAppearance', patch);
    await _load();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        appearance: _appearance,
        onSetAppearance: _setAppearance,
        account: _account,
        onAccountRefresh: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final signedIn = _account['isSignedIn'] == true;
    final displayName =
        _account['displayName']?.toString().ifBlank('Guest listener') ??
        'Guest listener';
    final email = _account['email']?.toString() ?? '';
    final avatar = _account['avatarUrl']?.toString() ?? '';
    final sections = _library.keys.toList();
    final selectedTitle = sections.isEmpty
        ? 'Liked'
        : sections[_section.clamp(0, sections.length - 1).toInt()];
    final songs = _library[selectedTitle] ?? const [];
    return CustomScrollView(
      key: const PageStorageKey('me-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  _AccountAvatar(name: displayName, imageUrl: avatar, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          signedIn
                              ? email.ifBlank('YouTube Music connected')
                              : 'Connect YouTube Music for your library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountSummaryCard(
                  signedIn: signedIn,
                  liked: ((_account['likedCount'] ?? 0) as num).toInt(),
                  playlists: ((_account['playlistCount'] ?? 0) as num).toInt(),
                  downloads: ((_account['downloadCount'] ?? 0) as num).toInt(),
                ),
                const SizedBox(height: 12),
                _FoxyFeatureTile(
                  icon: signedIn ? Icons.verified_rounded : Icons.login_rounded,
                  title: signedIn
                      ? 'Account connected'
                      : 'Connect YouTube Music',
                  subtitle: signedIn
                      ? 'Personalized home, account library, and recommendations are active.'
                      : 'Sign in for personalized home, library sync foundation, and better results.',
                  onTap: signedIn
                      ? null
                      : () => _method.invokeMethod('openWebLogin', {
                            'mode': 'webview',
                          }),
                ),
                _FoxyFeatureTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Player and audio',
                  subtitle:
                      'Equalizer, queue memory, crossfade, sleep timer, and stream quality.',
                  onTap: _openSettings,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: sections.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final label = sections[index];
                      return ChoiceChip(
                        selected: _section == index,
                        label: Text(label),
                        avatar: Icon(_sectionIcon(label), size: 18),
                        onSelected: (_) => setState(() => _section = index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(selectedTitle),
              title: 'No $selectedTitle yet',
              subtitle: selectedTitle == 'Playlists'
                  ? 'Saved playlists and library collections will appear here.'
                  : 'Your $selectedTitle songs will show up here.',
            ),
          )
        else
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 10,
                onTap: () => widget.onPlay(song, songs),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 172)),
      ],
    );
  }
}

List<_Song> _songsFrom(dynamic value) => (value as List? ?? const [])
    .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
    .where((song) => song.videoId.isNotEmpty)
    .toList();

class _UserPlaylist {
  const _UserPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    this.source = 'local',
    this.songCount,
  });

  factory _UserPlaylist.fromMap(Map<String, dynamic> map) => _UserPlaylist(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Playlist',
        songs: (map['songs'] as List? ?? const [])
            .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
            .where((s) => s.videoId.isNotEmpty)
            .toList(),
        source: map['source']?.toString() ?? 'local',
        songCount: (map['songCount'] as num?)?.toInt(),
      );

  final String id;
  final String name;
  final List<_Song> songs;
  final String source;
  final int? songCount;

  bool get isYoutube => source == 'youtube';

  int get displayTrackCount =>
      songs.isNotEmpty ? songs.length : (songCount ?? 0);
}

List<_UserPlaylist> _userPlaylistsFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _UserPlaylist.fromMap(_asMap(e) ?? const {}))
        .where((p) => p.id.isNotEmpty)
        .toList();

Future<void> playFetchedUserPlaylist(
  BuildContext context,
  _UserPlaylist p,
  FoxyOnPlay onPlay,
) async {
  if (p.songs.isNotEmpty) {
    onPlay(p.songs.first, p.songs);
    return;
  }
  if (!p.isYoutube) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This playlist is empty')),
    );
    return;
  }
  final raw = await _method.invokeMethod('playlistFetchSongs', {
    'playlistId': p.id,
  });
  final songs = _songsFrom(raw);
  if (!context.mounted) return;
  if (songs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not load tracks from YouTube Music. Try signing in again on the Account tab.',
        ),
      ),
    );
    return;
  }
  onPlay(songs.first, songs);
}

String? _songTitleForVideoId(
  String videoId,
  List<_Song> liked,
  List<_Song> history,
  List<_Song> downloads,
  List<_Song> recent,
  List<_Song> mostPlayed,
) {
  for (final list in [downloads, liked, recent, mostPlayed, history]) {
    for (final s in list) {
      if (s.videoId == videoId) return s.title;
    }
  }
  return null;
}

Future<void> showFoxySongOverflowMenu(
  BuildContext context, {
  required _Song song,
  required FoxyOnPlay onPlay,
  required List<_Song> queueForPlay,
  void Function(String query)? onDiscoverSearch,
  Future<void> Function()? onLibraryChanged,
  List<_Song>? searchResultsForExtras,
  String bulkQueuePlayTitle = 'Play all search results',
  String bulkQueuePlaySubtitle = 'Keeps the current result order',
  VoidCallback? onOpenLyricsTabInPlayer,
  int? playerProgressStyleForPicker,
  Future<void> Function(int style)? onPickPlayerProgressStyle,
  int? playerSeekMotionForPicker,
  Future<void> Function(int motion)? onPickPlayerSeekMotion,
  bool showRemoveFromQueue = false,
}) async {
  final feed = _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
  final likedIds =
      Set<String>.from(_songsFrom(feed['liked']).map((s) => s.videoId));
  final downloadedIds =
      Set<String>.from(_songsFrom(feed['downloads']).map((s) => s.videoId));
  final userPlaylists = _userPlaylistsFrom(feed['userPlaylists']);
  final appearance = _asMap(await _method.invokeMethod('getAppearance')) ?? const {};
  final crossfadeMs = ((appearance['crossfadeMs'] ?? 0) as num).toInt();
  final crossfadeOn = crossfadeMs > 0;
  final lrclib = appearance['lyricsPreferLrclib'] != false;
  final normalizeOn = appearance['normalizeVolume'] == true;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _Artwork(
                  url: song.artwork,
                  size: 52,
                  radius: 10,
                  identityTag: song.videoId,
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              if (onPickPlayerProgressStyle != null &&
                  playerProgressStyleForPicker != null) ...[
                ListTile(
                  leading: const Icon(Icons.linear_scale_rounded),
                  title: const Text('Progress bar style'),
                  subtitle: Text(
                    '${_playerProgressStyleLabel(playerProgressStyleForPicker!)} · '
                    '${playerSeekMotionForPicker != null ? _playerSeekMotionLabel(playerSeekMotionForPicker!) : 'Static'}',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    final next = await pickMetrolistSeekBarStyle(
                      context,
                      current: playerProgressStyleForPicker!,
                    );
                    if (next != null && context.mounted) {
                      await onPickPlayerProgressStyle!(next);
                    }
                    if (!context.mounted ||
                        onPickPlayerSeekMotion == null ||
                        playerSeekMotionForPicker == null) {
                      return;
                    }
                    final motion = await showDialog<int>(
                      context: context,
                      builder: (dCtx) => SimpleDialog(
                        backgroundColor: const Color(0xFF181818),
                        title: const Text('Progress animation'),
                        children: [
                          for (final e in <(int, String)>[
                            (0, 'Static'),
                            (1, 'Pulse thumb'),
                            (2, 'Shimmer'),
                          ])
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(dCtx, e.$1),
                              child: Text(e.$2),
                            ),
                        ],
                      ),
                    );
                    if (motion != null && context.mounted) {
                      await onPickPlayerSeekMotion(motion);
                    }
                  },
                ),
                const Divider(height: 1),
              ],
              if (searchResultsForExtras != null &&
                  searchResultsForExtras.length > 1) ...[
                ListTile(
                  leading: const Icon(Icons.podcasts_outlined),
                  title: const Text('Play with smart radio'),
                  subtitle: const Text(
                    'Builds a station from this track',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onPlay(song, [song], radioTail: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(bulkQueuePlayTitle),
                  subtitle: Text(bulkQueuePlaySubtitle),
                  onTap: () {
                    Navigator.pop(ctx);
                    onPlay(song, searchResultsForExtras);
                  },
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: Icon(
                  likedIds.contains(song.videoId)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: likedIds.contains(song.videoId)
                      ? const Color(0xFFE53935)
                      : Colors.white,
                ),
                title: Text(
                  likedIds.contains(song.videoId) ? 'Liked' : 'Like',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _method.invokeMethod(
                    likedIds.contains(song.videoId) ? 'unlike' : 'like',
                    {'song': song.toMap()},
                  );
                  await onLibraryChanged?.call();
                },
              ),
              ListTile(
                leading: Icon(
                  downloadedIds.contains(song.videoId) || song.isDownloaded
                      ? Icons.offline_pin_rounded
                      : Icons.download_outlined,
                ),
                title: Text(
                  downloadedIds.contains(song.videoId) || song.isDownloaded
                      ? 'Downloaded'
                      : 'Download',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (downloadedIds.contains(song.videoId) ||
                      song.isDownloaded) {
                    await _method.invokeMethod(
                      'removeDownload',
                      {'song': song.toMap()},
                    );
                  } else {
                    await _method.invokeMethod(
                      'download',
                      {'song': song.toMap()},
                    );
                  }
                  await onLibraryChanged?.call();
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to a playlist'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickPlaylistToAddSong(
                    context,
                    song: song,
                    playlists: userPlaylists,
                    onChanged: onLibraryChanged,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_play_next_rounded),
                title: const Text('Play next'),
                onTap: () {
                  Navigator.pop(ctx);
                  _method.invokeMethod('enqueuePlayNext', {
                    'song': song.toMap(),
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Add to queue'),
                onTap: () {
                  Navigator.pop(ctx);
                  _method.invokeMethod('addToQueue', {'song': song.toMap()});
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline_rounded),
                title: const Text('Artists'),
                subtitle: Text(
                  song.artist,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDiscoverSearch?.call(song.artist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Play this track'),
                onTap: () {
                  Navigator.pop(ctx);
                  onPlay(song, [song]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio_rounded),
                title: const Text('Start smart radio'),
                subtitle: const Text(
                  'Genre-aware station from this track (Metrolist-style)',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onPlay(song, [song], radioTail: true);
                },
              ),
              ListTile(
                leading: Icon(
                  lrclib ? Icons.lyrics_rounded : Icons.subtitles_rounded,
                ),
                title: const Text('Lyrics source'),
                subtitle: Text(
                  lrclib
                      ? 'LRCLIB first, then YouTube captions'
                      : 'YouTube captions first, then LRCLIB',
                ),
                trailing: Switch(
                  value: lrclib,
                  onChanged: (v) async {
                    Navigator.pop(ctx);
                    await _method.invokeMethod('setAppearance', {
                      'lyricsPreferLrclib': v,
                    });
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v
                              ? 'Synced lyrics will prefer LRCLIB.'
                              : 'Synced lyrics will prefer YouTube captions.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _method.invokeMethod('setAppearance', {
                    'lyricsPreferLrclib': !lrclib,
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Crossfade'),
                subtitle: Text(
                  crossfadeOn
                      ? '${(crossfadeMs / 1000).round()}s fade between tracks'
                      : 'Off — enable for smooth transitions',
                ),
                trailing: Switch(
                  value: crossfadeOn,
                  onChanged: (v) async {
                    Navigator.pop(ctx);
                    await _method.invokeMethod('setAppearance', {
                      'crossfadeMs': v ? 5000 : 0,
                    });
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v
                              ? 'Crossfade on (5s) — volume ramps at track ends.'
                              : 'Crossfade off.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _method.invokeMethod('setAppearance', {
                    'crossfadeMs': crossfadeOn ? 0 : 5000,
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Normalize volume'),
                subtitle: Text(
                  normalizeOn
                      ? 'On — quieter peaks for steadier loudness'
                      : 'Off — original stream levels',
                ),
                trailing: Switch(
                  value: normalizeOn,
                  onChanged: (v) async {
                    Navigator.pop(ctx);
                    await _method.invokeMethod('setAppearance', {
                      'normalizeVolume': v,
                    });
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v ? 'Volume normalization on.' : 'Volume normalization off.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _method.invokeMethod('setAppearance', {
                    'normalizeVolume': !normalizeOn,
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_rounded),
                title: const Text('Sleep timer'),
                onTap: () {
                  Navigator.pop(ctx);
                  _method.invokeMethod('sleepTimer', {'minutes': 30});
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('Playback speed & pitch'),
                subtitle: Text(
                  crossfadeOn
                      ? 'Crossfade is on — speed changes may sound uneven.'
                      : 'Quick presets (applies to the native player)',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  final speed = await showDialog<double>(
                    context: context,
                    builder: (dCtx) => SimpleDialog(
                      title: const Text('Playback speed'),
                      children: [
                        for (final v in [0.75, 1.0, 1.25, 1.5])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(dCtx, v),
                            child: Text('${v}x'),
                          ),
                      ],
                    ),
                  );
                  if (speed != null && context.mounted) {
                    await _method.invokeMethod('setPlaybackSpeed', {
                      'speed': speed,
                      'pitch': 1.0,
                    });
                  }
                },
              ),
              if (onOpenLyricsTabInPlayer != null)
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open synced lyrics tab'),
                  subtitle: const Text('Full-width lyrics in this player'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpenLyricsTabInPlayer!();
                  },
                ),
              if (showRemoveFromQueue)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Remove from queue'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _method.invokeMethod('removeFromQueue', {
                      'song': song.toMap(),
                    });
                  },
                ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Share'),
                onTap: () async {
                  final link =
                      'https://music.youtube.com/watch?v=${song.videoId}';
                  await Clipboard.setData(ClipboardData(text: link));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _pickPlaylistToAddSong(
  BuildContext context, {
  required _Song song,
  required List<_UserPlaylist> playlists,
  Future<void> Function()? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF151515),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            onTap: () async {
              Navigator.pop(ctx);
              final nameCtrl = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Playlist name'),
                  content: TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(hintText: 'My mix'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        dCtx,
                        nameCtrl.text.trim(),
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty && context.mounted) {
                await _method.invokeMethod('playlistCreate', {'name': name});
                await onChanged?.call();
                if (!context.mounted) return;
                await _pickPlaylistToAddSong(
                  context,
                  song: song,
                  playlists: _userPlaylistsFrom(
                    (_asMap(await _method.invokeMethod('libraryFeed')) ??
                            const {})['userPlaylists'],
                  ),
                  onChanged: onChanged,
                );
              }
            },
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                'No playlists yet. Tap “New playlist” above.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.42,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (c, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: Icon(
                      p.isYoutube ? Icons.cloud_queue_rounded : Icons.queue_music_rounded,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.isYoutube
                          ? '${p.displayTrackCount} songs · YouTube Music'
                          : '${p.displayTrackCount} songs · On device',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('playlistAddSong', {
                        'playlistId': p.id,
                        'song': song.toMap(),
                      });
                      await onChanged?.call();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${p.name}')),
                        );
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

IconData _sectionIcon(String label) {
  switch (label) {
    case 'Playlists':
      return Icons.playlist_play_rounded;
    case 'History':
      return Icons.history_rounded;
    case 'Downloaded':
    case 'Downloads':
      return Icons.download_rounded;
    case 'Most played':
      return Icons.trending_up_rounded;
    case 'Recently added':
      return Icons.library_add_rounded;
    default:
      return Icons.favorite_rounded;
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  final String name;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final initial = name.trim().isEmpty ? 'F' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: accent,
      foregroundImage: imageUrl.isBlank ? null : NetworkImage(imageUrl),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.signedIn,
    required this.liked,
    required this.playlists,
    required this.downloads,
  });

  final bool signedIn;
  final int liked;
  final int playlists;
  final int downloads;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(value: liked, label: 'Liked'),
          ),
          Expanded(
            child: _StatTile(value: playlists, label: 'Playlists'),
          ),
          Expanded(
            child: _StatTile(value: downloads, label: 'Downloads'),
          ),
          Icon(
            signedIn ? Icons.verified_rounded : Icons.login_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

void _showUpdateResultDialog(
  BuildContext context,
  Map<String, dynamic> map, {
  String? title,
}) {
  final ok = map['ok'] == true;
  final newer = map['updateAvailable'] == true;
  final installed =
      map['installedVersionName']?.toString().trim() ?? _kAppVersionName;
  final tag = map['tagName']?.toString() ?? map['latestTag']?.toString() ?? '';
  final html = map['htmlUrl']?.toString() ?? '';
  final apk = map['downloadUrl']?.toString() ?? '';
  final err = map['error']?.toString() ?? '';
  final notes = map['body']?.toString().trim() ?? '';
  final dialogTitle = title ??
      (ok
          ? (newer ? 'Update available' : 'You are up to date')
          : 'Update check failed');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ok)
              Text(err.isEmpty ? 'Could not reach GitHub.' : err),
            if (ok) ...[
              Text('Installed: v$installed'),
              if (tag.isNotEmpty) Text('Latest: $tag'),
              if (ok && !newer && tag.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No newer release than your installed build.'),
                ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  notes,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        if (html.isNotEmpty)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openExternalUrl(context, html);
            },
            child: const Text('Release page'),
          ),
        if (apk.isNotEmpty)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openExternalUrl(context, apk);
            },
            child: const Text('Download APK'),
          ),
      ],
    ),
  );
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  try {
    final ok =
        await _method.invokeMethod<bool>('openExternalUrl', {'url': url}) ==
        true;
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link on this device')),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link on this device')),
    );
  }
}

/// Dedicated About Us panel inside Settings (logo, credits, links).
class _AboutUsPanel extends StatelessWidget {
  const _AboutUsPanel({required this.onOpenExternal});

  final Future<void> Function(String url) onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.62);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: _FoxyAppLogo(size: 148, borderRadius: 28)),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'FoxyMusic',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _FoxyBrandPalette.foxAmber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _kAppVersionLabel,
              style: TextStyle(
                color: _FoxyBrandPalette.foxCream,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Your fox-themed YouTube Music player — playback, queues, and '
          'library on-device with a Flutter UI and Kotlin engine.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.4, fontSize: 14),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            gradient: LinearGradient(
              colors: [
                _FoxyBrandPalette.foxDeep.withValues(alpha: 0.45),
                const Color(0xFF1A1410),
              ],
            ),
            border: Border.all(
              color: _FoxyBrandPalette.foxAmber.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            _kAboutCreditLine,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsCard(
          title: 'Developer',
          subtitle: 'Source & releases',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                _kGitHubProjectUrl,
                style: TextStyle(
                  color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => onOpenExternal(_kGitHubProjectUrl),
                icon: const Icon(Icons.code_rounded, size: 20),
                label: const Text('Open GitHub project'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    onOpenExternal('https://github.com/sparkn2008-del'),
                icon: const Icon(Icons.person_outline_rounded, size: 20),
                label: const Text('sparkn2008-del on GitHub'),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => showLicensePage(context: context),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_kCardRadius),
            ),
          ),
          child: const Text('Open-source licenses'),
        ),
        const SizedBox(height: 12),
        Text(
          'Release $_kAppVersionName · FoxyMusic',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 12),
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.appearance,
    required this.onSetAppearance,
    this.account = const <String, dynamic>{},
    this.onAccountRefresh,
    this.onOpenAccountHub,
  });

  final Map<String, dynamic> appearance;
  final Future<void> Function(Map<String, dynamic> patch) onSetAppearance;
  final Map<String, dynamic> account;
  final Future<void> Function()? onAccountRefresh;
  final VoidCallback? onOpenAccountHub;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _m;
  late TextEditingController _contentLang;
  late TextEditingController _appLang;
  late TextEditingController _proxyEp;
  late TabController _settingsTabs;

  @override
  void initState() {
    super.initState();
    _settingsTabs = TabController(length: 2, vsync: this);
    _m = Map<String, dynamic>.from(widget.appearance);
    _contentLang = TextEditingController(
      text: _m['contentLanguageTag']?.toString() ?? 'en-US',
    );
    _appLang = TextEditingController(
      text: _m['appLanguageTag']?.toString() ?? '',
    );
    _proxyEp = TextEditingController(
      text: _m['proxyEndpoint']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _settingsTabs.dispose();
    _contentLang.dispose();
    _appLang.dispose();
    _proxyEp.dispose();
    super.dispose();
  }

  Future<void> _apply(Map<String, dynamic> patch) async {
    await widget.onSetAppearance(patch);
    if (!mounted) return;
    setState(() => _m.addAll(patch));
  }

  bool _bool(String key, [bool def = false]) {
    final v = _m[key];
    if (v == null) return def;
    return v == true;
  }

  int _int(String key, int def) => ((_m[key] ?? def) as num).toInt();

  Future<void> _openExternal(String url) async {
    try {
      final ok =
          await _method.invokeMethod<bool>('openExternalUrl', {'url': url}) ==
          true;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link on this device')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link on this device')),
      );
    }
  }

  Future<void> _checkUpdate() async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    try {
      final raw = await _method.invokeMethod('checkGitHubRelease');
      rootNav.pop();
      if (!mounted) return;
      _showUpdateResult(_asMap(raw) ?? const {});
    } catch (e) {
      rootNav.pop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
    }
  }

  void _showUpdateResult(Map<String, dynamic> map) {
    _showUpdateResultDialog(context, map);
  }

  Future<void> _openEqualizer() async {
    final ok = await _method.invokeMethod('openSystemEqualizer') == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Opened system audio effects'
              : 'No system equalizer panel on this device',
        ),
      ),
    );
  }

  Future<void> _openWebLogin([String mode = 'webview']) async {
    final ok = await _method.invokeMethod('openWebLogin', {'mode': mode}) == true;
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == 'ytmapp' || mode == 'ytm_app' || mode == 'app'
                ? 'Could not open YouTube Music on this device'
                : 'Could not open sign-in on this device',
          ),
        ),
      );
      return;
    }
    if (mode == 'ytmapp' || mode == 'ytm_app' || mode == 'app') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If you use the YouTube Music app first, come back and tap “Sign in inside FoxyMusic” to finish. Google does not share that login with other apps.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
    }
  }

  Future<void> _signOutYoutube() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of YouTube?'),
        content: const Text(
          'You stay in the app as a guest until you connect again using Sign in inside FoxyMusic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _method.invokeMethod('accountSignOut');
    } catch (_) {}
    await widget.onAccountRefresh?.call();
    if (mounted) setState(() {});
  }

  Future<void> _applyLanguages() async {
    final c = _contentLang.text.trim();
    final a = _appLang.text.trim();
    await _apply({
      'contentLanguageTag': c.isEmpty ? 'en-US' : c,
      'appLanguageTag': a,
    });
  }

  Future<void> _applyProxyEndpoint() async {
    await _apply({'proxyEndpoint': _proxyEp.text.trim()});
  }

  Future<void> _restartAppAfterHomeBackgroundChange() async {
    try {
      await _method.invokeMethod('restartApp');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Background saved — fully close and reopen FoxyMusic to apply',
          ),
        ),
      );
    }
  }

  Future<void> _pickHomeBackground() async {
    try {
      final raw = _asMap(await _method.invokeMethod('pickHomeBackground'));
      if (!mounted) return;
      if (raw?['ok'] == true) {
        Navigator.of(context).pop();
        await _restartAppAfterHomeBackgroundChange();
      } else if (raw?['cancelled'] != true && raw?['ok'] != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not set background')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Background picker failed: $e')),
      );
    }
  }

  Future<void> _resetHomeBackground() async {
    try {
      await _method.invokeMethod('clearHomeBackground');
      if (!mounted) return;
      Navigator.of(context).pop();
      await _restartAppAfterHomeBackgroundChange();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _int('themePalette', 0).clamp(0, 3);
    final mode = _int('themeMode', 0).clamp(0, 2);
    final thumbAccent = _bool('dynamicSongColors');
    final blur = _bool('blurEffects', true);
    final compact = _bool('compactPlayer');
    final gestures = _bool('gestureControls', true);
    final persistent = _bool('persistentQueue', true);
    final saveHistory = _bool('saveHistory', true);
    final sponsor = _bool('sponsorBlockEnabled', true);
    final lrclib = _bool('lyricsPreferLrclib', true);
    final proxyOn = _bool('proxyEnabled');
    final norm = _bool('normalizeVolume');
    final skipSil = _bool('skipSilence');
    final backup = _bool('autoBackupEnabled');
    final tier = _int('streamQualityTier', 2).clamp(0, 2);
    final cross = _int('crossfadeMs', 0);
    final prog = _int('playerProgressStyle', 2).clamp(0, 3);
    final progMotion = _int('playerSeekMotion', 0).clamp(0, 2);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: _FoxyGlassTint(
            borderRadius: 24,
            tintOpacity: 0.52,
            borderOpacity: 0.12,
            showBottomBorder: false,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Expanded(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _kAppVersionLabel,
                          style: TextStyle(
                            color: _FoxyBrandPalette.foxCream
                                .withValues(alpha: 0.75),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _settingsTabs,
                      indicatorColor: _FoxyBrandPalette.foxAmber,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      dividerColor: Colors.white12,
                      tabs: const [
                        Tab(text: 'General'),
                        Tab(text: 'About Us'),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _settingsTabs,
                  children: [
                    ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                      children: [
                        Builder(
                builder: (context) {
                  final signedIn = widget.account['isSignedIn'] == true;
                  final email = widget.account['email']?.toString() ?? '';
                  return _SettingsCard(
                    title: 'YouTube',
                    subtitle: signedIn
                        ? (email.isNotEmpty ? email : 'Signed in')
                        : 'Sign in inside FoxyMusic, or use the YouTube Music app then finish here',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _openWebLogin('webview'),
                          icon: const Icon(Icons.lock_open_rounded, size: 20),
                          label: const Text('Sign in inside FoxyMusic'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _openWebLogin('ytmapp'),
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                          label: const Text('Open YouTube Music app'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openWebLogin('browser'),
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: const Text('Open system browser instead'),
                        ),
                        if (signedIn) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _signOutYoutube,
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: const Text('Sign out'),
                          ),
                        ],
                        if (widget.onOpenAccountHub != null) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: widget.onOpenAccountHub,
                              child: const Text('Account overview'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _SettingsDrawerHeader(
                theme: theme,
                mode: mode,
                onTheme: (i) => _apply({
                  'themePalette': i.clamp(0, 3),
                  'accentArgb': 0xFFFF1744,
                }),
                onMode: (i) => _apply({'themeMode': i}),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Themes',
                subtitle:
                    'Pick a base palette. With “Song thumbnail accent”, Flutter reads the same artwork accent computed in Kotlin (no extra packages).',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        selected: theme == i,
                        label: Text(['Foxy', 'Aurora', 'Gold', 'Rose'][i]),
                        onSelected: (_) => _apply({
                          'themePalette': i,
                          'accentArgb': 0xFFFF1744,
                        }),
                      ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Theme mode',
                subtitle: 'System, always dark, or always light',
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'System'),
                      (1, 'Dark'),
                      (2, 'Light'),
                    ])
                      ChoiceChip(
                        selected: mode == item.$1,
                        label: Text(item.$2),
                        onSelected: (_) => _apply({'themeMode': item.$1}),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: thumbAccent,
                title: const Text(
                  'Song thumbnail accent',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Follow artwork colors on the full player when enabled',
                ),
                onChanged: (value) => _apply({
                  'dynamicSongColors': value,
                  'accentArgb': 0xFFFF1744,
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: blur,
                title: const Text(
                  'Blur on player',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Blurred artwork vs solid theme surfaces'),
                onChanged: (v) => _apply({'blurEffects': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: compact,
                title: const Text(
                  'Compact mini-player',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onChanged: (v) => _apply({'compactPlayer': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: gestures,
                title: const Text(
                  'Swipe to change song',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onChanged: (v) => _apply({'gestureControls': v}),
              ),
              _SettingsCard(
                title: 'App background',
                subtitle:
                    'Default Foxy art or your photo — glass-style UI on Home, Search, and Library',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickHomeBackground,
                      icon: const Icon(Icons.image_rounded, size: 20),
                      label: const Text('Choose custom background'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _resetHomeBackground,
                      icon: const Icon(Icons.restart_alt_rounded, size: 20),
                      label: const Text('Use default Foxy background'),
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Stream quality',
                subtitle:
                    'Caps preferred adaptive bitrate on the Kotlin extractor (low / medium / best).',
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'Low ~64'),
                      (1, 'Medium ~128'),
                      (2, 'High'),
                    ])
                      ChoiceChip(
                        selected: tier == item.$1,
                        label: Text(item.$2),
                        onSelected: (_) =>
                            _apply({'streamQualityTier': item.$1}),
                      ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Crossfade',
                subtitle:
                    'Fades out near the end of each track and in at the start of the next (SimpMusic-style). Also in ⋮ song menu.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'Off'),
                      (3000, '3s'),
                      (5000, '5s'),
                      (8000, '8s'),
                      (12000, '12s'),
                    ])
                      ChoiceChip(
                        selected: cross == item.$1,
                        label: Text(item.$2),
                        onSelected: (_) => _apply({'crossfadeMs': item.$1}),
                      ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Now playing · seek bar',
                subtitle:
                    'Metrolist-style fullscreen player: choose the bar shape in a 2×2 picker, '
                    'then add motion. Wavy and squiggly use your accent on the played side.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bar style',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final v = await pickMetrolistSeekBarStyle(
                            context,
                            current: prog,
                          );
                          if (v != null && mounted) {
                            await _apply({'playerProgressStyle': v});
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _playerProgressStyleLabel(prog),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap to open style gallery',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Motion & animation',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pulse animates the thumb; shimmer adds a soft sweep on the played segment; '
                      'with Wave or Squiggle, motion also scrolls the waveform.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < 3; i++)
                          ChoiceChip(
                            showCheckmark: false,
                            selected: progMotion == i,
                            label: Text(
                              ['Off', 'Thumb pulse', 'Played shimmer'][i],
                            ),
                            onSelected: (_) =>
                                _apply({'playerSeekMotion': i}),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Playback & data',
                subtitle:
                    'Queue persistence, history, and SponsorBlock-style skips',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: persistent,
                      title: const Text('Restore queue after restart'),
                      onChanged: (v) => _apply({'persistentQueue': v}),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: saveHistory,
                      title: const Text('Save listening history'),
                      onChanged: (v) => _apply({'saveHistory': v}),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sponsor,
                      title: const Text('SponsorBlock auto-skip'),
                      onChanged: (v) => _apply({'sponsorBlockEnabled': v}),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: lrclib,
                      title: const Text('Prefer LRCLIB for lyrics'),
                      subtitle: const Text(
                        'LRCLIB first, YouTube captions as fallback. Also in ⋮ song menu.',
                      ),
                      onChanged: (v) => _apply({'lyricsPreferLrclib': v}),
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'HTTP proxy',
                subtitle:
                    'host:port applied to stream extraction and ExoPlayer (OkHttp), like a desktop music client.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: proxyOn,
                      title: const Text('Enable proxy'),
                      onChanged: (v) => _apply({'proxyEnabled': v}),
                    ),
                    TextField(
                      controller: _proxyEp,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Proxy endpoint',
                        hintText: '127.0.0.1:8080',
                        filled: true,
                        fillColor: const Color(0xFF141414),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _applyProxyEndpoint(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _applyProxyEndpoint,
                        child: const Text('Save proxy host'),
                      ),
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Languages',
                subtitle:
                    'Catalogue bias (BCP-47) and optional UI language tag (blank = system)',
                child: Column(
                  children: [
                    TextField(
                      controller: _contentLang,
                      decoration: InputDecoration(
                        labelText: 'Content / catalogue',
                        hintText: 'en-US',
                        filled: true,
                        fillColor: const Color(0xFF141414),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _appLang,
                      decoration: InputDecoration(
                        labelText: 'App UI (optional)',
                        filled: true,
                        fillColor: const Color(0xFF141414),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _applyLanguages,
                        child: const Text('Apply languages'),
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: norm,
                title: const Text(
                  'Normalize volume',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Lowers loud tracks for steadier playback — applies immediately.',
                ),
                onChanged: (v) => _apply({'normalizeVolume': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: skipSil,
                title: const Text(
                  'Skip silence',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Persisted for future ExoPlayer wiring (reserved)',
                ),
                onChanged: (v) => _apply({'skipSilence': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: backup,
                title: const Text(
                  'Auto backup',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('UI + persistence only for now'),
                onChanged: (v) => _apply({'autoBackupEnabled': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('autoCheckUpdates', true),
                title: const Text(
                  'Check for updates automatically',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Looks for new GitHub releases about once per day.',
                ),
                onChanged: (v) => _apply({'autoCheckUpdates': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('updateNotifications', true),
                title: const Text(
                  'Update notifications',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Shows a system notification when a newer APK is published.',
                ),
                onChanged: (v) => _apply({'updateNotifications': v}),
              ),
              _SettingsCard(
                title: 'App updates',
                subtitle: 'GitHub releases · sparkn2008-del/FoxyMusic',
                child: OutlinedButton.icon(
                  onPressed: _checkUpdate,
                  icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_kCardRadius),
                    ),
                  ),
                  label: const Text('Check for updates now'),
                ),
              ),
              _SettingsCard(
                title: 'Shortcuts',
                subtitle: 'System integrations',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _openEqualizer,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                      ),
                      child: const Text('System equalizer'),
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'About FoxyMusic',
                subtitle: 'Logo, credits & GitHub',
                child: FilledButton.icon(
                  onPressed: () => _settingsTabs.animateTo(1),
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                  label: const Text('Open About Us'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: open the ⋮ menu on the full player for sleep timer and queue tools.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
                      ],
                    ),
                    ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                      children: [
                        _AboutUsPanel(onOpenExternal: _openExternal),
                      ],
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
            ),
          ),
          if (child is! SizedBox) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}

class _SettingsDrawerHeader extends StatelessWidget {
  const _SettingsDrawerHeader({
    required this.theme,
    required this.mode,
    required this.onTheme,
    required this.onMode,
  });

  final int theme;
  final int mode;
  final ValueChanged<int> onTheme;
  final ValueChanged<int> onMode;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final groups = [
      (Icons.palette_rounded, 'Appearance', 'Colors, blur, nav'),
      (Icons.album_rounded, 'Player', 'Seek bar style, motion, mini player'),
      (Icons.graphic_eq_rounded, 'Audio', 'Quality, crossfade'),
      (Icons.lyrics_rounded, 'Lyrics', 'Provider and animation'),
    ];
    return Material(
      color: Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Look, playback shell, and audio',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in groups)
                  Chip(
                    avatar: Icon(item.$1, size: 18),
                    label: Text(item.$2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CompactSegment(
                    label: [
                      'Foxy',
                      'Aurora',
                      'Gold',
                      'Rose',
                    ][theme.clamp(0, 3)],
                    icon: Icons.color_lens_rounded,
                    onTap: () => onTheme((theme + 1) % 4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSegment(
                    label: ['System', 'Dark', 'Light'][mode.clamp(0, 2)],
                    icon: Icons.dark_mode_rounded,
                    onTap: () => onMode((mode + 1) % 3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSegment extends StatelessWidget {
  const _CompactSegment({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
      ),
    );
  }
}

class _EmptyTabBody extends StatelessWidget {
  const _EmptyTabBody({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Icon(icon, size: 40, color: accent),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSpotlight extends StatelessWidget {
  const _HomeSpotlight({
    required this.song,
    required this.sectionTitle,
    required this.onPlay,
    required this.onRadio,
  });

  final _Song song;
  final String sectionTitle;
  final VoidCallback onPlay;
  final VoidCallback onRadio;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: _FoxyGlassButton(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(20),
        blurSigma: 14,
        tintOpacity: 0.38,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 196,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
            children: [
              Positioned.fill(
                child: _Artwork(
                  url: song.artwork,
                  size: 400,
                  radius: 0,
                  identityTag: song.videoId,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle.toUpperCase(),
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: onPlay,
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: onRadio,
                          icon: const Icon(Icons.radio_rounded, size: 20),
                          label: const Text('Radio'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _HomeQuickPicks extends StatefulWidget {
  const _HomeQuickPicks({
    required this.songs,
    required this.currentVideoId,
    required this.onPlay,
  });

  final List<_Song> songs;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  State<_HomeQuickPicks> createState() => _HomeQuickPicksState();
}

class _HomeQuickPicksState extends State<_HomeQuickPicks> {
  late final PageController _bannerController;
  int _bannerPage = 0;

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs.take(16).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "LET'S START WITH A RADIO",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick picks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _FoxyGlassTextButton(
                      label: 'Play all',
                      onPressed: () => widget.onPlay(songs.first, songs),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: songs.length,
              onPageChanged: (i) => setState(() => _bannerPage = i),
              itemBuilder: (context, index) {
                final song = songs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _QuickPickBannerCard(
                    song: song,
                    active: song.videoId == widget.currentVideoId,
                    onTap: () => widget.onPlay(song, songs),
                  ),
                );
              },
            ),
          ),
          if (songs.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < songs.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _bannerPage ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _bannerPage
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Swipable song banner for Quick picks (one track per page).
class _QuickPickBannerCard extends StatelessWidget {
  const _QuickPickBannerCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.highQualityArtwork,
                size: 600,
                radius: 0,
                identityTag: song.videoId,
                highQuality: true,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
              if (active)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: accent.withValues(alpha: 0.85),
                      width: 2,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (active)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.equalizer_rounded,
                              color: accent,
                              size: 18,
                            ),
                          ),
                        Text(
                          'QUICK PICK',
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.95),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.96),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onTap,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black87,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Tap to play',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCompactSongRow extends StatelessWidget {
  const _HomeCompactSongRow({
    required this.song,
    required this.active,
    required this.accent,
    required this.onTap,
    this.glass = true,
  });

  final _Song song;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final row = Row(
        children: [
          _Artwork(
            url: song.highQualityArtwork,
            size: 48,
            radius: 6,
            identityTag: song.videoId,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? accent : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
            color: active ? accent : Colors.white54,
          ),
        ],
    );
    if (!glass) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: row,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: row,
      ),
    );
  }
}

class _HomeFreshFindsRow extends StatelessWidget {
  const _HomeFreshFindsRow({
    required this.sections,
    required this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_SongSection> sections;
  final FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    final mixSongs = sections
        .expand((s) => s.songs)
        .where((s) => s.artwork.isNotEmpty)
        .take(4)
        .toList();
    _SongSection? replaySection;
    for (final s in sections) {
      if (s.title.toLowerCase().contains('fresh')) {
        replaySection = s;
        break;
      }
    }
    replaySection ??= sections.isNotEmpty ? sections.first : null;
    final replaySongs = replaySection?.songs.take(4).toList() ?? mixSongs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fresh finds, old favorites',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _HomeGradientMixCard(
                  title: 'Liked Music',
                  subtitle: 'Auto playlist',
                  gradient: const [
                    Color(0xFFE91E8C),
                    Color(0xFF9C27B0),
                  ],
                  icon: Icons.thumb_up_alt_rounded,
                  onTap: () => onDiscoverSearch?.call('liked songs playlist'),
                ),
                const SizedBox(width: 12),
                _HomeReplayMixCard(
                  title: 'Replay Mix',
                  songs: replaySongs,
                  onTap: () {
                    if (replaySongs.isNotEmpty) {
                      onPlay(replaySongs.first, replaySongs);
                    }
                  },
                ),
                const SizedBox(width: 12),
                _HomeGradientMixCard(
                  title: 'Discover Mix',
                  subtitle: 'Made for you',
                  gradient: const [
                    Color(0xFF1565C0),
                    Color(0xFF283593),
                  ],
                  icon: Icons.explore_rounded,
                  onTap: () => onDiscoverSearch?.call('discover mix music'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeGradientMixCard extends StatelessWidget {
  const _HomeGradientMixCard({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 52),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeReplayMixCard extends StatelessWidget {
  const _HomeReplayMixCard({
    required this.title,
    required this.songs,
    required this.onTap,
  });

  final String title;
  final List<_Song> songs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (songs.length >= 4)
                        Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _Artwork(
                                      url: songs[0].highQualityArtwork,
                                      size: 84,
                                      radius: 0,
                                      identityTag: songs[0].videoId,
                                    ),
                                  ),
                                  Expanded(
                                    child: _Artwork(
                                      url: songs[1].highQualityArtwork,
                                      size: 84,
                                      radius: 0,
                                      identityTag: songs[1].videoId,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _Artwork(
                                      url: songs[2].highQualityArtwork,
                                      size: 84,
                                      radius: 0,
                                      identityTag: songs[2].videoId,
                                    ),
                                  ),
                                  Expanded(
                                    child: _Artwork(
                                      url: songs[3].highQualityArtwork,
                                      size: 84,
                                      radius: 0,
                                      identityTag: songs[3].videoId,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        _Artwork(
                          url: songs.isNotEmpty
                              ? songs.first.highQualityArtwork
                              : '',
                          size: 168,
                          radius: 0,
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (songs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  songs
                      .map((s) => s.artist)
                      .where((a) => a.isNotEmpty)
                      .take(3)
                      .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
        ),
      ),
    );
  }
}

class _HomeFeedSection extends StatelessWidget {
  const _HomeFeedSection({
    required this.section,
    required this.layout,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final _HomeSectionLayout layout;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final titleLower = section.title.toLowerCase();
    if (titleLower.contains('fresh finds')) {
      return const SizedBox.shrink();
    }
    return switch (layout) {
      _HomeSectionLayout.grid => _HomeGridShelf(
          section: section,
          currentVideoId: currentVideoId,
          onPlay: onPlay,
        ),
      _HomeSectionLayout.video => _HomeVideoShelf(
          section: section,
          currentVideoId: currentVideoId,
          onPlay: onPlay,
        ),
      _HomeSectionLayout.chart => _HomeChartShelf(
          section: section,
          onPlay: onPlay,
        ),
      _HomeSectionLayout.artist => _HomeArtistShelf(
          section: section,
          onPlay: onPlay,
        ),
      _HomeSectionLayout.cards => _HomeSongCardsSection(
          section: section,
          currentVideoId: currentVideoId,
          onPlay: onPlay,
        ),
      _ => _HomeSongCardsSection(
          section: section,
          currentVideoId: currentVideoId,
          onPlay: onPlay,
        ),
    };
  }
}

class _HomeSongCardsSection extends StatelessWidget {
  const _HomeSongCardsSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final songs = section.songs.take(14).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final song in songs)
            _HomeSongCard(
              song: song,
              active: song.videoId == currentVideoId,
              onTap: () => onPlay(song, section.songs),
            ),
        ],
      ),
    );
  }
}

class _HomeSongCard extends StatelessWidget {
  const _HomeSongCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(_kCardRadius),
        blurSigma: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _Artwork(
              url: song.highQualityArtwork,
              size: 64,
              radius: 8,
              identityTag: song.videoId,
              highQuality: true,
              offlineArtworkPath: song.offlineArtworkPath,
              useOfflineArtwork: song.isDownloaded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? accent : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              active
                  ? Icons.equalizer_rounded
                  : Icons.play_arrow_rounded,
              color: active ? accent : Colors.white54,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGridShelf extends StatelessWidget {
  const _HomeGridShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(8).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return _HomeGridTile(
                  song: song,
                  active: song.videoId == currentVideoId,
                  onTap: () => onPlay(song, section.songs),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeGridTile extends StatelessWidget {
  const _HomeGridTile({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _FoxyGlassButton(
      onTap: onTap,
      selected: active,
      borderRadius: BorderRadius.circular(10),
      blurSigma: 12,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(
                    url: song.highQualityArtwork,
                    size: 200,
                    radius: 0,
                    identityTag: song.videoId,
                    highQuality: true,
                  ),
                  if (active)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: accent,
                        size: 36,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            song.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeVideoShelf extends StatelessWidget {
  const _HomeVideoShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = section.songs[index];
                return _HomeVideoCard(
                  song: song,
                  active: song.videoId == currentVideoId,
                  onTap: () => onPlay(song, section.songs),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeVideoCard extends StatelessWidget {
  const _HomeVideoCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const w = 248.0;
    const h = 140.0;
    return SizedBox(
      width: w,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: w - 16,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: w,
                      radius: 0,
                      identityTag: song.videoId,
                      highQuality: true,
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _FoxyGlassButton(
                        borderRadius: BorderRadius.circular(999),
                        blurSigma: 8,
                        padding: EdgeInsets.zero,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (active)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeChartShelf extends StatelessWidget {
  const _HomeChartShelf({
    required this.section,
    required this.onPlay,
  });

  final _SongSection section;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 148,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = section.songs[index];
                return SizedBox(
                  width: 148,
                  child: _FoxyGlassButton(
                    onTap: () => onPlay(song, section.songs),
                    borderRadius: BorderRadius.circular(10),
                    blurSigma: 12,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _Artwork(
                              url: song.highQualityArtwork,
                              size: 132,
                              radius: 0,
                              identityTag: song.videoId,
                              highQuality: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Chart • YouTube Music',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeArtistShelf extends StatelessWidget {
  const _HomeArtistShelf({
    required this.section,
    required this.onPlay,
  });

  final _SongSection section;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final song = section.songs[index];
                return SizedBox(
                  width: 120,
                  child: _FoxyGlassButton(
                    onTap: () => onPlay(song, section.songs),
                    borderRadius: BorderRadius.circular(14),
                    blurSigma: 12,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        ClipOval(
                          child: _Artwork(
                            url: song.highQualityArtwork,
                            size: 104,
                            radius: 0,
                            identityTag: song.videoId,
                            highQuality: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          song.artist.ifBlank(song.title),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Artists',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongShelf extends StatelessWidget {
  const _SongShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              section.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = section.songs[index];
                return _SongCard(
                  song: song,
                  active: song.videoId == currentVideoId,
                  onTap: () => onPlay(song, section.songs),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  static const double _thumb = 148;
  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: _thumb,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: SizedBox(
                width: _thumb - 16,
                height: _thumb - 16,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: _thumb - 16,
                      radius: 0,
                      identityTag: song.videoId,
                      highQuality: true,
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _FoxyGlassButton(
                        borderRadius: BorderRadius.circular(999),
                        blurSigma: 8,
                        padding: EdgeInsets.zero,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: active ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                        child: Icon(
                          Icons.equalizer_rounded,
                          color: accent,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    super.key,
    required this.player,
    required this.onOpen,
    this.onResync,
    this.glass = false,
  });

  final Map<String, dynamic> player;
  final VoidCallback onOpen;
  final Future<void> Function()? onResync;
  final bool glass;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    final p = _progressFrom(widget.player);
    _progressCtrl = AnimationController(
      vsync: this,
      value: p,
      duration: const Duration(milliseconds: 320),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  double _progressFrom(Map<String, dynamic> player) {
    final duration = ((player['durationMs'] ?? 0) as num).toDouble();
    final position = ((player['positionMs'] ?? 0) as num).toDouble();
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _progressFrom(widget.player);
    if ((target - _progressCtrl.value).abs() > 0.002) {
      _progressCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dynamicOn = widget.player['dynamicSongColors'] != false;
    final barColor =
        dynamicOn ? _miniPlayerTint(accent) : _kMiniPlayerFallbackTint;
    final song = _Song.fromMap(_asMap(widget.player['currentSong']) ?? const {});
    final liked = widget.player['songIsLiked'] == true;
    final playing = widget.player['isPlaying'] == true;
    final buffering = widget.player['isBuffering'] == true;

    final playerBody = SizedBox(
      height: 64,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                child: Row(
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: 48,
                      radius: 8,
                      identityTag: song.videoId,
                      offlineArtworkPath: song.offlineArtworkPath,
                      useOfflineArtwork: song.isDownloaded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: liked ? 'Unlike' : 'Like',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            onPressed: () async {
              try {
                await _method.invokeMethod(
                  liked ? 'unlike' : 'like',
                  {'song': song.toMap()},
                );
              } finally {
                await widget.onResync?.call();
              }
            },
            icon: Icon(
              liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: liked
                  ? const Color(0xFFE53935)
                  : Colors.white.withValues(alpha: 0.78),
              size: 24,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _MetrolistMiniPlayRing(
              progress: _progressCtrl,
              playing: playing,
              buffering: buffering,
              accent: accent,
              onPressed: () async {
                await _method.invokeMethod('togglePlayPause');
                await widget.onResync?.call();
              },
            ),
          ),
        ],
      ),
    );

    final Widget shell;
    if (widget.glass) {
      shell = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _FoxyGlassTint(
          borderRadius: 16,
          tintOpacity: 0.54,
          borderOpacity: 0.18,
          child: playerBody,
        ),
      );
    } else {
      shell = Material(
        color: barColor,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: playerBody,
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: shell,
      ),
    );
  }
}

/// Metrolist / SimpMusic-style circular progress around the mini-player play control.
class _MetrolistMiniPlayRing extends StatelessWidget {
  const _MetrolistMiniPlayRing({
    required this.progress,
    required this.playing,
    required this.buffering,
    required this.accent,
    required this.onPressed,
  });

  final Animation<double> progress;
  final bool playing;
  final bool buffering;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        return CustomPaint(
          painter: _MetrolistMiniRingPainter(
            progress: progress.value.clamp(0.0, 1.0),
            accent: accent,
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: buffering
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetrolistMiniRingPainter extends CustomPainter {
  _MetrolistMiniRingPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = accent.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        active,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetrolistMiniRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _MetrolistPlayerRoundIconButton extends StatelessWidget {
  const _MetrolistPlayerRoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: _kMetrolistNpSurface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.46,
            color: iconColor ?? Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _MetrolistPlayerSectionLabel extends StatelessWidget {
  const _MetrolistPlayerSectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final upper = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.25,
      color: Colors.white.withValues(alpha: 0.42),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(text.toUpperCase(), style: upper),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.player,
    this.initialTab = 0,
    this.homeBackgroundPath,
    this.onNotifyHomePlayerSync,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final Map<String, dynamic> player;
  final int initialTab;
  final String? homeBackgroundPath;
  final Future<void> Function()? onNotifyHomePlayerSync;
  final FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  late Map<String, dynamic> _player =
      _detachPlayerState(_asMap(widget.player) ?? <String, dynamic>{});
  StreamSubscription<dynamic>? _sub;
  final ScrollController _scrollController = ScrollController();
  late int _tab = widget.initialTab;
  int _progressStyle = 2;
  int _seekMotion = 0;
  List<_LyricLine> _lyrics = const [];
  String? _lyricsFor;
  bool _lyricsPreferLrclib = true;
  bool _lyricsLoading = false;
  double _artworkSwipeDx = 0;
  bool _blurPlayerBackdrop = true;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          final detached = _detachPlayerState(state);
          setState(() => _player = detached);
          _loadLyricsIfNeeded(detached);
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
        unawaited(_refreshPlayerSettings());
        _lyricsFor = '';
        if (_tab == 1) {
          unawaited(_loadLyricsIfNeeded(_player));
        }
      }
    });
    _loadLyricsIfNeeded(_player);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    setState(
      () {
        _progressStyle = ((map['playerProgressStyle'] ?? 2) as num)
            .toInt()
            .clamp(0, 3);
        _seekMotion = ((map['playerSeekMotion'] ?? 0) as num).toInt().clamp(0, 2);
        _blurPlayerBackdrop = map['blurEffects'] != false;
      },
    );
  }

  Future<void> _refreshPlayerSettings() async {
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap == null || !mounted) return;
    setState(() => _player = _detachPlayerState(snap));
  }

  Future<void> _loadLyricsIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final preferLrclib = player['lyricsPreferLrclib'] != false;
    if (song.videoId.isEmpty ||
        (_lyricsFor == song.videoId && _lyricsPreferLrclib == preferLrclib) ||
        _lyricsLoading) {
      return;
    }
    _lyricsFor = song.videoId;
    _lyricsPreferLrclib = preferLrclib;
    setState(() {
      _lyricsLoading = true;
      _lyrics = const [];
    });
    try {
      final response = await _method.invokeMethod('lyrics', {
        'song': song.toMap(),
      });
      final lines = (response as List? ?? const [])
          .map((item) => _LyricLine.fromMap(_asMap(item) ?? const {}))
          .where((line) => line.text.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _lyrics = lines;
        _lyricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lyricsLoading = false);
    }
  }

  Future<void> _setProgressStyle(int style) async {
    setState(() => _progressStyle = style);
    await _method.invokeMethod('setPlayerProgressStyle', {'style': style});
  }

  void _openMenu(_Song song) {
    final parent = context;
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList();
    showFoxySongOverflowMenu(
      parent,
      song: song,
      onPlay: onPlay,
      queueForPlay: queue.isEmpty ? <_Song>[song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: widget.onNotifyHomePlayerSync,
      searchResultsForExtras: queue.length > 1 ? queue : null,
      bulkQueuePlayTitle: 'Play full queue',
      bulkQueuePlaySubtitle: 'Keeps the current player queue order',
      onOpenLyricsTabInPlayer: () {
        if (mounted) setState(() => _tab = 1);
      },
      playerProgressStyleForPicker: _progressStyle,
      onPickPlayerProgressStyle: _setProgressStyle,
      playerSeekMotionForPicker: _seekMotion,
      onPickPlayerSeekMotion: _setSeekMotion,
    );
  }

  Future<void> _setSeekMotion(int motion) async {
    setState(() => _seekMotion = motion.clamp(0, 2));
    await _method.invokeMethod('setAppearance', {
      'playerSeekMotion': _seekMotion,
    });
  }

  void _showTrackInfo(_Song song) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Track info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              song.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(song.artist),
            const SizedBox(height: 8),
            SelectableText('Video ID: ${song.videoId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: 'https://music.youtube.com/watch?v=${song.videoId}',
                ),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('YouTube Music link copied')),
              );
            },
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSystemEqualizer() async {
    final ok = await _method.invokeMethod('openSystemEqualizer') == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Opened system audio effects'
              : 'No system equalizer panel on this device',
        ),
      ),
    );
  }

  Future<void> _showSleepTimerSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('Turn off sleep timer'),
                onTap: () {
                  _method.invokeMethod('cancelSleepTimer');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('End of this track'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 0});
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('In 15 minutes'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 15});
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('In 30 minutes'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 30});
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareSongLink(_Song song) {
    if (song.videoId.isEmpty) return;
    Clipboard.setData(
      ClipboardData(
        text: 'https://music.youtube.com/watch?v=${song.videoId}',
      ),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Link copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    final playing = _player['isPlaying'] == true;
    final buffering = _player['isBuffering'] == true;
    final shuffle = _player['shuffleEnabled'] == true;
    final repeat = (_player['repeatMode'] ?? 'Off').toString();
    final duration = ((_player['durationMs'] ?? 0) as num).toDouble();
    final position = ((_player['positionMs'] ?? 0) as num).toDouble();
    final hintMs = _durationHintMsFromCatalog(song.duration);
    final effectiveDurMs = duration > 750 ? duration : (hintMs?.toDouble() ?? 0.0);
    final progress = effectiveDurMs <= 0
        ? 0.0
        : (position / effectiveDurMs).clamp(0.0, 1.0);
    final endTimeLabel =
        effectiveDurMs > 750 ? _fmt(effectiveDurMs.round()) : '—:—';
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .toList();
    final queueIndex = ((_player['queueIndex'] ?? -1) as num).toInt();
    final padL = 14.0 + MediaQuery.paddingOf(context).left;
    final padR = 14.0 + MediaQuery.paddingOf(context).right;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.black,
      child: Stack(
            children: [
              Positioned.fill(
                child: _BlurBackdrop(
                  url: song.highQualityArtwork,
                  blurEnabled: _blurPlayerBackdrop,
                  offlineArtworkPath: song.offlineArtworkPath,
                  useOfflineArtwork: song.isDownloaded,
                  fullBleed: true,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padL, 4, padR, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2, bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              color: Colors.white,
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _PlayerTabs(
                                    accent: accent,
                                    selected: _tab,
                                    onPick: (tab) =>
                                        setState(() => _tab = tab),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              icon: const Icon(Icons.more_vert_rounded),
                              color: Colors.white,
                              tooltip: 'More',
                              onPressed: () => _openMenu(song),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(padL, 0, padR, 0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          child: switch (_tab) {
                          1 => SingleChildScrollView(
                            key: const ValueKey('lyrics'),
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: padBottom + 8),
                            child: _LyricsTab(
                              lines: _lyrics,
                              loading: _lyricsLoading,
                              positionMs: position.round(),
                              accent: accent,
                              preferLrclib:
                                  _player['lyricsPreferLrclib'] != false,
                            ),
                          ),
                          2 => SingleChildScrollView(
                            key: const ValueKey('queue'),
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: padBottom + 8),
                            child: _QueueTab(
                              queue: queue,
                              currentIndex: queueIndex,
                              onPlay: widget.onPlay,
                              onDiscoverSearch: widget.onDiscoverSearch,
                            ),
                          ),
                          _ => KeyedSubtree(
                            key: const ValueKey('player'),
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final prevEnabled =
                                    _player['canPlayPrevious'] == true ||
                                        queueIndex > 0;
                                final nextEnabled = queue.isNotEmpty &&
                                    queueIndex >= 0 &&
                                    queueIndex < queue.length - 1;
                                final maxW = c.maxWidth;
                                final viewH =
                                    MediaQuery.sizeOf(context).height;
                                final artSide = math.min(
                                  maxW - 4,
                                  viewH * 0.52,
                                ).clamp(360.0, 960.0);
                                return SingleChildScrollView(
                                  controller: _scrollController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(
                                    4,
                                    0,
                                    4,
                                    padBottom + 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                              const SizedBox(height: 14),
                                              Text(
                                                'NOW PLAYING',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.95),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              const SizedBox(height: 20),
                                              Center(
                                                child: GestureDetector(
                                                  onHorizontalDragUpdate:
                                                      (details) {
                                                    _artworkSwipeDx +=
                                                        details.delta.dx;
                                                  },
                                                  onHorizontalDragEnd: (_) {
                                                    if (_artworkSwipeDx > 64) {
                                                      _method.invokeMethod(
                                                        'previous',
                                                      );
                                                    } else if (_artworkSwipeDx <
                                                        -64) {
                                                      _method.invokeMethod(
                                                        'next',
                                                      );
                                                    }
                                                    _artworkSwipeDx = 0;
                                                  },
                                                  child: _PlayerArtwork(
                                                    url: song.highQualityArtwork,
                                                    playing: playing &&
                                                        !buffering,
                                                    tag:
                                                        'art-${song.videoId}',
                                                    offlineArtworkPath: song
                                                        .offlineArtworkPath,
                                                    useOfflineArtwork:
                                                        song.isDownloaded,
                                                    maxSide: artSide
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 22),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          song.title,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 22,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800,
                                                            height: 1.12,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          song.artist,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            height: 1.2,
                                                            color: Colors.white
                                                                .withValues(
                                                              alpha: 0.68,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Copy link',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      Icons.share_outlined,
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.92,
                                                      ),
                                                      size: 22,
                                                    ),
                                                    onPressed: () =>
                                                        _shareSongLink(song),
                                                  ),
                                                  IconButton(
                                                    tooltip: song.isDownloaded
                                                        ? 'Downloaded'
                                                        : 'Download',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      song.isDownloaded
                                                          ? Icons
                                                              .download_done_rounded
                                                          : Icons
                                                              .download_outlined,
                                                      color: song.isDownloaded
                                                          ? const Color(
                                                              0xFF81C784,
                                                            )
                                                          : Colors.white
                                                              .withValues(
                                                              alpha: 0.92,
                                                            ),
                                                      size: 22,
                                                    ),
                                                    onPressed:
                                                        song.isDownloaded
                                                            ? null
                                                            : () async {
                                                                await _method
                                                                    .invokeMethod(
                                                                  'download',
                                                                  {
                                                                    'song': song
                                                                        .toMap(),
                                                                  },
                                                                );
                                                                if (!mounted) {
                                                                  return;
                                                                }
                                                                final snap =
                                                                    _asMap(
                                                                  await _method
                                                                      .invokeMethod(
                                                                    'getPlayerState',
                                                                  ),
                                                                );
                                                                if (snap !=
                                                                    null) {
                                                                  setState(
                                                                    () => _player =
                                                                        _detachPlayerState(
                                                                      snap,
                                                                    ),
                                                                  );
                                                                }
                                                              },
                                                  ),
                                                  IconButton(
                                                    tooltip: _player['songIsLiked'] ==
                                                            true
                                                        ? 'Unlike'
                                                        : 'Like',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      _player['songIsLiked'] ==
                                                              true
                                                          ? Icons
                                                              .favorite_rounded
                                                          : Icons
                                                              .favorite_border_rounded,
                                                      color: _player['songIsLiked'] ==
                                                              true
                                                          ? const Color(
                                                              0xFFE57373,
                                                            )
                                                          : Colors.white
                                                              .withValues(
                                                              alpha: 0.92,
                                                            ),
                                                      size: 24,
                                                    ),
                                                    onPressed: () async {
                                                      final m = _player['songIsLiked'] ==
                                                              true
                                                          ? 'unlike'
                                                          : 'like';
                                                      await _method
                                                          .invokeMethod(
                                                        m,
                                                        {
                                                          'song':
                                                              song.toMap(),
                                                        },
                                                      );
                                                      if (!mounted) return;
                                                      final snap = _asMap(
                                                        await _method
                                                            .invokeMethod(
                                                          'getPlayerState',
                                                        ),
                                                      );
                                                      if (snap != null) {
                                                        setState(
                                                          () => _player =
                                                              _detachPlayerState(
                                                            snap,
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              if (buffering)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                    child:
                                                        LinearProgressIndicator(
                                                      minHeight: 4,
                                                      backgroundColor: Colors
                                                          .grey.shade800
                                                          .withValues(
                                                        alpha: 0.9,
                                                      ),
                                                      color: Colors
                                                          .grey.shade500,
                                                    ),
                                                  ),
                                                ),
                                              RepaintBoundary(
                                                child: _MetrolistSeekBar(
                                                  value: progress,
                                                  enabled: effectiveDurMs > 750,
                                                  style: _progressStyle,
                                                  motion: _seekMotion,
                                                  accent: accent,
                                                  onSeek: (value) =>
                                                      _method.invokeMethod(
                                                    'seekTo',
                                                    {
                                                      'positionMs':
                                                          (effectiveDurMs *
                                                                  value)
                                                              .round(),
                                                    },
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                  6,
                                                  0,
                                                  6,
                                                  0,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      _fmt(position.round()),
                                                      style: const TextStyle(
                                                        color: _kMetrolistNpTime,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      endTimeLabel,
                                                      style: const TextStyle(
                                                        color: _kMetrolistNpTime,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              _SimpMusicPlayerControlLayout(
                                                shuffle: shuffle,
                                                repeatMode: repeat,
                                                playing: playing,
                                                buffering: buffering,
                                                prevEnabled: prevEnabled,
                                                nextEnabled: nextEnabled,
                                              ),
                                              Transform.translate(
                                                offset: const Offset(0, -6),
                                                child: Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: padBottom > 0
                                                      ? 2
                                                      : 8,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceAround,
                                                  children: [
                                                    _PlayerBottomToolButton(
                                                      tooltip: 'Track info',
                                                      icon: Icons
                                                          .info_outline_rounded,
                                                      onPressed: () =>
                                                          _showTrackInfo(song),
                                                    ),
                                                    _PlayerBottomToolButton(
                                                      tooltip: 'Lyrics',
                                                      icon: Icons
                                                          .lyrics_outlined,
                                                      whiteGlow: true,
                                                      onPressed: () =>
                                                          setState(
                                                        () => _tab = 1,
                                                      ),
                                                    ),
                                                    _PlayerBottomToolButton(
                                                      tooltip: 'Queue',
                                                      icon: Icons
                                                          .queue_music_rounded,
                                                      onPressed: () =>
                                                          setState(
                                                        () => _tab = 2,
                                                      ),
                                                    ),
                                                    _PlayerBottomToolButton(
                                                      tooltip: 'Sleep timer',
                                                      icon: Icons
                                                          .bedtime_outlined,
                                                      onPressed: () =>
                                                          _showSleepTimerSheet(
                                                        context,
                                                      ),
                                                    ),
                                                    _PlayerBottomToolButton(
                                                      tooltip: 'Equalizer',
                                                      icon: Icons
                                                          .graphic_eq_rounded,
                                                      onPressed:
                                                          _openSystemEqualizer,
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
                          ),
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({
    required this.accent,
    required this.selected,
    required this.onPick,
  });

  final Color accent;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String)>[
      (Icons.play_circle_outline_rounded, 'Player'),
      (Icons.lyrics_outlined, 'Lyrics'),
      (Icons.queue_music_outlined, 'Queue'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kMetrolistNpSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _kMetrolistNpSurfaceHigh.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: tabs[i].$2,
                  child: Material(
                    color: selected == i
                        ? accent
                        : Colors.black.withValues(alpha: _kSubtleBlackTint),
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onPick(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Icon(
                          tabs[i].$1,
                          size: 21,
                          color: selected == i
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
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

class _MetrolistSeekBar extends StatefulWidget {
  const _MetrolistSeekBar({
    required this.value,
    required this.enabled,
    required this.style,
    required this.motion,
    required this.accent,
    required this.onSeek,
  });

  final double value;
  final bool enabled;
  final int style;
  final int motion;
  final Color accent;
  final ValueChanged<double> onSeek;

  @override
  State<_MetrolistSeekBar> createState() => _MetrolistSeekBarState();
}

class _MetrolistSeekBarState extends State<_MetrolistSeekBar>
    with TickerProviderStateMixin {
  late final AnimationController _motionCtrl;
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    final initial = widget.value.clamp(0.0, 1.0);
    _progressCtrl = AnimationController(
      vsync: this,
      value: initial,
      duration: const Duration(milliseconds: 280),
      lowerBound: 0,
      upperBound: 1,
    );
    _motionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.motion > 0 || widget.style >= 2) {
      if (!_motionCtrl.isAnimating) {
        _motionCtrl.repeat();
      }
    } else {
      _motionCtrl.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _MetrolistSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.value.clamp(0.0, 1.0);
    if ((target - _progressCtrl.value).abs() > 0.001) {
      _progressCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (oldWidget.motion != widget.motion || oldWidget.style != widget.style) {
      _syncMotion();
    }
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  double get _paintHeight {
    final s = widget.style.clamp(0, 3);
    if (s == 0) return 32.0;
    if (s == 1) return 46.0;
    return 54.0;
  }

  void _seek(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    widget.onSeek((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.style.clamp(0, 3);
    final mo = widget.motion.clamp(0, 2);
    Widget buildBar(double phase, double progress) {
      return CustomPaint(
        painter: _MetrolistSeekPainter(
          progress: progress,
          dimmed: !widget.enabled,
          style: st,
          accent: widget.accent,
          motion: mo,
          motionPhase: phase,
        ),
        child: SizedBox(height: _paintHeight, width: double.infinity),
      );
    }

    final content = AnimatedBuilder(
      animation: Listenable.merge([_motionCtrl, _progressCtrl]),
      builder: (context, _) => buildBar(
        _motionCtrl.value,
        _progressCtrl.value.clamp(0.0, 1.0),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      onHorizontalDragUpdate: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      child: content,
    );
  }
}

class _MetrolistSeekPainter extends CustomPainter {
  _MetrolistSeekPainter({
    required this.progress,
    required this.dimmed,
    required this.style,
    required this.accent,
    required this.motion,
    required this.motionPhase,
  });

  final double progress;
  final bool dimmed;
  final int style;
  final Color accent;
  final int motion;
  final double motionPhase;

  static const _inactive = Color(0xFF5C5C5C);
  static const _active = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final p = progress.clamp(0.0, 1.0);
    final inactiveColor = dimmed ? _inactive.withValues(alpha: 0.45) : _inactive;
    final shimmer = motion == 2 ? (0.72 + 0.28 * math.sin(motionPhase * math.pi * 2)) : 1.0;
    final useAccent = style >= 2;
    var activeColor = dimmed
        ? Colors.white38
        : (useAccent ? accent : _active);
    if (motion == 2) {
      activeColor = activeColor.withValues(alpha: (activeColor.a * shimmer).clamp(0.15, 1.0));
    }

    if (style == 1) {
      final trackH = 16.0;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
        const Radius.circular(999),
      );
      canvas.drawRRect(r, Paint()..color = inactiveColor);
      if (p > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
            const Radius.circular(999),
          ),
          Paint()..color = activeColor,
        );
      }
    } else if (style == 2 || style == 3) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final activePaint = Paint()
        ..color = activeColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(0, y);
      final amp = style == 3 ? 7.0 : 4.0;
      final freq = style == 3 ? 18.0 : 12.0;
      // When motion is on, scroll the phase so Wave / Squiggle feel alive (Metrolist-like).
      // Continuous phase — wave scroll is time-based, not tied to discrete progress ticks.
      final scroll = motionPhase * math.pi * 2 * 2.0;
      for (double x = 0; x <= size.width; x += 1.0) {
        path.lineTo(
          x,
          y +
              math.sin((x / freq) * math.pi * 2 + scroll) * amp,
        );
      }
      canvas.drawPath(path, inactivePaint);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * p, size.height));
      canvas.drawPath(path, activePaint);
      canvas.restore();
    } else {
      final trackH = 6.0;
      final full = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
        const Radius.circular(3),
      );
      canvas.drawRRect(full, Paint()..color = inactiveColor);
      if (p > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
            const Radius.circular(2),
          ),
          Paint()..color = activeColor,
        );
      }
    }

    final pulse = motion == 1
        ? (1.0 + 0.35 * math.sin(motionPhase * math.pi * 2))
        : 1.0;
    final tw = (3.0 * pulse).clamp(2.5, 5.5);
    final th = (14.0 * (0.92 + 0.08 * pulse)).clamp(12.0, 17.0);
    final half = tw / 2 + 1.0;
    final cx = (size.width * p).clamp(half, size.width - half);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: tw, height: th),
      Radius.circular(tw / 2),
    );
    canvas.drawRRect(
      thumb,
      Paint()..color = dimmed ? Colors.white54 : _active,
    );
  }

  @override
  bool shouldRepaint(covariant _MetrolistSeekPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.dimmed != dimmed ||
      oldDelegate.style != style ||
      oldDelegate.accent != accent ||
      oldDelegate.motion != motion ||
      oldDelegate.motionPhase != motionPhase;
}

/// Bottom tool row on the now-playing sheet (info, lyrics, queue, …).
class _PlayerBottomToolButton extends StatelessWidget {
  const _PlayerBottomToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.whiteGlow = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  /// Lyrics control: soft white glow only (no tinted tile).
  final bool whiteGlow;

  static const double _tapSize = 58;
  static const double _iconSize = 30;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      size: _iconSize,
      color: Colors.white.withValues(alpha: 0.94),
    );
    Widget child;
    if (whiteGlow) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.55),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.28),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: iconWidget,
      );
    } else {
      child = iconWidget;
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _tapSize,
            height: _tapSize,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// SimpMusic-style transport row: shuffle · previous · large play/pause · next · repeat
/// (see `PlayerControlLayout.kt` in SimpMusic).
class _SimpMusicPlayerControlLayout extends StatelessWidget {
  const _SimpMusicPlayerControlLayout({
    required this.shuffle,
    required this.repeatMode,
    required this.playing,
    required this.buffering,
    required this.prevEnabled,
    required this.nextEnabled,
  });

  final bool shuffle;
  final String repeatMode;
  final bool playing;
  final bool buffering;
  final bool prevEnabled;
  final bool nextEnabled;

  @override
  Widget build(BuildContext context) {
    final repeatOn = repeatMode != 'Off';
    final whiteOn = Colors.white.withValues(alpha: 0.95);
    final whiteOff = Colors.white.withValues(alpha: 0.55);

    Widget slot(Widget child) => Expanded(child: Center(child: child));

    Widget iconOnlyBtn({
      required VoidCallback? onTap,
      required Widget icon,
    }) {
      return IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 26,
        constraints: const BoxConstraints(
          minWidth: 52,
          minHeight: 52,
        ),
        icon: icon,
      );
    }

    Widget mainPlay() {
      const playSize = 183.0;
      return slot(
        Material(
          color: Colors.white.withValues(alpha: 0.96),
          elevation: 8,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _method.invokeMethod('togglePlayPause'),
            child: SizedBox(
              width: playSize,
              height: playSize,
              child: buffering
                  ? const Center(
                      child: SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black38,
                        ),
                      ),
                    )
                  : Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: playing ? 82 : 86,
                      color: Colors.black87,
                    ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 183,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            slot(
              iconOnlyBtn(
                onTap: () => _method.invokeMethod('toggleShuffle'),
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 30,
                  color: shuffle ? whiteOn : whiteOff,
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: prevEnabled
                    ? () => _method.invokeMethod('previous')
                    : null,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 50,
                  color: prevEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            mainPlay(),
            slot(
              iconOnlyBtn(
                onTap: nextEnabled
                    ? () => _method.invokeMethod('next')
                    : null,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 50,
                  color: nextEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: () => _method.invokeMethod('cycleRepeatMode'),
                icon: Icon(
                  repeatMode == 'One'
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  size: 30,
                  color: repeatOn ? whiteOn : whiteOff,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsTab extends StatelessWidget {
  const _LyricsTab({
    required this.lines,
    required this.loading,
    required this.positionMs,
    required this.accent,
    this.preferLrclib = true,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final bool preferLrclib;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
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
                'Loading lyrics…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 48),
        child: _EmptyTabBody(
          icon: Icons.subtitles_off_rounded,
          title: 'No synced lyrics',
          subtitle: preferLrclib
              ? 'LRCLIB had no match — try turning off “Prefer LRCLIB” in Settings or ⋮ menu.'
              : 'YouTube captions had no match — try “Prefer LRCLIB” in Settings.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            preferLrclib ? 'Synced · LRCLIB' : 'Synced · YouTube captions',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        _AnimatedLyricsList(
          lines: lines,
          positionMs: positionMs,
          accent: accent,
        ),
      ],
    );
  }
}

class _AnimatedLyricsList extends StatefulWidget {
  const _AnimatedLyricsList({
    required this.lines,
    required this.positionMs,
    required this.accent,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final Color accent;

  @override
  State<_AnimatedLyricsList> createState() => _AnimatedLyricsListState();
}

class _AnimatedLyricsListState extends State<_AnimatedLyricsList> {
  late final ScrollController _controller;
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = _activeIndex;
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final target = (active * 58.0 - 150).clamp(
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _MetrolistPlayerSectionLabel('Lyrics'),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              final isActive = index == active;
              final passed = index < active;
              return TweenAnimationBuilder<double>(
                key: ValueKey('${line.timeMs}-$isActive'),
                tween: Tween(begin: 0, end: isActive ? 1 : 0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  final scale = 1.0 + (0.055 * t);
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: EdgeInsets.symmetric(
                        horizontal: isActive ? 14 : 0,
                        vertical: isActive ? 12 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? widget.accent.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        line.text,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : passed
                              ? Colors.white.withValues(alpha: 0.34)
                              : Colors.white.withValues(alpha: 0.58),
                          fontSize: isActive ? 25 : 19,
                          height: 1.32,
                          fontWeight: isActive
                              ? FontWeight.w900
                              : FontWeight.w700,
                          shadows: isActive
                              ? [
                                  Shadow(
                                    color: widget.accent.withValues(
                                      alpha: 0.65,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.currentIndex,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_Song> queue;
  final int currentIndex;
  final FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _MetrolistPlayerSectionLabel(
          'Queue',
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: 1, right: 2),
            child: Text(
              '${queue.length} songs',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (queue.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: _EmptyTabBody(
              icon: Icons.queue_music_rounded,
              title: 'Queue is empty',
              subtitle: 'Play a song to build your queue, then open this tab.',
            ),
          )
        else
          ...queue.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final active = index == currentIndex;
            return _FoxySongTile(
              song: item,
              index: index,
              thumbRadius: 10,
              active: active,
              onMore: () {
                final play = onPlay;
                if (play != null) {
                  showFoxySongOverflowMenu(
                    context,
                    song: item,
                    onPlay: play,
                    queueForPlay: queue,
                    onDiscoverSearch: onDiscoverSearch,
                    onLibraryChanged: () async {},
                    showRemoveFromQueue: true,
                  );
                } else {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: const Color(0xFF111111),
                    builder: (_) => _QueueSongMenu(song: item),
                  );
                }
              },
              onTap: () =>
                  _method.invokeMethod('skipToQueueIndex', {'index': index}),
            );
          }),
      ],
    );
  }
}

class _MenuQuickAction extends StatelessWidget {
  const _MenuQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kCardRadius),
        onTap: () async {
          await onTap();
          if (context.mounted) Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueSongMenu extends StatelessWidget {
  const _QueueSongMenu({required this.song});

  final _Song song;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: _Artwork(
              url: song.artwork,
              size: 52,
              radius: 10,
              identityTag: song.videoId,
            ),
            title: Text(song.title, maxLines: 1),
            subtitle: Text(song.artist, maxLines: 1),
          ),
          _MenuAction(
            icon: Icons.queue_play_next_rounded,
            label: 'Play next',
            onTap: () =>
                _method.invokeMethod('enqueuePlayNext', {'song': song.toMap()}),
          ),
          _MenuAction(
            icon: Icons.delete_rounded,
            label: 'Remove from queue',
            onTap: () =>
                _method.invokeMethod('removeFromQueue', {'song': song.toMap()}),
          ),
        ],
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: () async {
        await onTap();
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}

class _LyricLine {
  const _LyricLine({required this.timeMs, required this.text});

  factory _LyricLine.fromMap(Map<String, dynamic> map) => _LyricLine(
    timeMs: ((map['timeMs'] ?? 0) as num).toInt(),
    text: map['text']?.toString() ?? '',
  );

  final int timeMs;
  final String text;
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.url,
    required this.playing,
    required this.tag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.maxSide,
  });

  final String url;
  final bool playing;
  final String tag;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;
  /// Caps artwork so transport rows never collide on narrow devices.
  final double? maxSide;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final base = math.min(w - 4, h * 0.52).clamp(360.0, 960.0);
    final side = maxSide ?? base;
    final artSide = side;
    final radius = (artSide * 0.06).clamp(12.0, 22.0);
    final discSize = artSide * 0.22;
    final accent = Theme.of(context).colorScheme.primary;
    final identity = tag.startsWith('art-') ? tag.substring(4) : tag;

    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.55),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: SizedBox(
                width: artSide,
                height: artSide,
                child: _Artwork(
                  url: url,
                  size: artSide,
                  radius: 0,
                  highQuality: true,
                  identityTag: identity,
                  offlineArtworkPath: offlineArtworkPath,
                  useOfflineArtwork: useOfflineArtwork,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _SpinningDiscOverlay(
              size: discSize,
              playing: playing,
              accent: accent,
              artworkUrl: url,
              identityTag: identity,
              offlineArtworkPath: offlineArtworkPath,
              useOfflineArtwork: useOfflineArtwork,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small vinyl disc badge — spins in the upper-right corner of the artwork.
class _SpinningDiscOverlay extends StatefulWidget {
  const _SpinningDiscOverlay({
    required this.size,
    required this.playing,
    required this.accent,
    required this.artworkUrl,
    required this.identityTag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
  });

  final double size;
  final bool playing;
  final Color accent;
  final String artworkUrl;
  final String identityTag;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  @override
  State<_SpinningDiscOverlay> createState() => _SpinningDiscOverlayState();
}

class _SpinningDiscOverlayState extends State<_SpinningDiscOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _SpinningDiscOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _syncSpin();
  }

  void _syncSpin() {
    if (widget.playing) {
      _spinCtrl.repeat();
    } else {
      _spinCtrl.stop();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: RotationTransition(
        turns: _spinCtrl,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipOval(
                child: _Artwork(
                  url: widget.artworkUrl,
                  size: widget.size,
                  radius: 0,
                  highQuality: true,
                  identityTag: 'disc-${widget.identityTag}',
                  offlineArtworkPath: widget.offlineArtworkPath,
                  useOfflineArtwork: widget.useOfflineArtwork,
                ),
              ),
              CustomPaint(
                painter: const _VinylDiskPainter(compact: true),
              ),
              Center(
                child: _FoxyAppIconBadge(size: widget.size * 0.36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vinyl ring overlay (full disc or compact corner badge).
class _VinylDiskPainter extends CustomPainter {
  const _VinylDiskPainter({this.accent, this.compact = false});

  final Color? accent;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final labelR = outerR * (compact ? 0.34 : 0.43);

    if (!compact) {
      final vinyl = Paint()..color = const Color(0xFF101010);
      canvas.drawCircle(center, outerR, vinyl);
    }

    final groove = Paint()
      ..color = Colors.white.withValues(alpha: compact ? 0.1 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 0.6 : 0.8;
    final step = compact ? 3.5 : 5.0;
    for (var r = labelR + (compact ? 3 : 6); r < outerR - 1; r += step) {
      canvas.drawCircle(center, r, groove);
    }

    if (compact) {
      final edge = Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawCircle(center, outerR - 0.5, edge);
      canvas.drawCircle(
        center,
        labelR,
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
    } else {
      final accentColor = accent ?? _FoxyBrandPalette.foxAmber;
      final ring = Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.55),
            _FoxyBrandPalette.foxDeep.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.92),
          ],
          stops: const [0.5, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outerR));
      canvas.drawCircle(center, outerR, ring);
      canvas.drawCircle(
        center,
        labelR + 3,
        Paint()..color = const Color(0xFF080808),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VinylDiskPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.compact != compact;
}

/// FoxyMusic logo badge on the vinyl outer ring.
class _FoxyAppIconBadge extends StatelessWidget {
  const _FoxyAppIconBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          _kFoxyLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: size * 0.58,
          ),
        ),
      ),
    );
  }
}

/// Fixed gramophone tonearm at the upper-right of the artwork.
class _VinylTonearmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.88, size.height * 0.12);
    final tip = Offset(size.width * 0.18, size.height * 0.78);
    final arm = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, tip, arm);
    canvas.drawCircle(
      pivot,
      size.width * 0.1,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: tip,
        width: size.width * 0.34,
        height: size.height * 0.16,
      ),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(
      head,
      Paint()..color = Colors.black.withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      head,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.size,
    required this.radius,
    this.identityTag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.highQuality = false,
  });

  final String url;
  final double size;
  final double radius;
  /// When set, combined with [url] for [Image.network] keys so artwork swaps on track change.
  final String? identityTag;
  /// Native-resolved JPEG path (embedded / cached) for offline artwork.
  final String? offlineArtworkPath;
  /// Only read [offlineArtworkPath] when true (downloaded tracks); streaming keeps network thumb.
  final bool useOfflineArtwork;
  /// Decode more pixels for large now-playing artwork.
  final bool highQuality;

  @override
  Widget build(BuildContext context) {
    File? offlineFile() {
      if (!useOfflineArtwork || kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      final f = File(p);
      if (f.existsSync()) return f;
      return null;
    }

    File? localPathFile() {
      if (kIsWeb) return null;
      final u = url.trim();
      if (u.isEmpty) return null;
      if (u.startsWith('http://') || u.startsWith('https://')) return null;
      final path = u.startsWith('file://') ? u.substring(7) : u;
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 0) return f;
      return null;
    }

    final of = offlineFile() ?? localPathFile();
    if (url.isBlank && of == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      );
    }
    final cacheKey = identityTag != null && identityTag!.isNotEmpty
        ? '${identityTag!}|${of?.path ?? url}|${offlineArtworkPath ?? ''}'
        : '${of?.path ?? url}|${offlineArtworkPath ?? ''}';
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.42),
      ),
    );

    final cacheMax = highQuality ? 1024 : 512;
    if (of != null) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(64, cacheMax);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          of,
          key: ValueKey<String>(cacheKey),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: false,
          filterQuality:
              highQuality ? FilterQuality.high : FilterQuality.medium,
          cacheWidth: cachePx,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    }

    if (url.isBlank) {
      return placeholder;
    }

    final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, cacheMax);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        key: ValueKey<String>(cacheKey),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: false,
        filterQuality: highQuality ? FilterQuality.high : FilterQuality.medium,
        cacheWidth: cachePx,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.blurEnabled,
    this.sigma = 56,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.fullBleed = false,
  });

  final String url;
  final bool blurEnabled;
  final double sigma;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;
  /// Full-screen blurred artwork only (now playing card).
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
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
    final brandUnderlay = fullBleed
        ? const ColoredBox(color: Color(0xFF050505))
        : _FoxyBrandGradientBackdrop(
            variant: _FoxyGradientVariant.player,
            child: const SizedBox.expand(),
          );
    if (!blurEnabled || (url.isBlank && of == null)) {
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
        ],
      );
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
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF080808),
            ),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF080808),
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: fullBleed ? 1.35 : 1.18,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: fullBleed ? sigma + 8 : sigma,
              sigmaY: fullBleed ? sigma + 8 : sigma,
            ),
            child: SizedBox.expand(child: imageChild),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fullBleed
                  ? [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.72),
                    ]
                  : [
                      accent.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.55),
                      Color.lerp(const Color(0xFF000000), accent, 0.08)!
                          .withValues(alpha: 0.94),
                    ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _SongSection {
  const _SongSection({
    required this.title,
    required this.songs,
    this.layout = 'shelf',
  });

  factory _SongSection.fromMap(Map<String, dynamic> map) => _SongSection(
    title: map['title']?.toString() ?? 'For you',
    layout: map['layout']?.toString() ?? 'shelf',
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList(),
  );

  final String title;
  final String layout;
  final List<_Song> songs;
}

class _Song {
  const _Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artwork,
    this.duration,
    this.isDownloaded = false,
    this.localPath,
    this.offlineArtworkPath,
  });

  factory _Song.fromMap(Map<String, dynamic> map) {
    final artwork = [map['artworkUrl'], map['thumbnail']]
        .map((value) => value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final lp = map['localPath']?.toString();
    final oap = map['offlineArtworkPath']?.toString();
    return _Song(
      videoId: map['videoId']?.toString() ?? '',
      title: map['title']?.toString().ifBlank('Untitled') ?? 'Untitled',
      artist:
          map['artist']?.toString().ifBlank('Unknown artist') ??
          'Unknown artist',
      artwork: artwork,
      duration: map['duration']?.toString(),
      isDownloaded: map['isDownloaded'] == true,
      localPath: (lp != null && lp.isNotEmpty) ? lp : null,
      offlineArtworkPath: (oap != null && oap.isNotEmpty) ? oap : null,
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final String artwork;
  final String? duration;
  final bool isDownloaded;
  final String? localPath;
  final String? offlineArtworkPath;

  String get highQualityArtwork => _upgradeYouTubeArtworkUrl(artwork, videoId);

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': artwork,
    'artworkUrl': artwork,
    'isDownloaded': isDownloaded,
    if (duration != null) 'duration': duration,
    if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
    if (offlineArtworkPath != null && offlineArtworkPath!.isNotEmpty)
      'offlineArtworkPath': offlineArtworkPath,
  };
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, dynamic item) => MapEntry(key.toString(), _normalize(item)),
    );
  }
  return null;
}

/// Fresh maps for [currentSong] / [queue] so the mini player always reflects the latest track.
Map<String, dynamic> _detachPlayerState(Map<String, dynamic> state) {
  final out = Map<String, dynamic>.from(state);
  final cs = state['currentSong'];
  if (cs is Map) {
    final m = _asMap(cs);
    if (m != null) out['currentSong'] = Map<String, dynamic>.from(m);
  }
  final q = state['queue'];
  if (q is List) {
    out['queue'] = q
        .map((dynamic e) {
          final m = _asMap(e);
          return m != null ? Map<String, dynamic>.from(m) : e;
        })
        .toList();
  }
  return out;
}

dynamic _normalize(dynamic value) {
  if (value is Map) return _asMap(value);
  if (value is List) return value.map(_normalize).toList();
  return value;
}

String _upgradeYouTubeArtworkUrl(String url, String videoId) {
  var u = url.trim();
  if (u.isEmpty && videoId.isNotEmpty) {
    return 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
  }
  if (u.isEmpty) return u;
  u = u
      .replaceAll('=s88-', '=s800-')
      .replaceAll('=s120-', '=s800-')
      .replaceAll('=s180-', '=s800-')
      .replaceAll('=s360-', '=s800-')
      .replaceAll('=w88-h88', '=w800-h800')
      .replaceAll('=w120-h120', '=w800-h800')
      .replaceAll('=w360-h360', '=w800-h800');
  u = u.replaceAll(
    RegExp(r'/(hqdefault|mqdefault|default)\.jpg'),
    '/maxresdefault.jpg',
  );
  return u;
}

String _fmt(int ms) {
  final total = (ms ~/ 1000).clamp(0, 999999);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

extension on String {
  bool get isBlank => trim().isEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
