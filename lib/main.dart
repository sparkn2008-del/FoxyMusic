import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'foxy_startup_splash.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

typedef _FoxyOnPlay =
    Future<void> Function(_Song song, List<_Song> queue, {bool radioTail});

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;

/// Vertical gap between home feed shelves (spotlight, rails, song rows).
const double _kHomeShelfGap = 28.0;

/// Space between a shelf title and its content.
const double _kHomeShelfTitleGap = 14.0;

String _kAppVersionLabel = 'v1.3';
String _kAppVersionName = '1.3';
const String _kGitHubProjectUrl = 'https://github.com/sparkn2008-del/FoxyMusic';
const String _kAboutCreditLine =
    'Made in shape by Foxy-Nish aka "sparkn2008-del"';
const String _kFoxyLogoAsset = 'assets/images/app_art.png';

/// Metrolist-style now playing foreground (backdrop stays full-bleed [_BlurBackdrop]).
const Color _kMetrolistNpTime = Color(0xFF9E9E9E);

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xCC000000),
    Color.lerp(const Color.fromARGB(139, 192, 16, 16), accent, 0.28)!,
  );
}

bool _effectivePlayerBuffering(Map<String, dynamic> player) {
  return player['isBuffering'] == true && player['isPlaying'] != true;
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
  PaintingBinding.instance.imageCache.maximumSize = 900;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FoxyAppLaunchGate(child: FoxyFlutterApp()));
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
          final shouldUpdateShell =
              nextDynamic != _dynamicSongColors ||
              accentChanged ||
              epochChanged ||
              videoChanged;
          if (shouldUpdateShell) {
            setState(() {
              _dynamicSongColors = nextDynamic;
              _songAccentArgb = nextAccent;
              _paletteEpoch = nextEpoch;
              _lastPlayerVideoId = vid;
            });
          }
          if (nextDynamic && shouldUpdateShell) {
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
          final bgEnabled = map['homeBackgroundEnabled'] == true;
          _homeBackgroundPath = bgEnabled && bg != null && bg.isNotEmpty
              ? bg
              : null;
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
  @override
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

String _cleanDisplayText(dynamic value, {String fallback = ''}) {
  var text = value?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  const replacements = <String, String>{
    'Ã‚Â·': ' - ',
    'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢': ' - ',
    'Ãƒâ€šÃ‚Â¢': ' - ',
    'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â': ' - ',
    'Ãƒâ€šÃ‚Â': '"',
    'Ãƒâ€¦Ã¢â‚¬Å“': '"',
    'Ãƒâ€šÃ‚Â¦': '...',
    'Ã¢â‚¬Â¦': '...',
    'Ã¢â‚¬Â¢': ' - ',
    'Ã¢â‚¬â€œ': ' - ',
    'Ã¢â‚¬â€': ' - ',
    'Ã¢â‚¬Å“': '"',
    'Ã¢â‚¬Â': '"',
    'Ã¢â‚¬Ëœ': "'",
    'Ã¢â‚¬â„¢': "'",
    'Ã¢â€šÂ¬': '',
    'Ã‚': '',
    'Â·': ' - ',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  text = text
      .replaceAll(RegExp(r'Ã\S*'), '')
      .replaceAll(RegExp(r'[\uFFFD]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? fallback : text;
}

String _primaryArtistNameForLookup(String value) {
  final cleaned = value.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ').trim();
  final parts = cleaned.split(
    RegExp(
      r'\s*(?:,|&|/|\+|\bx\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)\s*',
      caseSensitive: false,
    ),
  );
  return parts
      .firstWhere((part) => part.trim().isNotEmpty, orElse: () => value)
      .trim();
}

String _normalizeArtistLookupKey(String value) =>
    _primaryArtistNameForLookup(value)
        .toLowerCase()
        .replaceAll(RegExp(r'\b(official|topic|vevo|artist|channel)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

int _normalizePlayerProgressStyle(int raw) {
  return 0;
}

int _normalizePlayerBackgroundStyle(int raw) {
  final value = raw.clamp(0, 3);
  if (value == 1 || value == 2 || value == 3) return value;
  return 0;
}

/// Warm fox-fur tones from the FoxyMusic logo (amber, deep orange, cream).
class _FoxyBrandPalette {
  static const foxAmber = Color(0xFFFF9A3C);
  static const foxDeep = Color(0xFFE85D04);
  static const foxCream = Color(0xFFFFD9B0);
  static const foxEmber = Color(0xFFFF1744);
}

enum _FoxyGradientVariant { home, player }

/// Large soft blooms: fox logo warmth + dynamic song accent.
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
    // Foxy-style: dark base with one soft accent bloom (player is subtler than home).
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
                Color.lerp(
                  const Color(0xFF1A0E08),
                  const Color(0xFF0A0A0A),
                  0.5,
                )!,
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
                    Color.lerp(
                      _FoxyBrandPalette.foxCream,
                      accent,
                      0.35,
                    )!.withValues(alpha: strong ? 0.22 : 0.34),
                    _FoxyBrandPalette.foxAmber.withValues(
                      alpha: strong ? 0.14 : 0.22,
                    ),
                    _FoxyBrandPalette.foxDeep.withValues(
                      alpha: strong ? 0.06 : 0.1,
                    ),
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
                    _FoxyBrandPalette.foxEmber.withValues(
                      alpha: strong ? 0.1 : 0.18,
                    ),
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
                    _FoxyBrandPalette.foxDeep.withValues(
                      alpha: strong ? 0.14 : 0.16,
                    ),
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
          errorBuilder: (_, _, _) => Icon(
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
  const _FoxyHomeBackdrop({required this.child, this.customPath});

  final Widget child;
  final String? customPath;

  @override
  Widget build(BuildContext context) {
    final hasCustom =
        customPath != null &&
        customPath!.isNotEmpty &&
        !kIsWeb &&
        File(customPath!).existsSync();
    Widget bg = const ColoredBox(color: Color(0xFF000000));
    if (hasCustom) {
      bg = Image.file(
        File(customPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        if (hasCustom)
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

/// Translucent surface ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â does **not** blur the wallpaper (cards, bars, sheets).
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
    final radius = borderRadius > 0
        ? BorderRadius.circular(borderRadius)
        : null;
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
            : Border.all(color: Colors.white.withValues(alpha: borderOpacity)),
      ),
      child: child,
    );
  }
}

/// Glass control surface. Foxy-style: scrolling lists use [blur] off (tint
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

  /// Live [BackdropFilter] ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â only for small fixed chrome (nav, header icons).
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
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
        child: InkWell(onTap: onTap, borderRadius: borderRadius, child: core),
      );
    }
    return core;
  }
}

/// Text action styled as frosted glass (Play all, Retry, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦).
class _FoxyGlassTextButton extends StatelessWidget {
  const _FoxyGlassTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onPressed,
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
  final t = section.title.toLowerCase();
  if (t.contains('quick pick')) return _HomeSectionLayout.cards;
  if (t.contains('chart') || t.contains('trending')) {
    return _HomeSectionLayout.chart;
  }
  if (t.contains('resume') ||
      t.contains('replayed') ||
      t.contains('downloaded')) {
    return _HomeSectionLayout.square;
  }
  if (t.contains('today on foxy') ||
      t.contains('india pulse') ||
      t.contains('hidden gem')) {
    return _HomeSectionLayout.square;
  }
  switch (section.layout) {
    case 'square':
      return _HomeSectionLayout.square;
    case 'radio':
      return _HomeSectionLayout.radio;
    case 'mixes':
      return _HomeSectionLayout.mixes;
    case 'video':
      return _HomeSectionLayout.video;
    case 'grid':
      return _HomeSectionLayout.square;
    case 'chart':
      return _HomeSectionLayout.chart;
    case 'artist':
      return _HomeSectionLayout.artist;
    case 'cards':
      return _HomeSectionLayout.cards;
    default:
      final t = section.title.toLowerCase();
      if (t.contains('video')) return _HomeSectionLayout.video;
      if (t.contains('replayed') ||
          t.contains('radio') ||
          t.contains('starter')) {
        return _HomeSectionLayout.square;
      }
      if (t.contains('mix')) return _HomeSectionLayout.mixes;
      if (t.contains('chart') || t.contains('trending')) {
        return _HomeSectionLayout.chart;
      }
      if (t.contains('artist') || t.contains('similar')) {
        return _HomeSectionLayout.artist;
      }
      if (t.contains('release') ||
          t.contains('discover') ||
          t.contains('cover') ||
          t.contains('remix') ||
          t.contains('daily') ||
          t.contains('fresh')) {
        return _HomeSectionLayout.square;
      }
      return _HomeSectionLayout.square;
  }
}

bool _isSuppressedHomeSection(String title) {
  final t = title.toLowerCase();
  return t.contains('fresh finds') ||
      t.contains('old favorites') ||
      t.contains('old favourites') ||
      t.contains('late-night drive') ||
      t.contains('late night drive') ||
      t.contains('focus flow') ||
      t.contains('foxy mix') ||
      t.contains('radio starter');
}

const String _homeParamsRelax =
    'ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsSleep =
    'ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsEnergize =
    'ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsSad =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsRomance =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsFeelGood =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBADSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsWorkout =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBADSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsParty =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhADSgQIAxABSgQIBhAB';
const String _homeParamsCommute =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxADSgQIBhAB';
const String _homeParamsFocus =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAD';

String? _homeFeedParamsForChip(String chip) {
  switch (chip) {
    case 'Relax':
      return _homeParamsRelax;
    case 'Sleep':
      return _homeParamsSleep;
    case 'Energize':
      return _homeParamsEnergize;
    case 'Sad':
      return _homeParamsSad;
    case 'Romance':
      return _homeParamsRomance;
    case 'Feel good':
      return _homeParamsFeelGood;
    case 'Workout':
      return _homeParamsWorkout;
    case 'Party':
      return _homeParamsParty;
    case 'Drive':
      return _homeParamsCommute;
    case 'Commute':
      return _homeParamsCommute;
    case 'Focus':
      return _homeParamsFocus;
    default:
      return null;
  }
}

String _homeFeedCacheKey(String? params) => params ?? '__all__';

String? _homeMoodQueryForChip(String chip) {
  switch (chip) {
    case 'Moods':
      return 'moods';
    case 'Genres':
      return 'genres';
    case 'Charts':
      return 'charts';
    case 'Categories':
      return 'categories';
    case 'Downloads':
      return 'downloaded';
    case 'Radio':
      return 'radio';
    case 'History':
      return 'history';
    case 'Phonk':
      return 'phonk';
    default:
      return null;
  }
}

const _searchFilterChips = <String>[
  'All',
  'Songs',
  'Videos',
  'Albums',
  'Artists',
];

enum _HomeSectionLayout {
  cards,
  grid,
  video,
  chart,
  artist,
  radio,
  mixes,
  square,
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

class _FoxyHomeShellState extends State<FoxyHomeShell>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  final GlobalKey<_HomeTabState> _homeTabKey = GlobalKey<_HomeTabState>();
  final GlobalKey<_SearchTabState> _searchTabKey = GlobalKey<_SearchTabState>();
  final GlobalKey<_LibraryTabState> _libraryTabKey =
      GlobalKey<_LibraryTabState>();
  Map<String, dynamic> _player = const {};
  final ValueNotifier<Map<String, dynamic>> _miniPlayerNotifier =
      ValueNotifier<Map<String, dynamic>>(const {});
  Map<String, dynamic> _account = const {};
  Map<String, dynamic> _shellSettings = const {};
  StreamSubscription<dynamic>? _sub;

  /// Avoid mini player + expanded sheet stacking (and Hero flights from feed art).
  bool _nowPlayingSheetOpen = false;
  Timer? _playbackResyncTimer;
  bool _appliedDefaultOpenTab = false;

  void _schedulePlaybackResync({bool extended = false}) {
    for (final delayMs
        in extended ? const [250, 600, 1200, 2500] : const [250, 600]) {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        unawaited(_syncPlayerFromNative());
      });
    }
  }

  void _syncPlaybackResyncTimer() {
    final song = _asMap(_player['currentSong']);
    final hasSong = (song?['videoId']?.toString().isNotEmpty ?? false);
    final needsResync =
        hasSong && !_nowPlayingSheetOpen && _effectivePlayerBuffering(_player);
    if (!needsResync) {
      _playbackResyncTimer?.cancel();
      _playbackResyncTimer = null;
      return;
    }
    _playbackResyncTimer ??= Timer.periodic(const Duration(milliseconds: 450), (
      _,
    ) {
      if (!mounted) return;
      unawaited(_syncPlayerFromNative());
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccount();
    unawaited(_loadShellSettings());
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
        _SongMenuContextCache.invalidate();
        unawaited(_loadAccount());
      } else if (type == 'appearanceChanged') {
        unawaited(_loadShellSettings(applyDefaultTab: false));
      }
    });
  }

  Future<void> _loadShellSettings({bool applyDefaultTab = true}) async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppearance'));
      if (!mounted || map == null) return;
      setState(() => _shellSettings = map);
      if (applyDefaultTab && !_appliedDefaultOpenTab) {
        final tab = ((map['defaultOpenTab'] ?? 0) as num).toInt();
        if (tab == 1 || tab == 3) {
          setState(() => _tabIndex = tab);
        }
        _appliedDefaultOpenTab = true;
      }
    } catch (_) {
      if (applyDefaultTab) _appliedDefaultOpenTab = true;
    }
  }

  void _applyPlayerState(Map<String, dynamic> state) {
    final merged = <String, dynamic>{..._player, ...state};
    if (!state.containsKey('queue') && _player.containsKey('queue')) {
      merged['queue'] = _player['queue'];
    }
    final next = _detachPlayerState(merged);
    final previous = _player;
    final changed = _shellPlayerSnapshotChanged(previous, next);
    final miniChanged = _miniPlayerSnapshotChanged(previous, next);
    if (!changed) {
      _player = next;
      if (miniChanged) {
        _miniPlayerNotifier.value = next;
      }
      _syncPlaybackResyncTimer();
      return;
    }
    setState(() => _player = next);
    if (miniChanged) {
      _miniPlayerNotifier.value = next;
    }
    _syncPlaybackResyncTimer();
  }

  void _setOptimisticPlayerState(Map<String, dynamic> next) {
    final detached = _detachPlayerState(next);
    if (!mounted) return;
    setState(() => _player = detached);
    _miniPlayerNotifier.value = detached;
  }

  bool _miniPlayerSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (_shellPlayerSnapshotChanged(prev, next)) return true;
    if (prev['isPlaying'] != next['isPlaying']) return true;
    if (prev['isBuffering'] != next['isBuffering']) return true;
    if (prev['songIsLiked'] != next['songIsLiked']) return true;
    if (prev['volume'] != next['volume']) return true;
    if (prev['canPlayNext'] != next['canPlayNext']) return true;
    if (prev['canPlayPrevious'] != next['canPlayPrevious']) return true;
    if (prev['shuffleEnabled'] != next['shuffleEnabled']) return true;
    if (prev['repeatMode']?.toString() != next['repeatMode']?.toString()) {
      return true;
    }
    if (prev['queueIndex'] != next['queueIndex']) return true;
    if (_playerQueueSignature(prev['queue']) !=
        _playerQueueSignature(next['queue'])) {
      return true;
    }
    if (prev['streamBitrate'] != next['streamBitrate']) return true;
    if (prev['streamCodec']?.toString() != next['streamCodec']?.toString()) {
      return true;
    }
    if (prev['streamSource']?.toString() != next['streamSource']?.toString()) {
      return true;
    }
    if (prev['durationMs'] != next['durationMs']) return true;
    final pPos = ((prev['positionMs'] ?? 0) as num).toInt();
    final nPos = ((next['positionMs'] ?? 0) as num).toInt();
    return (nPos - pPos).abs() >= 5000;
  }

  bool _shellPlayerSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (prev['playerEpoch'] != next['playerEpoch']) return true;
    if (prev['paletteEpoch'] != next['paletteEpoch']) return true;
    final pVid = _asMap(prev['currentSong'])?['videoId']?.toString() ?? '';
    final nVid = _asMap(next['currentSong'])?['videoId']?.toString() ?? '';
    if (pVid != nVid) return true;
    final pSong = _asMap(prev['currentSong']) ?? const {};
    final nSong = _asMap(next['currentSong']) ?? const {};
    if (pSong['title']?.toString() != nSong['title']?.toString()) return true;
    if (pSong['artist']?.toString() != nSong['artist']?.toString()) {
      return true;
    }
    final pArt = _asMap(prev['currentSong'])?['artwork']?.toString() ?? '';
    final nArt = _asMap(next['currentSong'])?['artwork']?.toString() ?? '';
    if (pArt != nArt) return true;
    final pOff =
        _asMap(prev['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    final nOff =
        _asMap(next['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    if (pOff != nOff) return true;
    return false;
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

  Future<void> _startRecognitionFromHome() async {
    try {
      await _method.invokeMethod('startRecognition');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Listening for music...')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Recognition failed: $e')));
    }
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
    _playbackResyncTimer?.cancel();
    _miniPlayerNotifier.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPlayerFromNative());
    }
  }

  Future<void> _playSong(
    _Song song,
    List<_Song> queue, {
    bool radioTail = false,
  }) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    final start = math.max(index, 0);
    if (mounted) {
      _setOptimisticPlayerState(<String, dynamic>{
        ..._player,
        'currentSong': song.toMap(),
        'playerEpoch': DateTime.now().microsecondsSinceEpoch,
        'isBuffering': true,
        'isPlaying': false,
        'positionMs': 0,
        'durationMs': 0,
        'queue': songs.map((item) => item.toMap()).toList(),
        'queueIndex': start,
      });
    }
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': start,
      'radioTail': radioTail,
    });
    if (mounted) {
      await _syncPlayerFromNative();
      _schedulePlaybackResync(extended: true);
    }
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
    unawaited(_syncPlayerFromNative());
    setState(() => _nowPlayingSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final top = MediaQuery.paddingOf(sheetContext).top;
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 1,
            minChildSize: 0.82,
            maxChildSize: 1,
            shouldCloseOnMinExtent: true,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: _NowPlayingSheet(
                  player: _player,
                  initialTab: initialTab,
                  scrollController: scrollController,
                  homeBackgroundPath: widget.homeBackgroundPath,
                  onNotifyHomePlayerSync: _syncPlayerFromNative,
                  onPlay: _playSong,
                  onDiscoverSearch: _openSearchWithQuery,
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _nowPlayingSheetOpen = false);
      unawaited(_syncPlayerFromNative());
      _schedulePlaybackResync(extended: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSongMap = _asMap(_player['currentSong']) ?? const {};
    final currentSong = _Song.fromMap(currentSongMap);

    final hasSong =
        currentSong.videoId.isNotEmpty && currentSong.title.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasThreeButtonNav = bottomInset >= 28;
    final navShellHeight = hasThreeButtonNav ? 58.0 : 64.0;
    final miniBottom =
        bottomInset + navShellHeight + (hasThreeButtonNav ? 8.0 : 10.0);
    final homeBottomPadding = bottomInset + navShellHeight + 88.0;
    final miniStyle = ((_shellSettings['miniPlayerStyle'] ?? 0) as num)
        .toInt()
        .clamp(0, 2)
        .toInt();
    final navStyle = ((_shellSettings['bottomNavigationStyle'] ?? 0) as num)
        .toInt()
        .clamp(0, 2)
        .toInt();
    final tabs = [
      _HomeTab(
        key: _homeTabKey,
        currentVideoId: currentSong.videoId,
        onPlay: _playSong,
        account: _account,
        onOpenSettings: _openHomeSettings,
        onOpenDiscover: () => setState(() => _tabIndex = 2),
        onOpenLibrary: () => setState(() => _tabIndex = 3),
        onStartRecognition: _startRecognitionFromHome,
        onDiscoverSearch: _openSearchWithQuery,
        homeBackgroundPath: widget.homeBackgroundPath,
        bottomContentPadding: homeBottomPadding,
      ),
      KeyedSubtree(
        key: const PageStorageKey('search-tab'),
        child: _SearchTab(
          key: _searchTabKey,
          onPlay: _playSong,
          onDiscoverSearch: _openSearchWithQuery,
        ),
      ),
      _DiscoverTab(
        onOpenSearch: () => setState(() => _tabIndex = 1),
        onDiscoverSearch: _openSearchWithQuery,
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
        if (safeTab == 3 &&
            _libraryTabKey.currentState?.consumeAndroidBack() == true) {
          return;
        }
        if (safeTab == 1 &&
            (_searchTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab == 0 &&
            (_homeTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab != 0) {
          setState(() => _tabIndex = 0);
          return;
        }
        unawaited(_method.invokeMethod('moveTaskToBack'));
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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
                  child: ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: _miniPlayerNotifier,
                    builder: (context, player, _) {
                      return _MiniPlayer(
                        key: ValueKey<Object>(
                          player['playerEpoch'] ?? currentSong.videoId,
                        ),
                        player: player.isEmpty ? _player : player,
                        onOpen: () => _openPlayer(),
                        onResync: _syncPlayerFromNative,
                        glass: true,
                        style: miniStyle,
                        bottomGap: 0,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _FoxyBottomNav(
          selectedIndex: safeTab,
          onSelected: (index) {
            if (index == 0 && safeTab == 0) {
              _homeTabKey.currentState?.resetToDefault();
            }
            if (index == 1) {
              _searchTabKey.currentState?.resetToLanding();
            }
            if (index == 3) {
              _libraryTabKey.currentState?.openAtScope(0);
            }
            setState(() => _tabIndex = index);
          },
          style: navStyle,
          compact: hasThreeButtonNav,
        ),
      ),
    );
  }
}

class _FoxyBottomNav extends StatelessWidget {
  const _FoxyBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    this.style = 0,
    this.compact = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (0, Icons.home_rounded, 'Home'),
      (1, Icons.search_rounded, 'Search'),
      (3, Icons.library_music_rounded, 'Library'),
    ];
    final navStyle = style.clamp(0, 2);
    final transparent = navStyle == 2;
    final liquid = navStyle == 1;
    final navRow = SizedBox(
      height: compact ? 48 : 54,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: (transparent || liquid)
                    ? _FoxyGlassButton(
                        blur: liquid,
                        blurSigma: liquid ? 22 : 0,
                        tintOpacity: transparent ? 0.02 : 0.24,
                        onTap: () => onSelected(items[i].$1),
                        selected: selectedIndex == items[i].$1,
                        borderRadius: BorderRadius.circular(999),
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 4 : 6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].$2,
                              color: selectedIndex == items[i].$1
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.55),
                              size: 22,
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  items[i].$3,
                                  style: TextStyle(
                                    color: selectedIndex == items[i].$1
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : Material(
                        color: selectedIndex == items[i].$1
                            ? _kNavPillFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSelected(items[i].$1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                items[i].$2,
                                color: selectedIndex == items[i].$1
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                size: 22,
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    items[i].$3,
                                    style: TextStyle(
                                      color: selectedIndex == items[i].$1
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
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
        padding: EdgeInsets.fromLTRB(10, 0, 10, compact ? 4 : 8),
        child: transparent
            ? Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: compact ? 4 : 5,
                ),
                child: navRow,
              )
            : liquid
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.04),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: compact ? 4 : 5,
                  ),
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
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onStartRecognition,
    this.onDiscoverSearch,
    this.homeBackgroundPath,
    required this.bottomContentPadding,
  });

  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onStartRecognition;
  final void Function(String query)? onDiscoverSearch;
  final String? homeBackgroundPath;
  final double bottomContentPadding;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  static const int _initialHomeSections = 2;
  static const int _warmHomeSections = 4;
  static const int _homeSectionBatchSize = 2;

  List<_SongSection> _sections = _HomeCache.sections;
  List<_SongSection> _orderedSections = const [];
  _Song? _spotlightSongCache;
  Map<String, dynamic> _homeSettings = const {};
  bool _loading = _HomeCache.sections.isEmpty;
  String? _error = _HomeCache.error;
  String _homeChip = 'All';
  int _visibleSectionCount = _initialHomeSections;
  late final ScrollController _homeScrollController;
  Timer? _homeRevealTimer;
  StreamSubscription<dynamic>? _homeEvents;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _homeScrollController = ScrollController()
      ..addListener(_maybeRevealMoreHome);
    _refreshDerivedHomeSections(_sections);
    unawaited(_loadHomeSettings());
    _homeEvents = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map?['type']?.toString() == 'appearanceChanged') {
        unawaited(_loadHomeSettings());
      }
    });
    if (_HomeCache.sections.isEmpty) {
      _loadHome();
    } else {
      _scheduleStagedHomeReveal();
    }
  }

  @override
  void dispose() {
    _homeScrollController
      ..removeListener(_maybeRevealMoreHome)
      ..dispose();
    _homeEvents?.cancel();
    _homeRevealTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHomeSettings() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    setState(() => _homeSettings = map);
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account['isSignedIn'] != widget.account['isSignedIn']) {
      unawaited(_loadHome(force: true));
    }
  }

  bool _titleHasAny(String title, List<String> patterns) {
    final t = title.toLowerCase();
    return patterns.any(t.contains);
  }

  List<_SongSection> _curatedHomeSections(List<_SongSection> sections) {
    final seenTitles = <String>{};
    final kept = sections
        .where((section) {
          final title = section.title.trim().toLowerCase();
          if (title.isEmpty || !seenTitles.add(title)) return false;
          if (_titleHasAny(title, const [
            'most replayed',
            'high quality picks',
          ])) {
            return false;
          }
          if (_homeChip == 'All' &&
              _titleHasAny(title, const ['charting now'])) {
            return false;
          }
          if (_titleHasAny(title, const ['downloaded but forgotten'])) {
            return section.songs.any((song) => song.isDownloaded);
          }
          return true;
        })
        .toList(growable: false);
    final delayedDownloads = kept
        .where(
          (section) =>
              section.title.toLowerCase().contains('downloaded but forgotten'),
        )
        .toList(growable: false);
    if (delayedDownloads.isEmpty) return kept;
    final primary = kept
        .where(
          (section) =>
              !section.title.toLowerCase().contains('downloaded but forgotten'),
        )
        .toList(growable: true);
    final insertAt = math.min(5, primary.length);
    primary.insertAll(insertAt, delayedDownloads);
    return primary;
  }

  void _refreshDerivedHomeSections(List<_SongSection> sections) {
    _orderedSections = _curatedHomeSections(
      sections
          .where((section) => !_isSuppressedHomeSection(section.title))
          .toList(growable: false),
    );
    _spotlightSongCache = _findSpotlightSong(_orderedSections);
  }

  _Song? _findSpotlightSong(List<_SongSection> sections) {
    for (final section in sections) {
      for (final song in section.songs) {
        if (song.homeArtwork.isNotEmpty || song.artwork.isNotEmpty) {
          return song;
        }
      }
    }
    return null;
  }

  void _scheduleStagedHomeReveal() {
    _homeRevealTimer?.cancel();
    if (_loading || _homeChip != 'All') return;
    final target = math.min(_warmHomeSections, _orderedSections.length);
    if (_visibleSectionCount >= target) return;
    _homeRevealTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _loading || _homeChip != 'All') return;
      setState(() {
        _visibleSectionCount = math.min(target, _visibleSectionCount + 1);
      });
      _scheduleStagedHomeReveal();
    });
  }

  Future<void> _loadHome({bool force = false}) async {
    final params = _homeFeedParamsForChip(_homeChip);
    final mood = _homeMoodQueryForChip(_homeChip);
    final cacheKey = mood == null ? _homeFeedCacheKey(params) : 'mood:$mood';
    final cachedSections = _HomeCache.sectionsByParams[cacheKey];
    if (!force && cachedSections != null) {
      setState(() {
        _sections = cachedSections;
        _refreshDerivedHomeSections(cachedSections);
        _error = _HomeCache.errorsByParams[cacheKey];
        _loading = false;
        _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
      });
      _scheduleStagedHomeReveal();
      return;
    }
    _homeRevealTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _visibleSectionCount = _initialHomeSections;
    });
    try {
      final requestArgs = params == null && mood == null
          ? null
          : <String, dynamic>{};
      if (requestArgs != null) {
        if (params != null) requestArgs['params'] = params;
        if (mood != null) requestArgs['mood'] = mood;
      }
      final response =
          _asMap(await _method.invokeMethod('homeFeed', requestArgs)) ??
          const {};
      final sections = (response['sections'] as List? ?? const [])
          .map((item) => _SongSection.fromMap(_asMap(item) ?? const {}))
          .where((section) => section.songs.isNotEmpty)
          .toList();
      _HomeCache.sectionsByParams[cacheKey] = sections;
      _HomeCache.errorsByParams.remove(cacheKey);
      _HomeCache.sections = sections;
      _HomeCache.error = null;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _refreshDerivedHomeSections(sections);
        _loading = false;
        _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
      });
      _scheduleStagedHomeReveal();
    } catch (e) {
      _HomeCache.errorsByParams[cacheKey] = e.toString();
      _HomeCache.error = e.toString();
      if (!mounted) return;
      setState(() {
        _error = _HomeCache.error;
        _loading = false;
      });
    }
  }

  void _onHomeChip(String label) {
    _homeRevealTimer?.cancel();
    setState(() => _homeChip = label);
    unawaited(_loadHome());
  }

  void resetToDefault() {
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (_homeChip != 'All') {
      setState(() => _homeChip = 'All');
      unawaited(_loadHome());
      return;
    }
    setState(() {
      _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
    });
  }

  bool consumeAndroidBack() {
    if (_homeChip == 'All') return false;
    resetToDefault();
    return true;
  }

  int _initialVisibleCount(int total) {
    if (_homeChip != 'All') return total;
    return math.min(_initialHomeSections, total);
  }

  void _maybeRevealMoreHome() {
    if (!_homeScrollController.hasClients || _loading || _homeChip != 'All') {
      return;
    }
    final position = _homeScrollController.position;
    if (position.extentAfter > 420) return;
    if (_visibleSectionCount >= _orderedSections.length) return;
    setState(() {
      _visibleSectionCount = math.min(
        _orderedSections.length,
        _visibleSectionCount + _homeSectionBatchSize,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    super.build(context);
    final feedSections = _orderedSections;
    final categoryFeedSections = _homeChip == 'All' || _homeChip == 'Charts'
        ? feedSections
        : feedSections
              .where((section) {
                final title = section.title.toLowerCase();
                return !title.contains('chart') && !title.contains('trending');
              })
              .toList(growable: false);
    final visibleSections = _homeChip == 'All'
        ? feedSections.take(_visibleSectionCount).toList()
        : categoryFeedSections;
    final spotlightSong = _homeChip == 'All' ? _spotlightSongCache : null;
    final quickPicksDisplayMode =
        ((_homeSettings['quickPicksDisplayMode'] ?? 0) as num).toInt();
    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF151515),
      onRefresh: () async {
        setState(() => _homeChip = 'All');
        await _loadHome(force: true);
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 480,
        slivers: [
          SliverToBoxAdapter(
            child: _HomeTopBar(
              account: widget.account,
              onOpenSettings: widget.onOpenSettings,
              onOpenDiscover: widget.onOpenDiscover,
              onOpenLibrary: widget.onOpenLibrary,
              onStartRecognition: widget.onStartRecognition,
            ),
          ),
          if (_loading && _sections.isEmpty)
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
          else if (_homeChip == 'All' && feedSections.isEmpty)
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
            SliverToBoxAdapter(
              child: _HomeQuickActionChips(
                onOpenRadio: () => _onHomeChip('Radio'),
                onOpenMoods: () => _onHomeChip('Moods'),
                onOpenGenres: () => _onHomeChip('Genres'),
                onOpenCharts: () => _onHomeChip('Charts'),
                onOpenCategories: () => _onHomeChip('Categories'),
                onOpenDownloads: () => _onHomeChip('Downloads'),
                onOpenHistory: () => _onHomeChip('History'),
              ),
            ),
            if (spotlightSong != null)
              SliverToBoxAdapter(
                child: _HomeShelfShell(
                  child: _HomeSpotlight(
                    song: spotlightSong,
                    sectionTitle: 'Foxy Pick',
                    onPlay: () => widget.onPlay(
                      spotlightSong,
                      feedSections.expand((s) => s.songs).take(36).toList(),
                    ),
                    onRadio: () => widget.onPlay(
                      spotlightSong,
                      feedSections.expand((s) => s.songs).take(36).toList(),
                      radioTail: true,
                    ),
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: visibleSections.length,
              itemBuilder: (context, index) {
                final sec = visibleSections[index];
                return _HomeShelfShell(
                  child: _HomeFeedSection(
                    section: sec,
                    layout: _homeSectionLayout(sec),
                    currentVideoId: widget.currentVideoId,
                    onPlay: widget.onPlay,
                    onDiscoverSearch: widget.onDiscoverSearch,
                    quickPicksDisplayMode: quickPicksDisplayMode,
                  ),
                );
              },
            ),
            if (_visibleSectionCount < feedSections.length)
              const SliverToBoxAdapter(
                child: _HomeShelfShell(child: _HomeFeedLoadingMore()),
              ),
          ] else ...[
            SliverToBoxAdapter(
              child: _HomeCategoryHeader(
                title: _homeChip,
                onBack: resetToDefault,
              ),
            ),
            SliverList.builder(
              itemCount: categoryFeedSections.length,
              itemBuilder: (context, index) {
                final sec = categoryFeedSections[index];
                return _HomeShelfShell(
                  child: _HomeFeedSection(
                    section: sec,
                    layout: _homeSectionLayout(sec),
                    currentVideoId: widget.currentVideoId,
                    onPlay: widget.onPlay,
                    onDiscoverSearch: widget.onDiscoverSearch,
                    quickPicksDisplayMode: quickPicksDisplayMode,
                  ),
                );
              },
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                _kHomeShelfGap,
                16,
                widget.bottomContentPadding,
              ),
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
  static final Map<String, List<_SongSection>> sectionsByParams = {};
  static final Map<String, String?> errorsByParams = {};
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.account,
    required this.onOpenSettings,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onStartRecognition,
  });

  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onStartRecognition;

  @override
  Widget build(BuildContext context) {
    final avatar = account['avatarUrl']?.toString() ?? '';
    final name =
        account['displayName']?.toString().ifBlank('Foxy listener') ??
        'Foxy listener';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _kAppVersionLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _GlassIconButton(
                  tooltip: 'Discover',
                  icon: Icons.explore_rounded,
                  onPressed: onOpenDiscover,
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Recognize song',
                  icon: Icons.mic_rounded,
                  onPressed: onStartRecognition,
                ),
                const SizedBox(width: 6),
                if (account['isSignedIn'] == true) ...[
                  _FoxyGlassButton(
                    onTap: onOpenSettings,
                    borderRadius: BorderRadius.circular(999),
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: ClipOval(
                        child: _AccountAvatar(
                          name: name,
                          imageUrl: avatar,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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
                fontSize: 15,
                fontWeight: FontWeight.w600,
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

class _HomeQuickActionChips extends StatelessWidget {
  const _HomeQuickActionChips({
    required this.onOpenRadio,
    required this.onOpenMoods,
    required this.onOpenGenres,
    required this.onOpenCharts,
    required this.onOpenCategories,
    required this.onOpenDownloads,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenRadio;
  final VoidCallback onOpenMoods;
  final VoidCallback onOpenGenres;
  final VoidCallback onOpenCharts;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final chips = <({String label, IconData icon, VoidCallback onTap})>[
      (label: 'Moods', icon: Icons.auto_awesome_rounded, onTap: onOpenMoods),
      (label: 'Genres', icon: Icons.category_rounded, onTap: onOpenGenres),
      (
        label: 'Categories',
        icon: Icons.grid_view_rounded,
        onTap: onOpenCategories,
      ),
      (label: 'Charts', icon: Icons.show_chart_rounded, onTap: onOpenCharts),
      (
        label: 'Downloads',
        icon: Icons.download_rounded,
        onTap: onOpenDownloads,
      ),
      (label: 'Radio', icon: Icons.radio_rounded, onTap: onOpenRadio),
      (label: 'History', icon: Icons.history_rounded, onTap: onOpenHistory),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final chip = chips[index];
            return _FoxyGlassButton(
              onTap: chip.onTap,
              borderRadius: BorderRadius.circular(999),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    chip.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeCategoryHeader extends StatelessWidget {
  const _HomeCategoryHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _FoxyGlassButton(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            padding: EdgeInsets.zero,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _homeGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Up late Zzz..';
  if (h < 12) return 'Good morning...';
  if (h < 17) return 'Good afternoon...';
  if (h < 22) return 'Good evening...';
  return 'Wind down...';
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
    final leadingWidget = leading;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ...?(leadingWidget == null ? null : [leadingWidget]),
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

class _FoxySongTile extends StatelessWidget {
  const _FoxySongTile({
    required this.song,
    required this.onTap,
    this.onMore,
    this.active = false,
    this.index,
    this.thumbRadius = 6,
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool active;
  final int? index;
  final double thumbRadius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget trailing;
    if (onMore != null) {
      trailing = IconButton(
        tooltip: 'More',
        onPressed: onMore,
        icon: const Icon(Icons.more_vert_rounded),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: onTap,
        icon: Icon(
          Icons.play_circle_fill_rounded,
          color: active ? accent : Colors.white,
        ),
      );
    }

    return _FoxySurface(
      selected: active,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Row(
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

/// Foxy-style full-screen results with Songs / Videos / Albums / Artists tabs.
class _SearchResultsPage extends StatefulWidget {
  const _SearchResultsPage({required this.query, required this.onPlay});

  final String query;
  final _FoxyOnPlay onPlay;

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
    _tabs = TabController(length: 5, vsync: this);
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
      final response =
          _asMap(
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
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  void _openArtistResult(_Song artist) {
    final artistName = artist.title.ifBlank(artist.artist);
    if (artistName.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artistName,
          artworkUrl: artist.highQualityArtwork,
          onPlay: widget.onPlay,
        ),
      ),
    );
  }

  Widget _groupedAllBody() {
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
    final topAlbums = _albums.take(4).toList();
    final topArtists = _artists.take(6).toList();
    if (topAlbums.isEmpty && topArtists.isEmpty && _songs.isEmpty) {
      return const _EmptyTabBody(
        icon: Icons.search_off_rounded,
        title: 'Nothing here',
        subtitle: 'Try another spelling or category.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        if (topAlbums.isNotEmpty) ...[
          _SearchSectionLabel('Albums'),
          const SizedBox(height: 4),
          for (final album in topAlbums)
            _FoxySearchResultRow(
              song: album,
              kind: _SearchRowKind.album,
              onTap: () => widget.onPlay(album, _albums, radioTail: false),
              onMore: () => _openMenu(album, _albums),
            ),
          const SizedBox(height: 10),
        ],
        if (topArtists.isNotEmpty) ...[
          _SearchSectionLabel('Artists'),
          const SizedBox(height: 4),
          for (final artist in topArtists)
            _FoxySearchResultRow(
              song: artist,
              kind: _SearchRowKind.artist,
              onTap: () => _openArtistResult(artist),
              onMore: () {},
            ),
          const SizedBox(height: 10),
        ],
        if (_songs.isNotEmpty) ...[
          _SearchSectionLabel('Songs'),
          const SizedBox(height: 4),
          for (final song in _songs)
            _FoxySearchResultRow(
              song: song,
              kind: _SearchRowKind.song,
              onTap: () => widget.onPlay(song, _songs, radioTail: true),
              onMore: () => _openMenu(song, _songs),
            ),
        ],
      ],
    );
  }

  Widget _tabBody(
    List<_Song> items, {
    _SearchRowKind kind = _SearchRowKind.song,
    bool radioTail = true,
  }) {
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final song = items[index];
        return _FoxySearchResultRow(
          song: song,
          kind: kind,
          onTap: kind == _SearchRowKind.artist
              ? () => _openArtistResult(song)
              : () => widget.onPlay(song, items, radioTail: radioTail),
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
      body: Column(
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
            color: Colors.black,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: [
                Tab(text: 'All'),
                Tab(text: 'Songs (${_loading ? '...' : _songs.length})'),
                Tab(text: 'Videos (${_loading ? '...' : _videos.length})'),
                Tab(text: 'Albums (${_loading ? '...' : _albums.length})'),
                Tab(text: 'Artists (${_loading ? '...' : _artists.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _groupedAllBody(),
                _tabBody(_songs, kind: _SearchRowKind.song, radioTail: true),
                _tabBody(_videos, kind: _SearchRowKind.video, radioTail: false),
                _tabBody(_albums, kind: _SearchRowKind.album, radioTail: false),
                _tabBody(
                  _artists,
                  kind: _SearchRowKind.artist,
                  radioTail: false,
                ),
              ],
            ),
          ),
        ],
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

  final _FoxyOnPlay onPlay;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  static const int _historyLimit = 8;
  static const int _cacheLimit = 18;
  static final List<String> _history = <String>[];
  static final Map<String, _SearchResultSnapshot> _resultCache =
      <String, _SearchResultSnapshot>{};

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
  int _searchEpoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSearchHistory());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    try {
      final values =
          (await _method.invokeMethod('searchHistory') as List? ?? const [])
              .map((item) => item.toString().trim())
              .where((item) => item.length >= 2)
              .toList();
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(values.take(_historyLimit));
      });
    } catch (_) {}
  }

  void applyExternalQuery(String raw) {
    final q = raw.trim();
    setState(() {
      _query = q;
      _controller.text = q;
      _error = null;
    });
    if (q.length >= 2) {
      _rememberQuery(q);
      unawaited(_runSearch(q));
    }
  }

  void resetToLanding() {
    _debounce?.cancel();
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
  }

  bool consumeAndroidBack() {
    if (_controller.text.trim().isEmpty &&
        _query.trim().isEmpty &&
        _error == null &&
        !_hasResults) {
      return false;
    }
    resetToLanding();
    return true;
  }

  bool get _hasResults =>
      _songs.isNotEmpty ||
      _videos.isNotEmpty ||
      _albums.isNotEmpty ||
      _artists.isNotEmpty;

  List<({String header, List<({_Song song, _SearchRowKind kind})> rows})>
  get _allGroups {
    final groups =
        <({String header, List<({_Song song, _SearchRowKind kind})> rows})>[];
    final topAlbums = _albums
        .take(4)
        .map((song) => (song: song, kind: _SearchRowKind.album))
        .toList();
    if (topAlbums.isNotEmpty) {
      groups.add((header: 'Albums', rows: topAlbums));
    }
    final artists = _artists
        .take(6)
        .map((song) => (song: song, kind: _SearchRowKind.artist))
        .toList();
    if (artists.isNotEmpty) {
      groups.add((header: 'Artists', rows: artists));
    }
    final songs = _songs
        .map((song) => (song: song, kind: _SearchRowKind.song))
        .toList();
    if (songs.isNotEmpty) {
      groups.add((header: 'Songs', rows: songs));
    }
    if (groups.isEmpty && _videos.isNotEmpty) {
      groups.add((
        header: 'Videos',
        rows: _videos
            .map((song) => (song: song, kind: _SearchRowKind.video))
            .toList(),
      ));
    }
    return groups;
  }

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
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(q));
    });
  }

  void _rememberQuery(String raw) {
    final query = raw.trim();
    if (query.length < 2) return;
    _history.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
    _history.insert(0, query);
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
    }
    unawaited(_method.invokeMethod('addSearchHistory', {'query': query}));
  }

  void _clearSearchHistory() {
    setState(_history.clear);
    unawaited(_method.invokeMethod('clearSearchHistory'));
  }

  void _cacheSearchResult(String key, _SearchResultSnapshot snapshot) {
    _resultCache.remove(key);
    _resultCache[key] = snapshot;
    while (_resultCache.length > _cacheLimit) {
      _resultCache.remove(_resultCache.keys.first);
    }
  }

  void _removeSearchHistoryItem(String item) {
    setState(() {
      _history.remove(item);
    });
    unawaited(_method.invokeMethod('removeSearchHistory', {'query': item}));
  }

  void _openArtistPage(_Song artist) {
    final artistName = artist.title.ifBlank(artist.artist);
    if (artistName.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artistName,
          artworkUrl: '',
          onPlay: widget.onPlay,
          onDiscoverSearch: widget.onDiscoverSearch,
        ),
      ),
    );
  }

  void _activateSearchQuery(String raw) {
    final query = raw.trim();
    if (query.length < 2) return;
    _debounce?.cancel();
    _rememberQuery(query);
    setState(() {
      _query = query;
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
      _filter = 'All';
      _error = null;
    });
    unawaited(_runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final normalizedQuery = query.trim();
    final cacheKey = normalizedQuery.toLowerCase();
    final cached = _resultCache[cacheKey];
    final epoch = ++_searchEpoch;
    if (cached != null) {
      setState(() {
        _songs = cached.songs;
        _videos = cached.videos;
        _albums = cached.albums;
        _artists = cached.artists;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_looksLikeSpotifyTrackUrl(normalizedQuery)) {
        final raw = _asMap(
          await _method.invokeMethod('resolveSpotifyTrack', {
            'spotifyUrl': _normalizeSpotifyTrackUrl(normalizedQuery),
          }),
        );
        if (!mounted ||
            _query.trim() != normalizedQuery ||
            epoch != _searchEpoch) {
          return;
        }
        final songMap = _asMap(raw?['song']);
        final song = songMap == null ? null : _Song.fromMap(songMap);
        final songs = song == null || song.videoId.isEmpty
            ? const <_Song>[]
            : [song];
        _cacheSearchResult(
          cacheKey,
          _SearchResultSnapshot(
            songs: songs,
            videos: const [],
            albums: const [],
            artists: const [],
          ),
        );
        setState(() {
          _songs = songs;
          _videos = const [];
          _albums = const [];
          _artists = const [];
          _loading = false;
          _error = song == null || song.videoId.isEmpty
              ? 'No playable match found for that Spotify link'
              : null;
        });
        return;
      }
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': normalizedQuery,
              'limit': 18,
            }),
          ) ??
          const {};
      if (!mounted ||
          _query.trim() != normalizedQuery ||
          epoch != _searchEpoch) {
        return;
      }
      List<_Song> parseList(String key) => (response[key] as List? ?? const [])
          .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
          .where((s) => s.videoId.isNotEmpty)
          .toList();
      final songs = parseList('songs');
      final videos = parseList('videos');
      final albums = parseList('albums');
      final artists = parseList('artists');
      _cacheSearchResult(
        cacheKey,
        _SearchResultSnapshot(
          songs: songs,
          videos: videos,
          albums: albums,
          artists: artists,
        ),
      );
      setState(() {
        _songs = songs;
        _videos = videos;
        _albums = albums;
        _artists = artists;
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

  bool _looksLikeSpotifyTrackUrl(String value) {
    final q = value.trim().toLowerCase();
    return q.contains('open.spotify.com/track/') ||
        q.contains('spotify:track:');
  }

  String _normalizeSpotifyTrackUrl(String value) {
    final q = value.trim();
    if (!q.toLowerCase().startsWith('spotify:track:')) return q;
    final id = q.split(':').last.trim();
    return id.isEmpty ? q : 'https://open.spotify.com/track/$id';
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.length < 2) return;
    _activateSearchQuery(query);
  }

  List<({_Song song, _SearchRowKind kind})> get _visibleRows {
    switch (_filter) {
      case 'Songs':
        return _songs.map((s) => (song: s, kind: _SearchRowKind.song)).toList();
      case 'Videos':
        return _videos
            .map((s) => (song: s, kind: _SearchRowKind.video))
            .toList();
      case 'Albums':
        return _albums
            .map((s) => (song: s, kind: _SearchRowKind.album))
            .toList();
      case 'Artists':
        return _artists
            .map((s) => (song: s, kind: _SearchRowKind.artist))
            .toList();
      default:
        return _allGroups.expand((group) => group.rows).toList();
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
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

    final rows = _visibleRows;
    final history = List<String>.unmodifiable(_history);
    final showResults = _query.trim().length >= 2;
    return CustomScrollView(
      key: const PageStorageKey('search-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 180,
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
                    if (history.isNotEmpty) ...[
                      Row(
                        children: [
                          const Expanded(child: _SearchSectionLabel('Recent')),
                          _FoxyGlassTextButton(
                            label: 'Clear',
                            onPressed: _clearSearchHistory,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final item in history)
                        _SearchHistoryRow(
                          query: item,
                          onTap: () => _activateSearchQuery(item),
                          onRemove: () => _removeSearchHistoryItem(item),
                        ),
                      const SizedBox(height: 12),
                    ] else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 26, 8, 8),
                        child: Text(
                          'Search something and it will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.44),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                'No results for "${_cleanDisplayText(_query)}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else if (showResults && _filter == 'All')
          SliverList(
            delegate: SliverChildListDelegate.fixed([
              for (final group in _allGroups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: _SearchSectionLabel(group.header),
                ),
                for (final row in group.rows)
                  _FoxySearchResultRow(
                    song: row.song,
                    kind: row.kind,
                    onTap: row.kind == _SearchRowKind.artist
                        ? () => _openArtistPage(row.song)
                        : () => widget.onPlay(
                            row.song,
                            row.kind == _SearchRowKind.album
                                ? (_albums.isEmpty ? [row.song] : _albums)
                                : (_songs.isEmpty ? [row.song] : _songs),
                            radioTail: row.kind == _SearchRowKind.song,
                          ),
                    onMore: () => _openMenu(
                      row.song,
                      row.kind == _SearchRowKind.album
                          ? (_albums.isEmpty ? [row.song] : _albums)
                          : (_songs.isEmpty ? [row.song] : _songs),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ]),
          )
        else if (showResults)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final row = rows[index];
              final song = row.song;
              final queue = switch (row.kind) {
                _SearchRowKind.artist => _artists,
                _SearchRowKind.album => _albums,
                _SearchRowKind.video => _videos,
                _SearchRowKind.song => _songs,
              };
              return _FoxySearchResultRow(
                song: song,
                kind: row.kind,
                onTap: row.kind == _SearchRowKind.artist
                    ? () => _openArtistPage(song)
                    : () => widget.onPlay(
                        song,
                        queue.isEmpty ? [song] : queue,
                        radioTail: row.kind == _SearchRowKind.song,
                      ),
                onMore: () => _openMenu(song, queue.isEmpty ? [song] : queue),
              );
            }, childCount: rows.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _SearchResultSnapshot {
  const _SearchResultSnapshot({
    required this.songs,
    required this.videos,
    required this.albums,
    required this.artists,
  });

  final List<_Song> songs;
  final List<_Song> videos;
  final List<_Song> albums;
  final List<_Song> artists;
}

enum _SearchRowKind { song, video, album, artist }

class _SearchSectionLabel extends StatelessWidget {
  const _SearchSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.46),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _SearchHistoryRow extends StatelessWidget {
  const _SearchHistoryRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        blurSigma: 10,
        tintOpacity: 0.18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.58),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _FoxyGlassButton(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              padding: EdgeInsets.zero,
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white60,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoxySearchResultRow extends StatelessWidget {
  const _FoxySearchResultRow({
    required this.song,
    required this.kind,
    required this.onTap,
    required this.onMore,
  });

  final _Song song;
  final _SearchRowKind kind;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isArtist = kind == _SearchRowKind.artist;
    final thumbSize = 54.0;
    final secondary = switch (kind) {
      _SearchRowKind.artist => song.artist.ifBlank('Artist'),
      _SearchRowKind.album => song.artist.ifBlank('Album'),
      _SearchRowKind.video => '${song.artist} - Video',
      _SearchRowKind.song => song.artist,
    };
    final meta = switch (kind) {
      _SearchRowKind.album => 'Album',
      _SearchRowKind.video => song.duration?.trim().ifBlank('Video') ?? 'Video',
      _SearchRowKind.song => song.duration?.trim() ?? '',
      _SearchRowKind.artist => '',
    };
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.white.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArtist ? song.title.ifBlank(song.artist) : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.52),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isArtist ? onTap : onMore,
                  icon: Icon(
                    isArtist
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.more_vert_rounded,
                    size: isArtist ? 18 : 24,
                    color: Colors.white.withValues(alpha: 0.82),
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

class _ArtistPage extends StatefulWidget {
  const _ArtistPage({
    required this.artist,
    required this.onPlay,
    this.artworkUrl = '',
    this.onDiscoverSearch,
  });

  final String artist;
  final String artworkUrl;
  final _FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<_ArtistPage> {
  bool _loading = true;
  String? _error;
  String _artworkUrl = '';
  String _sourceLabel = '';
  List<_Song> _songs = const [];
  List<_Song> _albums = const [];

  @override
  void initState() {
    super.initState();
    _artworkUrl = widget.artworkUrl;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('resolveArtistProfile', {
              'artist': widget.artist,
              'limit': 28,
            }),
          ) ??
          const {};
      List<_Song> parse(String key) => (response[key] as List? ?? const [])
          .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
          .where((song) => song.videoId.isNotEmpty)
          .toList();
      if (!mounted) return;
      final artistArt = response['artworkUrl']?.toString().trim() ?? '';
      final sourceLabel = response['sourceLabel']?.toString().trim() ?? '';
      setState(() {
        _songs = parse('songs');
        _albums = parse('albums');
        _artworkUrl = artistArt.ifBlank(_artworkUrl);
        _sourceLabel = sourceLabel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _playArtistRadio() {
    final queue = _songs.isNotEmpty ? _songs : _albums;
    if (queue.isEmpty) {
      widget.onDiscoverSearch?.call('${widget.artist} songs');
      return;
    }
    widget.onPlay(queue.first, queue, radioTail: true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 300,
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(
                    url: _artworkUrl,
                    size: 720,
                    radius: 0,
                    highQuality: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artist',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_sourceLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _sourceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _FoxyGlassButton(
                      onTap: _playArtistRadio,
                      borderRadius: BorderRadius.circular(18),
                      blurSigma: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: accent,
                            size: 26,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Play artist radio',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FoxyGlassButton(
                    onTap: () => widget.onDiscoverSearch?.call(widget.artist),
                    borderRadius: BorderRadius.circular(18),
                    padding: EdgeInsets.zero,
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
            )
          else ...[
            _ArtistSongsSliver(
              title: 'Popular',
              songs: _songs.take(10).toList(),
              kind: _SearchRowKind.song,
              onPlay: widget.onPlay,
            ),
            _ArtistSongsSliver(
              title: 'Albums',
              songs: _albums.take(8).toList(),
              kind: _SearchRowKind.album,
              onPlay: widget.onPlay,
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}

class _ArtistSongsSliver extends StatelessWidget {
  const _ArtistSongsSliver({
    required this.title,
    required this.songs,
    required this.kind,
    required this.onPlay,
  });

  final String title;
  final List<_Song> songs;
  final _SearchRowKind kind;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: _SearchSectionLabel(title),
            ),
            for (final song in songs)
              _FoxySearchResultRow(
                song: song,
                kind: kind,
                onTap: () =>
                    onPlay(song, songs, radioTail: kind == _SearchRowKind.song),
                onMore: () => _showFoxySongOverflowMenu(
                  context,
                  song: song,
                  onPlay: onPlay,
                  queueForPlay: songs,
                  searchResultsForExtras: songs,
                  onLibraryChanged: () async {},
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
  });

  final int songCount;
  final int activeCount;

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
      final raw =
          _asMap(await _method.invokeMethod('storageStats')) ?? const {};
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
                  Icon(Icons.cloud_done_rounded, color: accent, size: 28),
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
                              ? 'Calculating storage...'
                              : '${widget.songCount} songs offline - ${_formatStorageBytes(bytes)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

class _DownloadsPlaylistHeader extends StatefulWidget {
  const _DownloadsPlaylistHeader({
    required this.songs,
    required this.songCount,
    required this.activeCount,
    this.onPlayAll,
  });

  final List<_Song> songs;
  final int songCount;
  final int activeCount;
  final VoidCallback? onPlayAll;

  @override
  State<_DownloadsPlaylistHeader> createState() =>
      _DownloadsPlaylistHeaderState();
}

class _DownloadsPlaylistHeaderState extends State<_DownloadsPlaylistHeader> {
  Map<String, dynamic> _storage = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw =
          _asMap(await _method.invokeMethod('storageStats')) ?? const {};
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
    final covers = widget.songs
        .where((song) => song.artwork.isNotEmpty)
        .take(4)
        .toList();
    final subtitle = _loading
        ? 'Calculating storage...'
        : '${widget.songCount} songs offline | ${_formatStorageBytes(bytes)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 1.9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (covers.isEmpty)
                ColoredBox(color: accent.withValues(alpha: 0.24))
              else
                _DownloadsCollage(covers: covers),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.28),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Downloads',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.activeCount > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${widget.activeCount} active download${widget.activeCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: accent.withValues(alpha: 0.98),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.onPlayAll != null)
                      _FoxyGlassButton(
                        onTap: widget.onPlayAll,
                        borderRadius: BorderRadius.circular(999),
                        tintOpacity: 0.34,
                        blur: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Play all',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
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

class _DownloadsCollage extends StatelessWidget {
  const _DownloadsCollage({required this.covers});

  final List<_Song> covers;

  @override
  Widget build(BuildContext context) {
    if (covers.length == 1) {
      final song = covers.first;
      return _Artwork(
        url: song.highQualityArtwork,
        size: 800,
        radius: 0,
        highQuality: true,
        identityTag: song.videoId,
        offlineArtworkPath: song.offlineArtworkPath,
        useOfflineArtwork: song.isDownloaded,
      );
    }
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      ),
      itemCount: math.max(4, covers.length),
      itemBuilder: (context, index) {
        final song = covers[index % covers.length];
        return _Artwork(
          url: song.highQualityArtwork,
          size: 400,
          radius: 0,
          highQuality: true,
          identityTag: song.videoId,
          offlineArtworkPath: song.offlineArtworkPath,
          useOfflineArtwork: song.isDownloaded,
        );
      },
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

  final _FoxyOnPlay onPlay;
  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({
    required this.onOpenSearch,
    required this.onDiscoverSearch,
  });

  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
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

  @override
  Widget build(BuildContext context) {
    void pick(String q) => onDiscoverSearch(q);
    return CustomScrollView(
      key: const PageStorageKey('discover-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 420,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            title: 'Discover',
            subtitle: 'Quick routes into fresh music, moods, and charts',
            onSearch: onOpenSearch,
            onSparkle: () => pick('top songs charts today'),
          ),
        ),
        SliverToBoxAdapter(child: _sectionTitle('PICKS FOR YOU')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
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
                        title: 'Discover',
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
                        title: 'Energy',
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
                  subtitle: 'Hidden gems & live sessions',
                  onTap: () => pick('deep cuts live sessions'),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin {
  static const int _scopeHub = 0;
  static const int _scopeLiked = 1;
  static const int _scopeHistory = 2;
  static const int _scopeDownloads = 3;
  static const int _scopeMostPlayed = 4;
  static const int _scopePlaylists = 5;
  static const int _scopeRecognized = 6;
  static const int _scopeLocal = 7;
  static int _lastScope = _scopeHub;

  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _downloads = const [];
  List<_Song> _local = const [];
  List<_Song> _mostPlayed = const [];
  List<_Song> _recentlyAdded = const [];
  List<_UserPlaylist> _userPlaylists = const [];
  List<_RecognizedTrack> _recognized = const [];
  Map<String, dynamic> _settings = const {};
  int _scope = _lastScope;
  final Map<String, double> _downloadProgress = {};
  StreamSubscription<dynamic>? _libraryEvents;
  Timer? _downloadsAutoRefreshTimer;

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
        _SongMenuContextCache.invalidate();
        _load();
      }
    });
    _downloadsAutoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (
      _,
    ) {
      if (!mounted) return;
      if (_scope == _scopeDownloads || _downloadProgress.isNotEmpty) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _libraryEvents?.cancel();
    _downloadsAutoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('libraryFeed'),
      _method.invokeMethod('getAppearance'),
    ]);
    final response = _asMap(values[0]) ?? const {};
    final settings = _asMap(values[1]) ?? const {};
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _liked = _songsFrom(response['liked']);
      _history = _songsFrom(response['history']);
      _downloads = _songsFrom(response['downloads']);
      _local = _songsFrom(response['local']);
      _mostPlayed = _songsFrom(response['mostPlayed']);
      _recentlyAdded = _songsFrom(response['recentlyAdded']).take(20).toList();
      _userPlaylists = _userPlaylistsFrom(response['userPlaylists']);
      _recognized = _recognizedTracksFrom(response['recognitionHistory']);
      _loading = false;
      if (!_libraryScopeVisible(_scope)) {
        _scope = _scopeHub;
        _lastScope = _scopeHub;
      }
    });
  }

  bool get _hub => _scope == _scopeHub;

  bool _settingBool(String key, [bool fallback = true]) =>
      _settings[key] == null ? fallback : _settings[key] == true;

  List<_Song> get _activeSongs {
    switch (_scope) {
      case _scopeLiked:
        return _liked;
      case _scopeHistory:
        return _history;
      case _scopeDownloads:
        return _downloads;
      case _scopeLocal:
        return _local;
      case _scopeMostPlayed:
        return _mostPlayed;
      case _scopePlaylists:
        return const [];
      case _scopeRecognized:
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
      case _scopeLocal:
        return 'Local library';
      case _scopeMostPlayed:
        return 'Most played';
      case _scopePlaylists:
        return 'Your playlists';
      case _scopeRecognized:
        return 'Recognized';
      default:
        return 'Recently added';
    }
  }

  void _setScope(int scope) {
    final next = scope.clamp(_scopeHub, _scopeLocal).toInt();
    if (!_libraryScopeVisible(next)) {
      _lastScope = _scopeHub;
      setState(() => _scope = _scopeHub);
      return;
    }
    _lastScope = next;
    setState(() => _scope = next);
  }

  bool _libraryScopeVisible(int scope) {
    return switch (scope) {
      _scopeLiked => _settingBool('showLikedInLibrary'),
      _scopeHistory => _settingBool('showHistoryInLibrary'),
      _scopeDownloads => _settingBool('showDownloadsInLibrary'),
      _scopeMostPlayed => _settingBool('showMostPlayedInLibrary'),
      _scopePlaylists => _settingBool('showPlaylistsInLibrary'),
      _scopeRecognized => _settingBool('showRecognizedInLibrary'),
      _scopeLocal => _settingBool('showLocalInLibrary'),
      _ => true,
    };
  }

  void _goHub() => _setScope(_scopeHub);

  /// Used from Home to jump into Library drill-ins.
  void openAtScope(int scope) {
    if (!mounted) return;
    _setScope(scope);
  }

  /// System back: leave a library drill-in (Liked, History, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦) before tabs handle back.
  bool consumeAndroidBack() {
    if (_hub) return false;
    _goHub();
    return true;
  }

  Future<void> _importLocalAudio({required bool folder}) async {
    try {
      final response = _asMap(
        await _method.invokeMethod(
          folder ? 'importLocalFolder' : 'importLocalAudio',
        ),
      );
      if (!mounted) return;
      final cancelled = response?['cancelled'] == true;
      if (cancelled) return;
      final imported = ((response?['imported'] ?? 0) as num).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Imported $imported local songs'
                : 'No new supported audio found',
          ),
        ),
      );
      await _load();
      if (mounted) setState(() => _scope = _scopeLocal);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  void _openSongOverflow(BuildContext context, _Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
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
    await _playFetchedUserPlaylist(snackContext, p, widget.onPlay);
  }

  void _shuffleCurrent() {
    final s = _activeSongs;
    if (s.isEmpty) return;
    final list = List<_Song>.from(s)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  Future<void> _playRecognizedTrack(
    BuildContext context,
    _RecognizedTrack item,
  ) async {
    try {
      final raw = _asMap(
        await _method.invokeMethod('resolveRecognizedTrack', {
          'title': item.title,
          'artist': item.artist,
          'youtubeVideoId': item.youtubeVideoId,
          'spotifyUrl': item.spotifyUrl,
        }),
      );
      final songMap = _asMap(raw?['song']);
      if (songMap == null) throw Exception('No playable match found');
      final song = _Song.fromMap(songMap);
      widget.onPlay(song, [song]);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve ${item.title} right now')),
      );
    }
  }

  Future<void> _clearRecognitionHistory(BuildContext context) async {
    await _method.invokeMethod('clearRecognitionHistory');
    if (!context.mounted) return;
    setState(() => _recognized = const []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recognition history cleared')),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty || !mounted) return;
      await _method.invokeMethod('playlistCreate', {'name': name});
      await _load();
    } finally {
      controller.dispose();
    }
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
    final collectionTiles = <Widget>[
      if (_libraryScopeVisible(_scopeLiked))
        _LibraryRichTile(
          color: const Color(0xFFF48FB1),
          icon: Icons.favorite_rounded,
          title: 'Liked',
          subtitle: '${_liked.length} songs',
          onTap: () => _setScope(_scopeLiked),
        ),
      if (_libraryScopeVisible(_scopeDownloads))
        _LibraryRichTile(
          color: const Color(0xFF64B5F6),
          icon: Icons.download_rounded,
          title: 'Downloads',
          subtitle: '${_downloads.length} offline',
          onTap: () => _setScope(_scopeDownloads),
        ),
      if (_libraryScopeVisible(_scopeHistory))
        _LibraryRichTile(
          color: const Color(0xFFFFB74D),
          icon: Icons.history_rounded,
          title: 'History',
          subtitle: '${_history.length} played',
          onTap: () => _setScope(_scopeHistory),
        ),
      if (_libraryScopeVisible(_scopeMostPlayed))
        _LibraryRichTile(
          color: const Color(0xFF81C784),
          icon: Icons.trending_up_rounded,
          title: 'Most played',
          subtitle: '${_mostPlayed.length} tracks',
          onTap: () => _setScope(_scopeMostPlayed),
        ),
      if (_libraryScopeVisible(_scopeLocal))
        _LibraryRichTile(
          color: const Color(0xFF90CAF9),
          icon: Icons.library_music_rounded,
          title: 'Local library',
          subtitle: _local.isEmpty
              ? 'Device songs'
              : '${_local.length} local songs',
          onTap: () => _setScope(_scopeLocal),
        ),
      if (_libraryScopeVisible(_scopePlaylists))
        _LibraryRichTile(
          color: const Color(0xFFA5D6A7),
          icon: Icons.playlist_play_rounded,
          title: 'Playlists',
          subtitle: '${_userPlaylists.length} saved mixes',
          onTap: () => _setScope(_scopePlaylists),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _librarySectionTitle('YOUR COLLECTION'),
          if (collectionTiles.isEmpty)
            Text(
              'Enable collection shortcuts in Settings.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: collectionTiles.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.75,
              ),
              itemBuilder: (_, index) => collectionTiles[index],
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
      (Icons.library_music_rounded, 'Library', _scopeHub),
      (Icons.favorite_rounded, 'Liked', _scopeLiked),
      (Icons.history_rounded, 'History', _scopeHistory),
      (Icons.download_rounded, 'Downloads', _scopeDownloads),
      (Icons.trending_up_rounded, 'Most played', _scopeMostPlayed),
      (Icons.playlist_play_rounded, 'Playlists', _scopePlaylists),
      (Icons.library_music_rounded, 'Local', _scopeLocal),
      (Icons.music_note_rounded, 'Recognized', _scopeRecognized),
    ].where((item) => _libraryScopeVisible(item.$3)).toList(growable: false);

    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 400,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            leading: !_hub
                ? _GlassIconButton(
                    tooltip: 'Back to Library',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _goHub,
                  )
                : null,
            title: 'Library',
            subtitle: _hub
                ? '${_liked.length} liked - ${_downloads.length} offline - ${_userPlaylists.length} playlists'
                : _sectionTitle,
            onRefresh: _load,
            onSearch: widget.onOpenSearch,
            onDownloads: _hub ? () => _setScope(_scopeDownloads) : null,
            onSparkle: () => widget.onDiscoverSearch('top songs charts today'),
          ),
        ),
        if (_scope == _scopeDownloads)
          SliverToBoxAdapter(
            child: _DownloadsPlaylistHeader(
              songs: _downloads,
              songCount: _downloads.length,
              activeCount: _downloadProgress.length,
              onPlayAll: _downloads.isEmpty
                  ? null
                  : () => widget.onPlay(_downloads.first, _downloads),
            ),
          ),
        if (!_hub && _scope != _scopeDownloads)
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
                          onTap: () => _setScope(chip.$3),
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
        if (_hub) ...[SliverToBoxAdapter(child: _hubGrid())],
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
                if (_scope == _scopeRecognized && _recognized.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () => _clearRecognitionHistory(context),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
                ] else if (_scope == _scopePlaylists) ...[
                  TextButton.icon(
                    onPressed: () => _createPlaylist(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New'),
                  ),
                ] else if (_scope == _scopeLocal) ...[
                  TextButton.icon(
                    onPressed: () => _importLocalAudio(folder: false),
                    icon: const Icon(Icons.library_add_rounded, size: 18),
                    label: const Text('Songs'),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Add folder',
                    onPressed: () => _importLocalAudio(folder: true),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                ] else if (songs.isNotEmpty && _scope != _scopePlaylists) ...[
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
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.25,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.9),
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
                        'Create a playlist with "New" above, add songs from the menu, or sign in on the Account tab to load your YouTube Music playlists.',
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
                                  ? '${p.displayTrackCount} songs - YouTube Music'
                                  : '${p.displayTrackCount} songs - On device',
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
        else if (_scope == _scopeRecognized && _recognized.isNotEmpty)
          SliverList.builder(
            itemCount: _recognized.length,
            itemBuilder: (context, index) {
              final item = _recognized[index];
              return _RecognizedHistoryTile(
                item: item,
                onTap: () => _playRecognizedTrack(context, item),
              );
            },
          )
        else if (songs.isEmpty &&
            _scope != _scopePlaylists &&
            _scope != _scopeRecognized)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_sectionTitle),
              title: 'Nothing here yet',
              subtitle:
                  'Play music, like tracks, and download for offline - your library grows automatically.',
            ),
          )
        else if (_scope == _scopeRecognized)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: Icons.music_note_rounded,
              title: 'No recognized songs yet',
              subtitle:
                  'Use the song finder and your identified tracks will land here.',
            ),
          )
        else if (_scope != _scopePlaylists && songs.isNotEmpty)
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _FoxySearchResultRow(
                song: song,
                kind: _SearchRowKind.song,
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

class _RecognizedHistoryTile extends StatelessWidget {
  const _RecognizedHistoryTile({required this.item, required this.onTap});

  final _RecognizedTrack item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(item.recognizedAt);
    final stamp =
        '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')} - ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return _FoxySearchResultRow(
      song: _Song(
        videoId: item.youtubeVideoId ?? 'recognized-${item.id}',
        title: item.title,
        artist: item.artist,
        artwork: item.coverArtUrl,
        duration: stamp,
      ),
      kind: _SearchRowKind.song,
      onTap: onTap,
      onMore: onTap,
    );
  }
}

class _AccountHubBody extends StatefulWidget {
  const _AccountHubBody({required this.onPlay});

  final _FoxyOnPlay onPlay;

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
    id: _cleanDisplayText(map['id']),
    name: _cleanDisplayText(map['name'], fallback: 'Playlist'),
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList(),
    source: _cleanDisplayText(map['source'], fallback: 'local'),
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

class _RecognizedTrack {
  const _RecognizedTrack({
    required this.id,
    required this.recognizedAt,
    required this.title,
    required this.artist,
    required this.coverArtUrl,
    this.youtubeVideoId,
    this.spotifyUrl,
  });

  factory _RecognizedTrack.fromMap(Map<String, dynamic> map) {
    final result = _asMap(map['result']) ?? const {};
    final hqCover = result['coverArtHqUrl']?.toString().trim() ?? '';
    final baseCover = result['coverArtUrl']?.toString().trim() ?? '';
    final youtubeVideoId = result['youtubeVideoId']?.toString().trim() ?? '';
    final spotifyUrl = result['spotifyUrl']?.toString().trim() ?? '';
    final cover = hqCover.isNotEmpty ? hqCover : baseCover;
    return _RecognizedTrack(
      id: ((map['id'] ?? 0) as num).toInt(),
      recognizedAt: ((map['recognizedAt'] ?? 0) as num).toInt(),
      title: _cleanDisplayText(result['title'], fallback: 'Unknown track'),
      artist: _cleanDisplayText(result['artist'], fallback: 'Unknown artist'),
      coverArtUrl: cover,
      youtubeVideoId: youtubeVideoId.isEmpty ? null : youtubeVideoId,
      spotifyUrl: spotifyUrl.isEmpty ? null : spotifyUrl,
    );
  }

  final int id;
  final int recognizedAt;
  final String title;
  final String artist;
  final String coverArtUrl;
  final String? youtubeVideoId;
  final String? spotifyUrl;
}

List<_UserPlaylist> _userPlaylistsFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _UserPlaylist.fromMap(_asMap(e) ?? const {}))
        .where((p) => p.id.isNotEmpty)
        .toList();

List<_RecognizedTrack> _recognizedTracksFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _RecognizedTrack.fromMap(_asMap(e) ?? const {}))
        .where((item) => item.title.isNotEmpty)
        .toList();

Future<void> _playFetchedUserPlaylist(
  BuildContext context,
  _UserPlaylist p,
  _FoxyOnPlay onPlay,
) async {
  if (p.songs.isNotEmpty) {
    onPlay(p.songs.first, p.songs);
    return;
  }
  if (!p.isYoutube) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('This playlist is empty')));
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

class _SongMenuContextCache {
  static Map<String, dynamic>? _feed;
  static Map<String, dynamic>? _appearance;
  static DateTime? _loadedAt;

  static bool get _fresh {
    final t = _loadedAt;
    if (t == null || _feed == null || _appearance == null) return false;
    return DateTime.now().difference(t) < const Duration(seconds: 12);
  }

  static (Map<String, dynamic>, Map<String, dynamic>)? snapshot() {
    if (!_fresh) return null;
    return (_feed!, _appearance!);
  }

  static Future<(Map<String, dynamic>, Map<String, dynamic>)> load() async {
    if (_fresh) return (_feed!, _appearance!);
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('songMenuContext'),
      _method.invokeMethod('getAppearance'),
    ]);
    _feed = _asMap(values[0]) ?? const {};
    _appearance = _asMap(values[1]) ?? const {};
    _loadedAt = DateTime.now();
    return (_feed!, _appearance!);
  }

  static void invalidate() {
    _feed = null;
    _appearance = null;
    _loadedAt = null;
  }
}

Future<void> _showFoxySongOverflowMenu(
  BuildContext context, {
  required _Song song,
  required _FoxyOnPlay onPlay,
  required List<_Song> queueForPlay,
  void Function(String query)? onDiscoverSearch,
  Future<void> Function()? onLibraryChanged,
  List<_Song>? searchResultsForExtras,
  String bulkQueuePlayTitle = 'Play all search results',
  String bulkQueuePlaySubtitle = 'Keeps the current result order',
  VoidCallback? onOpenLyricsTabInPlayer,
  bool showRemoveFromQueue = false,
  bool compactPlayerMenu = false,
}) async {
  final cached = _SongMenuContextCache.snapshot();
  final menuContextFuture = cached == null
      ? _SongMenuContextCache.load()
      : Future.value(cached);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FutureBuilder<(Map<String, dynamic>, Map<String, dynamic>)>(
      future: menuContextFuture,
      builder: (ctx, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return SafeArea(
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
                      url: song.highQualityArtwork,
                      size: 52,
                      radius: 10,
                      identityTag: song.videoId,
                      highQuality: true,
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
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 8),
                  for (final label in const [
                    'Like',
                    'Download',
                    'Add to a playlist',
                    'Add to queue',
                  ])
                    ListTile(
                      enabled: false,
                      leading: const Icon(Icons.more_horiz_rounded),
                      title: Text(label),
                    ),
                ],
              ),
            ),
          );
        }
        final (feed, appearance) = snapshot.data ?? (const {}, const {});
        final likedIds = Set<String>.from(
          _songsFrom(feed['liked']).map((s) => s.videoId),
        );
        final downloadedIds = Set<String>.from(
          _songsFrom(feed['downloads']).map((s) => s.videoId),
        );
        final userPlaylists = _userPlaylistsFrom(feed['userPlaylists']);
        final crossfadeMs = ((appearance['crossfadeMs'] ?? 0) as num).toInt();
        final crossfadeOn = crossfadeMs > 0;
        final romanize = appearance['lyricsRomanize'] == true;
        return SafeArea(
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
                      url: song.highQualityArtwork,
                      size: 52,
                      radius: 10,
                      identityTag: song.videoId,
                      highQuality: true,
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
                  if (!compactPlayerMenu &&
                      searchResultsForExtras != null &&
                      searchResultsForExtras.length > 1) ...[
                    ListTile(
                      leading: const Icon(Icons.podcasts_outlined),
                      title: const Text('Play with smart radio'),
                      subtitle: const Text('Builds a station from this track'),
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
                      _SongMenuContextCache.invalidate();
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
                        await _method.invokeMethod('removeDownload', {
                          'song': song.toMap(),
                        });
                      } else {
                        await _method.invokeMethod('download', {
                          'song': song.toMap(),
                        });
                      }
                      _SongMenuContextCache.invalidate();
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
                  if (!compactPlayerMenu)
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
                      _method.invokeMethod('addToQueue', {
                        'song': song.toMap(),
                      });
                    },
                  ),
                  if (!compactPlayerMenu)
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
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('Romanize lyrics'),
                    subtitle: Text(
                      romanize
                          ? 'On - show Romanized lyrics when available'
                          : 'Off - show original lyrics text',
                    ),
                    trailing: Switch(
                      value: romanize,
                      onChanged: (v) async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod('setAppearance', {
                          'lyricsRomanize': v,
                        });
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              v
                                  ? 'Romanized lyrics on.'
                                  : 'Romanized lyrics off.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('setAppearance', {
                        'lyricsRomanize': !romanize,
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
                          ? 'Crossfade is on - speed changes may sound uneven.'
                          : 'Quick presets (applies to the native player)',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      await _showPlaybackPitchSheet(context);
                    },
                  ),
                  if (onOpenLyricsTabInPlayer != null)
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: const Text('Open synced lyrics tab'),
                      subtitle: const Text('Full-width lyrics in this player'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onOpenLyricsTabInPlayer();
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
                  if (!compactPlayerMenu)
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
                            const SnackBar(
                              content: Text('Link copied to clipboard'),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
                      onPressed: () =>
                          Navigator.pop(dCtx, nameCtrl.text.trim()),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty && context.mounted) {
                await _method.invokeMethod('playlistCreate', {'name': name});
                _SongMenuContextCache.invalidate();
                await onChanged?.call();
                final libraryFeed =
                    _asMap(await _method.invokeMethod('libraryFeed')) ??
                    const {};
                if (!context.mounted) return;
                await _pickPlaylistToAddSong(
                  context,
                  song: song,
                  playlists: _userPlaylistsFrom(libraryFeed['userPlaylists']),
                  onChanged: onChanged,
                );
              }
            },
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                'No playlists yet. Tap "New playlist" above.',
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
                      p.isYoutube
                          ? Icons.cloud_queue_rounded
                          : Icons.queue_music_rounded,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.isYoutube
                          ? '${p.displayTrackCount} songs - YouTube Music'
                          : '${p.displayTrackCount} songs - On device',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('playlistAddSong', {
                        'playlistId': p.id,
                        'song': song.toMap(),
                      });
                      _SongMenuContextCache.invalidate();
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

Future<void> _showPlaybackPitchSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF121212),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      Future<void> apply(double speed, double pitch) async {
        await _method.invokeMethod('setPlaybackSpeed', {
          'speed': speed,
          'pitch': pitch,
        });
      }

      Widget preset(String label, double speed, double pitch) {
        return _FoxyGlassButton(
          onTap: () async {
            await apply(speed, pitch);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${speed}x - pitch ${pitch}x',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const Text(
                'Playback speed & pitch',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Quick presets. Pitch stays natural unless you choose a pitch preset.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  preset('Normal', 1.0, 1.0),
                  preset('Slow', 0.85, 1.0),
                  preset('Nightcore', 1.15, 1.08),
                  preset('Podcast', 1.25, 1.0),
                  preset('Chipmunk', 1.0, 1.18),
                  preset('Deep', 1.0, 0.88),
                ],
              ),
            ],
          ),
        ),
      );
    },
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
  final dialogTitle =
      title ??
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
            if (!ok) Text(err.isEmpty ? 'Could not reach GitHub.' : err),
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
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF181818),
            border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
          ),
          child: Column(
            children: [
              _FoxyAppLogo(size: 132, borderRadius: 30),
              const SizedBox(height: 18),
              const Text(
                'FoxyMusic',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AboutPill(
                    label: _kAppVersionLabel,
                    icon: Icons.bolt_rounded,
                  ),
                  const _AboutPill(
                    label: 'Flutter + Kotlin',
                    icon: Icons.layers_rounded,
                  ),
                  const _AboutPill(
                    label: 'Open source',
                    icon: Icons.code_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'A fast, glassy music player built around FoxyMusic vibes: clean playback, live lyrics, smart discovery, and a native audio engine.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.42, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _AboutFeatureChip(
              icon: Icons.graphic_eq_rounded,
              title: 'Ultra audio',
              subtitle: 'YT + SoundCloud resolver',
            ),
            _AboutFeatureChip(
              icon: Icons.lyrics_rounded,
              title: 'Synced lyrics',
              subtitle: 'LRCLIB + romanized text',
            ),
            _AboutFeatureChip(
              icon: Icons.blur_on_rounded,
              title: 'Foxy glass',
              subtitle: 'Adaptive player visuals',
            ),
            _AboutFeatureChip(
              icon: Icons.manage_search_rounded,
              title: 'Discovery',
              subtitle: 'Moods, charts, search',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            color: const Color(0xFF181818),
            border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
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
          subtitle: 'Source, releases, and credits',
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(context: context),
                icon: const Icon(Icons.article_outlined, size: 20),
                label: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Release $_kAppVersionName - FoxyMusic',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AboutPill extends StatelessWidget {
  const _AboutPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutFeatureChip extends StatelessWidget {
  const _AboutFeatureChip({
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
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 56) / 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.065),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

class _SettingsSheetState extends State<_SettingsSheet> {
  late Map<String, dynamic> _m;
  _FoxySettingsPage _settingsPage = _FoxySettingsPage.home;

  @override
  void initState() {
    super.initState();
    _m = Map<String, dynamic>.from(widget.appearance);
  }

  @override
  void didUpdateWidget(covariant _SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.appearance, widget.appearance)) {
      setState(() => _m = Map<String, dynamic>.from(widget.appearance));
    }
  }

  Future<void> _reloadAppearanceSnapshot() async {
    final fresh = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || fresh == null) return;
    setState(() => _m = Map<String, dynamic>.from(fresh));
  }

  Future<void> _apply(Map<String, dynamic> patch) async {
    await widget.onSetAppearance(patch);
    if (!mounted) return;
    await _reloadAppearanceSnapshot();
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

  Future<void> _runSettingsAction({
    required String method,
    required String success,
    required String failure,
  }) async {
    try {
      await _method.invokeMethod(method);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _reloadAppearanceSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$failure: $e')));
    }
  }

  Future<void> _showAccountHealth() async {
    try {
      final raw = _asMap(await _method.invokeMethod('accountInfo')) ?? const {};
      if (!mounted) return;
      final signedIn = raw['isSignedIn'] == true;
      final rows = <(String, String)>[
        ('YouTube', signedIn ? 'Connected' : 'Guest mode'),
        (
          'Name',
          raw['displayName']?.toString().ifBlank('Not available') ??
              'Not available',
        ),
        (
          'Email',
          raw['email']?.toString().ifBlank('Not available') ?? 'Not available',
        ),
        ('Liked songs', '${(raw['likedCount'] as num?)?.toInt() ?? 0}'),
        ('Downloads', '${(raw['downloadCount'] as num?)?.toInt() ?? 0}'),
        ('Playlists', '${(raw['playlistCount'] as num?)?.toInt() ?? 0}'),
      ];
      await _showSettingsInfoDialog(
        title: 'Account health',
        subtitle: signedIn
            ? 'Cookies and library snapshot are available.'
            : 'Sign in inside FoxyMusic to sync account shelves.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Account check failed: $e')));
    }
  }

  Future<void> _showPlaybackDiagnostics() async {
    try {
      final player =
          _asMap(await _method.invokeMethod('getPlayerState')) ?? const {};
      final settings =
          _asMap(await _method.invokeMethod('getAppearance')) ?? _m;
      if (!mounted) return;
      final bitrate = (player['streamBitrate'] as num?)?.toInt();
      final rows = <(String, String)>[
        ('State', player['isPlaying'] == true ? 'Playing' : 'Paused / idle'),
        ('Buffering', player['isBuffering'] == true ? 'Yes' : 'No'),
        (
          'Source',
          player['streamSource']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'Codec',
          player['streamCodec']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'MIME',
          player['streamMimeType']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'Bitrate',
          bitrate == null ? 'Unknown' : '${(bitrate / 1000).round()} kbps',
        ),
        (
          'Stream quality',
          _qualityLabel(((settings['streamQualityTier'] ?? 2) as num).toInt()),
        ),
        (
          'Source priority',
          _sourcePriorityLabel(
            ((settings['streamSourcePriority'] ?? 0) as num).toInt(),
          ),
        ),
        (
          'Crossfade',
          '${((settings['crossfadeMs'] ?? 0) as num).toInt() ~/ 1000}s',
        ),
      ];
      await _showSettingsInfoDialog(
        title: 'Playback diagnostics',
        subtitle: 'Live stream and quality state from the native player.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnostics failed: $e')));
    }
  }

  Future<void> _showStorageStatus() async {
    try {
      final storage =
          _asMap(await _method.invokeMethod('storageStats')) ?? const {};
      final backup =
          _asMap(await _method.invokeMethod('backupStatus')) ?? const {};
      if (!mounted) return;
      final rows = <(String, String)>[
        (
          'Downloads',
          _formatStorageBytes((storage['downloadBytes'] as num?) ?? 0),
        ),
        (
          'Stream cache',
          _formatStorageBytes((storage['cacheBytes'] as num?) ?? 0),
        ),
        (
          'Latest backup',
          backup['fileName']?.toString().ifBlank('None yet') ?? 'None yet',
        ),
        ('Backup size', _formatStorageBytes((backup['bytes'] as num?) ?? 0)),
        (
          'Backup file',
          backup['exists'] == true ? 'Ready to restore' : 'None yet',
        ),
      ];
      await _showSettingsInfoDialog(
        title: 'Storage status',
        subtitle: 'Foxy quick quick glance for cache, downloads, and backups.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Storage status failed: $e')));
    }
  }

  Future<void> _showSettingsInfoDialog({
    required String title,
    required String subtitle,
    required List<(String, String)> rows,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              const SizedBox(height: 14),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 112,
                        child: Text(
                          row.$1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Expanded(child: Text(row.$2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(int tier) {
    return switch (tier) {
      -1 => 'Follow default',
      0 => 'Low',
      1 => 'Balanced',
      2 => 'Normal',
      3 => 'High',
      _ => 'Ultra',
    };
  }

  String _sourcePriorityLabel(int sourcePriority) {
    return switch (sourcePriority) {
      1 => 'YouTube first',
      2 => 'SoundCloud first',
      _ => 'YouTube only',
    };
  }

  Future<void> _openWebLogin([String mode = 'webview']) async {
    final ok =
        await _method.invokeMethod('openWebLogin', {'mode': mode}) == true;
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
            'If you use the YouTube Music app first, come back and tap "Sign in inside FoxyMusic" to finish. Google does not share that login with other apps.',
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

  Future<void> _pickHomeBackground() async {
    try {
      final raw = _asMap(await _method.invokeMethod('pickHomeBackground'));
      if (!mounted) return;
      if (raw?['ok'] == true) {
        await _apply({'homeBackgroundEnabled': true});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custom background applied')),
          );
        }
      } else if (raw?['cancelled'] != true && raw?['ok'] != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not set background')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Background picker failed: $e')));
    }
  }

  Future<void> _resetHomeBackground() async {
    try {
      await _method.invokeMethod('clearHomeBackground');
      if (!mounted) return;
      await _apply({'homeBackgroundEnabled': false});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default background restored')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  void _clearFlutterImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Image cache cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final persistent = _bool('persistentQueue', true);
    final saveHistory = _bool('saveHistory', true);
    final sponsor = _bool('sponsorBlockEnabled', true);
    final lrclib = _bool('lyricsPreferLrclib', true);
    final norm = _bool('normalizeVolume');
    final skipSil = _bool('skipSilence');
    final backup = _bool('autoBackupEnabled');
    final tier = _int('streamQualityTier', 2).clamp(0, 4);
    final downloadTier = _int('downloadQualityTier', 2).clamp(0, 4);
    final sourcePriority = _int('streamSourcePriority', 0).clamp(0, 2);
    final cross = _int('crossfadeMs', 0);
    final continueDismiss = _bool('continuePlaybackWhenDismissed');
    final romanize = _bool('lyricsRomanize');
    final blurEffects = _bool('blurEffects', true);
    final disableAnimations = _bool('disableAnimations');
    final haptics = _bool('hapticFeedback', true);
    final playerButtonsStyle = _int('playerButtonsStyle', 0).clamp(0, 2);
    final miniPlayerStyle = _int('miniPlayerStyle', 0).clamp(0, 2);
    final bottomNavigationStyle = _int('bottomNavigationStyle', 0).clamp(0, 2);
    final playerProgressStyle = _int('playerProgressStyle', 0).clamp(0, 1);
    final hidePlayerArtwork = _bool('hidePlayerArtwork');
    final cropArtworkSquare = _bool('cropArtworkSquare', true);
    final thumbnailCornerRadius = _int(
      'thumbnailCornerRadius',
      16,
    ).clamp(0, 40);
    final defaultOpenTab = _int('defaultOpenTab', 0);
    final quickPicksDisplayMode = _int('quickPicksDisplayMode', 0).clamp(0, 1);

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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_settingsPage != _FoxySettingsPage.home) ...[
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => setState(
                                () => _settingsPage = _FoxySettingsPage.home,
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 2),
                          ],
                          Expanded(
                            child: Text(
                              _settingsPage.title,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _kAppVersionLabel,
                            style: TextStyle(
                              color: _FoxyBrandPalette.foxCream.withValues(
                                alpha: 0.75,
                              ),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _settingsPage.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: switch (_settingsPage) {
                      _FoxySettingsPage.home => _buildSettingsHome(controller),
                      _FoxySettingsPage.account => _buildAccountSettings(
                        controller,
                      ),
                      _FoxySettingsPage.playback => _buildPlaybackSettings(
                        controller,
                        persistent: persistent,
                        continueDismiss: continueDismiss,
                        saveHistory: saveHistory,
                        sponsor: sponsor,
                        tier: tier,
                        downloadTier: downloadTier,
                        sourcePriority: sourcePriority,
                        cross: cross,
                        norm: norm,
                        skipSil: skipSil,
                      ),
                      _FoxySettingsPage.appearance => _buildAppearanceTab(
                        controller,
                        playerButtonsStyle: playerButtonsStyle,
                        miniPlayerStyle: miniPlayerStyle,
                        bottomNavigationStyle: bottomNavigationStyle,
                        playerProgressStyle: playerProgressStyle,
                        hidePlayerArtwork: hidePlayerArtwork,
                        cropArtworkSquare: cropArtworkSquare,
                        thumbnailCornerRadius: thumbnailCornerRadius,
                      ),
                      _FoxySettingsPage.lyrics => _buildLyricsSettings(
                        controller,
                        lrclib: lrclib,
                        romanize: romanize,
                      ),
                      _FoxySettingsPage.storage => _buildStorageSettings(
                        controller,
                        backup: backup,
                      ),
                      _FoxySettingsPage.advanced => _buildAdvancedSettings(
                        controller,
                        blurEffects: blurEffects,
                        disableAnimations: disableAnimations,
                        haptics: haptics,
                        defaultOpenTab: defaultOpenTab,
                        quickPicksDisplayMode: quickPicksDisplayMode,
                      ),
                      _FoxySettingsPage.about => ListView(
                        key: const ValueKey('settings-about'),
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                        children: [
                          _AboutUsPanel(onOpenExternal: _openExternal),
                        ],
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountSettings(ScrollController controller) {
    return ListView(
      key: const ValueKey('settings-account'),
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
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 20,
                    ),
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
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _showAccountHealth,
                    icon: const Icon(Icons.verified_user_rounded, size: 20),
                    label: const Text('Account health check'),
                  ),
                ],
              ),
            );
          },
        ),
        _SettingsCard(
          title: 'Metadata matching',
          subtitle:
              'Spotify and SoundCloud are used as resolvers where FoxyMusic can match public metadata safely.',
          child: const Text(
            'Account sync is kept off until there is a stable authenticated path. Public metadata matching remains active in search, artwork, and playback resolution.',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackSettings(
    ScrollController controller, {
    required bool persistent,
    required bool continueDismiss,
    required bool saveHistory,
    required bool sponsor,
    required int tier,
    required int downloadTier,
    required int sourcePriority,
    required int cross,
    required bool norm,
    required bool skipSil,
  }) {
    return ListView(
      key: const ValueKey('settings-playback'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Stream quality',
          subtitle:
              'Choose the preferred playback target ,also affects the data/wifi usage.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                (0, 'Low'),
                (1, 'Balanced'),
                (2, 'Normal'),
                (3, 'High'),
                (4, 'Ultra'),
              ])
                ChoiceChip(
                  selected: tier == item.$1,
                  label: Text(item.$2),
                  onSelected: (_) => _apply({'streamQualityTier': item.$1}),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Download quality',
          subtitle:
              'Separate offline target so downloads can stay lighter or go all the way up.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                (0, 'Low'),
                (1, 'Balanced'),
                (2, 'Normal'),
                (3, 'High'),
                (4, 'Ultra'),
              ])
                ChoiceChip(
                  selected: downloadTier == item.$1,
                  label: Text(item.$2),
                  onSelected: (_) => _apply({'downloadQualityTier': item.$1}),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Playback source priority',
          subtitle: 'Pick the streaming quality',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                (0, 'Yt priority'),
                (1, 'Yt/Soundcloud'),
                (2, 'SoundCloud '),
              ])
                ChoiceChip(
                  selected: sourcePriority == item.$1,
                  label: Text(item.$2),
                  onSelected: (_) => _apply({'streamSourcePriority': item.$1}),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Crossfade',
          subtitle: '"beta" still in development.',
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
          title: 'Playback behavior',
          subtitle: 'Queue persistence, history, skips, and audio helpers.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: persistent,
                title: const Text('Restore queue after restart'),
                onChanged: (v) => _apply({'persistentQueue': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: continueDismiss,
                title: const Text('Keep playback alive'),
                subtitle: const Text(
                  'Lets audio continue when the app is swiped away from recents.',
                ),
                onChanged: (v) => _apply({'continuePlaybackWhenDismissed': v}),
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
                value: norm,
                title: const Text('Normalize volume'),
                subtitle: const Text(
                  'Lowers loud tracks for steadier playback.',
                ),
                onChanged: (v) => _apply({'normalizeVolume': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: skipSil,
                title: const Text('Skip silence'),
                subtitle: const Text('Reserved for deeper ExoPlayer tuning.'),
                onChanged: (v) => _apply({'skipSilence': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Shortcuts',
          subtitle: 'System integrations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _openEqualizer,
                icon: const Icon(Icons.equalizer_rounded, size: 20),
                label: const Text('System equalizer'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showPlaybackDiagnostics,
                icon: const Icon(Icons.monitor_heart_rounded, size: 20),
                label: const Text('Playback diagnostics'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsSettings(
    ScrollController controller, {
    required bool lrclib,
    required bool romanize,
  }) {
    return ListView(
      key: const ValueKey('settings-lyrics'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Lyrics sources',
          subtitle:
              'Control synced lyrics, source order, and Romanized output.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: lrclib,
                title: const Text('Prefer synced lyrics / LRCLIB first'),
                subtitle: const Text(
                  'YouTube captions are used as fallback. Turn off to try captions first.',
                ),
                onChanged: (v) => _apply({'lyricsPreferLrclib': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: romanize,
                title: const Text('Romanize lyrics'),
                subtitle: const Text(
                  'Show Latin-script lyrics when supported.',
                ),
                onChanged: (v) => _apply({'lyricsRomanize': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Lyrics tools',
          subtitle: 'Cache cleanup and lyric health checks.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'clearLyricsCache',
                  success: 'Lyrics cache cleared',
                  failure: 'Could not clear lyrics cache',
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                label: const Text('Clear lyrics cache'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Per-song lyric overrides and share-image export need a persistent lyric editor before they can be enabled safely.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSettings(
    ScrollController controller, {
    required bool backup,
  }) {
    return ListView(
      key: const ValueKey('settings-storage'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Backups',
          subtitle: 'Library and settings safety.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: backup,
                title: const Text('Auto backup'),
                subtitle: const Text(
                  'Writes local snapshots after settings changes.',
                ),
                onChanged: (v) => _apply({'autoBackupEnabled': v}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showStorageStatus,
                icon: const Icon(Icons.analytics_rounded, size: 20),
                label: const Text('Storage and backup status'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'createBackup',
                  success: 'Backup created',
                  failure: 'Backup failed',
                ),
                icon: const Icon(Icons.save_alt_rounded, size: 20),
                label: const Text('Create backup now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'restoreLatestBackup',
                  success: 'Latest backup restored',
                  failure: 'Restore failed',
                ),
                icon: const Icon(Icons.restore_rounded, size: 20),
                label: const Text('Restore latest backup'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Cache cleanup',
          subtitle: 'Free streaming and artwork memory cache.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'clearStreamCache',
                  success: 'Stream cache cleared',
                  failure: 'Could not clear stream cache',
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                label: const Text('Clear stream cache'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _clearFlutterImageCache,
                icon: const Icon(Icons.image_not_supported_rounded, size: 20),
                label: const Text('Clear image cache'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Playback recovery',
          subtitle: 'Move past broken streams automatically.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _bool('autoSkipNextOnError'),
            title: const Text('Auto-skip failed songs'),
            subtitle: const Text(
              'After one retry fails, Foxy jumps to the next queue item.',
            ),
            onChanged: (v) => _apply({'autoSkipNextOnError': v}),
          ),
        ),
        _SettingsCard(
          title: 'Library repair',
          subtitle: 'Rescan downloads and repair stale liked/history metadata.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'refreshDownloads',
                  success: 'Downloads refreshed',
                  failure: 'Could not refresh downloads',
                ),
                icon: const Icon(Icons.download_done_rounded, size: 20),
                label: const Text('Refresh downloads'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'repairLibraryMetadata',
                  success: 'Library metadata repaired',
                  failure: 'Could not repair library metadata',
                ),
                icon: const Icon(Icons.healing_rounded, size: 20),
                label: const Text('Repair library metadata'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'App updates',
          subtitle: 'GitHub releases',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('autoCheckUpdates', true),
                title: const Text('Check for updates automatically'),
                subtitle: const Text(
                  'Looks for new GitHub releases about once per day.',
                ),
                onChanged: (v) => _apply({'autoCheckUpdates': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('updateNotifications', true),
                title: const Text('Update notifications'),
                subtitle: const Text(
                  'Shows a system notification when a newer APK is published.',
                ),
                onChanged: (v) => _apply({'updateNotifications': v}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _checkUpdate,
                icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                label: const Text('Check for updates now'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings(
    ScrollController controller, {
    required bool blurEffects,
    required bool disableAnimations,
    required bool haptics,
    required int defaultOpenTab,
    required int quickPicksDisplayMode,
  }) {
    return ListView(
      key: const ValueKey('settings-advanced'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Performance & motion',
          subtitle: 'Control animation, blur, and touch feedback.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: blurEffects,
                title: const Text('Glass blur effects'),
                subtitle: const Text(
                  'Turn off on weaker phones if scrolling feels sticky.',
                ),
                onChanged: (v) => _apply({'blurEffects': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: disableAnimations,
                title: const Text('Reduce animations'),
                subtitle: const Text(
                  'Makes settings/page transitions instant.',
                ),
                onChanged: (v) => _apply({'disableAnimations': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: haptics,
                title: const Text('Haptic feedback'),
                subtitle: const Text('Light vibration on player controls.'),
                onChanged: (v) => _apply({'hapticFeedback': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Launch & home',
          subtitle: 'Choose where Foxy opens and how quick picks display.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default open tab',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: defaultOpenTab == 1 || defaultOpenTab == 3
                    ? defaultOpenTab
                    : 0,
                values: const [0, 1, 3],
                label: (v) => switch (v) {
                  1 => 'Search',
                  3 => 'Library',
                  _ => 'Home',
                },
                icon: (v) => switch (v) {
                  1 => Icons.search_rounded,
                  3 => Icons.library_music_rounded,
                  _ => Icons.home_rounded,
                },
                onChanged: (v) => _apply({'defaultOpenTab': v}),
              ),
              const SizedBox(height: 14),
              Text(
                'Quick picks layout',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: quickPicksDisplayMode,
                values: const [0, 1],
                label: (v) => v == 1 ? 'List' : 'Cards',
                icon: (v) => v == 1
                    ? Icons.view_list_rounded
                    : Icons.view_carousel_rounded,
                onChanged: (v) => _apply({'quickPicksDisplayMode': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Library visibility',
          subtitle: 'Hide sections you do not use.',
          child: Column(
            children: [
              for (final item in const [
                ('showLikedInLibrary', 'Liked'),
                ('showDownloadsInLibrary', 'Downloads'),
                ('showHistoryInLibrary', 'History'),
                ('showMostPlayedInLibrary', 'Most played'),
                ('showPlaylistsInLibrary', 'Playlists'),
                ('showLocalInLibrary', 'Local library'),
                ('showRecognizedInLibrary', 'Recognized songs'),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _bool(item.$1, true),
                  title: Text(item.$2),
                  onChanged: (v) => _apply({item.$1: v}),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsHome(ScrollController controller) {
    final signedIn = widget.account['isSignedIn'] == true;
    return ListView(
      key: const ValueKey('settings-home'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _SettingsProfileBanner(
          signedIn: signedIn,
          email: widget.account['email']?.toString() ?? '',
          onTap: () =>
              setState(() => _settingsPage = _FoxySettingsPage.account),
        ),
        const SizedBox(height: 14),
        _FoxySettingsSection(
          children: [
            _FoxySettingsItem(
              icon: Icons.account_circle_rounded,
              title: 'Account',
              subtitle: signedIn
                  ? 'YouTube Music connected'
                  : 'Sign in, cookies, and account overview',
              accent: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.account),
              first: true,
            ),
            _FoxySettingsItem(
              icon: Icons.graphic_eq_rounded,
              title: 'Playback & quality',
              subtitle: 'Ultra quality, source priority, crossfade, queue',
              accent: _FoxyBrandPalette.foxAmber,
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.playback),
            ),
            _FoxySettingsItem(
              icon: Icons.palette_rounded,
              title: 'Appearance',
              subtitle: 'Player background, glass, wallpaper, gestures',
              accent: const Color(0xFFB388FF),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.appearance),
            ),
            _FoxySettingsItem(
              icon: Icons.lyrics_rounded,
              title: 'Lyrics',
              subtitle: 'LRCLIB, synced lyrics, Romanized text',
              accent: const Color(0xFF64B5F6),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.lyrics),
            ),
            _FoxySettingsItem(
              icon: Icons.storage_rounded,
              title: 'Storage, backup & updates',
              subtitle: 'Backups, update checks, cache plans',
              accent: const Color(0xFF81C784),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.storage),
            ),
            _FoxySettingsItem(
              icon: Icons.tune_rounded,
              title: 'Advanced',
              subtitle: 'Performance, region, and layout controls',
              accent: const Color(0xFF4DD0E1),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.advanced),
            ),
            _FoxySettingsItem(
              icon: Icons.info_rounded,
              title: 'About FoxyMusic',
              subtitle: 'Version, credits, project links',
              accent: const Color(0xFFFF8A65),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.about),
              last: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearanceTab(
    ScrollController controller, {
    required int playerButtonsStyle,
    required int miniPlayerStyle,
    required int bottomNavigationStyle,
    required int playerProgressStyle,
    required bool hidePlayerArtwork,
    required bool cropArtworkSquare,
    required int thumbnailCornerRadius,
  }) {
    final thumbAccent = _bool('dynamicSongColors');
    final compact = _bool('compactPlayer');
    final gestures = _bool('gestureControls', true);
    final bgStyle = _normalizePlayerBackgroundStyle(
      _int('playerBackgroundStyle', 0),
    );
    final homeBackgroundEnabled = _bool('homeBackgroundEnabled');
    final recognitionSource = _int('recognitionSource', 0).clamp(0, 1);
    final recognitionHistoryLimit = _int(
      'recognitionHistoryLimit',
      40,
    ).clamp(10, 100);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Look & player',
          subtitle:
              'Keep the Foxy vibe fixed while still tuning the player feel and glass surfaces.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: thumbAccent,
                title: const Text('Song thumbnail accent'),
                subtitle: const Text(
                  'Follow artwork colors on the full player when enabled.',
                ),
                onChanged: (value) => _apply({
                  'dynamicSongColors': value,
                  'accentArgb': 0xFFFF1744,
                }),
              ),
              Text(
                'Player background',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: bgStyle,
                values: const [0, 1, 2, 3],
                label: (v) => switch (v) {
                  1 => 'Artwork',
                  2 => 'Black',
                  3 => 'Video',
                  _ => 'Blur',
                },
                icon: (v) => switch (v) {
                  1 => Icons.image_rounded,
                  2 => Icons.dark_mode_rounded,
                  3 => Icons.motion_photos_on_rounded,
                  _ => Icons.blur_on_rounded,
                },
                onChanged: (v) => _apply({'playerBackgroundStyle': v}),
              ),
              const SizedBox(height: 16),
              Text(
                'Button style',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: playerButtonsStyle,
                values: const [0, 1, 2],
                label: (v) => switch (v) {
                  1 => 'Outline',
                  2 => 'Solid',
                  _ => 'Glass',
                },
                icon: (v) => switch (v) {
                  1 => Icons.radio_button_unchecked_rounded,
                  2 => Icons.radio_button_checked_rounded,
                  _ => Icons.circle_rounded,
                },
                onChanged: (v) => _apply({'playerButtonsStyle': v}),
              ),
              const SizedBox(height: 16),
              Text(
                'Mini-player style',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: miniPlayerStyle,
                values: const [0, 1, 2],
                label: (v) => switch (v) {
                  1 => 'Liquid',
                  2 => 'Clear',
                  _ => 'Default',
                },
                icon: (v) => switch (v) {
                  1 => Icons.water_drop_rounded,
                  2 => Icons.opacity_rounded,
                  _ => Icons.music_note_rounded,
                },
                onChanged: (v) => _apply({'miniPlayerStyle': v}),
              ),
              const SizedBox(height: 16),
              Text(
                'Bottom navigation style',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: bottomNavigationStyle,
                values: const [0, 1, 2],
                label: (v) => switch (v) {
                  1 => 'Liquid',
                  2 => 'Clear',
                  _ => 'Default',
                },
                icon: (v) => switch (v) {
                  1 => Icons.water_drop_rounded,
                  2 => Icons.opacity_rounded,
                  _ => Icons.space_dashboard_rounded,
                },
                onChanged: (v) => _apply({'bottomNavigationStyle': v}),
              ),
              const SizedBox(height: 16),
              Text(
                'Seek bar',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: playerProgressStyle,
                values: const [0, 1],
                label: (v) => v == 1 ? 'Slim' : 'Standard',
                icon: (v) => v == 1
                    ? Icons.remove_rounded
                    : Icons.horizontal_rule_rounded,
                onChanged: (v) => _apply({'playerProgressStyle': v}),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: hidePlayerArtwork,
                title: const Text('Hide full-player artwork'),
                subtitle: const Text('Keeps lyrics and controls more open.'),
                onChanged: (v) => _apply({'hidePlayerArtwork': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cropArtworkSquare,
                title: const Text('Crop artwork to square'),
                subtitle: const Text('Turn off to contain wide poster art.'),
                onChanged: (v) => _apply({'cropArtworkSquare': v}),
              ),
              Text(
                'Artwork corner radius: $thumbnailCornerRadius',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Slider(
                value: thumbnailCornerRadius.toDouble(),
                min: 0,
                max: 40,
                divisions: 8,
                label: '$thumbnailCornerRadius',
                onChanged: (v) => _apply({'thumbnailCornerRadius': v.round()}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: compact,
                title: const Text('Compact mini-player'),
                onChanged: (v) => _apply({'compactPlayer': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: gestures,
                title: const Text('Swipe to change song'),
                onChanged: (v) => _apply({'gestureControls': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Recognition',
          subtitle: 'Shazam-style matching and local history retention.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fingerprint source',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in const [
                    (0, 'Foxy fingerprint'),
                    (1, 'Fast microphone'),
                  ])
                    ChoiceChip(
                      selected: recognitionSource == item.$1,
                      label: Text(item.$2),
                      onSelected: (_) => _apply({'recognitionSource': item.$1}),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'History limit',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in const [10, 25, 40, 75, 100])
                    ChoiceChip(
                      selected: recognitionHistoryLimit == item,
                      label: Text('$item'),
                      onSelected: (_) =>
                          _apply({'recognitionHistoryLimit': item}),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _runSettingsAction(
                    method: 'clearRecognitionHistory',
                    success: 'Recognition history cleared',
                    failure: 'Could not clear recognition history',
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                  label: const Text('Clear recognition history'),
                ),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'App background',
          subtitle:
              'Wallpaper and glass treatment for Home, Search, and Library.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: homeBackgroundEnabled,
                title: const Text('Enable custom wallpaper'),
                subtitle: const Text(
                  'Uses your saved wallpaper everywhere outside the player.',
                ),
                onChanged: (v) => _apply({'homeBackgroundEnabled': v}),
              ),
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
      ],
    );
  }
}

enum _FoxySettingsPage {
  home('Settings', 'Clean categories...'),
  account('Account', 'Sign-in, provider auth, and account health.'),
  playback(
    'Playback & quality',
    'Streams, downloads, queue, and audio behavior.',
  ),
  appearance(
    'Appearance',
    'Player background, glass, wallpaper, and gestures.',
  ),
  lyrics(
    'Lyrics',
    'Synced lyrics sources, Romanized output, and future tools.',
  ),
  storage(
    'Storage & updates',
    'Backups, update checks, cache plans, and cleanup.',
  ),
  advanced('Advanced', 'Performance, region, and low-level layout controls.'),
  about('About', 'Version, credits, links, and project info.');

  const _FoxySettingsPage(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _SettingsOptionGrid<T> extends StatelessWidget {
  const _SettingsOptionGrid({
    required this.value,
    required this.values,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) label;
  final IconData Function(T value) icon;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (context, index) {
        final item = values[index];
        final selected = item == value;
        return Material(
          color: selected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon(item), color: selected ? accent : Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsProfileBanner extends StatelessWidget {
  const _SettingsProfileBanner({
    required this.signedIn,
    required this.email,
    required this.onTap,
  });

  final bool signedIn;
  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _FoxyGlassButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      tintOpacity: 0.22,
      blurSigma: 14,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.92),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              signedIn ? Icons.verified_rounded : Icons.person_rounded,
              color: Colors.black,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn ? 'Connected' : 'Guest mode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  signedIn && email.isNotEmpty
                      ? email
                      : 'Tap to manage YouTube Music sign-in',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.62),
          ),
        ],
      ),
    );
  }
}

class _FoxySettingsSection extends StatelessWidget {
  const _FoxySettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Column(children: children),
    );
  }
}

class _FoxySettingsItem extends StatelessWidget {
  const _FoxySettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.first = false,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171717),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: last
                  ? BorderSide.none
                  : BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.95),
                ),
                child: Icon(icon, color: Colors.black, size: 25),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
      ),
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

class _HomeShelfShell extends StatelessWidget {
  const _HomeShelfShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _kHomeShelfGap),
      child: RepaintBoundary(child: child),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _FoxyGlassButton(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(24),
        blurSigma: 0,
        tintOpacity: 0.16,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 188,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Artwork(
                    url: song.homeArtwork,
                    size: 480,
                    radius: 0,
                    identityTag: song.videoId,
                    offlineArtworkPath: song.offlineArtworkPath,
                    useOfflineArtwork: song.isDownloaded,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.48),
                          Colors.black.withValues(alpha: 0.9),
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
                          OutlinedButton.icon(
                            onPressed: onPlay,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                            ),
                            label: const Text('Play'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: onRadio,
                            icon: const Icon(Icons.radio_rounded, size: 20),
                            label: const Text('Radio'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
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
  final _FoxyOnPlay onPlay;

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
                          fontSize: 20,
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

class _HomeFeedSection extends StatelessWidget {
  const _HomeFeedSection({
    required this.section,
    required this.layout,
    required this.currentVideoId,
    required this.onPlay,
    required this.quickPicksDisplayMode,
    this.onDiscoverSearch,
  });

  final _SongSection section;
  final _HomeSectionLayout layout;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final int quickPicksDisplayMode;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    if (_isSuppressedHomeSection(section.title)) {
      return const SizedBox.shrink();
    }
    if (section.title.toLowerCase().contains('quick pick')) {
      return quickPicksDisplayMode == 1
          ? _HomeQuickStartSection(
              section: section,
              currentVideoId: currentVideoId,
              onPlay: onPlay,
            )
          : _HomeQuickPicks(
              songs: section.songs,
              currentVideoId: currentVideoId,
              onPlay: onPlay,
            );
    }
    return switch (layout) {
      _HomeSectionLayout.square => _HomeSquareSwipeSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.radio => _HomeRadioStarterSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.mixes => _HomeMixesSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
      ),
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
        currentVideoId: currentVideoId,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.artist => _HomeArtistShelf(
        section: section,
        onPlay: onPlay,
        onDiscoverSearch: onDiscoverSearch,
      ),
      _HomeSectionLayout.cards => _HomeSongCardsSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
      ),
    };
  }
}

class _HomeQuickStartSection extends StatelessWidget {
  const _HomeQuickStartSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(24).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final tileWidth = (MediaQuery.sizeOf(context).width - 30).clamp(
      280.0,
      460.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Start a radio'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 218,
          child: GridView.builder(
            key: PageStorageKey('home-quick-picks-${section.title}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: tileWidth,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _HomeQuickPickRow(
                song: song,
                active: song.videoId == currentVideoId,
                onTap: () => onPlay(song, section.songs, radioTail: true),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeQuickPickRow extends StatelessWidget {
  const _HomeQuickPickRow({
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: 44,
                radius: 10,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 13,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                color: active ? accent : Colors.white.withValues(alpha: 0.56),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSquareSwipeSection extends StatelessWidget {
  const _HomeSquareSwipeSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(12).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    const cardSize = 151.0;
    const railHeight = 151.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            key: PageStorageKey('home-square-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _HomeSquareSongCard(
                song: song,
                active: song.videoId == currentVideoId,
                size: cardSize,
                onTap: () => onPlay(song, section.songs),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeSquareSongCard extends StatelessWidget {
  const _HomeSquareSongCard({
    required this.song,
    required this.active,
    required this.onTap,
    this.size = 152,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        blurSigma: 8,
        tintOpacity: 0.22,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: size,
                radius: 0,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.42, 0.68, 1],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 48,
                child: Icon(
                  active
                      ? Icons.equalizer_rounded
                      : Icons.play_circle_fill_rounded,
                  color: active ? accent : Colors.white,
                  size: 28,
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
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

class _HomeRadioStarterSection extends StatelessWidget {
  const _HomeRadioStarterSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(12).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final columns = <List<_Song>>[];
    for (var i = 0; i < songs.length; i += 2) {
      columns.add(songs.skip(i).take(2).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Fast stations'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 134,
          child: ListView.separated(
            key: PageStorageKey('home-radio-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, columnIndex) {
              final column = columns[columnIndex];
              return SizedBox(
                width: 238,
                child: Column(
                  children: [
                    for (var i = 0; i < column.length; i++) ...[
                      Expanded(
                        child: _HomeCompactSongTile(
                          song: column[i],
                          active: column[i].videoId == currentVideoId,
                          onTap: () => onPlay(column[i], section.songs),
                        ),
                      ),
                      if (i != column.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeMixesSection extends StatelessWidget {
  const _HomeMixesSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(9).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final groups = <List<_Song>>[];
    for (var i = 0; i < songs.length; i += 3) {
      groups.add(songs.skip(i).take(3).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Built from you'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 164,
          child: ListView.separated(
            key: PageStorageKey('home-mixes-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final group = groups[index];
              final lead = group.first;
              final active = group.any((s) => s.videoId == currentVideoId);
              return _HomeMixCard(
                title: index == 0
                    ? 'Resume your vibe'
                    : index == 1
                    ? 'Offline gems'
                    : 'Replay stack',
                songs: group,
                active: active,
                onTap: () => onPlay(lead, group),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeCompactSongTile extends StatelessWidget {
  const _HomeCompactSongTile({
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
      borderRadius: BorderRadius.circular(12),
      blurSigma: 8,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _Artwork(
            url: song.homeArtwork,
            size: 52,
            radius: 8,
            identityTag: song.videoId,
            offlineArtworkPath: song.offlineArtworkPath,
            useOfflineArtwork: song.isDownloaded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? accent : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist.ifBlank('Radio'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
            color: active ? accent : Colors.white.withValues(alpha: 0.56),
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _HomeMixCard extends StatelessWidget {
  const _HomeMixCard({
    required this.title,
    required this.songs,
    required this.active,
    required this.onTap,
  });

  final String title;
  final List<_Song> songs;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final art = songs.take(4).toList();
    return SizedBox(
      width: 183,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(14),
        blurSigma: 10,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                  ),
                  itemCount: math.max(1, art.length),
                  itemBuilder: (context, index) {
                    final song = art[index % art.length];
                    return _Artwork(
                      url: song.homeArtwork,
                      size: 80,
                      radius: 0,
                      identityTag: song.videoId,
                      offlineArtworkPath: song.offlineArtworkPath,
                      useOfflineArtwork: song.isDownloaded,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                  color: active ? accent : Colors.white.withValues(alpha: 0.58),
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeedLoadingMore extends StatelessWidget {
  const _HomeFeedLoadingMore();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white.withValues(alpha: 0.72),
        ),
      ),
    );
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
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final songs = section.songs.take(14).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: _kHomeShelfTitleGap),
        for (final song in songs)
          _HomeSongCard(
            song: song,
            active: song.videoId == currentVideoId,
            onTap: () => onPlay(song, section.songs),
          ),
      ],
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
        borderRadius: BorderRadius.circular(18),
        blurSigma: 8,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 87,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Artwork(
                  url: song.homeArtwork,
                  size: 360,
                  radius: 0,
                  identityTag: song.videoId,
                  offlineArtworkPath: song.offlineArtworkPath,
                  useOfflineArtwork: song.isDownloaded,
                ),
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.86),
                            Colors.black.withValues(alpha: 0.54),
                            Colors.black.withValues(alpha: 0.18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _Artwork(
                        url: song.homeArtwork,
                        size: 60,
                        radius: 8,
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
                                color: active ? accent : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
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
              ],
            ),
          ),
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
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: _kHomeShelfTitleGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1,
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
      borderRadius: BorderRadius.circular(18),
      blurSigma: 12,
      tintOpacity: 0.2,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Artwork(
              url: song.homeArtwork,
              size: 240,
              radius: 0,
              identityTag: song.videoId,
              offlineArtworkPath: song.offlineArtworkPath,
              useOfflineArtwork: song.isDownloaded,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0.48, 0.7, 1],
                ),
              ),
            ),
            if (active)
              Positioned(
                right: 10,
                top: 10,
                child: Icon(Icons.equalizer_rounded, color: accent, size: 30),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      height: 1.06,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
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

class _HomeVideoShelf extends StatelessWidget {
  const _HomeVideoShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 159,
          child: ListView.separated(
            key: PageStorageKey('home-video-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: section.songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
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
    const w = 234.0;
    const h = 132.0;
    return SizedBox(
      width: w,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(16),
        blurSigma: 10,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      stops: const [0, 0.48, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 42,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.66),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Icon(
                    active
                        ? Icons.equalizer_rounded
                        : Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 28,
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

class _HomeChartShelf extends StatelessWidget {
  const _HomeChartShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 190,
          child: ListView.separated(
            key: PageStorageKey('home-chart-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: section.songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = section.songs[index];
              return _HomeChartBannerCard(
                song: song,
                active: song.videoId == currentVideoId,
                onTap: () => onPlay(song, section.songs),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeChartBannerCard extends StatelessWidget {
  const _HomeChartBannerCard({
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
    return SizedBox(
      width: 344,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(18),
        blurSigma: 10,
        tintOpacity: 0.18,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: 320,
                radius: 0,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              Positioned(
                left: 12,
                right: 56,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist.ifBlank('Chart - YouTube Music'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Icon(
                  active
                      ? Icons.equalizer_rounded
                      : Icons.play_circle_fill_rounded,
                  color: active ? accent : Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeArtistShelf extends StatelessWidget {
  const _HomeArtistShelf({
    required this.section,
    required this.onPlay,
    this.onDiscoverSearch,
  });

  final _SongSection section;
  final _FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    final artists = section.songs
        .where(
          (song) =>
              song.videoId.startsWith('UC') ||
              song.artist.toLowerCase().contains('subscriber') ||
              song.artist == 'Artist',
        )
        .toList(growable: false);
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            section.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 142,
          child: ListView.separated(
            key: PageStorageKey('home-artist-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final song = artists[index];
              return SizedBox(
                width: 108,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      final query = '${song.title} artist songs';
                      if (onDiscoverSearch != null) {
                        onDiscoverSearch!(query);
                      } else {
                        onPlay(song, section.songs);
                      }
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Column(
                      children: [
                        ClipOval(
                          child: _Artwork(
                            url: song.highQualityArtwork,
                            size: 96,
                            radius: 0,
                            identityTag: song.videoId,
                            highQuality: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          song.title.ifBlank(song.artist),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
    this.style = 0,
    this.bottomGap = 0,
  });

  final Map<String, dynamic> player;
  final VoidCallback onOpen;
  final Future<void> Function()? onResync;
  final bool glass;
  final int style;
  final double bottomGap;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  Timer? _progressTicker;
  int _lastProgressTickAtMs = 0;
  double _pullDy = 0;

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
    _syncProgressTicker();
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
    _syncProgressTicker();
  }

  @override
  void dispose() {
    _progressTicker?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _syncProgressTicker() {
    final playing = widget.player['isPlaying'] == true;
    final buffering = _effectivePlayerBuffering(widget.player);
    final duration = ((widget.player['durationMs'] ?? 0) as num).toDouble();
    final shouldRun = playing && !buffering && duration > 0;
    if (!shouldRun) {
      _progressTicker?.cancel();
      _progressTicker = null;
      _lastProgressTickAtMs = 0;
      return;
    }
    _lastProgressTickAtMs = DateTime.now().millisecondsSinceEpoch;
    _progressTicker ??= Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (!mounted) return;
      final latestDuration = ((widget.player['durationMs'] ?? 0) as num)
          .toDouble();
      final latestPlaying = widget.player['isPlaying'] == true;
      if (!latestPlaying ||
          _effectivePlayerBuffering(widget.player) ||
          latestDuration <= 0) {
        _progressTicker?.cancel();
        _progressTicker = null;
        _lastProgressTickAtMs = 0;
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = _lastProgressTickAtMs == 0
          ? 0
          : (now - _lastProgressTickAtMs).clamp(0, 1200);
      _lastProgressTickAtMs = now;
      final delta = elapsed / latestDuration;
      _progressCtrl.value = (_progressCtrl.value + delta).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dynamicOn = widget.player['dynamicSongColors'] != false;
    final barColor = dynamicOn
        ? _miniPlayerTint(accent)
        : _kMiniPlayerFallbackTint;
    final song = _Song.fromMap(
      _asMap(widget.player['currentSong']) ?? const {},
    );
    final playing = widget.player['isPlaying'] == true;
    final buffering = _effectivePlayerBuffering(widget.player);

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
            tooltip: 'Previous',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () async {
              await _method.invokeMethod('previous');
              await widget.onResync?.call();
            },
            icon: Icon(
              Icons.skip_previous_rounded,
              color: Colors.white.withValues(alpha: 0.82),
              size: 24,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
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
          IconButton(
            tooltip: 'Next',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () async {
              await _method.invokeMethod('next');
              await widget.onResync?.call();
            },
            icon: Icon(
              Icons.skip_next_rounded,
              color: Colors.white.withValues(alpha: 0.82),
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );

    final miniStyle = widget.style.clamp(0, 2);
    final Widget shell;
    if (miniStyle == 2) {
      shell = playerBody;
    } else if (miniStyle == 1) {
      shell = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.1),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: playerBody,
          ),
        ),
      );
    } else if (widget.glass) {
      shell = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: _FoxyGlassTint(
            borderRadius: 16,
            tintOpacity: 0.44,
            borderOpacity: 0.18,
            child: playerBody,
          ),
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _pullDy = 0,
      onVerticalDragUpdate: (details) {
        _pullDy += details.primaryDelta ?? details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_pullDy < -34 || velocity < -360) {
          widget.onOpen();
        }
        _pullDy = 0;
      },
      onVerticalDragCancel: () => _pullDy = 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, widget.bottomGap),
        child: shell,
      ),
    );
  }
}

/// Metrolist / Foxy-style circular progress around the mini-player play control.
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

class _MetrolistPlayerSectionLabel extends StatelessWidget {
  const _MetrolistPlayerSectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
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
            Expanded(child: Text(text.toUpperCase(), style: upper)),
            ...?(trailingWidget == null ? null : [trailingWidget]),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.player,
    required this.scrollController,
    this.initialTab = 0,
    this.homeBackgroundPath,
    this.onNotifyHomePlayerSync,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final Map<String, dynamic> player;
  final ScrollController scrollController;
  final int initialTab;
  final String? homeBackgroundPath;
  final Future<void> Function()? onNotifyHomePlayerSync;
  final _FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  static final Map<String, List<_LyricLine>> _lyricsCache =
      <String, List<_LyricLine>>{};
  static final Map<String, String> _artistArtworkCache = <String, String>{};

  late Map<String, dynamic> _player = _detachPlayerState(
    _asMap(widget.player) ?? <String, dynamic>{},
  );
  StreamSubscription<dynamic>? _sub;
  late int _tab = widget.initialTab;
  int _progressStyle = 0;
  int _seekMotion = 0;
  int _playerButtonsStyle = 0;
  bool _hapticFeedback = true;
  bool _hidePlayerArtwork = false;
  bool _cropArtworkSquare = true;
  double _thumbnailCornerRadius = 16;
  List<_LyricLine> _lyrics = const [];
  String? _lyricsFor;
  String? _lyricsCacheKeyFor;
  int _lyricsRequestSerial = 0;
  bool _lyricsLoading = false;
  String? _artistArtFor;
  String? _artistArtworkUrl;
  String? _motionArtworkFor;
  String? _motionArtworkUrl;
  double _artworkSwipeDx = 0;
  bool _swipeCompleting = false;
  int _playerBackgroundStyle = 0;
  int _lastNowPlayingProgressUiMs = -1;
  final ScrollController _lyricsPanelScroll = ScrollController();
  final ScrollController _queuePanelScroll = ScrollController();
  final GlobalKey _compactLyricsKey = GlobalKey();

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
          final previousId = _asMap(
            _player['currentSong'],
          )?['videoId']?.toString();
          final detached = _mergePlayerState(state);
          final nextId = _asMap(
            detached['currentSong'],
          )?['videoId']?.toString();
          final structuralChanged = _nowPlayingSnapshotChanged(
            _player,
            detached,
          );
          final nextPosition = ((detached['positionMs'] ?? 0) as num).toInt();
          final shouldRefreshProgress =
              _lastNowPlayingProgressUiMs < 0 ||
              (nextPosition - _lastNowPlayingProgressUiMs).abs() >= 900 ||
              _player['durationMs'] != detached['durationMs'];
          if (structuralChanged || shouldRefreshProgress) {
            setState(() {
              _player = detached;
              _lastNowPlayingProgressUiMs = nextPosition;
              if (previousId != nextId) {
                _artworkSwipeDx = 0;
                _swipeCompleting = false;
              }
            });
          } else {
            _player = detached;
          }
          _loadLyricsIfNeeded(detached);
          _loadArtistArtworkIfNeeded(detached);
          if (_playerBackgroundStyle == 1) {
            _loadMotionArtworkIfNeeded(detached);
          }
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
        unawaited(_refreshPlayerSettings());
        _lyricsFor = '';
        _lyricsCacheKeyFor = null;
        unawaited(_loadLyricsIfNeeded(_player));
      }
    });
    _loadLyricsIfNeeded(_player);
    _loadArtistArtworkIfNeeded(_player);
    if (_playerBackgroundStyle == 1) {
      _loadMotionArtworkIfNeeded(_player);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lyricsPanelScroll.dispose();
    _queuePanelScroll.dispose();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    final nextBackgroundStyle = _normalizePlayerBackgroundStyle(
      ((map['playerBackgroundStyle'] ?? 0) as num).toInt(),
    );
    setState(() {
      _progressStyle = _normalizePlayerProgressStyle(
        ((map['playerProgressStyle'] ?? 0) as num).toInt(),
      );
      _seekMotion = 0;
      _playerButtonsStyle = ((map['playerButtonsStyle'] ?? 0) as num)
          .toInt()
          .clamp(0, 2);
      _hapticFeedback = map['hapticFeedback'] != false;
      _hidePlayerArtwork = map['hidePlayerArtwork'] == true;
      _cropArtworkSquare = map['cropArtworkSquare'] != false;
      _thumbnailCornerRadius = ((map['thumbnailCornerRadius'] ?? 16) as num)
          .toDouble()
          .clamp(0, 40);
      _playerBackgroundStyle = nextBackgroundStyle;
    });
    if (nextBackgroundStyle == 1) {
      unawaited(_loadMotionArtworkIfNeeded(_player));
    }
  }

  Future<void> _refreshPlayerSettings() async {
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap == null || !mounted) return;
    setState(() => _player = _mergePlayerState(snap));
  }

  Map<String, dynamic> _mergePlayerState(Map<String, dynamic> state) {
    final merged = <String, dynamic>{..._player, ...state};
    if (!state.containsKey('queue') && _player.containsKey('queue')) {
      merged['queue'] = _player['queue'];
    }
    return _detachPlayerState(merged);
  }

  bool _nowPlayingSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (prev['playerEpoch'] != next['playerEpoch']) return true;
    if (prev['isPlaying'] != next['isPlaying']) return true;
    if (prev['isBuffering'] != next['isBuffering']) return true;
    if (prev['songIsLiked'] != next['songIsLiked']) return true;
    if (prev['shuffleEnabled'] != next['shuffleEnabled']) return true;
    if (prev['repeatMode']?.toString() != next['repeatMode']?.toString()) {
      return true;
    }
    if (prev['queueIndex'] != next['queueIndex']) return true;
    if (_playerQueueSignature(prev['queue']) !=
        _playerQueueSignature(next['queue'])) {
      return true;
    }
    final pSong = _asMap(prev['currentSong']) ?? const {};
    final nSong = _asMap(next['currentSong']) ?? const {};
    for (final key in const [
      'videoId',
      'title',
      'artist',
      'artwork',
      'thumbnail',
      'offlineArtworkPath',
      'isDownloaded',
    ]) {
      if (pSong[key]?.toString() != nSong[key]?.toString()) return true;
    }
    return false;
  }

  Future<void> _loadLyricsIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final preferLrclib = player['lyricsPreferLrclib'] != false;
    final romanize = player['lyricsRomanize'] == true;
    final cacheKey = '${song.videoId}|$preferLrclib|$romanize';
    if (song.videoId.isEmpty) {
      if (_lyrics.isNotEmpty || _lyricsLoading || _lyricsFor != null) {
        setState(() {
          _lyrics = const [];
          _lyricsFor = null;
          _lyricsCacheKeyFor = null;
          _lyricsLoading = false;
        });
      }
      return;
    }
    if (_lyricsCacheKeyFor == cacheKey &&
        (_lyricsLoading || _lyrics.isNotEmpty)) {
      return;
    }
    final requestSerial = ++_lyricsRequestSerial;
    _lyricsFor = song.videoId;
    _lyricsCacheKeyFor = cacheKey;
    final cached = _lyricsCache[cacheKey];
    if (cached != null) {
      setState(() {
        _lyrics = cached;
        _lyricsLoading = false;
      });
      return;
    }
    setState(() {
      _lyricsLoading = true;
      _lyrics = const [];
    });
    try {
      final response = await _method.invokeMethod('lyrics', {
        'song': song.toMap(),
      });
      if (!mounted ||
          requestSerial != _lyricsRequestSerial ||
          _lyricsCacheKeyFor != cacheKey) {
        return;
      }
      final lines = (response as List? ?? const [])
          .map((item) => _LyricLine.fromMap(_asMap(item) ?? const {}))
          .where((line) => line.text.isNotEmpty)
          .toList();
      _lyricsCache[cacheKey] = lines;
      if (_lyricsCache.length > 32) {
        _lyricsCache.remove(_lyricsCache.keys.first);
      }
      setState(() {
        _lyrics = lines;
        _lyricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (requestSerial != _lyricsRequestSerial ||
          _lyricsCacheKeyFor != cacheKey) {
        return;
      }
      setState(() => _lyricsLoading = false);
    }
  }

  Future<void> _loadArtistArtworkIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final artist = _primaryArtistNameForLookup(song.artist).trim();
    final artistKey = _normalizeArtistLookupKey(artist);
    if (artist.isEmpty || artistKey.isEmpty || _artistArtFor == artistKey) {
      return;
    }
    _artistArtFor = artistKey;
    final cached = _artistArtworkCache[artistKey];
    if (cached != null) {
      setState(() => _artistArtworkUrl = cached.isEmpty ? null : cached);
      return;
    }
    setState(() => _artistArtworkUrl = null);
    try {
      final response =
          _asMap(
            await _method.invokeMethod('resolveArtistProfile', {
              'artist': artist,
              'limit': 18,
            }),
          ) ??
          const {};
      if (!mounted || _artistArtFor != artistKey) return;
      final resolvedArtist = response['artist']?.toString().trim() ?? '';
      final resolvedKey = _normalizeArtistLookupKey(resolvedArtist);
      final artwork = resolvedKey == artistKey
          ? (response['artworkUrl']?.toString().trim() ?? '')
          : '';
      _artistArtworkCache[artistKey] = artwork;
      if (_artistArtworkCache.length > 48) {
        _artistArtworkCache.remove(_artistArtworkCache.keys.first);
      }
      setState(() {
        _artistArtworkUrl = artwork.isEmpty ? null : artwork;
      });
    } catch (_) {
      if (!mounted || _artistArtFor != artistKey) return;
      setState(() => _artistArtworkUrl = null);
    }
  }

  Future<void> _loadMotionArtworkIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final key = song.videoId.ifBlank('${song.title}|${song.artist}').trim();
    if (key.isEmpty || _motionArtworkFor == key) return;
    _motionArtworkFor = key;
    setState(() => _motionArtworkUrl = null);
    try {
      final raw = _asMap(
        await _method.invokeMethod('resolveMotionArtwork', {
          'song': song.toMap(),
        }),
      );
      final staticUrl = raw?['staticUrl']?.toString().trim() ?? '';
      if (!mounted || _motionArtworkFor != key) return;
      setState(() {
        _motionArtworkUrl = staticUrl.isEmpty ? null : staticUrl;
      });
    } catch (_) {
      if (!mounted || _motionArtworkFor != key) return;
      setState(() => _motionArtworkUrl = null);
    }
  }

  void _openDefaultPlayerPage() {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openFullLyrics() {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _toggleLike(_Song song) async {
    final method = _player['songIsLiked'] == true ? 'unlike' : 'like';
    await _method.invokeMethod(method, {'song': song.toMap()});
    if (!mounted) return;
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap != null) {
      setState(() => _player = _mergePlayerState(snap));
    }
    await widget.onNotifyHomePlayerSync?.call();
  }

  Future<void> _openPlaylistPicker(_Song song) async {
    final feed = _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;
    await _pickPlaylistToAddSong(
      context,
      song: song,
      playlists: _userPlaylistsFrom(feed['userPlaylists']),
      onChanged: widget.onNotifyHomePlayerSync,
    );
  }

  void _openMenu(_Song song) {
    final parent = context;
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList();
    _showFoxySongOverflowMenu(
      parent,
      song: song,
      onPlay: onPlay,
      queueForPlay: queue.isEmpty ? <_Song>[song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: widget.onNotifyHomePlayerSync,
      searchResultsForExtras: queue.length > 1 ? queue : null,
      bulkQueuePlayTitle: 'Play full queue',
      bulkQueuePlaySubtitle: 'Keeps the current player queue order',
      compactPlayerMenu: true,
      onOpenLyricsTabInPlayer: () {
        if (mounted) _openFullLyrics();
      },
    );
  }

  void _openArtistPage(_Song song) {
    final artist = song.artist.trim();
    if (artist.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artist,
          artworkUrl: _artistArtworkUrl ?? '',
          onPlay: widget.onPlay ?? _fallbackPlayFromArtistPage,
          onDiscoverSearch: widget.onDiscoverSearch,
        ),
      ),
    );
  }

  Future<void> _fallbackPlayFromArtistPage(
    _Song song,
    List<_Song> queue, {
    bool radioTail = false,
  }) async {
    await _method.invokeMethod('playQueue', {
      'songs': (queue.isEmpty ? <_Song>[song] : queue)
          .map((item) => item.toMap())
          .toList(),
      'startIndex': math.max(
        0,
        queue.indexWhere((s) => s.videoId == song.videoId),
      ),
      'radioTail': radioTail,
    });
  }

  void _shareSongLink(_Song song) {
    if (song.videoId.isEmpty) return;
    Clipboard.setData(
      ClipboardData(text: 'https://music.youtube.com/watch?v=${song.videoId}'),
    );
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    final posterArtworkUrl = song.highQualityArtwork;
    final backgroundArtworkUrl = _playerBackgroundStyle == 1
        ? (_motionArtworkUrl?.ifBlank(posterArtworkUrl) ?? posterArtworkUrl)
        : posterArtworkUrl;
    final playing = _player['isPlaying'] == true;
    final buffering = _effectivePlayerBuffering(_player);
    final shuffle = _player['shuffleEnabled'] == true;
    final repeat = (_player['repeatMode'] ?? 'Off').toString();
    final duration = ((_player['durationMs'] ?? 0) as num).toDouble();
    final position = ((_player['positionMs'] ?? 0) as num).toDouble();
    final hintMs = _durationHintMsFromCatalog(song.duration);
    final effectiveDurMs = duration > 750
        ? duration
        : (hintMs?.toDouble() ?? 0.0);
    final progress = effectiveDurMs <= 0
        ? 0.0
        : (position / effectiveDurMs).clamp(0.0, 1.0);
    final endTimeLabel = effectiveDurMs > 750
        ? _fmt(effectiveDurMs.round())
        : '--:--';
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .toList();
    final queueIndex = ((_player['queueIndex'] ?? -1) as num).toInt();
    final effectiveQueue = queue.isNotEmpty
        ? queue
        : (song.videoId.isNotEmpty ? <_Song>[song] : const <_Song>[]);
    final effectiveQueueIndex = effectiveQueue.isEmpty
        ? -1
        : queueIndex.clamp(0, effectiveQueue.length - 1);
    final padL = 14.0 + MediaQuery.paddingOf(context).left;
    final padR = 14.0 + MediaQuery.paddingOf(context).right;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: _tab != 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted && _tab == 1) {
          setState(() => _tab = 0);
        }
      },
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: _NowPlayingBackdrop(
                song: song,
                artworkUrl: backgroundArtworkUrl,
                backgroundStyle: _playerBackgroundStyle,
                playing: playing,
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
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                                  onPlayer: _openDefaultPlayerPage,
                                  onLyrics: _openFullLyrics,
                                  onQueue: () => setState(() => _tab = 2),
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
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final prevEnabled =
                          _player['canPlayPrevious'] == true ||
                          effectiveQueueIndex > 0;
                      final nextEnabled =
                          effectiveQueue.isNotEmpty &&
                          effectiveQueueIndex >= 0 &&
                          effectiveQueueIndex < effectiveQueue.length - 1;
                      final previousSong =
                          effectiveQueueIndex > 0 &&
                              effectiveQueueIndex < effectiveQueue.length
                          ? effectiveQueue[effectiveQueueIndex - 1]
                          : null;
                      final nextSong = nextEnabled
                          ? effectiveQueue[effectiveQueueIndex + 1]
                          : null;
                      final maxW = c.maxWidth;
                      final viewH = MediaQuery.sizeOf(context).height;
                      final titleSeekGap = viewH * 0.032;
                      final controlsLyricsGap = viewH * 0.008;
                      final artSide = math
                          .min(maxW - 18, viewH * 0.45)
                          .clamp(300.0, 760.0);
                      final swipePageWidth = math.max(1.0, maxW - 36);
                      return SingleChildScrollView(
                        controller: widget.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(18, 0, 18, padBottom + 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 14),
                            Text(
                              'NOW PLAYING',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_tab == 1) ...[
                              _LyricsFullscreenTrackHeader(
                                song: song,
                                liked: _player['songIsLiked'] == true,
                                onLike: () => unawaited(_toggleLike(song)),
                                onMenu: () => _openMenu(song),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: (viewH * 0.62).clamp(500.0, 760.0),
                                child: _LyricsTab(
                                  lines: _lyrics,
                                  loading: _lyricsLoading,
                                  positionMs: position.round(),
                                  accent: accent,
                                  scrollController: _lyricsPanelScroll,
                                  preferLrclib:
                                      _player['lyricsPreferLrclib'] != false,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ] else ...[
                              GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragUpdate: (details) {
                                  if (_swipeCompleting) return;
                                  setState(() {
                                    _artworkSwipeDx =
                                        (_artworkSwipeDx + details.delta.dx)
                                            .clamp(
                                              -swipePageWidth,
                                              swipePageWidth,
                                            );
                                  });
                                },
                                onHorizontalDragEnd: (_) {
                                  if (_swipeCompleting) return;
                                  if (_artworkSwipeDx > 72) {
                                    setState(() {
                                      _swipeCompleting = true;
                                      _artworkSwipeDx = swipePageWidth;
                                    });
                                    _method.invokeMethod('previous');
                                  } else if (_artworkSwipeDx < -72) {
                                    setState(() {
                                      _swipeCompleting = true;
                                      _artworkSwipeDx = -swipePageWidth;
                                    });
                                    _method.invokeMethod('next');
                                  } else {
                                    setState(() => _artworkSwipeDx = 0);
                                  }
                                },
                                onHorizontalDragCancel: () {
                                  if (!_swipeCompleting) {
                                    setState(() => _artworkSwipeDx = 0);
                                  }
                                },
                                child: AnimatedSlide(
                                  duration: _swipeCompleting
                                      ? const Duration(milliseconds: 180)
                                      : Duration.zero,
                                  curve: Curves.easeOutCubic,
                                  offset: Offset.zero,
                                  child: _SwipePlayerPageDeck(
                                    current: song,
                                    previous: previousSong,
                                    next: nextSong,
                                    currentArtworkUrl: posterArtworkUrl,
                                    playing: playing && !buffering,
                                    dragDx: _artworkSwipeDx,
                                    pageWidth: swipePageWidth,
                                    maxSide: artSide,
                                    liked: _player['songIsLiked'] == true,
                                    hideArtwork: _hidePlayerArtwork,
                                    cropArtworkSquare: _cropArtworkSquare,
                                    thumbnailCornerRadius:
                                        _thumbnailCornerRadius,
                                    onLike: () => unawaited(_toggleLike(song)),
                                    onShare: () => _shareSongLink(song),
                                    onDownload: song.isDownloaded
                                        ? null
                                        : () async {
                                            await _method.invokeMethod(
                                              'download',
                                              {'song': song.toMap()},
                                            );
                                            if (!mounted) return;
                                            final snap = _asMap(
                                              await _method.invokeMethod(
                                                'getPlayerState',
                                              ),
                                            );
                                            if (snap != null) {
                                              setState(
                                                () => _player =
                                                    _mergePlayerState(snap),
                                              );
                                            }
                                          },
                                    onPlaylist: () =>
                                        unawaited(_openPlaylistPicker(song)),
                                  ),
                                ),
                              ),
                              SizedBox(height: titleSeekGap),
                            ],
                            if (buffering)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    minHeight: 4,
                                    backgroundColor: Colors.grey.shade800
                                        .withValues(alpha: 0.9),
                                    color: Colors.grey.shade500,
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
                                    _method.invokeMethod('seekTo', {
                                      'positionMs': (effectiveDurMs * value)
                                          .round(),
                                    }),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _fmt(position.round()),
                                    style: const TextStyle(
                                      color: _kMetrolistNpTime,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    endTimeLabel,
                                    style: const TextStyle(
                                      color: _kMetrolistNpTime,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _FoxyPlayerControlLayout(
                              shuffle: shuffle,
                              repeatMode: repeat,
                              playing: playing,
                              buffering: buffering,
                              prevEnabled: prevEnabled,
                              nextEnabled: nextEnabled,
                              buttonStyle: _playerButtonsStyle,
                              hapticFeedback: _hapticFeedback,
                            ),
                            SizedBox(height: controlsLyricsGap),
                            if (_tab != 1)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeOutCubic,
                                child: switch (_tab) {
                                  2 => SizedBox(
                                    key: const ValueKey('queue-section'),
                                    height: viewH * 0.48,
                                    child: _QueueTab(
                                      queue: effectiveQueue,
                                      currentIndex: effectiveQueueIndex,
                                      scrollController: _queuePanelScroll,
                                      onPlay: widget.onPlay,
                                      onDiscoverSearch: widget.onDiscoverSearch,
                                    ),
                                  ),
                                  _ => Column(
                                    key: const ValueKey('details-section'),
                                    children: [
                                      _CompactLyricsPreviewCard(
                                        key: _compactLyricsKey,
                                        lines: _lyrics,
                                        loading: _lyricsLoading,
                                        positionMs: position.round(),
                                        accent: accent,
                                        onTap: _openFullLyrics,
                                      ),
                                      const SizedBox(height: 10),
                                      _PlayerArtistMiniCard(
                                        artist: song.artist,
                                        artworkUrl: _artistArtworkUrl ?? '',
                                        accent: accent,
                                        onTap: () => _openArtistPage(song),
                                      ),
                                      const SizedBox(height: 10),
                                      _SongDetailsCard(
                                        song: song,
                                        player: _player,
                                      ),
                                    ],
                                  ),
                                },
                              ),
                          ],
                        ),
                      );
                    },
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

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({
    required this.accent,
    required this.selected,
    required this.onPlayer,
    required this.onLyrics,
    required this.onQueue,
  });

  final Color accent;
  final int selected;
  final VoidCallback onPlayer;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String, VoidCallback, bool)>[
      (Icons.album_rounded, 'Player', onPlayer, selected == 0),
      (Icons.lyrics_outlined, 'Lyrics', onLyrics, selected == 1),
      (Icons.queue_music_outlined, 'Queue', onQueue, selected == 2),
    ];
    return _FoxyGlassButton(
      borderRadius: BorderRadius.circular(999),
      tintOpacity: 0.26,
      blurSigma: 14,
      blur: true,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: tabs[i].$2,
                child: _FoxyGlassButton(
                  onTap: tabs[i].$3,
                  borderRadius: BorderRadius.circular(999),
                  blur: true,
                  blurSigma: 10,
                  tintOpacity: tabs[i].$4 ? 0.2 : 0.08,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  child: Icon(
                    tabs[i].$1,
                    size: 21,
                    color: tabs[i].$4
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ),
        ],
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
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  double get _paintHeight {
    final s = _normalizePlayerProgressStyle(widget.style);
    if (s == 0) return 34.0;
    return 28.0;
  }

  void _seek(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    widget.onSeek((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final st = _normalizePlayerProgressStyle(widget.style);
    Widget buildBar(double phase, double progress) {
      return CustomPaint(
        painter: _MetrolistSeekPainter(
          progress: progress,
          dimmed: !widget.enabled,
          style: st,
          accent: widget.accent,
          motion: 0,
          motionPhase: phase,
        ),
        child: SizedBox(height: _paintHeight, width: double.infinity),
      );
    }

    final content = AnimatedBuilder(
      animation: _progressCtrl,
      builder: (context, _) => buildBar(0, _progressCtrl.value.clamp(0.0, 1.0)),
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
    final inactiveColor = dimmed
        ? _inactive.withValues(alpha: 0.45)
        : _inactive;
    final activeColor = dimmed ? Colors.white38 : _active;
    final trackH = 8.5;
    final radius = const Radius.circular(999);
    final full = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
      radius,
    );
    canvas.drawRRect(full, Paint()..color = inactiveColor);
    if (p > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
          radius,
        ),
        Paint()..color = activeColor,
      );
    }
    const tw = 4.0;
    const th = 17.0;
    final half = tw / 2 + 1.0;
    final cx = (size.width * p).clamp(half, size.width - half);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: tw, height: th),
      Radius.circular(tw / 2),
    );
    canvas.drawRRect(thumb, Paint()..color = dimmed ? Colors.white54 : _active);
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

/// Bottom tool row on the now-playing sheet (info, lyrics, queue, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦).
/// Foxy-style transport row: shuffle ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· previous ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· large play/pause ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· next ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· repeat
/// .
class _FoxyPlayerControlLayout extends StatelessWidget {
  const _FoxyPlayerControlLayout({
    required this.shuffle,
    required this.repeatMode,
    required this.playing,
    required this.buffering,
    required this.prevEnabled,
    required this.nextEnabled,
    required this.buttonStyle,
    required this.hapticFeedback,
  });

  final bool shuffle;
  final String repeatMode;
  final bool playing;
  final bool buffering;
  final bool prevEnabled;
  final bool nextEnabled;
  final int buttonStyle;
  final bool hapticFeedback;

  void _tap(String method) {
    if (hapticFeedback) HapticFeedback.lightImpact();
    _method.invokeMethod(method);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final repeatOn = repeatMode != 'Off';

    Widget slot(Widget child) => Expanded(child: Center(child: child));

    Widget iconOnlyBtn({required VoidCallback? onTap, required Widget icon}) {
      return IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 26,
        constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
        icon: icon,
      );
    }

    Widget mainPlay() {
      const playSize = 140.0;
      final solid = buttonStyle == 2;
      final outline = buttonStyle == 1;
      return slot(
        Material(
          color: solid
              ? accent.withValues(alpha: 0.95)
              : outline
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.96),
          elevation: outline ? 0 : 8,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _tap('togglePlayPause'),
            child: Container(
              width: playSize,
              height: playSize,
              decoration: outline
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 2),
                    )
                  : null,
              child: buffering
                  ? Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: outline ? Colors.white70 : Colors.black38,
                        ),
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: playing ? 64 : 68,
                      color: outline ? Colors.white : Colors.black87,
                    ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            slot(
              iconOnlyBtn(
                onTap: () => _tap('toggleShuffle'),
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 30,
                  color: shuffle ? accent : Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: prevEnabled ? () => _tap('previous') : null,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 40,
                  color: prevEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            mainPlay(),
            slot(
              iconOnlyBtn(
                onTap: nextEnabled ? () => _tap('next') : null,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 40,
                  color: nextEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: () => _tap('cycleRepeatMode'),
                icon: Icon(
                  repeatMode == 'One'
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  size: 30,
                  color: repeatOn
                      ? accent
                      : Colors.white.withValues(alpha: 0.9),
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
    required this.scrollController,
    this.preferLrclib = true,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final ScrollController scrollController;
  final bool preferLrclib;
  bool get _showProviderHeading => false;

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
                'Loading lyrics...',
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
              ? 'LRCLIB had no match - try turning off "Prefer LRCLIB" in Settings or the menu.'
              : 'YouTube captions had no match - try "Prefer LRCLIB" in Settings.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showProviderHeading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              preferLrclib ? 'Synced - LRCLIB' : 'Synced - YouTube captions',
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
          scrollController: scrollController,
        ),
      ],
    );
  }
}

const int _kFullscreenLyricsExtraLines = 4;
const double _kLyricLineExtent = 74.0;

class _AnimatedLyricsList extends StatefulWidget {
  const _AnimatedLyricsList({
    required this.lines,
    required this.positionMs,
    required this.accent,
    required this.scrollController,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final Color accent;
  final ScrollController scrollController;

  @override
  State<_AnimatedLyricsList> createState() => _AnimatedLyricsListState();
}

class _AnimatedLyricsListState extends State<_AnimatedLyricsList> {
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerActiveLine(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = _activeIndex;
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerActiveLine(animated: true);
      });
    }
  }

  void _centerActiveLine({required bool animated}) {
    if (!widget.scrollController.hasClients) return;
    final viewport = widget.scrollController.position.viewportDimension.isFinite
        ? widget.scrollController.position.viewportDimension
        : 520.0;
    final target =
        (_activeIndex * _kLyricLineExtent -
                viewport * 0.5 +
                _kLyricLineExtent * 0.5)
            .clamp(0.0, widget.scrollController.position.maxScrollExtent);
    if (animated) {
      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.scrollController.jumpTo(target);
    }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackHeight = MediaQuery.sizeOf(context).height * 0.58;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackHeight;
        final topPad = math.max(92.0, h * 0.42);
        final bottomPad = math.max(120.0, h * 0.48);
        return SizedBox(
          height: h,
          child: ListView.builder(
            controller: widget.scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(4, topPad, 4, bottomPad),
            itemCount: widget.lines.length,
            cacheExtent: _kLyricLineExtent * _kFullscreenLyricsExtraLines,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              final isActive = index == active;
              final passed = index < active;
              final distance = (index - active).abs();
              final inactiveAlpha = (0.62 - distance * 0.06).clamp(0.18, 0.56);
              return TweenAnimationBuilder<double>(
                key: ValueKey('${line.timeMs}-$isActive'),
                tween: Tween(begin: 0, end: isActive ? 1 : 0),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  final scale = 1.0 + (0.045 * t);
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: isActive ? 1 : inactiveAlpha.toDouble(),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          vertical: isActive ? 12 : 9,
                        ),
                        child: Text(
                          line.text,
                          maxLines: isActive ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : passed
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.86),
                            fontSize: isActive ? 28 : 23,
                            height: 1.14,
                            fontWeight: isActive
                                ? FontWeight.w900
                                : FontWeight.w700,
                            shadows: isActive
                                ? [
                                    Shadow(
                                      color: widget.accent.withValues(
                                        alpha: 0.26,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.currentIndex,
    required this.scrollController,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_Song> queue;
  final int currentIndex;
  final ScrollController scrollController;
  final _FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 120),
        children: const [
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.only(top: 48),
            child: _EmptyTabBody(
              icon: Icons.queue_music_rounded,
              title: 'Queue is empty',
              subtitle: 'Play a song to build your queue, then open this tab.',
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: queue.length + 1,
      itemBuilder: (context, rawIndex) {
        if (rawIndex == 0) {
          final current =
              queue[currentIndex.clamp(0, queue.length - 1).toInt()];
          return Column(
            children: [
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: _Artwork(
                      url: current.artwork,
                      size: 54,
                      radius: 12,
                      identityTag: current.videoId,
                    ),
                    title: const Text(
                      'Now playing',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
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
            ],
          );
        }
        final index = rawIndex - 1;
        final item = queue[index];
        final active = index == currentIndex;
        return _FoxySongTile(
          song: item,
          index: index,
          thumbRadius: 10,
          active: active,
          onMore: () {
            final play = onPlay;
            if (play != null) {
              _showFoxySongOverflowMenu(
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
      },
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
  });

  final IconData icon;
  final String label;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
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

class _PlayerArtistMiniCard extends StatelessWidget {
  const _PlayerArtistMiniCard({
    required this.artist,
    required this.artworkUrl,
    required this.accent,
    this.onTap,
  });

  final String artist;
  final String artworkUrl;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (artist.trim().isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.58,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: artworkUrl,
                size: 600,
                radius: 0,
                highQuality: true,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    stops: const [0, 0.46, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 14,
                child: Text(
                  'Artists',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tap to explore artist radio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: accent.withValues(alpha: 0.95),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactLyricsPreviewCard extends StatelessWidget {
  const _CompactLyricsPreviewCard({
    super.key,
    required this.lines,
    required this.loading,
    required this.positionMs,
    required this.accent,
    required this.onTap,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = lines.isEmpty
        ? null
        : lines.lastWhere(
            (line) => line.timeMs <= positionMs,
            orElse: () => lines.first,
          );
    final preview = loading
        ? 'Loading lyrics...'
        : active?.text.trim().ifBlank('Open synced lyrics') ??
              'Open synced lyrics';

    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              if (loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: accent.withValues(alpha: 0.9),
                  ),
                )
              else
                Icon(Icons.lyrics_rounded, color: accent, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: loading
                        ? Colors.white.withValues(alpha: 0.72)
                        : Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongDetailsCard extends StatelessWidget {
  const _SongDetailsCard({required this.song, required this.player});

  final _Song song;
  final Map<String, dynamic> player;

  @override
  Widget build(BuildContext context) {
    final title = song.title.trim();
    final artist = song.artist.trim();
    final details = <String>[
      if ((player['streamQualityLabel']?.toString().trim().isNotEmpty ?? false))
        player['streamQualityLabel'].toString().trim(),
      if ((player['streamBitrate'] as num?) != null)
        '${(player['streamBitrate'] as num).toInt()} kbps',
      if ((player['streamCodec']?.toString().trim().isNotEmpty ?? false))
        player['streamCodec'].toString().trim(),
      if ((player['streamSource']?.toString().trim().isNotEmpty ?? false))
        player['streamSource'].toString().trim(),
      if ((song.duration?.trim().isNotEmpty ?? false)) song.duration!.trim(),
    ];

    final description = <String>[
      if (title.isNotEmpty && artist.isNotEmpty) '$title - $artist',
      if (details.isNotEmpty) details.join(' | '),
      'FoxyMusic keeps this info lightweight while playback stays smooth.',
    ].join('\n\n');

    return _ExpandableSongDescriptionCard(
      publishedLabel: song.duration == null
          ? 'Track details'
          : 'Duration ${song.duration}',
      headline: artist.ifBlank('FoxyMusic'),
      description: description,
      details: details,
    );
  }
}

class _ExpandableSongDescriptionCard extends StatefulWidget {
  const _ExpandableSongDescriptionCard({
    required this.publishedLabel,
    required this.headline,
    required this.description,
    required this.details,
  });

  final String publishedLabel;
  final String headline;
  final String description;
  final List<String> details;

  @override
  State<_ExpandableSongDescriptionCard> createState() =>
      _ExpandableSongDescriptionCardState();
}

class _ExpandableSongDescriptionCardState
    extends State<_ExpandableSongDescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _FoxyGlassTint(
        borderRadius: 16,
        tintOpacity: 0.34,
        borderOpacity: 0.08,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.publishedLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.headline,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.96),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              if (widget.details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in widget.details.take(4))
                      Text(
                        item,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Text(
                  widget.description,
                  maxLines: _expanded ? 80 : 4,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    height: 1.46,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'Less' : 'More',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerTitleActionRow extends StatelessWidget {
  const _PlayerTitleActionRow({
    required this.song,
    required this.onShare,
    required this.onPlaylist,
    this.onDownload,
  });

  final _Song song;
  final VoidCallback onShare;
  final VoidCallback onPlaylist;
  final Future<void> Function()? onDownload;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy link',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            Icons.share_outlined,
            color: Colors.white.withValues(alpha: 0.92),
            size: 22,
          ),
          onPressed: onShare,
        ),
        IconButton(
          tooltip: song.isDownloaded ? 'Downloaded' : 'Download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            song.isDownloaded
                ? Icons.download_done_rounded
                : Icons.download_outlined,
            color: song.isDownloaded
                ? const Color(0xFF81C784)
                : Colors.white.withValues(alpha: 0.92),
            size: 22,
          ),
          onPressed: song.isDownloaded || onDownload == null
              ? null
              : () => unawaited(onDownload!()),
        ),
        IconButton(
          tooltip: 'Add to playlist',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            Icons.playlist_add_rounded,
            color: Colors.white.withValues(alpha: 0.92),
            size: 24,
          ),
          onPressed: onPlaylist,
        ),
      ],
    );
  }
}

class _LyricsFullscreenTrackHeader extends StatelessWidget {
  const _LyricsFullscreenTrackHeader({
    required this.song,
    required this.liked,
    required this.onLike,
    required this.onMenu,
  });

  final _Song song;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _Artwork(
            url: song.highQualityArtwork,
            size: 48,
            radius: 9,
            highQuality: true,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: liked ? 'Unlike' : 'Like',
            onPressed: onLike,
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: 28,
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMenu,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.url,
    required this.playing,
    required this.tag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.maxSide,
    this.liked = false,
    this.hideArtwork = false,
    this.cropArtworkSquare = true,
    this.thumbnailCornerRadius = 16,
    this.onLike,
  });

  final String url;
  final bool playing;
  final String tag;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;
  final bool liked;
  final bool hideArtwork;
  final bool cropArtworkSquare;
  final double thumbnailCornerRadius;
  final VoidCallback? onLike;

  /// Caps artwork so transport rows never collide on narrow devices.
  final double? maxSide;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final base = math.min(w - 18, h * 0.45).clamp(300.0, 760.0);
    final side = maxSide ?? base;
    final artSide = side;
    final radius = thumbnailCornerRadius.clamp(0.0, 40.0);
    final identity = tag.startsWith('art-') ? tag.substring(4) : tag;

    if (hideArtwork) {
      return SizedBox(
        width: side,
        height: 72,
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            size: 44,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
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
                fit: cropArtworkSquare ? BoxFit.cover : BoxFit.contain,
              ),
            ),
          ),
          if (onLike != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: _FoxyGlassButton(
                onTap: onLike,
                borderRadius: BorderRadius.circular(999),
                tintOpacity: 0.28,
                blurSigma: 12,
                blur: true,
                padding: const EdgeInsets.all(10),
                child: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked
                      ? const Color(0xFFFF8A80)
                      : Colors.white.withValues(alpha: 0.92),
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwipePlayerPageDeck extends StatelessWidget {
  const _SwipePlayerPageDeck({
    required this.current,
    required this.currentArtworkUrl,
    required this.playing,
    required this.dragDx,
    required this.pageWidth,
    required this.maxSide,
    required this.liked,
    required this.hideArtwork,
    required this.cropArtworkSquare,
    required this.thumbnailCornerRadius,
    required this.onLike,
    required this.onShare,
    required this.onPlaylist,
    this.onDownload,
    this.previous,
    this.next,
  });

  final _Song current;
  final String currentArtworkUrl;
  final _Song? previous;
  final _Song? next;
  final bool playing;
  final double dragDx;
  final double pageWidth;
  final double maxSide;
  final bool liked;
  final bool hideArtwork;
  final bool cropArtworkSquare;
  final double thumbnailCornerRadius;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onPlaylist;
  final Future<void> Function()? onDownload;

  Widget _previewTitle(_Song song, double opacity) {
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                height: 1.04,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page({
    required _Song song,
    required bool primary,
    required double opacity,
  }) {
    final artworkUrl = primary ? currentArtworkUrl : song.highQualityArtwork;
    return SizedBox(
      width: pageWidth,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: primary ? 1.0 : 0.965,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: _PlayerArtwork(
                  url: artworkUrl,
                  playing: primary && playing,
                  tag: 'art-${song.videoId}',
                  offlineArtworkPath: song.offlineArtworkPath,
                  useOfflineArtwork:
                      song.isDownloaded &&
                      artworkUrl == song.highQualityArtwork,
                  maxSide: maxSide,
                  liked: primary ? liked : false,
                  hideArtwork: primary && hideArtwork,
                  cropArtworkSquare: cropArtworkSquare,
                  thumbnailCornerRadius: thumbnailCornerRadius,
                  onLike: primary ? onLike : null,
                ),
              ),
              const SizedBox(height: 14),
              if (primary)
                _PlayerTitleActionRow(
                  song: song,
                  onShare: onShare,
                  onDownload: onDownload,
                  onPlaylist: onPlaylist,
                )
              else
                _previewTitle(song, opacity),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = pageWidth <= 0 ? MediaQuery.sizeOf(context).width : pageWidth;
    final progress = (dragDx.abs() / width).clamp(0.0, 1.0);
    final previewOpacity = (0.38 + progress * 0.62).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            if (previous != null)
              Transform.translate(
                offset: Offset(dragDx - width, 0),
                child: _page(
                  song: previous!,
                  primary: false,
                  opacity: previewOpacity,
                ),
              ),
            if (next != null)
              Transform.translate(
                offset: Offset(dragDx + width, 0),
                child: _page(
                  song: next!,
                  primary: false,
                  opacity: previewOpacity,
                ),
              ),
            Transform.translate(
              offset: Offset(dragDx, 0),
              child: _page(song: current, primary: true, opacity: 1),
            ),
          ],
        ),
      ),
    );
  }
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
    this.fit = BoxFit.cover,
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
  final BoxFit fit;

  static final Map<String, File> _existingFileCache = <String, File>{};

  static File? _existingFile(String path) {
    final cached = _existingFileCache[path];
    if (cached != null) return cached;
    final f = File(path);
    if (!f.existsSync()) return null;
    _existingFileCache[path] = f;
    return f;
  }

  @override
  Widget build(BuildContext context) {
    File? offlineFile() {
      if (!useOfflineArtwork || kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      return _existingFile(p);
    }

    File? localPathFile() {
      if (kIsWeb) return null;
      final u = url.trim();
      if (u.isEmpty) return null;
      if (u.startsWith('http://') || u.startsWith('https://')) return null;
      final path = u.startsWith('file://') ? u.substring(7) : u;
      return _existingFile(path);
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
          fit: fit,
          gaplessPlayback: false,
          filterQuality: highQuality
              ? FilterQuality.high
              : FilterQuality.medium,
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
        fit: fit,
        gaplessPlayback: false,
        filterQuality: highQuality ? FilterQuality.high : FilterQuality.medium,
        cacheWidth: cachePx,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _NowPlayingBackdrop extends StatelessWidget {
  const _NowPlayingBackdrop({
    required this.song,
    required this.artworkUrl,
    required this.backgroundStyle,
    required this.playing,
  });

  final _Song song;
  final String artworkUrl;
  final int backgroundStyle;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final style = _normalizePlayerBackgroundStyle(backgroundStyle);
    if (style == 2) {
      return const ColoredBox(color: Colors.black);
    }
    if (style == 3) {
      return _VideoClipBackdrop(song: song, playing: playing);
    }
    if (style == 1) {
      return _NonBlurredArtworkBackdrop(
        url: artworkUrl,
        offlineArtworkPath: song.offlineArtworkPath,
        useOfflineArtwork:
            song.isDownloaded && artworkUrl == song.highQualityArtwork,
      );
    }
    return _BlurBackdrop(
      url: artworkUrl,
      blurEnabled: true,
      offlineArtworkPath: song.offlineArtworkPath,
      useOfflineArtwork:
          song.isDownloaded && artworkUrl == song.highQualityArtwork,
      fullBleed: true,
    );
  }
}

class _VideoClipBackdrop extends StatefulWidget {
  const _VideoClipBackdrop({required this.song, required this.playing});

  final _Song song;
  final bool playing;

  @override
  State<_VideoClipBackdrop> createState() => _VideoClipBackdropState();
}

class _VideoClipBackdropState extends State<_VideoClipBackdrop> {
  VideoPlayerController? _controller;
  bool _failed = false;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _VideoClipBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.videoId != widget.song.videoId ||
        oldWidget.song.title != widget.song.title ||
        oldWidget.song.artist != widget.song.artist) {
      unawaited(_load());
      return;
    }
    _syncPlayback();
  }

  @override
  void dispose() {
    _serial++;
    final old = _controller;
    _controller = null;
    unawaited(old?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final song = widget.song;
    final videoId = song.videoId.trim();
    final serial = ++_serial;
    final old = _controller;
    _controller = null;
    _failed = false;
    if (mounted) setState(() {});
    unawaited(old?.dispose());
    if (videoId.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final raw = await _method.invokeMethod('getVideoClipStream', {
        'videoId': videoId,
        'title': song.title,
        'artist': song.artist,
      });
      if (!mounted || serial != _serial) return;
      final map = _asMap(raw) ?? const {};
      final url = map['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.initialize();
      if (!mounted || serial != _serial) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _failed = false;
      _syncPlayback();
      setState(() {});
    } catch (_) {
      if (mounted && serial == _serial) {
        setState(() => _failed = true);
      }
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.playing) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.34),
                Colors.black.withValues(alpha: 0.82),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NonBlurredArtworkBackdrop extends StatelessWidget {
  const _NonBlurredArtworkBackdrop({
    required this.url,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
  });

  final String url;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  File? _offlineFile() {
    if (!useOfflineArtwork || kIsWeb) return null;
    final p = offlineArtworkPath?.trim();
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final of = _offlineFile();
    final deviceWidth =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = deviceWidth.isFinite
        ? deviceWidth.round().clamp(960, 2200)
        : 1600;
    final image = of != null
        ? Image.file(
            of,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF050505)),
          )
        : url.isBlank
        ? const ColoredBox(color: Color(0xFF050505))
        : Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF050505)),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: image),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.22),
              radius: 1.18,
              colors: [
                accent.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.54),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.26),
                Colors.black.withValues(alpha: 0.68),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.blurEnabled,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.fullBleed = false,
  });

  final String url;
  final bool blurEnabled;
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
            errorBuilder: (_, _, _) => url.isBlank
                ? const ColoredBox(color: Color(0xFF080808))
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF080808)),
                  ),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF080808)),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: fullBleed ? 1.35 : 1.18,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: fullBleed ? 38 : 34,
              sigmaY: fullBleed ? 38 : 34,
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
                      Color.lerp(
                        const Color(0xFF000000),
                        accent,
                        0.08,
                      )!.withValues(alpha: 0.94),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HomeSkeletonBox(width: double.infinity, height: 188, radius: 24),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 190),
          SizedBox(height: 14),
          _HomeSkeletonRail(),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 160),
          SizedBox(height: 14),
          _HomeSkeletonRail(),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 175),
          SizedBox(height: 14),
          _HomeSkeletonQuickPicks(),
        ],
      ),
    );
  }
}

class _HomeSkeletonLine extends StatelessWidget {
  const _HomeSkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) =>
      _HomeSkeletonBox(width: width, height: 24, radius: 8);
}

class _HomeSkeletonRail extends StatelessWidget {
  const _HomeSkeletonRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) =>
            const _HomeSkeletonBox(width: 160, height: 206, radius: 18),
      ),
    );
  }
}

class _HomeSkeletonQuickPicks extends StatelessWidget {
  const _HomeSkeletonQuickPicks();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 256,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 320,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: 12,
        itemBuilder: (_, _) =>
            const _HomeSkeletonBox(width: 320, height: 58, radius: 12),
      ),
    );
  }
}

class _HomeSkeletonBox extends StatelessWidget {
  const _HomeSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0.07),
          ],
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline =
        message.toLowerCase().contains('internet') ||
        message.toLowerCase().contains('network') ||
        message.toLowerCase().contains('host lookup');
    final title = offline ? 'No internet connection' : 'Home could not load';
    final subtitle = offline
        ? 'Check your connection, then try again.'
        : message;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Icon(Icons.wifi_off_rounded, size: 34),
            ),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
    title: _cleanDisplayText(map['title'], fallback: 'For you'),
    layout: _cleanDisplayText(map['layout'], fallback: 'shelf'),
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
    final artwork = [map['thumbnail'], map['artworkUrl']]
        .map((value) => value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final lp = map['localPath']?.toString();
    final oap = map['offlineArtworkPath']?.toString();
    return _Song(
      videoId: _cleanDisplayText(map['videoId']),
      title: _cleanDisplayText(map['title'], fallback: 'Untitled'),
      artist: _cleanDisplayText(map['artist'], fallback: 'Unknown artist'),
      artwork: artwork,
      duration: _cleanDisplayText(map['duration']).ifBlank(''),
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

  bool get isLocalTrack => videoId.startsWith('local_');
  String get highQualityArtwork =>
      isLocalTrack ? artwork : _upgradeYouTubeArtworkUrl(artwork, videoId);
  String get homeArtwork =>
      isLocalTrack ? artwork : _homeThumbnailArtworkUrl(artwork, videoId);

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
    out['queue'] = q.map((dynamic e) {
      final m = _asMap(e);
      return m != null ? Map<String, dynamic>.from(m) : e;
    }).toList();
  }
  return out;
}

String _playerQueueSignature(dynamic queue) {
  if (queue is! List) return '';
  return queue
      .map((dynamic item) => _asMap(item)?['videoId']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .join('|');
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
    RegExp(r'/(hqdefault|sddefault|mqdefault|default)\.jpg'),
    '/maxresdefault.jpg',
  );
  return u;
}

String _homeThumbnailArtworkUrl(String url, String videoId) {
  var u = url.trim();
  if (u.isEmpty && videoId.isNotEmpty) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }
  if (u.isEmpty) return u;
  u = u
      .replaceAll('=s88-', '=s480-')
      .replaceAll('=s120-', '=s480-')
      .replaceAll('=s180-', '=s480-')
      .replaceAll('=s360-', '=s480-')
      .replaceAll('=w88-h88', '=w480-h360')
      .replaceAll('=w120-h120', '=w480-h360')
      .replaceAll('=w360-h360', '=w480-h360');
  u = u.replaceAll(
    RegExp(r'/(maxresdefault|sddefault|mqdefault|default)\.jpg'),
    '/hqdefault.jpg',
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
